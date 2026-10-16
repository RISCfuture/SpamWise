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
    )
  ],
  targets: [
    .target(name: "MessageModel", resources: [.copy("Resources/public_suffix_list.dat")]),
    .target(name: "Signals", dependencies: ["MessageModel"]),
    .target(
      name: "Classifier",
      dependencies: [
        "MessageModel", "Signals",
        .product(name: "ClaudeForFoundationModels", package: "ClaudeForFoundationModels")
      ]
    ),
    .target(name: "Decision", dependencies: ["Classifier"]),
    .target(name: "Learning", dependencies: ["Classifier", "Signals", "MessageModel"]),
    .target(name: "Store", dependencies: ["MessageModel", "Signals", "Classifier", "Decision"]),
    .target(
      name: "SpamWiseCore",
      dependencies: ["MessageModel", "Signals", "Classifier", "Decision", "Store", "Learning"]
    ),
    .target(name: "MailIntegration", dependencies: ["SpamWiseCore"]),
    .target(name: "Evaluation", dependencies: ["SpamWiseCore"]),
    .executableTarget(
      name: "SpamWiseEval",
      dependencies: ["SpamWiseCore", "MailIntegration", "Evaluation"]
    ),
    .executableTarget(name: "SpamWiseDaemon", dependencies: ["SpamWiseCore", "MailIntegration"]),
    .testTarget(
      name: "SpamWiseCoreTests",
      dependencies: ["SpamWiseCore", "MailIntegration", "Evaluation", "Learning"],
      resources: [.copy("Fixtures")]
    )
  ],
  swiftLanguageModes: [.v6]
)

for target in package.targets { target.swiftSettings = swiftSettings }
