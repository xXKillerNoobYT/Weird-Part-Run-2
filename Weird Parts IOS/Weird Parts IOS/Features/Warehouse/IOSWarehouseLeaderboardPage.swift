import SwiftUI
import WiredPartCore

/// Warehouse leaderboard & user ratings page.
///
/// Shows all users ranked by overall warehouse rating.
/// Managers can tap users for detailed breakdowns and training suggestions.
struct IOSWarehouseLeaderboardPage: View {
    @EnvironmentObject private var appCore: AppCore

    // MARK: - State

    @State private var isLoading = true
    @State private var loadError: String?
    @State private var leaderboard: [UserWarehouseRating] = []
    @State private var userNames: [Int64: String] = [:]
    @State private var activeSheet: ActiveSheet?

    private enum ActiveSheet: Identifiable {
        case userDetail(UserWarehouseRating)
        case consensusInfo
        case help

        var id: String {
            switch self {
            case .userDetail(let r): "detail-\(r.userId)"
            case .consensusInfo: "consensus"
            case .help: "help"
            }
        }
    }

    private var isManager: Bool {
        appCore.currentUser?.role == "manager" ||
        appCore.currentUser?.role == "admin" ||
        appCore.currentUser?.role == "owner"
    }

    var body: some View {
        VStack(spacing: 0) {
            if isLoading {
                ProgressView("Loading leaderboard...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error = loadError {
                ErrorStateView(message: error) { loadData() }
            } else {
                leaderboardContent
            }
        }
        .navigationTitle("Warehouse Leaderboard")
        .toolbar {
            ToolbarItem(placement: .secondaryAction) {
                Button { activeSheet = .help } label: {
                    Image(systemName: "questionmark.circle")
                }
            }
        }
        .sheet(item: $activeSheet) { sheet in
            sheetContent(for: sheet)
        }
        .refreshable { loadData() }
        .task { loadData() }
    }

    // MARK: - Sheet Content

    @ViewBuilder
    private func sheetContent(for sheet: ActiveSheet) -> some View {
        switch sheet {
        case .userDetail(let rating):
            UserRatingDetailSheet(rating: rating, userName: userNames[rating.userId] ?? "User")
                .environmentObject(appCore)
        case .consensusInfo:
            ConsensusInfoSheet()
        case .help:
            PageHelpSheet(
                title: "Leaderboard Help",
                sections: [
                    ("Ratings", "Each user earns a warehouse rating based on accuracy, effort, placement, speed, and proactive fixes."),
                    ("Scores", "Scores range from 0-10. Accurate counts raise your score; misplacements lower it."),
                    ("Managers", "Managers can see detailed breakdowns and training suggestions for each user.")
                ]
            )
        }
    }

    // MARK: - Content

    @ViewBuilder
    private var leaderboardContent: some View {
        List {
            // Top 3 podium
            if leaderboard.count >= 3 {
                Section {
                    HStack(alignment: .bottom, spacing: 12) {
                        Spacer()
                        podiumColumn(rank: 2, rating: leaderboard[1])
                        podiumColumn(rank: 1, rating: leaderboard[0])
                        podiumColumn(rank: 3, rating: leaderboard[2])
                        Spacer()
                    }
                    .padding(.vertical, 8)
                }
            }

            // Full list
            Section("Rankings") {
                ForEach(Array(leaderboard.enumerated()), id: \.element.userId) { index, rating in
                    leaderboardRow(rank: index + 1, rating: rating)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            if isManager {
                                activeSheet = .userDetail(rating)
                            }
                        }
                }
            }

            // Consensus verification info
            Section {
                Button {
                    activeSheet = .consensusInfo
                } label: {
                    HStack {
                        Image(systemName: "person.3.fill")
                            .foregroundStyle(.blue)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Multi-User Consensus")
                                .font(.subheadline)
                                .fontWeight(.medium)
                            Text("How consensus verification works")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .listStyle(.insetGrouped)
    }

    // MARK: - Podium

    private func podiumColumn(rank: Int, rating: UserWarehouseRating) -> some View {
        VStack(spacing: 4) {
            // Medal
            Image(systemName: rank == 1 ? "medal.fill" : rank == 2 ? "medal.fill" : "medal.fill")
                .font(.title2)
                .foregroundStyle(rank == 1 ? .yellow : rank == 2 ? Color(.systemGray3) : .orange)

            Text(userNames[rating.userId] ?? "User")
                .font(.caption)
                .fontWeight(.semibold)
                .lineLimit(1)

            Text(String(format: "%.1f", rating.overallRating))
                .font(.title3)
                .fontWeight(.bold)
                .foregroundStyle(ratingColor(rating.overallRating))

            // Bar
            RoundedRectangle(cornerRadius: 4)
                .fill(ratingColor(rating.overallRating).opacity(0.3))
                .frame(width: 60, height: CGFloat(rank == 1 ? 80 : rank == 2 ? 60 : 45))
                .overlay(alignment: .bottom) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(ratingColor(rating.overallRating))
                        .frame(height: CGFloat(rating.overallRating / 10.0) * CGFloat(rank == 1 ? 80 : rank == 2 ? 60 : 45))
                }

            Text("#\(rank)")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(width: 80)
    }

    // MARK: - List Row

    private func leaderboardRow(rank: Int, rating: UserWarehouseRating) -> some View {
        HStack(spacing: 12) {
            // Rank badge
            Text("\(rank)")
                .font(.system(.caption, weight: .bold))
                .foregroundStyle(rank <= 3 ? .white : .secondary)
                .frame(width: 28, height: 28)
                .background(
                    Circle().fill(rank <= 3 ? ratingColor(rating.overallRating) : Color(.systemGray5))
                )

            // Name
            VStack(alignment: .leading, spacing: 2) {
                Text(userNames[rating.userId] ?? "User #\(rating.userId)")
                    .font(.subheadline)
                    .fontWeight(.medium)
                Text("\(rating.totalAudits) audits · \(rating.totalAccurate) accurate")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            // Rating bar
            VStack(alignment: .trailing, spacing: 4) {
                Text(String(format: "%.1f", rating.overallRating))
                    .font(.subheadline)
                    .fontWeight(.bold)
                    .foregroundStyle(ratingColor(rating.overallRating))

                ProgressView(value: rating.overallRating, total: 10)
                    .tint(ratingColor(rating.overallRating))
                    .frame(width: 60)
            }

            if isManager {
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 2)
    }

    // MARK: - Helpers

    private func ratingColor(_ rating: Double) -> Color {
        if rating >= 8 { return .green }
        if rating >= 5 { return .orange }
        return .red
    }

    // MARK: - Data Loading

    private func loadData() {
        guard let service = appCore.warehouseService else {
            loadError = "Warehouse service unavailable"
            isLoading = false
            return
        }
        isLoading = leaderboard.isEmpty
        loadError = nil
        do {
            leaderboard = try service.getWarehouseLeaderboard()
            // Load user names
            for rating in leaderboard {
                if userNames[rating.userId] == nil {
                    userNames[rating.userId] = try? fetchUserName(userId: rating.userId)
                }
            }
        } catch {
            loadError = error.localizedDescription
        }
        isLoading = false
    }

    private func fetchUserName(userId: Int64) throws -> String? {
        // Use people service if available
        if let name = try? appCore.peopleService?.getUser(userId: userId) {
            return name.displayName
        }
        return "User #\(userId)"
    }
}

// MARK: - User Rating Detail Sheet (Manager Only)

private struct UserRatingDetailSheet: View {
    @EnvironmentObject private var appCore: AppCore
    @Environment(\.dismiss) private var dismiss

    let rating: UserWarehouseRating
    let userName: String

    var body: some View {
        NavigationStack {
            List {
                // Overview
                Section {
                    HStack {
                        Text(userName)
                            .font(.title3)
                            .fontWeight(.bold)
                        Spacer()
                        Text(String(format: "%.1f", rating.overallRating))
                            .font(.title)
                            .fontWeight(.bold)
                            .foregroundStyle(ratingColor(rating.overallRating))
                        Text("/ 10")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }

                // Detailed breakdown
                Section("Rating Breakdown") {
                    ratingBar("Accuracy", value: rating.accuracyRating, weight: "30%")
                    ratingBar("Placement", value: rating.placementRating, weight: "20%")
                    ratingBar("Effort", value: rating.effortRating, weight: "15%")
                    ratingBar("Proactive", value: rating.proactiveRating, weight: "15%")
                    ratingBar("Speed", value: rating.speedRating, weight: "10%")
                    ratingBar("Compliance", value: rating.wizardCompliance, weight: "10%")
                }

                // Stats
                Section("Statistics") {
                    LabeledContent("Total Audits", value: "\(rating.totalAudits)")
                    LabeledContent("Accurate Counts", value: "\(rating.totalAccurate)")
                    if rating.totalAudits > 0 {
                        let pct = Double(rating.totalAccurate) / Double(rating.totalAudits) * 100
                        LabeledContent("Accuracy Rate", value: String(format: "%.0f%%", pct))
                    }
                    LabeledContent("Misplacements Found", value: "\(rating.totalMisplacementsFound)")
                    LabeledContent("Proactive Fixes", value: "\(rating.totalProactiveFixes)")
                }

                // Training suggestions
                Section("Training Suggestions") {
                    trainingSection
                }
            }
            .navigationTitle("User Detail")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func ratingBar(_ label: String, value: Double, weight: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(label)
                    .font(.subheadline)
                Spacer()
                Text(String(format: "%.1f", value))
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundStyle(ratingColor(value))
                Text("(\(weight))")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            ProgressView(value: value, total: 10)
                .tint(ratingColor(value))
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private var trainingSection: some View {
        let weakest = findWeakestArea()

        switch weakest.area {
        case "accuracy":
            trainingRow(
                icon: "target",
                title: "Accuracy Training",
                suggestion: rating.accuracyRating < 3
                    ? "Start with larger, easier-to-count items before moving to small parts."
                    : "Double-count when variance occurs. Use bins for small parts."
            )
        case "placement":
            trainingRow(
                icon: "mappin",
                title: "Placement Training",
                suggestion: "Buddy up with a higher-rated user to learn optimal storage patterns."
            )
        case "effort":
            trainingRow(
                icon: "flame",
                title: "Engagement",
                suggestion: "Set a personal goal: audit at least 10 parts per shift."
            )
        case "proactive":
            trainingRow(
                icon: "hand.raised",
                title: "Proactive Improvement",
                suggestion: "When you spot something out of place, take 30 seconds to fix it."
            )
        case "speed":
            trainingRow(
                icon: "hare",
                title: "Speed Training",
                suggestion: "Use speed mode for familiar areas. Scan QR codes instead of searching."
            )
        case "compliance":
            trainingRow(
                icon: "list.bullet.clipboard",
                title: "Process Compliance",
                suggestion: "Follow the movement wizard for every stock move — it tracks everything."
            )
        default:
            trainingRow(
                icon: "star",
                title: "Great Performance",
                suggestion: "All ratings are strong. Consider mentoring newer team members."
            )
        }
    }

    private func trainingRow(icon: String, title: String, suggestion: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .foregroundStyle(.blue)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.medium)
                Text(suggestion)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func findWeakestArea() -> (area: String, value: Double) {
        let areas: [(String, Double)] = [
            ("accuracy", rating.accuracyRating),
            ("placement", rating.placementRating),
            ("effort", rating.effortRating),
            ("proactive", rating.proactiveRating),
            ("speed", rating.speedRating),
            ("compliance", rating.wizardCompliance)
        ]
        let weakest = areas.min(by: { $0.1 < $1.1 }) ?? ("none", 10)
        // Only show suggestion if there's actual room for improvement
        if weakest.1 >= 8 { return ("none", weakest.1) }
        return weakest
    }

    private func ratingColor(_ rating: Double) -> Color {
        if rating >= 8 { return .green }
        if rating >= 5 { return .orange }
        return .red
    }
}

// MARK: - Consensus Info Sheet

private struct ConsensusInfoSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section("What is Consensus Verification?") {
                    Text("When a part has low confidence (<60%), high dollar value, or a history of mismatches, the system assigns 2-3 users to count it independently.")
                        .font(.subheadline)
                }

                Section("How It Works") {
                    infoRow(step: "1", text: "System assigns 2-3 users to count the same part")
                    infoRow(step: "2", text: "Users count independently — they can't see others' counts")
                    infoRow(step: "3", text: "System compares all counts when complete")
                }

                Section("Results") {
                    HStack(spacing: 12) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("All Match").fontWeight(.medium)
                            Text("All users boosted, confidence → 100%").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    HStack(spacing: 12) {
                        Image(systemName: "person.2.fill")
                            .foregroundStyle(.orange)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("2 Match, 1 Off").fontWeight(.medium)
                            Text("2 boosted, 1 lowered + training suggestion").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    HStack(spacing: 12) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.red)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("All Different").fontWeight(.medium)
                            Text("All lowered, manager recount flagged").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .navigationTitle("Consensus Verification")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func infoRow(step: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(step)
                .font(.caption)
                .fontWeight(.bold)
                .foregroundStyle(.white)
                .frame(width: 24, height: 24)
                .background(Circle().fill(.blue))
            Text(text)
                .font(.subheadline)
        }
    }
}
