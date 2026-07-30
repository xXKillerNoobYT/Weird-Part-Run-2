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
        // DuckDuckGo fork of GRDB bundles GRDB 7.x + SQLCipher 4.7.0 as a prebuilt
        // XCFramework. Chosen over plain groue/GRDB.swift because it keeps the same
        // `GRDB` product name — zero import-site changes across 300+ Swift files.
        // Closes CodeQL cleartext-storage-database alerts by encrypting the whole DB.
        //
        // Pinned exactly to 2.4.2-1 (rev 80cae244b20530bc3a4aae93ed2f211167ac08c0).
        // This tag imports string_h/Darwin for strcmp in StatementAuthorizer.swift and
        // builds GRDB against the bundled SQLCipher target. DDG v3.7.0 fails macOS CLI
        // `swift test` with "cannot find 'strcmp' in scope" in Swift 6 strict-module mode.
        // Package.resolved is committed to pin every environment to this exact revision.
        .package(url: "https://github.com/duckduckgo/GRDB.swift", exact: "2.4.2-1"),
        .package(url: "https://github.com/weichsel/ZIPFoundation", from: "0.9.19"),
    ],
    targets: [
        .target(
            name: "WiredPartCore",
            dependencies: [
                .product(name: "GRDB", package: "GRDB.swift"),
                .product(name: "ZIPFoundation", package: "ZIPFoundation"),
            ]
        ),
        .testTarget(
            name: "WiredPartCoreTests",
            dependencies: ["WiredPartCore"],
            resources: [
                .copy("Resources/parts-import-fixtures"),
            ]
        ),
    ]
)
