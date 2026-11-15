// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "EnergyCore",
    platforms: [
        .iOS(.v16),
        .macOS(.v13)
    ],
    products: [
        .library(name: "EnergyCore", targets: ["EnergyCore"])
    ],
    targets: [
        .target(name: "EnergyCore"),
        .testTarget(name: "EnergyCoreTests", dependencies: ["EnergyCore"])
    ]
)
