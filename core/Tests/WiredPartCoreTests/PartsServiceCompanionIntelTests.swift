import Foundation
import Testing
import GRDB
@testable import WiredPartCore

// File-private helper: seed a co_occurrence_pairs row with the full extended schema.
private func seedPair(
    _ env: E2ETestHelpers.TestEnvironment,
    catAId: Int64,
    catBId: Int64,
    points: Int = 200,
    isBlocked: Bool = false,
    rejectionCount: Int = 0
) throws -> Int64 {
    try env.db.writer.write { db in
        try db.execute(sql: """
            INSERT INTO co_occurrence_pairs
                (category_a_id, category_b_id, co_occurrence_count, total_jobs_a, total_jobs_b,
                 confidence, points, match_level, rejection_count, is_blocked, last_computed)
            VALUES (?, ?, 20, 20, 20, 0.5, ?, 'category', ?, ?, datetime('now'))
            """, arguments: [catAId, catBId, points, rejectionCount, isBlocked ? 1 : 0])
        return db.lastInsertedRowID
    }
}

@Suite("PartsService Companion Intelligence Tests")
struct PartsServiceCompanionIntelTests {

    // MARK: - applySkipPenalty

    @Test("applySkipPenalty reduces pair points by 50")
    func testApplySkipPenalty_reduces() throws {
        let env = try E2ETestHelpers.setUp()
        let catAId = try E2ETestHelpers.seedCategory(env, name: "SkipA")
        let catBId = try E2ETestHelpers.seedCategory(env, name: "SkipB")
        let pairId = try seedPair(env, catAId: catAId, catBId: catBId, points: 200)

        try env.parts.applySkipPenalty(pairId: pairId)

        let row = try env.db.writer.read { db in
            try Row.fetchOne(db, sql: "SELECT points FROM co_occurrence_pairs WHERE id = ?", arguments: [pairId])
        }
        let points: Int = try #require(row)["points"]
        #expect(points == 150)
    }

    @Test("applySkipPenalty clamps points to 0 when penalty exceeds remaining")
    func testApplySkipPenalty_clampsToZero() throws {
        let env = try E2ETestHelpers.setUp()
        let catAId = try E2ETestHelpers.seedCategory(env, name: "ClampA")
        let catBId = try E2ETestHelpers.seedCategory(env, name: "ClampB")
        let pairId = try seedPair(env, catAId: catAId, catBId: catBId, points: 10)

        try env.parts.applySkipPenalty(pairId: pairId)

        let row = try env.db.writer.read { db in
            try Row.fetchOne(db, sql: "SELECT points FROM co_occurrence_pairs WHERE id = ?", arguments: [pairId])
        }
        let points: Int = try #require(row)["points"]
        #expect(points == 0, "MAX(0, 10-50) must floor at 0, not go negative")
    }

    // MARK: - resetBlockedPair

    @Test("resetBlockedPair clears is_blocked flag and resets rejection_count")
    func testResetBlockedPair() throws {
        let env = try E2ETestHelpers.setUp()
        let catAId = try E2ETestHelpers.seedCategory(env, name: "BlockA")
        let catBId = try E2ETestHelpers.seedCategory(env, name: "BlockB")
        let pairId = try seedPair(env, catAId: catAId, catBId: catBId, isBlocked: true, rejectionCount: 5)

        try env.parts.resetBlockedPair(pairId: pairId)

        let row = try env.db.writer.read { db in
            try Row.fetchOne(db, sql: "SELECT is_blocked, rejection_count FROM co_occurrence_pairs WHERE id = ?", arguments: [pairId])
        }
        let r = try #require(row)
        let isBlocked: Int = r["is_blocked"]
        let rejectionCount: Int = r["rejection_count"]
        #expect(isBlocked == 0)
        #expect(rejectionCount == 0)
    }

    // MARK: - getCompanionSuggestionsForPart

