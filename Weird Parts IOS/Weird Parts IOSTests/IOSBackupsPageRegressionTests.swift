import XCTest

final class IOSBackupsPageRegressionTests: XCTestCase {

    // MARK: - WAL/SHM sidecar integrity

    func testWALSidecarCopyUsesThrowingTryNotSilentTryQuestion() throws {
        let source = try Self.readBackupsPageSource()

        // The WAL copy must use `try` (not `try?`) so a failure propagates to
        // the enclosing do/catch and surfaces as a user-visible error.
        XCTAssertFalse(
            source.contains("try? FileManager.default.copyItem") &&
            source.contains("-wal"),
            "WAL sidecar copy must not use `try?` — failures must be propagated as backup errors, not silently swallowed."
        )
    }

    func testSHMSidecarCopyUsesThrowingTryNotSilentTryQuestion() throws {
        let source = try Self.readBackupsPageSource()

        // The SHM copy must use `try` (not `try?`) so a failure propagates to
        // the enclosing do/catch and surfaces as a user-visible error.
        XCTAssertFalse(
            source.contains("try? FileManager.default.copyItem") &&
            source.contains("-shm"),
            "SHM sidecar copy must not use `try?` — failures must be propagated as backup errors, not silently swallowed."
        )
    }

    func testBackupSuccessIsGuardedBySidecarCopies() throws {
        let source = try Self.readBackupsPageSource()

        // backupSuccess = true must appear AFTER the WAL and SHM copy blocks,
        // confirming that success is only reported once all files are copied.
        guard
            let walRange  = source.range(of: "walPath"),
            let shmRange  = source.range(of: "shmPath"),
            let succRange = source.range(of: "backupSuccess = true")
        else {
            XCTFail("Expected walPath, shmPath, and backupSuccess = true to all be present in IOSBackupsPage.")
            return
        }

        XCTAssertTrue(
            walRange.upperBound < succRange.lowerBound,
            "WAL copy block must appear before `backupSuccess = true` so success is only reported after WAL is copied."
        )
        XCTAssertTrue(
            shmRange.upperBound < succRange.lowerBound,
            "SHM copy block must appear before `backupSuccess = true` so success is only reported after SHM is copied."
        )
    }

    // MARK: - Helpers

    private static func readBackupsPageSource(
        file: StaticString = #filePath
    ) throws -> String {
        let testFileURL = URL(fileURLWithPath: "\(file)")
        let projectRoot = testFileURL
            .deletingLastPathComponent() // Weird Parts IOSTests
            .deletingLastPathComponent() // Weird Parts IOS
        let sourceURL = projectRoot
            .appendingPathComponent("Weird Parts IOS")
            .appendingPathComponent("Features")
            .appendingPathComponent("Settings")
            .appendingPathComponent("IOSBackupsPage.swift")
        return try String(contentsOf: sourceURL, encoding: .utf8)
    }
}
