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
        // the same `GRDB` product name — zero import-site changes across 300+ Swift files.
        // Closes CodeQL cleartext-storage-database alerts by encrypting the whole DB.
        //
        // Pinned exactly to 2.4.2-1: this DDG SQLCipher tag imports string_h/Darwin for
        // strcmp in StatementAuthorizer.swift and still builds GRDB against the bundled
        // SQLCipher target. Later DDG v3.7.0 still fails macOS CLI `swift test` with
        // "cannot find 'strcmp' in scope". Package.resolved is committed to keep every
        // environment on this exact revision.
        .package(url: "https://github.com/duckduckgo/GRDB.swift", exact: "2.4.2-1"),
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
