// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "Cellar",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "CellarCore", targets: ["CellarCore"]),
    ],
    targets: [
        .target(name: "CellarCore"),
        .testTarget(name: "CellarCoreTests", dependencies: ["CellarCore"]),
    ]
)
