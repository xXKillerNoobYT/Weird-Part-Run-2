import XCTest

final class AppCoreMigrationRollbackRegressionTests: XCTestCase {
    func testProductionRollbackPathRetriesDatabaseOpenAfterSuccessfulRestore() throws {
        let source = try Self.readAppCoreSource()

        XCTAssertTrue(
            source.contains("let originalError = error"),
            "Rollback handling should retain the original migration/open failure for retry logging."
        )
        XCTAssertTrue(
            source.contains("try AppDatabase.restoreDatabase(from: backup, to: path)"),
            "The rollback path must restore the backup before retrying startup."
        )
        XCTAssertTrue(
            source.contains("try AppDatabase.migratePlaintextDBIfNeeded(atPath: path, keyHex: keyHex)"),
            "After restore, startup should retry plaintext migration so legacy backups can still open."
        )
        XCTAssertTrue(
            source.contains("database = try AppDatabase.openEncryptedDatabase(atPath: path, keyHex: keyHex)"),
            "After restore, startup should retry opening the restored encrypted database."
        )
        XCTAssertTrue(
            source.contains("throw retryError"),
            "If restore retry fails, startup should surface the retry failure instead of hiding it."
        )
    }

    private static func readAppCoreSource(file: StaticString = #filePath) throws -> String {
        let testFileURL = URL(fileURLWithPath: "\(file)")
        let projectRoot = testFileURL
            .deletingLastPathComponent() // Weird Parts IOSTests
            .deletingLastPathComponent() // Weird Parts IOS
        let sourceURL = projectRoot
            .appendingPathComponent("Weird Parts IOS")
            .appendingPathComponent("App")
            .appendingPathComponent("AppCore.swift")
        return try String(contentsOf: sourceURL, encoding: .utf8)
    }
}
