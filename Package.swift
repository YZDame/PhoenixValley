// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "PhoenixValley",
    platforms: [
        .iOS(.v17),
        .macOS(.v14),
    ],
    products: [
        .library(name: "PhoenixValleyCore", targets: ["PhoenixValleyCore"]),
    ],
    targets: [
        .target(name: "PhoenixValleyCore"),
        .testTarget(
            name: "PhoenixValleyCoreTests",
            dependencies: ["PhoenixValleyCore"]
        ),
    ]
)
