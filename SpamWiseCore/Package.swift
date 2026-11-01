// swift-tools-version: 6.4
import PackageDescription
let swiftSettings: [SwiftSetting] = [
  .enableUpcomingFeature("NonisolatedNonsendingByDefault"),
  .enableUpcomingFeature("InferIsolatedConformances"),
  .enableUpcomingFeature("ImmutableWeakCaptures"),
  .enableUpcomingFeature("MemberImportVisibility"),
  .enableUpcomingFeature("ExistentialAny"),
  .enableUpcomingFeature("InternalImportsByDefault"),
  .strictMemorySafety()
]
let localizedStrings: [Resource] = [.process("Localizable.xcstrings")]

/// Embeds an Info.plist listing the localizations, which a bare executable otherwise lacks.
func embeddedInfoPlist(_ tool: String) -> [LinkerSetting] {
  let plist = "\(Context.packageDirectory)/Support/\(tool)-Info.plist"
  return [
    .unsafeFlags(
      ["-sectcreate", "__TEXT", "__info_plist", plist].flatMap { ["-Xlinker", $0] }
    )
  ]
}

let package = Package(
  name: "SpamWiseCore",
  defaultLocalization: "en",
  platforms: [.macOS("27.0")],
  products: [
    .library(name: "SpamWiseCore", targets: ["SpamWiseCore"]),
    .library(name: "MailIntegration", targets: ["MailIntegration"]),
    .executable(name: "spamwise-eval", targets: ["SpamWiseEval"]),
    .executable(name: "spamwise-daemon", targets: ["SpamWiseDaemon"])
  ],
  dependencies: [
    .package(
      url: "https://github.com/anthropics/ClaudeForFoundationModels.git",
      from: "0.2.3"
    ),
    .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.8.2"),
    .package(url: "https://github.com/apple/swift-nio.git", from: "2.104.0"),
    .package(url: "https://github.com/apple/swift-nio-imap.git", from: "0.4.0"),
    .package(url: "https://github.com/apple/swift-nio-transport-services.git", from: "1.28.0")
  ],
  targets: [
    .target(
      name: "MessageModel",
      resources: [.copy("Resources/public_suffix_list.dat")] + localizedStrings
    ),
    .systemLibrary(name: "CResolver"),
    .target(
      name: "Signals",
      dependencies: ["MessageModel", "CResolver"],
      resources: localizedStrings
    ),
    .target(
      name: "Classifier",
      dependencies: [
        "MessageModel", "Signals",
        .product(name: "ClaudeForFoundationModels", package: "ClaudeForFoundationModels")
      ],
      resources: localizedStrings
    ),
    .target(name: "Decision", dependencies: ["Classifier", "Signals"], resources: localizedStrings),
    .target(name: "Learning", dependencies: ["Classifier", "Signals", "MessageModel"]),
    .target(
      name: "Store",
      dependencies: ["MessageModel", "Signals", "Classifier", "Decision"],
      resources: localizedStrings
    ),
    .target(
      name: "SpamWiseCore",
      dependencies: ["MessageModel", "Signals", "Classifier", "Decision", "Store", "Learning"],
      resources: localizedStrings
    ),
    .target(
      name: "MailIntegration",
      dependencies: [
        "SpamWiseCore",
        .product(name: "NIOCore", package: "swift-nio"),
        .product(name: "NIOIMAP", package: "swift-nio-imap"),
        .product(name: "NIOTransportServices", package: "swift-nio-transport-services")
      ],
      resources: localizedStrings
    ),
    .target(name: "Evaluation", dependencies: ["SpamWiseCore"], resources: localizedStrings),
    .executableTarget(
      name: "SpamWiseEval",
      dependencies: [
        "SpamWiseCore", "MailIntegration", "Evaluation",
        .product(name: "ArgumentParser", package: "swift-argument-parser")
      ],
      resources: localizedStrings,
      linkerSettings: embeddedInfoPlist("spamwise-eval")
    ),
    .executableTarget(
      name: "SpamWiseDaemon",
      dependencies: [
        "SpamWiseCore", "MailIntegration",
        .product(name: "ArgumentParser", package: "swift-argument-parser")
      ],
      resources: localizedStrings,
      linkerSettings: embeddedInfoPlist("spamwise-daemon")
    ),
    .testTarget(
      name: "SpamWiseCoreTests",
      dependencies: [
        "SpamWiseCore", "MailIntegration", "Evaluation", "Learning",
        .product(name: "NIOEmbedded", package: "swift-nio"),
        .product(name: "NIOIMAP", package: "swift-nio-imap")
      ],
      resources: [.copy("Fixtures")]
    )
  ],
  swiftLanguageModes: [.v6]
)

for target in package.targets where target.type != .system { target.swiftSettings = swiftSettings }
