import Foundation
import Testing
import GRDB
@testable import WiredPartCore

@Suite("BreakService Tests")
struct BreakServiceTests {

    private func freshEnv() throws -> E2ETestHelpers.TestEnvironment {
        try E2ETestHelpers.setUp()
    }

    // MARK: - Break Policy CRUD

    @Test("Save and retrieve break policy")
    func testSavePolicy() throws {
        let env = try freshEnv()
        let breakService = BreakService(db: env.db)

        let policy = try breakService.savePolicy(
            stateCode: "CA",
            policyType: "state",
            workDayHours: 8,
            lunchMinutes: 30,
            breakCount: 2,
            breakMinutes: 15
        )
        #expect(policy.stateCode == "CA")
        #expect(policy.lunchMinutes == 30)
        #expect(policy.breakCount == 2)
    }

    @Test("Get all policies returns saved policies")
    func testGetAllPolicies() throws {
        let env = try freshEnv()
        let breakService = BreakService(db: env.db)

        _ = try breakService.savePolicy(stateCode: "CA", policyType: "state")
        _ = try breakService.savePolicy(stateCode: "TX", policyType: "state")

        let policies = try breakService.getAllPolicies()
        #expect(policies.count >= 2)
    }

    @Test("Get break policy by state code")
    func testGetBreakPolicy() throws {
        let env = try freshEnv()
        let breakService = BreakService(db: env.db)

        _ = try breakService.savePolicy(stateCode: "NY", policyType: "state", lunchMinutes: 45)

        let policies = try breakService.getBreakPolicy(stateCode: "NY")
        #expect(!policies.isEmpty)
    }

    // MARK: - Break Bonus CRUD

    @Test("Create and retrieve break bonus")
    func testBreakBonus() throws {
        let env = try freshEnv()
        let breakService = BreakService(db: env.db)

        let policy = try breakService.savePolicy(stateCode: "CA", policyType: "state")

        let bonus = try breakService.createBonus(
            policyId: policy.id!,
            bonusType: "early_lunch",
            bonusAmount: 5.0,
            description: "Bonus for taking early lunch"
        )
        #expect(bonus.bonusType == "early_lunch")
        #expect(bonus.bonusAmount == 5.0)

        let bonuses = try breakService.getBreakBonuses(policyId: policy.id!)
        #expect(bonuses.count == 1)
    }

    @Test("Toggle break bonus enabled state")
    func testToggleBonus() throws {
        let env = try freshEnv()
        let breakService = BreakService(db: env.db)

        let policy = try breakService.savePolicy(stateCode: "CA", policyType: "state")
        let bonus = try breakService.createBonus(
            policyId: policy.id!,
            bonusType: "extra",
            bonusAmount: 10.0,
            isEnabled: false
        )

        try breakService.toggleBonus(bonusId: bonus.id!, isEnabled: true)
        let updated = try breakService.getBreakBonuses(policyId: policy.id!)
        #expect(updated[0].isEnabled)
    }

    // MARK: - Break Records

    @Test("Start and end a break")
    func testStartEndBreak() throws {
        let env = try freshEnv()
        let breakService = BreakService(db: env.db)

        let record = try breakService.startBreak(
            userId: env.adminUserId,
            breakType: "lunch",
            timerMinutes: 30
        )
        #expect(record.breakType == "lunch")
        #expect(record.endedAt == nil)

        try breakService.endBreak(recordId: record.id!)
    }

    @Test("Get active break for user")
    func testGetActiveBreak() throws {
        let env = try freshEnv()
        let breakService = BreakService(db: env.db)

        // No active break initially
        let none = try breakService.getActiveBreak(userId: env.adminUserId)
        #expect(none == nil)

        // Start a break
        _ = try breakService.startBreak(userId: env.adminUserId, breakType: "rest")

        let active = try breakService.getActiveBreak(userId: env.adminUserId)
        #expect(active != nil)
        #expect(active?.breakType == "rest")
    }

    @Test("Get break records for day")
    func testGetBreakRecordsForDay() throws {
        let env = try freshEnv()
        let breakService = BreakService(db: env.db)

        let record = try breakService.startBreak(userId: env.adminUserId, breakType: "lunch")
        try breakService.endBreak(recordId: record.id!)

        let records = try breakService.getBreakRecordsForDay(userId: env.adminUserId)
        #expect(records.count >= 1)
    }

    // MARK: - Company Break Settings

    @Test("Get and update company break settings")
    func testCompanyBreakSettings() throws {
        let env = try freshEnv()
        let breakService = BreakService(db: env.db)

        let defaults = try breakService.getCompanyBreakSettings()
        #expect(defaults.roundingMinutes >= 0)

        try breakService.updateCompanyBreakSettings(
            stateCode: "CA",
            roundingMinutes: 15,
            roundingEnabled: true,
            autoFillBreaks: true
        )

        let updated = try breakService.getCompanyBreakSettings()
        #expect(updated.roundingEnabled)
    }

    // MARK: - Compliance

    @Test("Calculate break compliance for user")
    func testBreakCompliance() throws {
        let env = try freshEnv()
        let breakService = BreakService(db: env.db)

        let compliance = try breakService.calculateBreakCompliance(userId: env.adminUserId)
        // With no labor entries, compliance should still compute without error
        #expect(compliance.takenLunchMinutes >= 0)
    }

    // MARK: - Rounding

    @Test("getRoundedTime rounds correctly")
    func testRoundedTime() throws {
        let env = try freshEnv()
        let breakService = BreakService(db: env.db)

        let rounded = breakService.getRoundedTime(time: "10:07", roundingMinutes: 15)
        #expect(rounded == "10:00" || rounded == "10:15")
    }
}
