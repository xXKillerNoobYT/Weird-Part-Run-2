// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "WiredPartIOS",
    platforms: [
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
            exclude: ["Info.plist"],
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