    @Test("getCompanionSuggestionsForPart returns empty when no companion rules exist")
    func testGetCompanionSuggestionsEmpty() throws {
        let env = try E2ETestHelpers.setUp()
        let catId = try E2ETestHelpers.seedCategory(env, name: "SuggCat")
        let partId = try E2ETestHelpers.seedPart(env, name: "Sugg Part", categoryId: catId)

        let suggestions = try env.parts.getCompanionSuggestionsForPart(partId: partId)
        #expect(suggestions.isEmpty)
    }

    @Test("getCompanionSuggestionsForPart returns empty for unknown part ID")
    func testGetCompanionSuggestionsUnknownPart() throws {
        let env = try E2ETestHelpers.setUp()
        let suggestions = try env.parts.getCompanionSuggestionsForPart(partId: 99999)
        #expect(suggestions.isEmpty)
    }

    @Test("getCompanionSuggestionsForPart excludes suggestions from soft-deleted companion rules")
    func testGetCompanionSuggestions_excludesDeletedRule() throws {
        let env = try E2ETestHelpers.setUp()
        let catSrc = try E2ETestHelpers.seedCategory(env, name: "RuleSrcCat")
        let catTgt = try E2ETestHelpers.seedCategory(env, name: "RuleTgtCat")
        let sourcePart = try E2ETestHelpers.seedPart(env, name: "RuleSrcPart", categoryId: catSrc)
        let targetPart = try E2ETestHelpers.seedPart(env, name: "RuleTgtPart", categoryId: catTgt)
        _ = targetPart

        // Seed a rule that maps cat-src → cat-tgt, leaving it active. Regression:
        // `JOIN companion_rules cr ON cr.id = rs.rule_id AND cr.is_active = 1` was
        // missing `AND cr.deleted_at IS NULL`. A tombstoned rule (deleted_at set,
        // is_active possibly still 1 after soft-delete drift) would still feed
        // suggestions through the join.
        let ruleId: Int64 = try env.db.writer.write { db -> Int64 in
            try db.execute(sql: """
                INSERT INTO companion_rules (name, description, style_match, qty_mode, qty_ratio, is_active)
                VALUES ('SoftDel Rule', 'test', 'auto', 'sum', 1.0, 1)
                """)
            let rid = db.lastInsertedRowID
            try db.execute(sql: """
                INSERT INTO companion_rule_sources (rule_id, category_id) VALUES (?, ?)
                """, arguments: [rid, catSrc])
            try db.execute(sql: """
                INSERT INTO companion_rule_targets (rule_id, category_id) VALUES (?, ?)
                """, arguments: [rid, catTgt])
            return rid
        }

        // Baseline: active rule → suggestion surfaces
        let before = try env.parts.getCompanionSuggestionsForPart(partId: sourcePart)
        #expect(!before.isEmpty, "Active companion rule should produce at least one suggestion")

        // Soft-delete the rule (is_active left as 1 to simulate drift between the two flags)
        try env.db.writer.write { db in
            try db.execute(sql: "UPDATE companion_rules SET deleted_at = datetime('now') WHERE id = ?",
                           arguments: [ruleId])
        }

        let after = try env.parts.getCompanionSuggestionsForPart(partId: sourcePart)
        #expect(after.isEmpty,
                "Soft-deleted companion rule must not produce suggestions — JOIN must guard cr.deleted_at IS NULL")
    }

    // MARK: - recordCompanionFeedback

    @Test("recordCompanionFeedback upserts co_occurrence_pairs and logs to companion_feedback")
    func testRecordCompanionFeedback_upserts() throws {
        let env = try E2ETestHelpers.setUp()
        let catAId = try E2ETestHelpers.seedCategory(env, name: "FbkCatA")
        let catBId = try E2ETestHelpers.seedCategory(env, name: "FbkCatB")
        let sourcePartId = try E2ETestHelpers.seedPart(env, name: "Source Part", categoryId: catAId)
        let targetPartId = try E2ETestHelpers.seedPart(env, name: "Target Part", categoryId: catBId)
        _ = try seedPair(env, catAId: catAId, catBId: catBId, points: 100)

        try env.parts.recordCompanionFeedback(
            sourcePartId: sourcePartId,
            targetPartId: targetPartId,
            suggestedQty: 2,
            acceptedQty: 2,
            source: "companion",
            userId: env.adminUserId
        )

        let row = try env.db.writer.read { db in
            try Row.fetchOne(db, sql: "SELECT points FROM co_occurrence_pairs WHERE category_a_id = ? AND category_b_id = ?",
                             arguments: [catAId, catBId])
        }
        let points: Int = try #require(row)["points"]
        #expect(points == 101, "Points should increment by 1 after feedback")
    }

    @Test("recordCompanionFeedback inserts new co_occurrence_pair when none exists")
    func testRecordCompanionFeedback_insertsNew() throws {
        let env = try E2ETestHelpers.setUp()
        let catAId = try E2ETestHelpers.seedCategory(env, name: "FbkNewA")
        let catBId = try E2ETestHelpers.seedCategory(env, name: "FbkNewB")
        let sourcePartId = try E2ETestHelpers.seedPart(env, name: "Src Part", categoryId: catAId)
        let targetPartId = try E2ETestHelpers.seedPart(env, name: "Tgt Part", categoryId: catBId)

        try env.parts.recordCompanionFeedback(
            sourcePartId: sourcePartId,
            targetPartId: targetPartId,
            suggestedQty: 1,
            acceptedQty: 1,
            source: "ai",
            userId: nil
        )

        let row = try env.db.writer.read { db in
            try Row.fetchOne(db, sql: "SELECT points FROM co_occurrence_pairs WHERE category_a_id = ? AND category_b_id = ?",
                             arguments: [catAId, catBId])
        }
        #expect(row != nil, "co_occurrence_pair should be auto-created on first feedback")
    }

    // MARK: - getNextPollPreview

    @Test("getNextPollPreview returns nil when no qualified pairs exist")
    func testGetNextPollPreview_empty() throws {
        let env = try E2ETestHelpers.setUp()
        let preview = try env.parts.getNextPollPreview()
        #expect(preview == nil)
    }

    @Test("getNextPollPreview returns best pair when qualified pairs exist")
    func testGetNextPollPreview_returnsPair() throws {
        let env = try E2ETestHelpers.setUp()
        let catAId = try E2ETestHelpers.seedCategory(env, name: "PreviewA")
        let catBId = try E2ETestHelpers.seedCategory(env, name: "PreviewB")
        _ = try seedPair(env, catAId: catAId, catBId: catBId, points: 300)

        let preview = try env.parts.getNextPollPreview()
        let p = try #require(preview)
        #expect(p.catAName == "PreviewA" || p.catBName == "PreviewB")
        #expect(p.points == 300)
    }

    // MARK: - getTrainingQuestion

    @Test("getTrainingQuestion returns nil on empty database")
    func testGetTrainingQuestion_empty() throws {
        let env = try E2ETestHelpers.setUp()
        let question = try env.parts.getTrainingQuestion()
        #expect(question == nil)
    }

    // MARK: - tracePartFromSupplier

    @Test("tracePartFromSupplier returns empty when no stock movements exist for that supplier")
    func testTracePartFromSupplier_empty() throws {
        let env = try E2ETestHelpers.setUp()
        let catId = try E2ETestHelpers.seedCategory(env)
        let partId = try E2ETestHelpers.seedPart(env, categoryId: catId)
        let supplierId = try E2ETestHelpers.seedSupplier(env)

        let steps = try env.parts.tracePartFromSupplier(partId: partId, supplierId: supplierId)
        #expect(steps.isEmpty)
    }

    // MARK: - logPartFieldChanges

    @Test("logPartFieldChanges writes multiple change entries readable via getPartChangeLog")
    func testLogPartFieldChanges_roundTrip() throws {
        let env = try E2ETestHelpers.setUp()
        let catId = try E2ETestHelpers.seedCategory(env)
        let partId = try E2ETestHelpers.seedPart(env, name: "Logged Part", categoryId: catId)

        let changes: [(field: String, oldValue: String?, newValue: String?)] = [
            (field: "name", oldValue: "Old Name", newValue: "New Name"),
            (field: "code", oldValue: nil, newValue: "ABC-001")
        ]

        try env.parts.logPartFieldChanges(
            partId: partId,
            userId: env.adminUserId,
            userName: "Test Admin",
            changes: changes,
            context: "unit test"
        )

        // getPartChangeLog may include an initial "created" entry from createPart; filter to
        // only the "updated" entries written by logPartFieldChanges.
        let log = try env.parts.getPartChangeLog(partId: partId).filter { $0.action == "updated" }
        #expect(log.count == 2)
        let nameEntry = log.first(where: { $0.fieldName == "name" })
        #expect(nameEntry?.oldValue == "Old Name")
        #expect(nameEntry?.newValue == "New Name")
        let codeEntry = log.first(where: { $0.fieldName == "code" })
        #expect(codeEntry?.oldValue == nil)
        #expect(codeEntry?.newValue == "ABC-001")
    }

    @Test("logPartFieldChanges is a no-op when changes array is empty")
    func testLogPartFieldChanges_noOpOnEmpty() throws {
        let env = try E2ETestHelpers.setUp()
        let catId = try E2ETestHelpers.seedCategory(env)
        let partId = try E2ETestHelpers.seedPart(env, name: "NoChange Part", categoryId: catId)

        try env.parts.logPartFieldChanges(partId: partId, userId: nil, userName: nil, changes: [])

        // Only "updated" entries should exist — none, since we passed an empty changes array.
        let updatedLog = try env.parts.getPartChangeLog(partId: partId).filter { $0.action == "updated" }
        #expect(updatedLog.isEmpty)
    }

    // MARK: - calculateStyleCoOccurrence / calculateTypeCoOccurrence

    @Test("calculateStyleCoOccurrence completes without throwing when no job parts exist")
    func testCalculateStyleCoOccurrence_noOp() throws {
        let env = try E2ETestHelpers.setUp()
        let catAId = try E2ETestHelpers.seedCategory(env, name: "StyleCatA")
        let catBId = try E2ETestHelpers.seedCategory(env, name: "StyleCatB")

        #expect(throws: Never.self) {
            try env.parts.calculateStyleCoOccurrence(categoryAId: catAId, categoryBId: catBId)
        }
    }

    @Test("calculateTypeCoOccurrence completes without throwing when no job parts exist")
    func testCalculateTypeCoOccurrence_noOp() throws {
        let env = try E2ETestHelpers.setUp()
        let (_, styleAId, _) = try E2ETestHelpers.seedPartHierarchy(env, category: "TypeCatA", style: "StyleA", type: "TypeA")
        let (_, styleBId, _) = try E2ETestHelpers.seedPartHierarchy(env, category: "TypeCatB", style: "StyleB", type: "TypeB")
        let catAId = try E2ETestHelpers.seedCategory(env, name: "TypeXA")
        let catBId = try E2ETestHelpers.seedCategory(env, name: "TypeXB")

        #expect(throws: Never.self) {
            try env.parts.calculateTypeCoOccurrence(
                styleAId: styleAId, styleBId: styleBId,
                categoryAId: catAId, categoryBId: catBId
            )
        }
    }

    // MARK: - runAutoDiscoveryCycle

    @Test("runAutoDiscoveryCycle completes without throwing on empty database")
    func testRunAutoDiscoveryCycle_emptyDB() throws {
        let env = try E2ETestHelpers.setUp()
        #expect(throws: Never.self) {
            try env.parts.runAutoDiscoveryCycle()
        }
    }

    // MARK: - getJobPartsForSandbox / getNextLevelCoOccurrences

    @Test("getJobPartsForSandbox returns empty for job with no consumed parts")
    func testGetJobPartsForSandbox_empty() throws {
        let env = try E2ETestHelpers.setUp()
        let jobId = try E2ETestHelpers.seedJob(env)

        let rows = try env.parts.getJobPartsForSandbox(jobId: jobId)
        #expect(rows.isEmpty)
    }

    @Test("getNextLevelCoOccurrences returns empty for empty categoryIds input")
    func testGetNextLevelCoOccurrences_emptyInput() throws {
        let env = try E2ETestHelpers.setUp()
        let rows = try env.parts.getNextLevelCoOccurrences(categoryIds: [])
        #expect(rows.isEmpty)
    }
}
