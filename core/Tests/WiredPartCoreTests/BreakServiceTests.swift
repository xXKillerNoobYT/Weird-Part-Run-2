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

    @Test("10-hour presets differ from 8-hour presets where state law differs")
    func testTenHourPresetsDifferWhereLawDiffers() throws {
        let env = try freshEnv()
        let breakService = BreakService(db: env.db)

        func policy(_ state: String, _ type: String, _ hours: Int) throws -> BreakPolicy? {
            try breakService.getBreakPolicy(stateCode: state, dayHours: hours)
                .first { $0.policyType == type && $0.workDayHours == hours }
        }

        // CA rest: 10 min per 4 hours or major fraction — 2 breaks at 8h, 3 at 10h.
        #expect(try policy("CA", "state_required_paid", 8)?.breakCount == 2)
        #expect(try policy("CA", "state_required_paid", 10)?.breakCount == 3)
        #expect(try policy("CA", "state_required_paid", 10)?.breakMinutes == 10)

        // CA meal: second 30-minute meal period on the 10+ hour row.
        #expect(try policy("CA", "state_required_offered", 8)?.lunchMinutes == 30)
        #expect(try policy("CA", "state_required_offered", 10)?.lunchMinutes == 60)

        // Same per-4-hour rest rule for the other rest-break states.
        for state in ["CO", "KY", "NV", "OR", "WA"] {
            #expect(try policy(state, "state_required_paid", 8)?.breakCount == 2)
            #expect(try policy(state, "state_required_paid", 10)?.breakCount == 3)
        }

        // MD: additional 15-minute break applies only to shifts longer than 10 hours.
        #expect(try policy("MD", "state_required_offered", 8)?.breakCount == 0)
        #expect(try policy("MD", "state_required_offered", 10)?.breakCount == 1)
        #expect(try policy("MD", "state_required_offered", 10)?.breakMinutes == 15)

        // NY: additional 20-minute break on 10+ hour days only.
        #expect(try policy("NY", "state_required_offered", 8)?.breakCount == 0)
        #expect(try policy("NY", "state_required_offered", 10)?.breakCount == 1)
        #expect(try policy("NY", "state_required_offered", 10)?.breakMinutes == 20)
    }

    @Test("Seeding presets re-links existing break bonuses to the replacement rows")
    func testSeedRelinksBonusesToReplacementPresetRows() throws {
        let env = try freshEnv()

        // Simulate a pre-preset install: only the migration-042 WY row exists,
        // with a configured lunch bonus attached to it.
        try env.db.writer.write { db in
            try db.execute(sql: "DELETE FROM break_bonuses")
            try db.execute(sql: "DELETE FROM break_policies")
            try db.execute(sql: """
                INSERT INTO break_policies
                    (state_code, policy_type, work_day_hours, lunch_minutes, break_count, break_minutes, data_source, data_date)
                VALUES ('WY', 'state_required_paid', 8, 30, 2, 15, 'us_dept_of_labor', date('now'))
                """)
            try db.execute(sql: """
                INSERT INTO break_bonuses (policy_id, bonus_type, bonus_amount, description, is_enabled)
                VALUES ((SELECT id FROM break_policies WHERE state_code = 'WY'), 'lunch', 5.0, 'Lunch compliance bonus', 1)
                """)
            try AppDatabase.seedBreakPolicyPresets(db)
        }

        let (replacementId, bonusPolicyId, oldRowDeleted) = try env.db.writer.read { db -> (Int64?, Int64?, Bool) in
            let replacementId = try Int64.fetchOne(db, sql: """
                SELECT id FROM break_policies
                WHERE deleted_at IS NULL
                  AND state_code = 'WY'
                  AND policy_type = 'state_required_paid'
                  AND work_day_hours = 8
                """)
            let bonusPolicyId = try Int64.fetchOne(db, sql: """
                SELECT policy_id FROM break_bonuses WHERE bonus_type = 'lunch'
                """)
            let oldRowDeleted = try Bool.fetchOne(db, sql: """
                SELECT deleted_at IS NOT NULL FROM break_policies
                WHERE data_source = 'us_dept_of_labor'
                """) ?? false
            return (replacementId, bonusPolicyId, oldRowDeleted)
        }

        #expect(replacementId != nil)
        #expect(bonusPolicyId == replacementId)
        #expect(oldRowDeleted)

        // The bonus must be resolvable through the id the Settings page now uses.
        let breakService = BreakService(db: env.db)
        let bonuses = try breakService.getBreakBonuses(policyId: replacementId ?? -1)
        #expect(bonuses.count == 1)
        #expect(bonuses.first?.bonusType == "lunch")
        #expect(bonuses.first?.isEnabled == true)
    }

    @Test("Paid lunch timer falls back to 30 minutes when the state lists no paid lunch")
    func testPaidLunchTimerNeverZeroFromSeededPresets() throws {
        let env = try freshEnv()
        let breakService = BreakService(db: env.db)

        // Default company state (WY): seeded state_required_paid row has lunch 0,
        // but the timer must never start at 0 minutes.
        #expect(try breakService.paidLunchTimerMinutes() == 30)

        // Same for every other seeded jurisdiction (none mandate a paid lunch).
        try breakService.updateCompanyBreakSettings(stateCode: "CA")
        #expect(try breakService.paidLunchTimerMinutes() == 30)

        // A positive state paid-lunch value, when present, wins over the default.
        try env.db.writer.write { db in
            try db.execute(sql: """
                UPDATE break_policies
                SET lunch_minutes = 45
                WHERE deleted_at IS NULL
                  AND state_code = 'CA'
                  AND policy_type = 'state_required_paid'
                  AND work_day_hours = 8
                """)
        }
        #expect(try breakService.paidLunchTimerMinutes() == 45)
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

    @Test("Break compliance keeps 2-break/30-minute defaults when state presets list zero")
    func testBreakComplianceDefaultsNotNeuteredBySeededPresets() throws {
        let env = try freshEnv()
        let breakService = BreakService(db: env.db)

        // Default state (WY) presets list 0 required breaks / 0 lunch. Compliance must
        // keep the historical 2-break / 30-minute requirements, not become trivially
        // compliant — and bonus eligibility must not invert to "took zero breaks".
        let empty = try breakService.calculateBreakCompliance(userId: env.adminUserId)
        #expect(empty.requiredBreaks == 2)
        #expect(empty.requiredLunchMinutes == 30)
        #expect(!empty.isCompliant)
        #expect(!empty.bonusEligible)

        // Taking the required breaks + lunch (manually, not auto-filled) is compliant
        // and bonus-eligible, matching pre-preset behavior.
        try env.db.writer.write { db in
            try db.execute(sql: """
                INSERT INTO break_records
                    (user_id, break_type, started_at, ended_at, duration_minutes, is_paid, auto_filled)
                VALUES
                    (?, 'break', date('now') || 'T10:00:00', date('now') || 'T10:15:00', 15, 1, 0),
                    (?, 'break', date('now') || 'T14:30:00', date('now') || 'T14:45:00', 15, 1, 0),
                    (?, 'lunch_paid', date('now') || 'T12:00:00', date('now') || 'T12:30:00', 30, 1, 0)
                """, arguments: [env.adminUserId, env.adminUserId, env.adminUserId])
        }

        let met = try breakService.calculateBreakCompliance(userId: env.adminUserId)
        #expect(met.takenBreaks == 2)
        #expect(met.takenLunchMinutes == 30)
        #expect(met.isCompliant)
        #expect(met.bonusEligible)
    }

    @Test("Break compliance uses positive seeded state requirements when present")
    func testBreakComplianceUsesSeededStateRequirements() throws {
        let env = try freshEnv()
        let breakService = BreakService(db: env.db)

        // IL seeds 2 x 15 paid rest breaks and a 20-minute meal period.
        try breakService.updateCompanyBreakSettings(stateCode: "IL", autoFillBreaks: false)

        let compliance = try breakService.calculateBreakCompliance(userId: env.adminUserId)
        #expect(compliance.requiredBreaks == 2)
        #expect(compliance.requiredLunchMinutes == 20)
        #expect(!compliance.isCompliant)
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
