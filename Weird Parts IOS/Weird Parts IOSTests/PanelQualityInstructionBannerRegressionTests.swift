import GRDB
import WiredPartCore
import XCTest
@testable import Weird_Parts

final class PanelQualityInstructionBannerRegressionTests: XCTestCase {

    func testUITestingCriticalCostConflictResolvesEitherSideAgainstItsLiveFixtureRow() throws {
        func seededDatabase() throws -> AppDatabase {
            let db = try AppDatabase.openInMemoryDatabase()
            try AppCore.seedUITestingFixtures(db: db, authService: AuthService(db: db))
            return db
        }

        let localDB = try seededDatabase()
        let localConflict = try XCTUnwrap(
            ConflictResolver.getUnreviewedConflicts(db: localDB)
                .first { $0.fieldName == "company_cost_price" }
        )
        let localRecordId = try XCTUnwrap(Int64(localConflict.recordId))
        try ConflictResolver.applyConflictResolution(db: localDB, conflict: localConflict, choice: .keepLocal)
        let localCost = try localDB.writer.read { dbConn in
            try Double.fetchOne(dbConn, sql: "SELECT company_cost_price FROM parts WHERE id = ?", arguments: [localRecordId])
        }
        XCTAssertEqual(localCost, 17.45)
        XCTAssertFalse(try ConflictResolver.getUnreviewedConflicts(db: localDB).contains { $0.id == localConflict.id })

        let remoteDB = try seededDatabase()
        let remoteConflict = try XCTUnwrap(
            ConflictResolver.getUnreviewedConflicts(db: remoteDB)
                .first { $0.fieldName == "company_cost_price" }
        )
        let remoteRecordId = try XCTUnwrap(Int64(remoteConflict.recordId))
        try ConflictResolver.applyConflictResolution(db: remoteDB, conflict: remoteConflict, choice: .keepRemote)
        let remoteCost = try remoteDB.writer.read { dbConn in
            try Double.fetchOne(dbConn, sql: "SELECT company_cost_price FROM parts WHERE id = ?", arguments: [remoteRecordId])
        }
        XCTAssertEqual(remoteCost, 21.90)
        XCTAssertFalse(try ConflictResolver.getUnreviewedConflicts(db: remoteDB).contains { $0.id == remoteConflict.id })
    }

    @MainActor
    func testAcceptAllLeavesHumanRequiredConflictsPendingInDatabase() throws {
        let db = try AppDatabase.openInMemoryDatabase()
        let manager = IOSSyncManager()
        manager.configure(db: db, settingsService: SettingsService(db: db))

        try insertConflict(db: db, fieldName: "name", localValue: "Local", remoteValue: "Remote")
        try insertConflict(db: db, fieldName: "description", localValue: "Local notes", remoteValue: "Remote notes")
        try insertConflict(db: db, fieldName: "company_markup_percent", localValue: "18", remoteValue: "24")

        XCTAssertTrue(manager.markAutoResolvableConflictsReviewed())

        let pending = try ConflictResolver.getUnreviewedConflicts(db: db)
        XCTAssertEqual(Set(pending.map(\.fieldName)), ["description", "company_markup_percent"])
        XCTAssertEqual(manager.unreviewedConflictCount, 2)
    }

    @MainActor
    func testEveryPersistedCriticalPartsFieldClassifiesCriticalAndResolvesEitherSide() throws {
        let fields = [
            "company_cost_price",
            "company_markup_percent",
            "min_stock_level",
            "target_stock_level",
            "max_stock_level",
        ]

        for field in fields {
            for keepLocal in [true, false] {
                let db = try AppDatabase.openInMemoryDatabase()
                try AppCore.seedUITestingFixtures(db: db, authService: AuthService(db: db))
                let recordId = try XCTUnwrap(db.writer.read { dbConn in
                    try Int64.fetchOne(dbConn, sql: "SELECT id FROM parts ORDER BY id LIMIT 1")
                })
                // Conflict rows are recorded after LWW has already written the
                // winner. Seed that invariant so keepRemote proves the no-op
                // winner path while keepLocal proves the write-back path.
                try db.writer.write { dbConn in
                    try dbConn.execute(
                        sql: "UPDATE parts SET [\(field)] = 22 WHERE id = ?",
                        arguments: [recordId]
                    )
                }
                let insertedConflictId = try insertConflict(
                    db: db,
                    recordId: recordId,
                    fieldName: field,
                    localValue: "11",
                    remoteValue: "22"
                )
                let conflict = try XCTUnwrap(
                    ConflictResolver.getUnreviewedConflicts(db: db).first { $0.id == insertedConflictId }
                )
                guard case .critical = SyncConflictClassifier.classify(conflict) else {
                    return XCTFail("Expected persisted Parts field \(field) to require an explicit critical choice")
                }

                let manager = IOSSyncManager()
                manager.configure(db: db, settingsService: SettingsService(db: db))
                XCTAssertTrue(
                    manager.resolveConflict(conflict, keepLocal: keepLocal),
                    "Expected \(field) to retain the \(keepLocal ? "local" : "remote") action path"
                )

                let storedValue = try db.writer.read { dbConn in
                    try Double.fetchOne(
                        dbConn,
                        sql: "SELECT [\(field)] FROM parts WHERE id = ?",
                        arguments: [recordId]
                    )
                }
                XCTAssertEqual(storedValue, keepLocal ? 11 : 22, "Wrong chosen value persisted for \(field)")
                XCTAssertFalse(try ConflictResolver.getUnreviewedConflicts(db: db).contains { $0.id == conflict.id })
            }
        }
    }


    @discardableResult
    private func insertConflict(
        db: AppDatabase,
        recordId: Int64 = 1,
        fieldName: String,
        localValue: String,
        remoteValue: String
    ) throws -> Int64 {
        try db.writer.write { dbConn in
            try dbConn.execute(
                sql: """
                    INSERT INTO _conflict_log (
                        table_name, record_id, field_name, local_value, remote_value,
                        winner, local_device, remote_device, local_ts, remote_ts, resolved_at
                    ) VALUES (?, ?, ?, ?, ?, 'remote', 'local-device', 'remote-device', ?, ?, ?)
                    """,
                arguments: [
                    "parts", String(recordId), fieldName, localValue, remoteValue,
                    "2026-07-14T09:00:00Z", "2026-07-14T10:00:00Z", "2026-07-14T10:00:00Z",
                ]
            )
            return dbConn.lastInsertedRowID
        }
    }

}
