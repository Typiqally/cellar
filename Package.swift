// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "Cellar",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "CellarCore", targets: ["CellarCore"]),
        .executable(name: "cellar", targets: ["CellarCLI"]),
    ],
    targets: [
        .systemLibrary(name: "CSQLite"),
        .target(name: "CellarCore", dependencies: ["CSQLite"]),
        .executableTarget(name: "CellarCLI", dependencies: ["CellarCore"]),
        .testTarget(name: "CellarCoreTests", dependencies: ["CellarCore"]),
    ]
)
