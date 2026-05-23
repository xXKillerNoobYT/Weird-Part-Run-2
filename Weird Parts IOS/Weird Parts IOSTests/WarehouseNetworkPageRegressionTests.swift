import XCTest

final class WarehouseNetworkPageRegressionTests: XCTestCase {
    func testConnectedDevicesSectionUsesPeerBrowserInsteadOfStaticNotEnabledCopy() throws {
        let source = try Self.readWarehouseNetworkPageSource()

        XCTAssertTrue(
            source.contains("case peerBrowser"),
            "Warehouse network page should route connected-device discovery to the shared peer browser instead of remaining a static placeholder."
        )
        XCTAssertTrue(
            source.contains("IOSPeerBrowser()"),
            "Connected Devices should launch the existing peer browser so the page has real discovery behavior."
        )
        XCTAssertTrue(
            source.contains("syncManager.discoveredPeers.count"),
            "The page should summarize live discovered-peer state from IOSSyncManager."
        )
        XCTAssertTrue(
            source.contains("syncManager.startPeerDiscovery()"),
            "The page should expose a Scan button backed by the existing discovery manager."
        )
        XCTAssertFalse(
            source.contains("Device network discovery is not enabled yet"),
            "The beta-facing page must not show stale 'not enabled yet' placeholder copy now that IOSPeerBrowser exists."
        )
    }

    private static func readWarehouseNetworkPageSource(
        file: StaticString = #filePath
    ) throws -> String {
        let testFileURL = URL(fileURLWithPath: "\(file)")
        let projectRoot = testFileURL
            .deletingLastPathComponent() // Weird Parts IOSTests
            .deletingLastPathComponent() // Weird Parts IOS
        let sourceURL = projectRoot
            .appendingPathComponent("Weird Parts IOS")
            .appendingPathComponent("Features")
            .appendingPathComponent("Warehouse")
            .appendingPathComponent("IOSWarehouseNetworkPage.swift")
        return try String(contentsOf: sourceURL, encoding: .utf8)
    }
}
