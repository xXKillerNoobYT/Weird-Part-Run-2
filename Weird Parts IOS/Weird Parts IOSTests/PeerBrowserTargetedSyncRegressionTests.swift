import XCTest

final class PeerBrowserTargetedSyncRegressionTests: XCTestCase {
    func testRowLevelPeerSyncTargetsSelectedPeerInsteadOfGlobalSyncNow() throws {
        let source = try Self.readPeerBrowserSource()

        XCTAssertTrue(
            source.contains("syncManager.syncWithPeer(peerDeviceId: peer.id)"),
            "Each peer row's Sync button must pass the selected peer ID into IOSSyncManager."
        )
        XCTAssertFalse(
            source.contains("Task { await syncManager.syncNow() }"),
            "A row-level Sync button must not dispatch the global syncNow fan-out path."
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
        guard let nameRange = source.range(of: "func \(methodName)(peerDeviceId: String) async") else {
            throw XCTSkip("Expected method \(methodName)(peerDeviceId: String) async in source")
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
