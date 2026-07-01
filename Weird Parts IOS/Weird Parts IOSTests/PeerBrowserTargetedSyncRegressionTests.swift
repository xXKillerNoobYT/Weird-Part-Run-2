import XCTest

final class PeerBrowserTargetedSyncRegressionTests: XCTestCase {
    func testRowLevelPeerSyncTargetsSelectedPeerInsteadOfGlobalSyncNow() throws {
        let source = try Self.readPeerBrowserSource()

        XCTAssertTrue(
            source.contains("if peer.isManuallySyncable"),
            "The row-level Sync button should be gated by an explicit peer sync capability, not display state strings."
        )
        XCTAssertTrue(
            source.contains("syncManager.syncWithPeer(peerDeviceId: peer.id)"),
            "Each peer row's Sync button must pass the selected peer ID into IOSSyncManager."
        )
        XCTAssertFalse(
            source.contains("Task { await syncManager.syncNow() }"),
            "A row-level Sync button must not dispatch the global syncNow fan-out path."
        )
        XCTAssertFalse(
            source.contains("peer.state == \"found\" || peer.state == \"multipeer\" || peer.state == \"lan\""),
            "Unconnected Multipeer rows must not expose an impossible Sync button."
        )
        XCTAssertTrue(
            source.contains("if peer.isManuallySyncable") && source.contains("Text(\"Waiting\")"),
            "Connected peers and addressable LAN/found rows should stay syncable while unconnected Multipeer rows show a waiting state."
        )
    }

    func testIOSSyncManagerProvidesSelectedPeerSyncWithoutGlobalFanOut() throws {
        let source = try Self.readSyncManagerSource()

        XCTAssertTrue(
            source.contains("func syncWithPeer(peerDeviceId: String) async"),
            "IOSSyncManager should expose an explicit selected-peer sync entry point for row-level UI actions."
        )
        XCTAssertTrue(
            source.contains("pm.syncWithPeer(deviceId: peerDeviceId)"),
            "The selected-peer entry point should call PeerManager's device-id selector."
        )
        XCTAssertTrue(
            source.contains("errorMessage = \"\\(failureReason) for \\(peerLabel)\""),
            "Selected-peer failures should include the chosen device ID so row-level sync errors are diagnosable."
        )

        let selectedPeerMethod = try Self.methodBody(named: "syncWithPeer", in: source)
        XCTAssertFalse(
            selectedPeerMethod.contains("syncWithAllPeers()"),
            "Selected-peer sync must not call syncWithAllPeers()."
        )
        XCTAssertFalse(
            selectedPeerMethod.contains("manualSync("),
            "Selected-peer sync must not trigger the configured LAN-server sync path."
        )
    }

    func testPeerBrowserOnlyShowsManualSyncForSyncablePeers() throws {
        let source = try Self.readPeerBrowserSource()

        XCTAssertTrue(
            source.contains("if peer.isManuallySyncable"),
            "The row-level Sync button should be gated by explicit sync capability, not by display state strings."
        )
        XCTAssertFalse(
            source.contains("peer.state == \"found\" || peer.state == \"multipeer\" || peer.state == \"lan\""),
            "Unconnected Multipeer rows must not be grouped with LAN/addressable rows as syncable."
        )
        let syncManagerSource = try Self.readSyncManagerSource()
        XCTAssertTrue(
            syncManagerSource.contains("let isManuallySyncable: Bool"),
            "PeerInfo should carry the capability used by the view instead of deriving behavior from presentation state."
        )
        XCTAssertTrue(
            syncManagerSource.contains("isManuallySyncablePeer(") &&
                syncManagerSource.contains("if transport == \"multipeer\"") &&
                syncManagerSource.contains("return multipeerState == \"connected\"") &&
                syncManagerSource.contains("return transport == \"lan\" && address != nil"),
            "PeerInfo syncability should be derived from transport, Multipeer connection state, and endpoint availability."
        )
        XCTAssertTrue(
            syncManagerSource.contains("isManuallySyncable: Self.isManuallySyncablePeer("),
            "PeerInfo construction should store a capability boolean for the view instead of making the view switch on presentation state."
        )
    }

    private static func readPeerBrowserSource(
        file: StaticString = #filePath
    ) throws -> String {
        let projectRoot = URL(fileURLWithPath: "\(file)")
            .deletingLastPathComponent() // Weird Parts IOSTests
            .deletingLastPathComponent() // Weird Parts IOS
        let sourceURL = projectRoot
            .appendingPathComponent("Weird Parts IOS")
            .appendingPathComponent("Sync")
            .appendingPathComponent("IOSPeerBrowser.swift")
        return try String(contentsOf: sourceURL, encoding: .utf8)
    }

    private static func readSyncManagerSource(
        file: StaticString = #filePath
    ) throws -> String {
        let projectRoot = URL(fileURLWithPath: "\(file)")
            .deletingLastPathComponent() // Weird Parts IOSTests
            .deletingLastPathComponent() // Weird Parts IOS
        let sourceURL = projectRoot
            .appendingPathComponent("Weird Parts IOS")
            .appendingPathComponent("Sync")
            .appendingPathComponent("IOSSyncManager.swift")
        return try String(contentsOf: sourceURL, encoding: .utf8)
    }

    private static func methodBody(named methodName: String, in source: String) throws -> String {
        guard let nameRange = source.range(of: "func \(methodName)(") else {
            throw XCTSkip("Expected method \(methodName) in source")
        }
        guard let openBrace = source[nameRange.upperBound...].firstIndex(of: "{") else {
            throw XCTSkip("Expected opening brace for \(methodName)")
        }

        var depth = 0
        var index = openBrace
        while index < source.endIndex {
            let char = source[index]
            if char == "{" { depth += 1 }
            if char == "}" { depth -= 1 }
            let next = source.index(after: index)
            if depth == 0 {
                return String(source[openBrace..<next])
            }
            index = next
        }

        throw XCTSkip("Expected closing brace for \(methodName)")
    }
}
