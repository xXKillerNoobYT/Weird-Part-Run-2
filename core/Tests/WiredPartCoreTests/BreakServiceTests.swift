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
        // Migration seeds 1 default WY policy; CA and TX add 2 more = 3 total
        #expect(policies.count == 3)
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

    @Test("Break compliance reflects completed lunch break duration")
    func testBreakCompliance() throws {
        let env = try freshEnv()
        let breakService = BreakService(db: env.db)

        // Insert a completed lunch break record with durationMinutes = 30 directly.
        // (using startBreak/endBreak yields ~0 minutes since tests run instantly)
        // getBreakRecordsForDay filters by substr(started_at, 1, 10) == formatDateUTC(Date())
        // which uses UTC. Use date('now') here so both sides produce the same UTC date string.
        try env.db.writer.write { db in
            try db.execute(sql: """
                INSERT INTO break_records
                    (user_id, break_type, started_at, ended_at, duration_minutes, is_paid, auto_filled)
                VALUES (?, 'lunch', date('now') || 'T12:00:00', date('now') || 'T12:30:00', 30, 1, 0)
                """, arguments: [env.adminUserId])
        }

        let compliance = try breakService.calculateBreakCompliance(userId: env.adminUserId)
        #expect(compliance.takenLunchMinutes == 30)
    }

    // MARK: - Auto Fill

    @Test("autoFillBreaksForDay is no-op when autoFill is disabled")
    func testAutoFillDisabled() throws {
        let env = try freshEnv()
        let breakService = BreakService(db: env.db)

        // Migration seeds a default row with auto_fill_breaks=1; override it with UPDATE
        try env.db.writer.write { db in
            try db.execute(sql: "UPDATE company_break_settings SET auto_fill_breaks = 0")
        }

        try breakService.autoFillBreaksForDay(userId: env.adminUserId)
        let records = try breakService.getBreakRecordsForDay(userId: env.adminUserId)
        #expect(records.isEmpty)
    }

    @Test("autoFillBreaksForDay inserts breaks when autoFill is enabled with defaults")
    func testAutoFillEnabled() throws {
        let env = try freshEnv()
        let breakService = BreakService(db: env.db)

        // Enable auto-fill with default break times
        try breakService.updateCompanyBreakSettings(
            stateCode: "CA",
            roundingMinutes: 15,
            roundingEnabled: false,
            autoFillBreaks: true,
            defaultMorningBreak: "10:00",
            defaultLunch: "12:00",
            defaultAfternoonBreak: "14:00"
        )

        try breakService.autoFillBreaksForDay(userId: env.adminUserId)

        let records = try breakService.getBreakRecordsForDay(userId: env.adminUserId)
        // morning break + afternoon break + lunch = 3 auto-filled records
        #expect(records.count == 3)
        #expect(records.allSatisfy { $0.autoFilled == true })
    }

    @Test("autoFillBreaksForDay fills only the missing scheduled break")
    func testAutoFillFillsMissingScheduledBreak() throws {
        let env = try freshEnv()
        let breakService = BreakService(db: env.db)

        try breakService.updateCompanyBreakSettings(
            stateCode: "CA",
            roundingMinutes: 15,
            roundingEnabled: false,
            autoFillBreaks: true,
            defaultMorningBreak: "10:00",
            defaultLunch: "12:00",
            defaultAfternoonBreak: "14:00"
        )

        // Manually start a break first
        let record = try breakService.startBreak(userId: env.adminUserId, breakType: "break")
        try breakService.endBreak(recordId: record.id!)

        try breakService.autoFillBreaksForDay(userId: env.adminUserId)

        let records = try breakService.getBreakRecordsForDay(userId: env.adminUserId)
        let breakRecords = records.filter { $0.breakType == "break" }
        let lunchRecords = records.filter { $0.breakType.hasPrefix("lunch") }

        #expect(breakRecords.count == 2)
        #expect(lunchRecords.count == 1)
        #expect(breakRecords.contains { $0.autoFilled == false })
        #expect(breakRecords.contains { $0.autoFilled == true && $0.startedAt.hasSuffix("T14:00:00") })
    }

    @Test("autoFillBreaksForDay keeps existing lunch and still fills breaks")
    func testAutoFillKeepsExistingLunchAndFillsBreaks() throws {
        let env = try freshEnv()
        let breakService = BreakService(db: env.db)

        try breakService.updateCompanyBreakSettings(
            stateCode: "CA",
            roundingMinutes: 15,
            roundingEnabled: false,
            autoFillBreaks: true,
            defaultMorningBreak: "10:00",
            defaultLunch: "12:00",
            defaultAfternoonBreak: "14:00"
        )

        try env.db.writer.write { db in
            try db.execute(sql: """
                INSERT INTO break_records
                    (user_id, break_type, started_at, ended_at, duration_minutes, is_paid, auto_filled)
                VALUES (?, 'lunch_paid', date('now') || 'T12:00:00', date('now') || 'T12:30:00', 30, 1, 0)
                """, arguments: [env.adminUserId])
        }

        try breakService.autoFillBreaksForDay(userId: env.adminUserId)

        let records = try breakService.getBreakRecordsForDay(userId: env.adminUserId)
        #expect(records.filter { $0.breakType == "break" }.count == 2)
        #expect(records.filter { $0.breakType.hasPrefix("lunch") }.count == 1)
    }

    @Test("autoFillBreaksForDay does not duplicate default breaks when already present")
    func testAutoFillDoesNotDuplicateExistingDefaultBreaks() throws {
        let env = try freshEnv()
        let breakService = BreakService(db: env.db)

        try breakService.updateCompanyBreakSettings(
            stateCode: "CA",
            roundingMinutes: 15,
            roundingEnabled: false,
            autoFillBreaks: true,
            defaultMorningBreak: "10:00",
            defaultLunch: "12:00",
            defaultAfternoonBreak: "14:00"
        )

        try breakService.autoFillBreaksForDay(userId: env.adminUserId)
        try breakService.autoFillBreaksForDay(userId: env.adminUserId)

        let records = try breakService.getBreakRecordsForDay(userId: env.adminUserId)
        #expect(records.filter { $0.breakType == "break" }.count == 2)
        #expect(records.filter { $0.breakType.hasPrefix("lunch") }.count == 1)
    }

    // MARK: - Rounding

    @Test("getRoundedTime rounds correctly")
    func testRoundedTime() throws {
        let env = try freshEnv()
        let breakService = BreakService(db: env.db)

        // Integer floor division: 7 / 15 = 0 → 0 * 15 = 0 → "10:00"
        let rounded = breakService.getRoundedTime(time: "10:07", roundingMinutes: 15)
        #expect(rounded == "10:00")

        // 10:16 should round down to 10:15
        let rounded2 = breakService.getRoundedTime(time: "10:16", roundingMinutes: 15)
        #expect(rounded2 == "10:15")
    }
}
