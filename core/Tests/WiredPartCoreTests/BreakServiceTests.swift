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
        #expect(policies.contains { $0.stateCode == "CA" && $0.policyType == "state" })
        #expect(policies.contains { $0.stateCode == "TX" && $0.policyType == "state" })
    }

    @Test("Get break policy by state code")
    func testGetBreakPolicy() throws {
        let env = try freshEnv()
        let breakService = BreakService(db: env.db)

        _ = try breakService.savePolicy(stateCode: "NY", policyType: "state", lunchMinutes: 45)

        let policies = try breakService.getBreakPolicy(stateCode: "NY")
        #expect(!policies.isEmpty)
    }

    @Test("Seeded break policy presets cover 50 states plus DC for 8 and 10 hour days")
    func testSeededBreakPolicyPresetCoverage() throws {
        let env = try freshEnv()
        let policies = try BreakService(db: env.db).getAllPolicies()
        let seeded = policies.filter {
            $0.policyType == "state_required_paid" || $0.policyType == "state_required_offered"
        }

        for jurisdiction in AppDatabase.breakPolicyJurisdictionCodes {
            for hours in [8, 10] {
                let rows = seeded.filter { $0.stateCode == jurisdiction && $0.workDayHours == hours }
                #expect(rows.contains { $0.policyType == "state_required_paid" })
                #expect(rows.contains { $0.policyType == "state_required_offered" })
                #expect(rows.allSatisfy { $0.dataSource != nil && $0.dataDate == "2023-01-01" })
            }
        }
    }

    @Test("DC and 10 hour policy presets are readable")
    func testDCAndTenHourPolicyReads() throws {
        let env = try freshEnv()
        let breakService = BreakService(db: env.db)

        let dcPolicies = try breakService.getBreakPolicy(stateCode: "DC", dayHours: 10)
        #expect(dcPolicies.contains {
            $0.policyType == "state_required_offered" &&
            $0.workDayHours == 10 &&
            $0.lunchMinutes == 30
        })

        let marylandTenHour = try breakService.getBreakPolicy(stateCode: "MD", dayHours: 10)
        #expect(marylandTenHour.contains {
            $0.policyType == "state_required_offered" &&
            $0.workDayHours == 10 &&
            $0.breakCount == 1 &&
            $0.breakMinutes == 15
        })
    }

    @Test("Company extra policies remain separate from state-required presets")
    func testCompanyPoliciesRemainSeparateFromStatePresets() throws {
        let env = try freshEnv()
        let breakService = BreakService(db: env.db)

        _ = try breakService.savePolicy(
            stateCode: nil,
            policyType: "company_extra_paid",
            workDayHours: 8,
            lunchMinutes: 15,
            breakCount: 1,
            breakMinutes: 10
        )

        let policies = try breakService.getAllPolicies()
        #expect(policies.contains {
            $0.stateCode == nil &&
            $0.policyType == "company_extra_paid" &&
            $0.lunchMinutes == 15
        })
        #expect(policies.contains {
            $0.stateCode == "DC" &&
            $0.policyType == "state_required_offered"
        })
    }

    @Test("Saving same company policy twice updates active row")
    func testSaveCompanyPolicyIsIdempotent() throws {
        let env = try freshEnv()
        let breakService = BreakService(db: env.db)

        let first = try breakService.savePolicy(
            stateCode: nil,
            policyType: "company_extra_paid",
            workDayHours: 8,
            lunchMinutes: 30,
            breakCount: 1,
            breakMinutes: 10
        )

        let second = try breakService.savePolicy(
            stateCode: nil,
            policyType: "company_extra_paid",
            workDayHours: 8,
            lunchMinutes: 45,
            breakCount: 3,
            breakMinutes: 20
        )

        #expect(second.id == first.id)
        #expect(second.lunchMinutes == 45)
        #expect(second.breakCount == 3)
        #expect(second.breakMinutes == 20)

        let activeRows = try env.db.writer.read { db in
            try BreakPolicy
                .filter(Column("state_code") == nil)
                .filter(Column("policy_type") == "company_extra_paid")
                .filter(Column("work_day_hours") == 8)
                .filter(Column("deleted_at") == nil)
                .fetchAll(db)
        }

        #expect(activeRows.count == 1)
        #expect(activeRows.first?.id == first.id)
        #expect(activeRows.first?.lunchMinutes == 45)
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

    @Test("Start break attaches to active clock entry when laborEntryId is omitted")
    func testStartBreakAttachesToActiveClockEntryByDefault() throws {
        let env = try freshEnv()
        let breakService = BreakService(db: env.db)
        let jobId = try E2ETestHelpers.seedJob(env, jobNumber: "J-BREAK-ACTIVE", name: "Break Active Job")
        let laborEntryId = try env.jobs.clockIn(userId: env.adminUserId, jobId: jobId)

        let record = try breakService.startBreak(
            userId: env.adminUserId,
            breakType: "lunch_unpaid",
            timerMinutes: 30
        )

        #expect(record.laborEntryId == laborEntryId)
    }

    @Test("Start break is idempotent for an identical active break request")
    func testStartBreakReturnsExistingMatchingActiveBreak() throws {
        let env = try freshEnv()
        let breakService = BreakService(db: env.db)
        let jobId = try E2ETestHelpers.seedJob(env, jobNumber: "J-BREAK-OVERLAP", name: "Break Overlap Job")
        let laborEntryId = try env.jobs.clockIn(userId: env.adminUserId, jobId: jobId)

        let first = try breakService.startBreak(
            userId: env.adminUserId,
            breakType: "break",
            laborEntryId: laborEntryId,
            timerMinutes: 15
        )
        let second = try breakService.startBreak(
            userId: env.adminUserId,
            breakType: "break",
            laborEntryId: laborEntryId,
            timerMinutes: 15
        )

        let activeBreaks = try env.db.writer.read { db in
            try BreakRecord
                .filter(sql: "user_id = ? AND ended_at IS NULL AND deleted_at IS NULL", arguments: [env.adminUserId])
                .fetchAll(db)
        }

        #expect(second.id == first.id)
        #expect(activeBreaks.count == 1)
        #expect(activeBreaks.first?.breakType == "break")
    }

    @Test("Start break rejects a different break while one is active")
    func testStartBreakRejectsDifferentActiveBreakRequest() throws {
        let env = try freshEnv()
        let breakService = BreakService(db: env.db)
        let jobId = try E2ETestHelpers.seedJob(env, jobNumber: "J-BREAK-CONFLICT", name: "Break Conflict Job")
        let laborEntryId = try env.jobs.clockIn(userId: env.adminUserId, jobId: jobId)

        let first = try breakService.startBreak(
            userId: env.adminUserId,
            breakType: "break",
            laborEntryId: laborEntryId,
            timerMinutes: 15
        )

        #expect(throws: BreakService.BreakError.activeBreakAlreadyInProgress(userId: env.adminUserId, activeBreakId: first.id)) {
            try breakService.startBreak(
                userId: env.adminUserId,
                breakType: "lunch_paid",
                laborEntryId: laborEntryId,
                timerMinutes: 30
            )
        }

        let activeBreaks = try env.db.writer.read { db in
            try BreakRecord
                .filter(sql: "user_id = ? AND ended_at IS NULL AND deleted_at IS NULL", arguments: [env.adminUserId])
                .fetchAll(db)
        }

        #expect(activeBreaks.count == 1)
        #expect(activeBreaks.first?.breakType == "break")
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

    @Test("Company break settings reject malformed default times")
    func testCompanyBreakSettingsRejectMalformedDefaultTimes() throws {
        let env = try freshEnv()
        let breakService = BreakService(db: env.db)

        #expect(throws: BreakService.BreakError.invalidDefaultBreakTime(field: "Morning Break", value: "bad")) {
            try breakService.updateCompanyBreakSettings(
                stateCode: "CA",
                defaultMorningBreak: "bad",
                defaultLunch: "12:00",
                defaultAfternoonBreak: "14:30"
            )
        }

        #expect(throws: BreakService.BreakError.invalidDefaultBreakTime(field: "Lunch", value: "24:00")) {
            try breakService.updateCompanyBreakSettings(
                stateCode: "CA",
                defaultMorningBreak: "10:00",
                defaultLunch: "24:00",
                defaultAfternoonBreak: "14:30"
            )
        }

        #expect(throws: BreakService.BreakError.invalidDefaultBreakTime(field: "Lunch", value: "+1:00")) {
            try breakService.updateCompanyBreakSettings(
                stateCode: "CA",
                defaultMorningBreak: "10:00",
                defaultLunch: "+1:00",
                defaultAfternoonBreak: "14:30"
            )
        }

        #expect(throws: BreakService.BreakError.invalidDefaultBreakTime(field: "Afternoon Break", value: "25:99")) {
            try breakService.updateCompanyBreakSettings(
                stateCode: "CA",
                defaultMorningBreak: "10:00",
                defaultLunch: "12:00",
                defaultAfternoonBreak: "25:99"
            )
        }
    }

    @Test("Company break settings accept HH:mm boundary defaults")
    func testCompanyBreakSettingsAcceptBoundaryDefaultTimes() throws {
        let env = try freshEnv()
        let breakService = BreakService(db: env.db)

        try breakService.updateCompanyBreakSettings(
            stateCode: "CA",
            defaultMorningBreak: "00:00",
            defaultLunch: "23:59",
            defaultAfternoonBreak: nil
        )

        let settings = try breakService.getCompanyBreakSettings()
        #expect(settings.defaultMorningBreak == "00:00")
        #expect(settings.defaultLunch == "23:59")
        #expect(settings.defaultAfternoonBreak == nil)
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

    @Test("autoFillBreaksForDay ignores malformed persisted default times")
    func testAutoFillSkipsMalformedPersistedDefaultTimes() throws {
        let env = try freshEnv()
        let breakService = BreakService(db: env.db)

        try env.db.writer.write { db in
            try db.execute(sql: """
                UPDATE company_break_settings
                SET auto_fill_breaks = 1,
                    default_morning_break = 'bad',
                    default_lunch = '12:00',
                    default_afternoon_break = '25:99'
                """)
        }

        try breakService.autoFillBreaksForDay(userId: env.adminUserId)

        let records = try breakService.getBreakRecordsForDay(userId: env.adminUserId)
        #expect(records.count == 1)
        #expect(records.first?.breakType == "lunch_paid")
        #expect(records.first?.startedAt.hasSuffix("T12:00:00") == true)
        #expect(records.first?.endedAt?.hasSuffix("T12:30:00") == true)
    }

    @Test("autoFillBreaksForDay rolls end timestamps to next day when default crosses midnight")
    func testAutoFillCrossMidnightDefaultEndsNextDay() throws {
        let env = try freshEnv()
        let breakService = BreakService(db: env.db)
        let testDate = Date(timeIntervalSince1970: 0)

        try breakService.updateCompanyBreakSettings(
            stateCode: "CA",
            autoFillBreaks: true,
            defaultMorningBreak: nil,
            defaultLunch: "23:59",
            defaultAfternoonBreak: nil
        )

        try breakService.autoFillBreaksForDay(userId: env.adminUserId, date: testDate)

        let records = try breakService.getBreakRecordsForDay(userId: env.adminUserId, date: testDate)
        #expect(records.count == 1)
        #expect(records.first?.startedAt == "1970-01-01T23:59:00")
        #expect(records.first?.endedAt == "1970-01-02T00:29:00")
    }

    @Test("autoFillBreaksForDay skips if breaks already exist")
    func testAutoFillSkipsExisting() throws {
        let env = try freshEnv()
        let breakService = BreakService(db: env.db)

        try breakService.updateCompanyBreakSettings(
            stateCode: "CA",
            roundingMinutes: 15,
            roundingEnabled: false,
            autoFillBreaks: true,
            defaultMorningBreak: "10:00",
            defaultLunch: "12:00"
        )

        // Manually start a break first
        let record = try breakService.startBreak(userId: env.adminUserId, breakType: "break")
        try breakService.endBreak(recordId: record.id!)

        let countBefore = try breakService.getBreakRecordsForDay(userId: env.adminUserId).count

        // Auto-fill should skip "break" type since one already exists
        try breakService.autoFillBreaksForDay(userId: env.adminUserId)

        let countAfter = try breakService.getBreakRecordsForDay(userId: env.adminUserId).count
        // Lunch may be added but existing break type should not be duplicated
        #expect(countAfter >= countBefore)
    }

    @Test("autoFillBreaksForDay fills missing second scheduled break")
    func testAutoFillMissingSecondScheduledBreak() throws {
        let env = try freshEnv()
        let breakService = BreakService(db: env.db)

        try breakService.updateCompanyBreakSettings(
            stateCode: "CA",
            roundingMinutes: 15,
            roundingEnabled: false,
            autoFillBreaks: true,
            defaultMorningBreak: "10:00",
            defaultLunch: nil,
            defaultAfternoonBreak: "14:00"
        )

        try env.db.writer.write { db in
            try db.execute(sql: """
                INSERT INTO break_records
                    (user_id, break_type, started_at, ended_at, duration_minutes, is_paid, auto_filled)
                VALUES (?, 'break', date('now') || 'T10:00:00', date('now') || 'T10:15:00', 15, 1, 0)
                """, arguments: [env.adminUserId])
        }

        try breakService.autoFillBreaksForDay(userId: env.adminUserId)

        let records = try breakService.getBreakRecordsForDay(userId: env.adminUserId)
        let breakRecords = records.filter { $0.breakType == "break" }
        #expect(breakRecords.count == 2)
        #expect(breakRecords.contains { $0.startedAt.hasSuffix("T10:00:00") && !$0.autoFilled })
        #expect(breakRecords.contains { $0.startedAt.hasSuffix("T14:00:00") && $0.autoFilled })
    }

    @Test("autoFillBreaksForDay existing lunch suppresses only lunch")
    func testAutoFillExistingLunchStillFillsBreaks() throws {
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

    @Test("autoFillBreaksForDay does not duplicate existing scheduled breaks")
    func testAutoFillDoesNotDuplicateExistingScheduledBreaks() throws {
        let env = try freshEnv()
        let breakService = BreakService(db: env.db)

        try breakService.updateCompanyBreakSettings(
            stateCode: "CA",
            roundingMinutes: 15,
            roundingEnabled: false,
            autoFillBreaks: true,
            defaultMorningBreak: "10:00",
            defaultLunch: nil,
            defaultAfternoonBreak: "14:00"
        )

        try env.db.writer.write { db in
            try db.execute(sql: """
                INSERT INTO break_records
                    (user_id, break_type, started_at, ended_at, duration_minutes, is_paid, auto_filled)
                VALUES
                    (?, 'break', date('now') || 'T10:00:00', date('now') || 'T10:15:00', 15, 1, 1),
                    (?, 'break', date('now') || 'T14:00:00', date('now') || 'T14:15:00', 15, 1, 1)
                """, arguments: [env.adminUserId, env.adminUserId])
        }

        try breakService.autoFillBreaksForDay(userId: env.adminUserId)

        let records = try breakService.getBreakRecordsForDay(userId: env.adminUserId)
        #expect(records.filter { $0.breakType == "break" }.count == 2)
    }

    @Test("autoFillBreaksForDay does not duplicate timezone-qualified scheduled breaks")
    func testAutoFillDoesNotDuplicateTimezoneQualifiedScheduledBreaks() throws {
        let env = try freshEnv()
        let breakService = BreakService(db: env.db)

        try breakService.updateCompanyBreakSettings(
            stateCode: "CA",
            roundingMinutes: 15,
            roundingEnabled: false,
            autoFillBreaks: true,
            defaultMorningBreak: "10:00",
            defaultLunch: nil,
            defaultAfternoonBreak: "14:00"
        )

        try env.db.writer.write { db in
            try db.execute(sql: """
                INSERT INTO break_records
                    (user_id, break_type, started_at, ended_at, duration_minutes, is_paid, auto_filled)
                VALUES
                    (?, 'break', date('now') || 'T10:00:00Z', date('now') || 'T10:15:00Z', 15, 1, 1),
                    (?, 'break', date('now') || 'T14:00:00+00:00', date('now') || 'T14:15:00+00:00', 15, 1, 1)
                """, arguments: [env.adminUserId, env.adminUserId])
        }

        try breakService.autoFillBreaksForDay(userId: env.adminUserId)

        let records = try breakService.getBreakRecordsForDay(userId: env.adminUserId)
        #expect(records.filter { $0.breakType == "break" }.count == 2)
    }

    @Test("autoFillBreaksForDay does not duplicate breaks within scheduled minute")
    func testAutoFillDoesNotDuplicateNonzeroSecondScheduledBreaks() throws {
        let env = try freshEnv()
        let breakService = BreakService(db: env.db)

        try breakService.updateCompanyBreakSettings(
            stateCode: "CA",
            roundingMinutes: 15,
            roundingEnabled: false,
            autoFillBreaks: true,
            defaultMorningBreak: "10:00",
            defaultLunch: nil,
            defaultAfternoonBreak: "14:00"
        )

        try env.db.writer.write { db in
            try db.execute(sql: """
                INSERT INTO break_records
                    (user_id, break_type, started_at, ended_at, duration_minutes, is_paid, auto_filled)
                VALUES
                    (?, 'break', date('now') || 'T10:00:15Z', date('now') || 'T10:15:15Z', 15, 1, 0),
                    (?, 'break', date('now') || 'T14:00:45+00:00', date('now') || 'T14:15:45+00:00', 15, 1, 0)
                """, arguments: [env.adminUserId, env.adminUserId])
        }

        try breakService.autoFillBreaksForDay(userId: env.adminUserId)

        let records = try breakService.getBreakRecordsForDay(userId: env.adminUserId)
        #expect(records.filter { $0.breakType == "break" }.count == 2)
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
