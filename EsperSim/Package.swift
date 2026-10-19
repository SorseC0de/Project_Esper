// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "EsperSim",
    platforms: [.iOS(.v18), .macOS(.v14), .tvOS(.v18)],
    products: [
        .library(name: "EsperSim", targets: ["EsperSim"]),
    ],
    targets: [
        // The drinks (`Greateraid.swift`) sit beside this file, out of Sources, to be easy to find and edit.
        .target(name: "EsperSim", path: ".", sources: ["Sources/EsperSim", "Greateraid.swift"],
                swiftSettings: [.swiftLanguageMode(.v5)]),
        .testTarget(name: "EsperSimTests", dependencies: ["EsperSim"], path: "Tests/EsperSimTests",
                    swiftSettings: [.swiftLanguageMode(.v5)]),
    ]
)
