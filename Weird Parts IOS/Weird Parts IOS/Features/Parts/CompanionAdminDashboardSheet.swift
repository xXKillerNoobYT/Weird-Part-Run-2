import SwiftUI
import WiredPartCore

/// Admin voting analytics dashboard for companion rule polls.
/// Shows team voting accuracy, poll history, and rule statistics.
struct CompanionAdminDashboardSheet: View {
    @EnvironmentObject private var appCore: AppCore
    @Environment(\.dismiss) private var dismiss

    @State private var userStats: [UserVotingStat] = []
    @State private var pollHistory: [PollHistoryRow] = []
    @State private var loadError: String?
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
            .refreshable { await loadData() }
            .task { await loadData() }
            .alert("Error", isPresented: Binding<Bool>(
                get: { loadError != nil },
                set: { if !$0 { loadError = nil } }
            )) {
                Button("OK") { loadError = nil }
            } message: {
                Text(loadError ?? "")
            }
        }
    }

    private func loadData() async {
        guard let service = appCore.partsService else {
            loadError = "Service not available"
            return
        }
        do {
            // Load active users with vote power, then enrich with accuracy
            let users = try service.getActiveUsersWithVotePower()

            var stats: [UserVotingStat] = []
            for user in users {
                let accuracy = try service.getUserVotingAccuracy(userId: user.id)
                stats.append(UserVotingStat(
                    id: user.id,
                    displayName: user.displayName,
                    totalVotes: accuracy.totalVotes,
                    correctVotes: accuracy.correctVotes,
                    accuracy: accuracy.accuracy,
                    hasPower: user.hasPower
                ))
            }
            // Sort by accuracy descending, then by total votes
            stats.sort { $0.accuracy > $1.accuracy }

            // Load poll history via service
            let historyRows = try service.getPollHistory(limit: 20)
            let history = historyRows.map { row in
                PollHistoryRow(
                    id: row.id,
                    name: row.name,
                    result: row.result,
                    totalVotes: row.totalVotes,
                    poweredAccept: row.poweredAccept,
                    poweredReject: row.poweredReject,
                    wasLocked: row.wasLocked,
                    finalizedAt: row.finalizedAt
                )
            }

            // Load rule stats via service
            let ruleStatsResult = try service.getCompanionRuleStats()

            await MainActor.run {
                userStats = stats
                pollHistory = history
                ruleStats = (manual: ruleStatsResult.manual, autoDiscovered: ruleStatsResult.autoDiscovered)
            }
        } catch {
            await MainActor.run {
                loadError = userFriendlyError(error, context: "load companion admin data")
            }
        }
    }
}
