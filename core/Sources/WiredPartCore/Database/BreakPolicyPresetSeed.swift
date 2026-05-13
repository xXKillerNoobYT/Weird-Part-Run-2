import GRDB

struct BreakPolicyPreset: Sendable {
    let stateCode: String
    let policyType: String
    let workDayHours: Int
    let lunchMinutes: Int
    let breakCount: Int
    let breakMinutes: Int
    let dataSource: String
    let dataDate: String
}

extension AppDatabase {
    static let breakPolicyJurisdictionCodes: [String] = [
        "AL", "AK", "AZ", "AR", "CA", "CO", "CT", "DC", "DE", "FL",
        "GA", "HI", "ID", "IL", "IN", "IA", "KS", "KY", "LA", "ME",
        "MD", "MA", "MI", "MN", "MS", "MO", "MT", "NE", "NV", "NH",
        "NJ", "NM", "NY", "NC", "ND", "OH", "OK", "OR", "PA", "RI",
        "SC", "SD", "TN", "TX", "UT", "VT", "VA", "WA", "WV", "WI",
        "WY"
    ]

    private static let dolPresetSource = "US DOL WHD adult private-sector meal/rest period tables"
    private static let dolPresetDate = "2023-01-01"

    static var breakPolicyPresets: [BreakPolicyPreset] {
        breakPolicyJurisdictionCodes.flatMap { code in
            [
                paidRestPreset(stateCode: code, workDayHours: 8),
                paidRestPreset(stateCode: code, workDayHours: 10),
                mealPreset(stateCode: code, workDayHours: 8),
                mealPreset(stateCode: code, workDayHours: 10),
            ]
        }
    }

    static func seedBreakPolicyPresets(_ db: Database) throws {
        let expectedCount = breakPolicyPresets.count
        let currentPresetCount = try Int.fetchOne(db, sql: """
            SELECT COUNT(*)
            FROM break_policies
            WHERE deleted_at IS NULL
              AND policy_type IN ('state_required_paid', 'state_required_offered')
              AND data_source = ?
              AND data_date = ?
            """, arguments: [dolPresetSource, dolPresetDate]) ?? 0

        guard currentPresetCount != expectedCount else { return }

        try db.execute(sql: """
            UPDATE break_policies
            SET deleted_at = datetime('now'),
                updated_at = datetime('now')
            WHERE deleted_at IS NULL
              AND policy_type IN ('state_required_paid', 'state_required_offered')
            """)

        for preset in breakPolicyPresets {
            try db.execute(sql: """
                INSERT INTO break_policies (
                    state_code, policy_type, work_day_hours, lunch_minutes,
                    break_count, break_minutes, data_source, data_date
                )
                VALUES (?, ?, ?, ?, ?, ?, ?, ?)
                """, arguments: [
                    preset.stateCode,
                    preset.policyType,
                    preset.workDayHours,
                    preset.lunchMinutes,
                    preset.breakCount,
                    preset.breakMinutes,
                    preset.dataSource,
                    preset.dataDate,
                ])
        }
    }

    private static func paidRestPreset(stateCode: String, workDayHours: Int) -> BreakPolicyPreset {
        let breakCount: Int
        let breakMinutes: Int

        switch stateCode {
        case "CA", "CO", "KY", "NV", "OR", "WA":
            breakCount = 2
            breakMinutes = 10
        case "IL":
            breakCount = 2
            breakMinutes = 15
        case "MN", "VT":
            // DOL lists these as reasonable/adequate opportunities without a fixed minute value.
            breakCount = 0
            breakMinutes = 0
        default:
            breakCount = 0
            breakMinutes = 0
        }

        return BreakPolicyPreset(
            stateCode: stateCode,
            policyType: "state_required_paid",
            workDayHours: workDayHours,
            lunchMinutes: 0,
            breakCount: breakCount,
            breakMinutes: breakMinutes,
            dataSource: dolPresetSource,
            dataDate: dolPresetDate
        )
    }

    private static func mealPreset(stateCode: String, workDayHours: Int) -> BreakPolicyPreset {
        let lunchMinutes: Int
        let breakCount: Int
        let breakMinutes: Int

        switch stateCode {
        case "CA", "CO", "CT", "DC", "DE", "KY", "ME", "MA", "NE", "NV", "NH", "ND", "OR", "TN", "WA":
            lunchMinutes = 30
            breakCount = 0
            breakMinutes = 0
        case "IL", "WV":
            lunchMinutes = 20
            breakCount = 0
            breakMinutes = 0
        case "MD":
            lunchMinutes = 30
            breakCount = workDayHours >= 8 ? 1 : 0
            breakMinutes = workDayHours >= 8 ? 15 : 0
        case "MN", "VT":
            lunchMinutes = 0
            breakCount = 0
            breakMinutes = 0
        case "NY":
            lunchMinutes = 30
            breakCount = workDayHours >= 10 ? 1 : 0
            breakMinutes = workDayHours >= 10 ? 20 : 0
        case "RI":
            lunchMinutes = workDayHours >= 8 ? 30 : 20
            breakCount = 0
            breakMinutes = 0
        default:
            lunchMinutes = 0
            breakCount = 0
            breakMinutes = 0
        }

        return BreakPolicyPreset(
            stateCode: stateCode,
            policyType: "state_required_offered",
            workDayHours: workDayHours,
            lunchMinutes: lunchMinutes,
            breakCount: breakCount,
            breakMinutes: breakMinutes,
            dataSource: dolPresetSource,
            dataDate: dolPresetDate
        )
    }
}
