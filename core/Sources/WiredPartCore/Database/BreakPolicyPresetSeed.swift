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

        // Capture the active state rows being replaced BEFORE soft-deleting them so
        // configured break bonuses (break_bonuses.policy_id → break_policies FK) can be
        // re-linked to the replacement preset rows. Without this, bonuses attached to the
        // migration-042 WY row would dangle on a soft-deleted policy and silently
        // disappear from Settings on upgraded installs.
        let replacedPolicies = try Row.fetchAll(db, sql: """
            SELECT id, state_code, policy_type, work_day_hours
            FROM break_policies
            WHERE deleted_at IS NULL
              AND policy_type IN ('state_required_paid', 'state_required_offered')
            """)

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

        // Re-link bonuses from each replaced policy row to the replacement preset row
        // for the same (state_code, policy_type) and closest preset workday length.
        // COALESCE keeps the old policy_id when no replacement exists (e.g. a row with
        // a jurisdiction code outside the preset table) rather than orphaning the bonus.
        for replaced in replacedPolicies {
            let oldId: Int64 = replaced["id"]
            let stateCode: String? = replaced["state_code"]
            let policyType: String = replaced["policy_type"]
            let workDayHours: Int = replaced["work_day_hours"]
            let presetHours = workDayHours >= 10 ? 10 : 8
            try db.execute(sql: """
                UPDATE break_bonuses
                SET policy_id = COALESCE(
                    (
                        SELECT id
                        FROM break_policies
                        WHERE deleted_at IS NULL
                          AND policy_type = ?
                          AND state_code = ?
                          AND work_day_hours = ?
                        LIMIT 1
                    ),
                    policy_id
                )
                WHERE policy_id = ?
                """, arguments: [policyType, stateCode, presetHours, oldId])
        }
    }

    private static func paidRestPreset(stateCode: String, workDayHours: Int) -> BreakPolicyPreset {
        let breakCount: Int
        let breakMinutes: Int

        switch stateCode {
        case "CA", "CO", "KY", "NV", "OR", "WA":
            // 10-minute paid rest period per 4 hours worked (or major fraction thereof):
            // an 8-hour day yields 2 rest breaks, a 10-hour day yields 3 (the third
            // 4-hour segment is entered / is a major fraction at 10 hours).
            breakCount = workDayHours >= 10 ? 3 : 2
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
        case "CA":
            // One 30-minute meal period for shifts over 5 hours; a second 30-minute
            // meal period is required when working beyond 10 hours. The 10-hour
            // preset row covers 10+ hour days, so it carries both meal periods.
            lunchMinutes = workDayHours >= 10 ? 60 : 30
            breakCount = 0
            breakMinutes = 0
        case "CO", "CT", "DC", "DE", "KY", "ME", "MA", "NE", "NV", "NH", "ND", "OR", "TN", "WA":
            lunchMinutes = 30
            breakCount = 0
            breakMinutes = 0
        case "IL", "WV":
            lunchMinutes = 20
            breakCount = 0
            breakMinutes = 0
        case "MD":
            // 30-minute shift break for 6+ hour shifts; an additional 15-minute
            // break applies only to shifts longer than 10 hours (Healthy Retail
            // Employee Act), so the 8-hour row must not carry it.
            lunchMinutes = 30
            breakCount = workDayHours >= 10 ? 1 : 0
            breakMinutes = workDayHours >= 10 ? 15 : 0
        case "MN", "VT":
            lunchMinutes = 0
            breakCount = 0
            breakMinutes = 0
        case "NY":
            lunchMinutes = 30
            breakCount = workDayHours >= 10 ? 1 : 0
            breakMinutes = workDayHours >= 10 ? 20 : 0
        case "RI":
            // 30-minute meal period for 8-hour shifts (the 20-minute tier applies
            // to 6-hour shifts, which are below both seeded workday lengths).
            lunchMinutes = 30
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
