// swift-tools-version:6.0
// Pure game logic: no UIKit, no SpriteKit. Builds and tests on macOS, iOS and Linux.
import PackageDescription

let package = Package(
    name: "BalanceCore",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "BalanceCore", targets: ["BalanceCore"]),
    ],
    targets: [
        .target(name: "BalanceCore"),
        .testTarget(
            name: "BalanceCoreTests",
            dependencies: ["BalanceCore"],
            resources: [.copy("Fixtures")]
        ),
    ],
    swiftLanguageModes: [.v6]
)
