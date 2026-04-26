// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "WiredPartCore",
    platforms: [
        .macOS(.v14),
        .iOS(.v17),
    ],
    products: [
        .library(name: "WiredPartCore", targets: ["WiredPartCore"]),
    ],
    dependencies: [
        // DuckDuckGo fork bundles GRDB 7.4.1 + SQLCipher 4.7.0 as a prebuilt XCFramework.
        // Chosen over plain groue/GRDB.swift + separate sqlcipher-swift because it keeps
        // the same `GRDB` product name — smallest possible diff to existing import sites.
        // Closes CodeQL cleartext-storage-database alerts by encrypting the whole DB.
        .package(url: "https://github.com/duckduckgo/GRDB.swift", from: "3.0.0"),
    ],
    targets: [
        .target(
            name: "WiredPartCore",
            dependencies: [
                .product(name: "GRDB", package: "GRDB.swift"),
            ]
        ),
        .testTarget(
            name: "WiredPartCoreTests",
            dependencies: ["WiredPartCore"]
        ),
    ]
)
