// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "WiredPartIOS",
    platforms: [
        .macOS(.v14),
        .iOS(.v17),
    ],
    dependencies: [
        .package(path: "../core"),
    ],
    targets: [
        .executableTarget(
            name: "WiredPartIOS",
            dependencies: [
                .product(name: "WiredPartCore", package: "core"),
            ],
            path: "WiredPartIOS",
            resources: [
                .process("Assets.xcassets"),
            ]
        ),
        .testTarget(
            name: "WiredPartIOSTests",
            dependencies: ["WiredPartIOS"],
            path: "WiredPartIOSTests"
        ),
    ]
)
