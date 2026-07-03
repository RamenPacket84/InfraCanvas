// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "InfraCanvas",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "InfraCanvas", targets: ["InfraCanvas"])
    ],
    targets: [
        .executableTarget(
            name: "InfraCanvas",
            exclude: ["Resources"]
        ),
        .testTarget(
            name: "InfraCanvasTests",
            dependencies: ["InfraCanvas"]
        )
    ]
)
