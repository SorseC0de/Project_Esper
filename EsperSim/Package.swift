// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "EsperSim",
    platforms: [.iOS(.v18), .macOS(.v14), .tvOS(.v18)],
    products: [
        .library(name: "EsperSim", targets: ["EsperSim"]),
    ],
    targets: [
        .target(name: "EsperSim", swiftSettings: [.swiftLanguageMode(.v5)]),
        .testTarget(name: "EsperSimTests", dependencies: ["EsperSim"], swiftSettings: [.swiftLanguageMode(.v5)]),
    ]
)
