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
        // Pinned to 3.7.0: earlier releases (including 3.0.0) shipped GRDB source that
        // references C stdlib functions (strcmp) without an explicit `import Darwin` guard
        // on macOS.  In Swift 6 strict-module mode only the explicitly-imported C module
        // (CSQLite) is in scope; Darwin is no longer implicitly available, so the build
        // fails with "cannot find 'strcmp' in scope" in StatementAuthorizer.swift.
        // 3.7.0 carries the necessary `#if os(Linux) import Glibc` guard which is
        // sufficient on Linux; macOS builds rely on the Darwin module being transitively
        // available through CSQLite, which works with the 3.7.0 sources.
        // Package.resolved is committed to keep every environment on this exact revision.
        .package(url: "https://github.com/duckduckgo/GRDB.swift", from: "3.7.0"),
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
