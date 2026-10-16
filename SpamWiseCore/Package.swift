// swift-tools-version: 6.4
import PackageDescription
let package = Package(
    name: "SpamWiseCore",
    platforms: [.macOS("27.0")],
    products: [.library(name: "SpamWiseCore", targets: ["SpamWiseCore"]),
               .executable(name: "spamwise-eval", targets: ["SpamWiseEval"])],
    targets: [
        .target(name: "MessageModel", resources: [.copy("Resources/public_suffix_list.dat")]),
        .target(name: "Signals", dependencies: ["MessageModel"]),
        .target(name: "Classifier", dependencies: ["MessageModel", "Signals"]),
        .target(name: "Decision", dependencies: ["Classifier"]),
        .target(name: "Store", dependencies: ["MessageModel", "Signals", "Classifier", "Decision"]),
        .target(name: "SpamWiseCore", dependencies: ["MessageModel", "Signals", "Classifier", "Decision", "Store"]),
        .executableTarget(name: "SpamWiseEval", dependencies: ["SpamWiseCore"]),
        .testTarget(name: "SpamWiseCoreTests", dependencies: ["SpamWiseCore"], resources: [.copy("Fixtures")])
    ],
    swiftLanguageModes: [.v6]
)
