# 19I — Admin Voting Dashboard

## Context
You are working on a SwiftUI iOS app. Admins need visibility into voting analytics for training purposes. This adds an admin-only section to the Companions page.

**Available PartsService methods (from 19C):**
- `getUserVotingAccuracy(userId:)` → `(totalVotes, correctVotes, accuracy)`
- `getLastWeekResults(userId:)` → results array

**Available AuthService patterns:**
- Users loaded via raw SQL: `SELECT id, display_name FROM users WHERE is_active = 1`
- Permission check: `appCore.hasPermission("manage_people")`

## Task

### 1. Add Admin Dashboard sheet

Add a `.adminDashboard` case to the `ActiveSheet` enum in `PartsCompanionsPage.swift`.

Add a toolbar button visible only to admin/manager:
```swift
if appCore.hasPermission("manage_people") {
    Button { activeSheet = .adminDashboard } label: {
        Image(systemName: "chart.bar.xaxis")
    }
}
```

### 2. Create CompanionAdminDashboardSheet

```swift
private struct CompanionAdminDashboardSheet: View {
    @EnvironmentObject private var appCore: AppCore
    @Environment(\.dismiss) private var dismiss

    @State private var userStats: [UserVotingStat] = []
    @State private var pollHistory: [PollHistoryRow] = []
    @State private var isLoading = true
    @State private var ruleStats: (manual: Int, autoDiscovered: Int) = (0, 0)

    struct UserVotingStat: Identifiable {
        let id: Int64
        let displayName: String
        let totalVotes: Int
        let correctVotes: Int
        let accuracy: Double
        let hasPower: Bool
    }

    struct PollHistoryRow: Identifiable {
        let id: Int64
        let name: String
        let result: String
        let totalVotes: Int
        let poweredAccept: Int
        let poweredReject: Int
        let wasLocked: Bool
        let finalizedAt: String
    }

    var body: some View {
        NavigationStack {
            List {
                // Stats summary
                Section("Overview") {
                    HStack {
                        Label("Manual Rules", systemImage: "hand.draw")
                        Spacer()
                        Text("\(ruleStats.manual)")
                            .fontWeight(.medium)
                    }
                    HStack {
                        Label("Auto-Discovered", systemImage: "sparkles")
                        Spacer()
                        Text("\(ruleStats.autoDiscovered)")
                            .fontWeight(.medium)
                    }
                }

                // User voting accuracy
                Section("Team Voting Accuracy") {
                    if userStats.isEmpty {
                        Text("No voting data yet")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(userStats) { user in
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    HStack {
                                        Text(user.displayName)
                                            .fontWeight(.medium)
                                        if !user.hasPower {
                                            Text("(no vote power)")
                                                .font(.caption2)
                                                .foregroundStyle(.orange)
                                        }
                                    }
                                    Text("\(user.correctVotes)/\(user.totalVotes) correct")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Text("\(Int(user.accuracy * 100))%")
                                    .font(.title3)
                                    .fontWeight(.bold)
                                    .foregroundStyle(user.accuracy >= 0.7 ? .green : user.accuracy >= 0.4 ? .orange : .red)
                            }
                        }
                    }
                }

                // Poll history
                Section("Poll History") {
                    if pollHistory.isEmpty {
                        Text("No completed polls yet")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(pollHistory) { poll in
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Text(poll.name)
                                        .fontWeight(.medium)
                                    Spacer()
                                    Text(poll.result.capitalized)
                                        .font(.caption)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(poll.result == "accepted" ? Color.green.opacity(0.1) : Color.red.opacity(0.1))
                                        .clipShape(Capsule())
                                }
                                HStack {
                                    Text("Votes: \(poll.poweredAccept) accept / \(poll.poweredReject) reject")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    if poll.wasLocked {
                                        Label("Admin Locked", systemImage: "lock.fill")
                                            .font(.caption2)
                                            .foregroundStyle(.orange)
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Voting Analytics")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .task { await loadData() }
        }
    }

    private func loadData() async {
        guard let service = appCore.partsService, let db = appCore.db else { return }
        do {
            // Load user voting stats
            let users = try await db.writer.read { dbConn in
                try Row.fetchAll(dbConn, sql: """
                    SELECT u.id, u.display_name,
                           EXISTS(SELECT 1 FROM user_hats uh
                                  JOIN hat_permissions hp ON hp.hat_id = uh.hat_id
                                  WHERE uh.user_id = u.id AND uh.is_active = 1
                                  AND hp.permission_key = 'companion_vote_power') AS has_power
                    FROM users u WHERE u.is_active = 1 AND u.deleted_at IS NULL
                    ORDER BY u.display_name ASC
                    """)
            }

            var stats: [UserVotingStat] = []
            for user in users {
                let userId: Int64 = user["id"]
                let accuracy = try service.getUserVotingAccuracy(userId: userId)
                stats.append(UserVotingStat(
                    id: userId,
                    displayName: user["display_name"],
                    totalVotes: accuracy.totalVotes,
                    correctVotes: accuracy.correctVotes,
                    accuracy: accuracy.accuracy,
                    hasPower: (user["has_power"] as Int) == 1
                ))
            }
            // Sort by accuracy descending
            stats.sort { $0.accuracy > $1.accuracy }

            // Load poll history
            let historyRows = try await db.writer.read { dbConn in
                try Row.fetchAll(dbConn, sql: """
                    SELECT cp.id, cp.proposed_rule_name, cp.result,
                           cpr.total_votes, cpr.powered_accept, cpr.powered_reject,
                           cpr.was_admin_locked, cpr.finalized_at
                    FROM companion_polls cp
                    JOIN companion_poll_results cpr ON cpr.poll_id = cp.id
                    ORDER BY cpr.finalized_at DESC
                    LIMIT 20
                    """)
            }

            let history = historyRows.map { row in
                PollHistoryRow(
                    id: row["id"], name: row["proposed_rule_name"],
                    result: row["result"] ?? "unknown",
                    totalVotes: row["total_votes"],
                    poweredAccept: row["powered_accept"],
                    poweredReject: row["powered_reject"],
                    wasLocked: (row["was_admin_locked"] as Int) == 1,
                    finalizedAt: row["finalized_at"] ?? ""
                )
            }

            // Load rule stats
            let manualCount = try await db.writer.read { dbConn in
                try Int.fetchOne(dbConn, sql: """
                    SELECT COUNT(*) FROM companion_rules
                    WHERE deleted_at IS NULL AND id NOT IN (
                        SELECT COALESCE(created_rule_id, 0) FROM companion_polls WHERE created_rule_id IS NOT NULL
                    )
                    """) ?? 0
            }
            let autoCount = try await db.writer.read { dbConn in
                try Int.fetchOne(dbConn, sql: """
                    SELECT COUNT(*) FROM companion_polls WHERE created_rule_id IS NOT NULL
                    """) ?? 0
            }

            await MainActor.run {
                userStats = stats
                pollHistory = history
                ruleStats = (manual: manualCount, autoDiscovered: autoCount)
                isLoading = false
            }
        } catch {
            await MainActor.run { isLoading = false }
        }
    }
}
```

## Success Criteria
- [ ] Admin dashboard accessible via toolbar button (manage_people permission gated)
- [ ] Shows manual vs auto-discovered rule counts
- [ ] User voting accuracy table with % correct, color-coded
- [ ] Shows which users have vote power and which don't
- [ ] Poll history with accept/reject results, vote counts, lock indicator
- [ ] Project builds with no errors

## Log Entry
```
## Prompt 19I Results (YYYY-MM-DD)
- Added CompanionAdminDashboardSheet with voting analytics
- User accuracy table (training tool), poll history, rule stats
- Permission-gated: manage_people required
- Build: [PASS/FAIL]
```

When done, start prompt 19J next.
