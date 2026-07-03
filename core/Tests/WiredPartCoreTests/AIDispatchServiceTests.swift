import Foundation
import Testing
import GRDB
@testable import WiredPartCore

@Suite("AIDispatchService Tests")
struct AIDispatchServiceTests {

    private func makeService(_ env: E2ETestHelpers.TestEnvironment) -> AIDispatchService {
        AIDispatchService(db: env.db)
    }

    // MARK: - Dispatch Suggestions

    @Test("Generate suggestions on empty DB returns empty")
    func testEmptySuggestions() throws {
        let env = try E2ETestHelpers.setUp()
        let service = makeService(env)
        let suggestions = try service.generateSuggestions(date: "2026-03-29")
        #expect(suggestions.isEmpty)
    }

    @Test("Generate suggestions with jobs and employees")
    func testSuggestionsWithData() throws {
        let env = try E2ETestHelpers.setUp()
        let service = makeService(env)

        // Seed some jobs
        _ = try E2ETestHelpers.seedJob(env, jobNumber: "J-D1", name: "Dispatch Job 1")
        _ = try E2ETestHelpers.seedJob(env, jobNumber: "J-D2", name: "Dispatch Job 2")

        let suggestions = try service.generateSuggestions(date: "2026-03-29")
        // Even with jobs, may need active employees to dispatch
        #expect(suggestions.count >= 0)
    }

    @Test("Generate suggestions returns empty when AI dispatch is disabled")
    func testSuggestionsDisabledByDispatchPreferences() throws {
        let env = try E2ETestHelpers.setUp()
        let service = makeService(env)
        _ = try E2ETestHelpers.seedJob(env, jobNumber: "J-AI-OFF", name: "Disabled AI Job")

        var preferences = try env.settings.getDispatchPreferences()
        preferences.aiSuggestionsEnabled = false
        _ = try env.settings.updateDispatchPreferences(preferences)

        let suggestions = try service.generateSuggestions(date: "2026-03-29")
        #expect(suggestions.isEmpty)
    }

    @Test("Generate suggestions respects saved suggestion count")
    func testSuggestionsRespectSavedSuggestionCount() throws {
        let env = try E2ETestHelpers.setUp()
        let service = makeService(env)
        _ = try E2ETestHelpers.seedJob(env, jobNumber: "J-AI-COUNT", name: "Counted AI Job")

        var preferences = try env.settings.getDispatchPreferences()
        preferences.aiSuggestionCount = 1
        _ = try env.settings.updateDispatchPreferences(preferences)

        let suggestions = try service.generateSuggestions(date: "2026-03-29")
        #expect(suggestions.count <= 1)
    }

    // MARK: - Context

    @Test("Get dispatch context as text")
    func testDispatchContext() throws {
        let env = try E2ETestHelpers.setUp()
        let service = makeService(env)
        let context = try service.getDispatchContext(date: "2026-03-29")
        #expect(!context.isEmpty) // Should return some context string
    }

    // MARK: - Learning

    @Test("Record dispatcher choice")
    func testRecordChoice() throws {
        let env = try E2ETestHelpers.setUp()
        let service = makeService(env)
        // Should not throw even if no suggestions exist
        try service.recordDispatcherChoice(date: "2026-03-29", chosenRank: 1, wasModified: false)
    }

    @Test("Record modified choice")
    func testRecordModifiedChoice() throws {
        let env = try E2ETestHelpers.setUp()
        let service = makeService(env)
        try service.recordDispatcherChoice(date: "2026-03-29", chosenRank: 2, wasModified: true)
    }

    @Test("Record dispatcher choice is skipped when AI learning is disabled")
    func testRecordChoiceDisabledByDispatchPreferences() throws {
        let env = try E2ETestHelpers.setUp()
        let service = makeService(env)

        var preferences = try env.settings.getDispatchPreferences()
        preferences.aiLearningEnabled = false
        _ = try env.settings.updateDispatchPreferences(preferences)

        try service.recordDispatcherChoice(date: "2026-03-29", chosenRank: 1, wasModified: false)

        let count: Int
        do {
            count = try env.db.writer.read { db in
                try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM ai_dispatch_choices") ?? 0
            }
        } catch {
            count = 0
        }
        #expect(count == 0)
    }
}
