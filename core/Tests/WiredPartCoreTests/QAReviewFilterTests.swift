import Foundation
import Testing
import GRDB
@testable import WiredPartCore

/// Regression tests for #1200 — "Needs My Review" and the RFI queue must be
/// ownership/escalation-level aware instead of showing every open thread.
@Suite("QA Review Filter Tests")
struct QAReviewFilterTests {

    // MARK: - Helpers

    /// Create an active user wearing the given built-in hat and return their ID.
    private func seedUser(_ env: E2ETestHelpers.TestEnvironment, name: String, hat: String?) throws -> Int64 {
        try env.db.writer.write { db in
            try db.execute(
                sql: """
                    INSERT INTO users (display_name, pin_hash, is_active, created_at, updated_at)
                    VALUES (?, 'test-hash', 1, datetime('now'), datetime('now'))
                    """,
                arguments: [name]
            )
            let userId = db.lastInsertedRowID
            if let hat {
                try db.execute(
                    sql: """
                        INSERT INTO user_hats (user_id, hat_id, is_active)
                        SELECT ?, id, 1 FROM hats WHERE name = ?
                        """,
                    arguments: [userId, hat]
                )
            }
            return userId
        }
    }

    /// Force a thread to a specific escalation level (test setup shortcut).
    private func setLevel(_ env: E2ETestHelpers.TestEnvironment, threadId: Int64, level: String) throws {
        try env.db.writer.write { db in
            try db.execute(
                sql: "UPDATE qa_threads SET current_level = ? WHERE id = ?",
                arguments: [level, threadId]
            )
        }
    }

    // MARK: - actionableQALevels

    @Test("Admin hat covers the entire escalation chain")
    func testAdminLevels() throws {
        let env = try E2ETestHelpers.setUp()
        let levels = try env.chat.actionableQALevels(userId: env.adminUserId)
        #expect(levels == Set(ChatService.qaEscalationLevels))
    }

    @Test("Built-in hats map to their matching escalation level")
    func testHatLevelMapping() throws {
        let env = try E2ETestHelpers.setUp()
        let workerId = try seedUser(env, name: "Wanda Worker", hat: "Worker")
        let leadId = try seedUser(env, name: "Lee Lead", hat: "Lead")
        let managerId = try seedUser(env, name: "Mgr Mary", hat: "Manager")
        let officeId = try seedUser(env, name: "Olive Office", hat: "Office")

        #expect(try env.chat.actionableQALevels(userId: workerId) == ["worker"])
        #expect(try env.chat.actionableQALevels(userId: leadId) == ["lead"])
        #expect(try env.chat.actionableQALevels(userId: managerId) == ["manager"])
        #expect(try env.chat.actionableQALevels(userId: officeId) == ["office"])
    }

    @Test("Non-responder hats and hatless users map to no levels")
    func testNonResponderLevels() throws {
        let env = try E2ETestHelpers.setUp()
        let apprenticeId = try seedUser(env, name: "Abe Apprentice", hat: "Apprentice")
        let hatlessId = try seedUser(env, name: "No Hat Nancy", hat: nil)

        #expect(try env.chat.actionableQALevels(userId: apprenticeId).isEmpty)
        #expect(try env.chat.actionableQALevels(userId: hatlessId).isEmpty)
        #expect(try env.chat.listQAThreadsNeedingReview(userId: hatlessId).isEmpty)
    }

    // MARK: - listQAThreadsNeedingReview

    @Test("Needs-review only includes threads at the user's level")
    func testReviewFiltersByLevel() throws {
        let env = try E2ETestHelpers.setUp()
        let jobId = try E2ETestHelpers.seedJob(env)
        let askerId = try seedUser(env, name: "Asker", hat: "Worker")
        let workerId = try seedUser(env, name: "Peer Worker", hat: "Worker")
        let leadId = try seedUser(env, name: "Lead", hat: "Lead")
        let managerId = try seedUser(env, name: "Manager", hat: "Manager")
        let officeId = try seedUser(env, name: "Office", hat: "Office")

        let workerThread = try env.chat.createQAThread(jobId: jobId, askedBy: askerId, subject: "Worker-level question")
        let leadThread = try env.chat.createQAThread(jobId: jobId, askedBy: askerId, subject: "Lead-level question")
        let managerThread = try env.chat.createQAThread(jobId: jobId, askedBy: askerId, subject: "Manager-level question")
        let officeThread = try env.chat.createQAThread(jobId: jobId, askedBy: askerId, subject: "Office-level question")
        try setLevel(env, threadId: leadThread, level: "lead")
        try setLevel(env, threadId: managerThread, level: "manager")
        try setLevel(env, threadId: officeThread, level: "office")

        #expect(try env.chat.listQAThreadsNeedingReview(userId: workerId).map(\.id) == [workerThread])
        #expect(try env.chat.listQAThreadsNeedingReview(userId: leadId).map(\.id) == [leadThread])
        #expect(try env.chat.listQAThreadsNeedingReview(userId: managerId).map(\.id) == [managerThread])
        #expect(try env.chat.listQAThreadsNeedingReview(userId: officeId).map(\.id) == [officeThread])

        // Admin oversees every level — all four open threads.
        let adminIds = Set(try env.chat.listQAThreadsNeedingReview(userId: env.adminUserId).map(\.id))
        #expect(adminIds == [workerThread, leadThread, managerThread, officeThread])
    }

