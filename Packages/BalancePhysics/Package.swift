// swift-tools-version:6.0
// SpriteKit layer shared by the game and LevelForge. Same constants, same body setup, same order.
import PackageDescription

let package = Package(
    name: "BalancePhysics",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "BalancePhysics", targets: ["BalancePhysics"]),
    ],
    dependencies: [
        .package(path: "../BalanceCore"),
    ],
    targets: [
        .target(name: "BalancePhysics", dependencies: ["BalanceCore"]),
        .testTarget(name: "BalancePhysicsTests", dependencies: ["BalancePhysics", "BalanceCore"]),
    ],
    swiftLanguageModes: [.v6]
)
