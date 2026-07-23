// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "RoadSketch",
    platforms: [
        .iOS(.v17),
        .macOS(.v14),
    ],
    products: [
        .library(name: "RoadSketchCore", targets: ["RoadSketchCore"]),
    ],
    targets: [
        .target(name: "RoadSketchCore"),
        .testTarget(
            name: "RoadSketchCoreTests",
            dependencies: ["RoadSketchCore"]
        ),
    ]
)
