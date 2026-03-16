// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "WiredPartMac",
    platforms: [
        .macOS(.v14),
    ],
    dependencies: [
        .package(path: "../core"),
    ],
    targets: [
        .executableTarget(
            name: "WiredPart",
            dependencies: [
                .product(name: "WiredPartCore", package: "core"),
            ],
            path: "WiredPart",
            exclude: ["Info.plist"],
            resources: [
                .copy("Assets.xcassets"),
            ]
        ),
        .testTarget(
            name: "WiredPartTests",
            dependencies: ["WiredPart"],
            path: "WiredPartTests"
        ),
    ]
)
