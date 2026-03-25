import SwiftUI
import WiredPartCore

/// Office Dashboard — the manager's morning starting point.
///
/// Sections: AI Briefing, Needs Your Attention (priority-colored),
/// Today's Schedule, Financial Snapshot (hat-gated), Background Tasks.
struct IOSOfficeDashboardPage: View {
    @EnvironmentObject private var appCore: AppCore
    @State private var briefing: DashboardService.OfficeBriefing?
    @State private var attentionItems: [DashboardService.AttentionItem] = []
    @State private var todaySchedule: [DashboardService.ScheduleItem] = []
    @State private var financialSnapshot: DashboardService.FinancialSnapshot?
    @State private var loadError: String?
    @State private var isLoading = true

    // Simple 1-hour briefing cache
    @State private var cachedBriefing: DashboardService.OfficeBriefing?
    @State private var cachedAt: Date?

    var body: some View {
        List {
            if isLoading {
                Section {
                    HStack {
                        Spacer()
                        ProgressView("Loading dashboard...")
                        Spacer()
                    }
                }
            } else if let error = loadError {
                Section {
                    Label(error, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.red)
                }
                Section {
                    Button("Retry") { loadData() }
                        .buttonStyle(.bordered)
                }
            } else {
                aiSummarySection
                attentionSection
                scheduleSection
                if appCore.hasPermission("view_financials") {
                    financialSection
                }
                backgroundTasksSection
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Office Dashboard")
        .refreshable { loadData() }
        .onAppear { loadData() }
    }

    // MARK: - AI Summary Section

    @ViewBuilder
    private var aiSummarySection: some View {
        Section {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: "sparkles")
                        .foregroundStyle(.purple)
                    Text("Daily Briefing")
                        .font(.headline)
                    Spacer()
                    if let briefing {
                        Text(briefing.generatedAt, format: .dateTime.hour().minute())
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }

                if let briefing {
                    Text(briefing.summary)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    if !briefing.highlights.isEmpty {
                        Divider()
                        ForEach(briefing.highlights, id: \.self) { highlight in
                            HStack(alignment: .top, spacing: 6) {
                                Circle()
                                    .fill(.blue)
                                    .frame(width: 6, height: 6)
                                    .padding(.top, 5)
                                Text(highlight)
                                    .font(.caption)
                            }
                        }
                    }
                } else {
                    Text("Generating briefing...")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 4)
        }
    }

    // MARK: - Attention Section

    @ViewBuilder
    private var attentionSection: some View {
        Section {
            if attentionItems.isEmpty {
                HStack {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    Text("All caught up!")
                        .foregroundStyle(.secondary)
                }
            } else {
                ForEach(attentionItems) { item in
                    HStack(spacing: 10) {
                        Image(systemName: iconForPriority(item.priority))
                            .foregroundStyle(colorForPriority(item.priority))
                            .frame(width: 24)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.title)
                                .font(.subheadline)
                            Text(item.subtitle)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        Text(item.createdAt, format: .relative(presentation: .numeric))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        } header: {
            HStack {
                Text("Needs Your Attention")
                Spacer()
                if !attentionItems.isEmpty {
                    Text("\(attentionItems.count)")
                        .font(.caption)
                        .fontWeight(.bold)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(.red)
                        .foregroundStyle(.white)
                        .clipShape(Capsule())
                }
            }
        }
    }

    // MARK: - Schedule Section

    @ViewBuilder
    private var scheduleSection: some View {
        Section("Today's Schedule") {
            if todaySchedule.isEmpty {
                Text("Nothing scheduled for today")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(todaySchedule) { item in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.employeeName)
                                .font(.subheadline)
                            Text(item.jobName ?? "No job")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        if let shift = item.shiftStart {
                            Text(shift)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Financial Section

    @ViewBuilder
    private var financialSection: some View {
        Section("Financial Snapshot") {
            if let snapshot = financialSnapshot {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("This Week")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(formatCurrency(snapshot.spendingThisWeek))
                            .font(.title3)
                            .fontWeight(.semibold)
                        let diff = snapshot.spendingThisWeek - snapshot.spendingLastWeek
                        Text("\(diff >= 0 ? "+" : "")\(formatCurrency(diff)) vs last week")
                            .font(.caption2)
                            .foregroundStyle(diff <= 0 ? .green : .red)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 4) {
                        Text("This Month")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(formatCurrency(snapshot.spendingThisMonth))
                            .font(.title3)
                            .fontWeight(.semibold)
                        let diff = snapshot.spendingThisMonth - snapshot.spendingLastMonth
                        Text("\(diff >= 0 ? "+" : "")\(formatCurrency(diff)) vs last month")
                            .font(.caption2)
                            .foregroundStyle(diff <= 0 ? .green : .red)
                    }
                }

                if snapshot.outstandingPOValue > 0 {
                    HStack {
                        Image(systemName: "dollarsign.circle.fill")
                            .foregroundStyle(.orange)
                        Text("Outstanding POs: \(formatCurrency(snapshot.outstandingPOValue))")
                            .font(.caption)
                    }
                }
            }
        }
    }

    // MARK: - Background Tasks Section

    @ViewBuilder
    private var backgroundTasksSection: some View {
        Section("Background") {
            HStack {
                Image(systemName: "arrow.triangle.2.circlepath")
                    .foregroundStyle(.blue)
                Text("Last sync: Not available")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Helpers

    private func colorForPriority(_ priority: DashboardService.AttentionPriority) -> Color {
        switch priority {
        case .low: return .green
        case .medium: return .yellow
        case .high: return .orange
        case .overdue: return .red
        }
    }

    private func iconForPriority(_ priority: DashboardService.AttentionPriority) -> String {
        switch priority {
        case .low: return "circle.fill"
        case .medium: return "exclamationmark.circle.fill"
        case .high: return "exclamationmark.triangle.fill"
        case .overdue: return "flame.fill"
        }
    }

    private func formatCurrency(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "USD"
        formatter.maximumFractionDigits = 0
        return formatter.string(from: NSNumber(value: value)) ?? "$\(Int(value))"
    }

    // MARK: - Data Loading

    private func loadData() {
        guard let service = appCore.dashboardService else {
            loadError = "Dashboard service not available"
            isLoading = false
            return
        }

        isLoading = true
        loadError = nil

        do {
            // Check briefing cache (1hr TTL)
            if let cached = cachedBriefing,
               let cachedTime = cachedAt,
               Date().timeIntervalSince(cachedTime) < 3600 {
                briefing = cached
            } else {
                let newBriefing = try service.getOfficeBriefing()
                briefing = newBriefing
                cachedBriefing = newBriefing
                cachedAt = Date()
            }

            attentionItems = try service.getAttentionItems()
            todaySchedule = try service.getTodaySchedule()

            if appCore.hasPermission("view_financials") {
                financialSnapshot = try service.getFinancialSnapshot()
            }
        } catch {
            loadError = error.localizedDescription
        }

        isLoading = false
    }
}