    @Test("Asker does not see their own question as needing review")
    func testAskerExcluded() throws {
        let env = try E2ETestHelpers.setUp()
        let jobId = try E2ETestHelpers.seedJob(env)
        let askerId = try seedUser(env, name: "Asker", hat: "Worker")
        let peerId = try seedUser(env, name: "Peer", hat: "Worker")

        let threadId = try env.chat.createQAThread(jobId: jobId, askedBy: askerId, subject: "My own question")

        #expect(try env.chat.listQAThreadsNeedingReview(userId: askerId).isEmpty)
        #expect(try env.chat.listQAThreadsNeedingReview(userId: peerId).map(\.id) == [threadId])
    }

    @Test("Push-back returns the thread to the asker's review queue")
    func testPushBackReturnsToAsker() throws {
        let env = try E2ETestHelpers.setUp()
        let jobId = try E2ETestHelpers.seedJob(env)
        let askerId = try seedUser(env, name: "Asker", hat: "Worker")

        let threadId = try env.chat.createQAThread(jobId: jobId, askedBy: askerId, subject: "Needs clarification")
        // Escalate to lead, then push back down to worker with feedback.
        try env.chat.escalateThread(threadId: threadId, escalatedBy: env.adminUserId, notes: "Up to lead")
        #expect(try env.chat.listQAThreadsNeedingReview(userId: askerId).isEmpty)

        try env.chat.pushBackThread(threadId: threadId, pushedBackBy: env.adminUserId, reason: "Please clarify the panel location")
        #expect(try env.chat.listQAThreadsNeedingReview(userId: askerId).map(\.id) == [threadId])
    }

    @Test("Resolved and answered threads never need review")
    func testResolvedExcluded() throws {
        let env = try E2ETestHelpers.setUp()
        let jobId = try E2ETestHelpers.seedJob(env)
        let askerId = try seedUser(env, name: "Asker", hat: "Worker")
        let peerId = try seedUser(env, name: "Peer", hat: "Worker")

        let threadId = try env.chat.createQAThread(jobId: jobId, askedBy: askerId, subject: "Soon resolved")
        try env.chat.resolveQAThread(threadId: threadId, resolvedBy: env.adminUserId)

        #expect(try env.chat.listQAThreadsNeedingReview(userId: peerId).isEmpty)
        #expect(try env.chat.listQAThreadsNeedingReview(userId: env.adminUserId).isEmpty)
    }

    @Test("Escalated threads appear for the escalated-to level")
    func testEscalatedStatusIncluded() throws {
        let env = try E2ETestHelpers.setUp()
        let jobId = try E2ETestHelpers.seedJob(env)
        let askerId = try seedUser(env, name: "Asker", hat: "Worker")
        let leadId = try seedUser(env, name: "Lead", hat: "Lead")

        let threadId = try env.chat.createQAThread(jobId: jobId, askedBy: askerId, subject: "Escalating")
        try env.chat.escalateThread(threadId: threadId, escalatedBy: env.adminUserId, notes: nil)

        // Status is now "escalated" at level "lead".
        #expect(try env.chat.listQAThreadsNeedingReview(userId: leadId).map(\.id) == [threadId])
    }

    // MARK: - listQAThreads(levels:) — RFI queue

    @Test("RFI level filter returns only office-level threads")
    func testListThreadsLevelFilter() throws {
        let env = try E2ETestHelpers.setUp()
        let jobId = try E2ETestHelpers.seedJob(env)
        let askerId = try seedUser(env, name: "Asker", hat: "Worker")

        let workerThread = try env.chat.createQAThread(jobId: jobId, askedBy: askerId, subject: "Field question")
        let officeThread = try env.chat.createQAThread(jobId: jobId, askedBy: askerId, subject: "Office RFI")
        try setLevel(env, threadId: officeThread, level: "office")

        let rfis = try env.chat.listQAThreads(levels: ["office"])
        #expect(rfis.map(\.id) == [officeThread])
        #expect(!rfis.contains(where: { $0.id == workerThread }))

        // Level + status combine.
        try env.chat.resolveQAThread(threadId: officeThread, resolvedBy: env.adminUserId)
        #expect(try env.chat.listQAThreads(status: "open", levels: ["office"]).isEmpty)
        #expect(try env.chat.listQAThreads(status: "resolved", levels: ["office"]).map(\.id) == [officeThread])

        // Empty level list means "no levels" — nothing matches.
        #expect(try env.chat.listQAThreads(levels: []).isEmpty)

        // nil keeps the previous behavior: all levels.
        let all = Set(try env.chat.listQAThreads().map(\.id))
        #expect(all == [workerThread, officeThread])
    }
}
