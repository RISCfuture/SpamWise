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
let package = Package(
  name: "SpamWiseCore",
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
      revision: "0262e1a766c461a4268dcec656eca95dd74cebf8"
    ),
    .package(url: "https://github.com/apple/swift-argument-parser.git", exact: "1.8.2"),
    .package(url: "https://github.com/apple/swift-nio.git", exact: "2.103.0"),
    .package(url: "https://github.com/apple/swift-nio-imap.git", exact: "0.4.0"),
    .package(url: "https://github.com/apple/swift-nio-transport-services.git", exact: "1.28.0")
  ],
  targets: [
    .target(name: "MessageModel", resources: [.copy("Resources/public_suffix_list.dat")]),
    .systemLibrary(name: "CResolver"),
    .target(name: "Signals", dependencies: ["MessageModel", "CResolver"]),
    .target(
      name: "Classifier",
      dependencies: [
        "MessageModel", "Signals",
        .product(name: "ClaudeForFoundationModels", package: "ClaudeForFoundationModels")
      ]
    ),
    .target(name: "Decision", dependencies: ["Classifier", "Signals"]),
    .target(name: "Learning", dependencies: ["Classifier", "Signals", "MessageModel"]),
    .target(name: "Store", dependencies: ["MessageModel", "Signals", "Classifier", "Decision"]),
    .target(
      name: "SpamWiseCore",
      dependencies: ["MessageModel", "Signals", "Classifier", "Decision", "Store", "Learning"]
    ),
    .target(
      name: "MailIntegration",
      dependencies: [
        "SpamWiseCore",
        .product(name: "NIOCore", package: "swift-nio"),
        .product(name: "NIOIMAP", package: "swift-nio-imap"),
        .product(name: "NIOTransportServices", package: "swift-nio-transport-services")
      ]
    ),
    .target(name: "Evaluation", dependencies: ["SpamWiseCore"]),
    .executableTarget(
      name: "SpamWiseEval",
      dependencies: [
        "SpamWiseCore", "MailIntegration", "Evaluation",
        .product(name: "ArgumentParser", package: "swift-argument-parser")
      ]
    ),
    .executableTarget(name: "SpamWiseDaemon", dependencies: ["SpamWiseCore", "MailIntegration"]),
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
