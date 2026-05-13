import Testing
import GRDB
@testable import WiredPartCore

@Suite("OnboardingTelemetryService Tests")
struct OnboardingTelemetryServiceTests {
    private func freshService() throws -> OnboardingTelemetryService {
        try OnboardingTelemetryService(db: AppDatabase.openInMemoryDatabase())
    }

    @Test("telemetry is disabled by default and writes no events")
    func testDisabledByDefault() throws {
        let service = try freshService()

        #expect(try service.isEnabled == false)
        try service.record(.cardShown)

        let events = try service.listEvents()
        #expect(events.isEmpty)
    }

    @Test("enabled telemetry writes event with payload")
    func testEnabledWritesEvent() throws {
        let service = try freshService()

        try service.setEnabled(true)
        try service.record(.stepCompleted, payload: [
            "stepId": .string("create-job"),
            "secondsSinceFirstLaunch": .int(42),
        ])

        let events = try service.listEvents()
        #expect(events.count == 1)
        #expect(events[0].eventType == "onboarding.step_completed")
        #expect(events[0].payloadJSON?.contains("\"stepId\":\"create-job\"") == true)
        #expect(events[0].payloadJSON?.contains("\"secondsSinceFirstLaunch\":42") == true)
    }

    @Test("disabling telemetry stops new writes without deleting existing local data")
    func testDisableStopsNewWrites() throws {
        let service = try freshService()

        try service.setEnabled(true)
        try service.record(.cardShown)
        try service.setEnabled(false)
        try service.record(.stepTapped, payload: ["stepId": .string("supplier")])

        let events = try service.listEvents()
        #expect(events.count == 1)
        #expect(events[0].eventType == "onboarding.card_shown")
    }
}
