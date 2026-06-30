import XCTest

final class IOSPeerBrowserRegressionTests: XCTestCase {
    func testPeerRowsDoNotDispatchGlobalSyncAsRowLevelAction() throws {
        let source = try Self.readSyncSource(named: "IOSPeerBrowser.swift")

        XCTAssertFalse(
            source.contains("Button(\"Sync\")"),
            "A row-level Sync button must not dispatch the global syncNow() path; that can sync every peer/server while implying only the selected row is affected."
        )
        XCTAssertTrue(
            source.contains("Label(\"Sync All Devices\", systemImage: \"arrow.triangle.2.circlepath\")"),
            "The remaining global sync action should be labeled as Sync All Devices so users understand it can touch every peer/server."
        )
        XCTAssertTrue(
            source.contains("Task { await syncManager.syncNow() }"),
            "IOSPeerBrowser should still expose a manual global sync action, but not as a per-peer row control."
        )
        XCTAssertEqual(
            source.components(separatedBy: "syncManager.syncNow()").count - 1,
            1,
            "IOSPeerBrowser should route syncNow() through one clearly labeled global action, not through any peer-row action."
        )
        XCTAssertTrue(
            source.contains(".disabled(syncManager.syncStatus == .syncing)"),
            "The global Sync All Devices action should be disabled while a sync is already running."
        )
    }

    private static func readSyncSource(
        named name: String,
        file: StaticString = #filePath
    ) throws -> String {
        let testFileURL = URL(fileURLWithPath: "\(file)")
        let projectRoot = testFileURL
            .deletingLastPathComponent() // Weird Parts IOSTests
            .deletingLastPathComponent() // Weird Parts IOS
        let sourceURL = projectRoot
            .appendingPathComponent("Weird Parts IOS")
            .appendingPathComponent("Sync")
            .appendingPathComponent(name)
        return try String(contentsOf: sourceURL, encoding: .utf8)
    }
}
