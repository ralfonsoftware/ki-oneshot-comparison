// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "EnergyCore",
    defaultLocalization: "en",
    platforms: [.iOS(.v26), .macOS(.v26)],
    products: [
        .library(name: "EnergyCore", targets: ["EnergyCore"]),
    ],
    targets: [
        .target(name: "EnergyCore"),
        .testTarget(name: "EnergyCoreTests", dependencies: ["EnergyCore"]),
    ]
)
