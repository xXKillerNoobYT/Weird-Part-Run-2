import Testing
import Foundation
@testable import WiredPartCore

@Suite("Text Predictor Tests")
struct TextPredictorTests {

    // MARK: - Entity Lookup Tests

    @Test("Entity lookup returns matching suppliers")
    func testEntityLookupSupplier() async throws {
        let db = try AppDatabase.openInMemoryDatabase()

        // Insert test suppliers
        try await db.writer.write { dbConnection in
            try dbConnection.execute(
                sql: "INSERT INTO suppliers (id, name) VALUES (1, 'Acme Electrical Supply')"
            )
            try dbConnection.execute(
                sql: "INSERT INTO suppliers (id, name) VALUES (2, 'Best Wire Co')"
            )
        }

        let predictor = TextPredictor(db: db)
        let results = await predictor.predict(
            partialText: "Acme",
            fieldType: "supplier_name",
            entityType: .supplier
        )

        #expect(!results.isEmpty)
        #expect(results.first?.text == "Acme Electrical Supply")
        #expect(results.first?.source == .entityLookup)
    }

    // MARK: - History Tests

    @Test("Record and retrieve prediction history")
    func testPhraseHistory() async throws {
        let db = try AppDatabase.openInMemoryDatabase()

        // Insert a user
        try await db.writer.write { dbConnection in
            try dbConnection.execute(
                sql: "INSERT INTO users (id, display_name, pin_hash) VALUES (1, 'Test User', 'hash')"
            )
        }

        let predictor = TextPredictor(db: db)

        // Record some entries
        try await predictor.recordEntry(text: "Installed new panel", fieldType: "job_notes", userId: 1)
        try await predictor.recordEntry(text: "Installed conduit run", fieldType: "job_notes", userId: 1)
        try await predictor.recordEntry(text: "Replaced breaker", fieldType: "job_notes", userId: 1)

        // Predict should find history entries
        let results = await predictor.predict(
            partialText: "Inst",
            fieldType: "job_notes",
            userId: 1
        )

        let historyResults = results.filter { $0.source == .history }
        #expect(!historyResults.isEmpty)
    }

    @Test("Frequency increases with repeated entries")
    func testFrequencyTracking() async throws {
        let db = try AppDatabase.openInMemoryDatabase()

        try await db.writer.write { dbConnection in
            try dbConnection.execute(
                sql: "INSERT INTO users (id, display_name, pin_hash) VALUES (1, 'Test', 'hash')"
            )
        }

        let predictor = TextPredictor(db: db)

        // Record the same entry multiple times
        for _ in 0..<5 {
            try await predictor.recordEntry(text: "Rough-in complete", fieldType: "job_notes", userId: 1)
        }

        // Verify frequency is 5
        let frequency: Int? = try await db.writer.read { dbConnection in
            try Int.fetchOne(
                dbConnection,
                sql: "SELECT frequency FROM _text_history WHERE text = 'Rough-in complete'"
            )
        }

        #expect(frequency == 5)
    }

    // MARK: - Template Expansion Tests

    @Test("Template expansion for job notes")
    func testTemplateExpansion() async throws {
        let db = try AppDatabase.openInMemoryDatabase()
        let predictor = TextPredictor(db: db)

        let results = await predictor.predict(
            partialText: "inst",
            fieldType: "job_notes"
        )

        let templateResults = results.filter { $0.source == .template }
        #expect(!templateResults.isEmpty)
        #expect(templateResults.first?.text == "Installed")
    }

    // MARK: - Clear History Tests

    @Test("Clear history removes all entries for user")
    func testClearHistory() async throws {
        let db = try AppDatabase.openInMemoryDatabase()

        try await db.writer.write { dbConnection in
            try dbConnection.execute(
                sql: "INSERT INTO users (id, display_name, pin_hash) VALUES (1, 'Test', 'hash')"
            )
        }

        let predictor = TextPredictor(db: db)

        try await predictor.recordEntry(text: "Entry 1", fieldType: "notes", userId: 1)
        try await predictor.recordEntry(text: "Entry 2", fieldType: "notes", userId: 1)

        try await predictor.clearHistory(userId: 1)

        let count: Int = try await db.writer.read { dbConnection in
            try Int.fetchOne(
                dbConnection,
                sql: "SELECT COUNT(*) FROM _text_history WHERE user_id = 1"
            ) ?? 0
        }

        #expect(count == 0)
    }

    // MARK: - Empty Input Tests

    @Test("Empty partial text returns empty predictions")
    func testEmptyInput() async throws {
        let db = try AppDatabase.openInMemoryDatabase()
        let predictor = TextPredictor(db: db)

        let results = await predictor.predict(
            partialText: "",
            fieldType: "job_notes"
        )

        #expect(results.isEmpty)
    }

    // MARK: - Prediction Entity Type Tests

    @Test("All prediction entity types have valid table/column pairs")
    func testEntityTypeTableMapping() {
        for entityType in PredictionEntityType.allCases {
            let (table, column) = entityType.tableAndColumn
            #expect(!table.isEmpty, "\(entityType) should have a table name")
            #expect(!column.isEmpty, "\(entityType) should have a column name")
        }
    }
}
