import SwiftUI
import WiredPartCore

/// Long-term pipeline page showing a 3-year capacity timeline.
///
/// Monthly capacity bars show utilization, pending bids, and job counts.
/// AI warnings flag over- and under-committed months. Tapping a month
/// shows the jobs scheduled for that period.
struct IOSLongTermPipelinePage: View {
    @EnvironmentObject private var appCore: AppCore

    @State private var timelineMonths: [SchedulingService.MonthCapacity] = []
    @State private var aiWarnings: [SchedulingService.CapacityWarning] = []
    @State private var isLoading = true
    @State private var loadError: String?
    @State private var selectedMonthId: String?
    @State private var searchText = ""
    @State private var activeSheet: ActiveSheet?

    private enum ActiveSheet: Identifiable {
        case help
        var id: String { "help" }
    }

    private var filteredTimelineMonths: [SchedulingService.MonthCapacity] {
        if searchText.isEmpty { return timelineMonths }
        return timelineMonths.filter {
            $0.monthLabel.localizedCaseInsensitiveContains(searchText) ||
            $0.jobs.contains(where: { $0.name.localizedCaseInsensitiveContains(searchText) })
        }
    }

    private var selectedMonth: SchedulingService.MonthCapacity? {
        guard let id = selectedMonthId else { return nil }
        return timelineMonths.first(where: { $0.id == id })
    }

    var body: some View {
        Group {
            if isLoading {
                ProgressView("Loading pipeline...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error = loadError {
                ErrorStateView(message: error) { loadData() }
            } else {
                pipelineContent
            }
        }
        .navigationTitle("Long-Term Pipeline")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { activeSheet = .help } label: {
                    Image(systemName: "questionmark.circle")
                }
            }
        }
        .sheet(item: $activeSheet) { _ in
            PageHelpSheet(title: "Long-Term Pipeline Help", sections: [
                ("What This Page Does", "The Long-Term Pipeline shows a 3-year capacity timeline organized by month. Each month displays a utilization bar, job count, and pending bid count so you can see how booked you are months in advance."),
                ("How to Use It", "Scroll through the monthly timeline to see capacity at a glance. Tap any month to expand it and see the individual jobs scheduled for that period. AI warnings at the top flag months that are over- or under-committed."),
                ("Reading the Bars", "Green means light workload, blue is moderate, orange is getting full, and red means overcommitted. The fraction (e.g. 18/22 days) shows scheduled days vs. available working days."),
                ("Tips", "Use this view to plan bids and new work. If a month is red, avoid committing more jobs there. If months ahead look empty, it is time to ramp up sales and bidding efforts.")
            ])
        }
        .searchable(text: $searchText, prompt: "Search months or jobs...")
        .refreshable { loadData() }
        .task { loadData() }
    }

    // MARK: - Content

    private var pipelineContent: some View {
        List {
            // AI Warnings
            if !aiWarnings.isEmpty {
                Section {
                    ForEach(aiWarnings, id: \.id) { warning in
                        HStack(spacing: 10) {
                            Image(systemName: warning.isOvercommitted
                                  ? "exclamationmark.triangle.fill"
                                  : "chart.bar.xaxis")
                                .foregroundStyle(warning.isOvercommitted ? .red : .orange)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(warning.message)
                                    .font(.subheadline)
                                Text(warning.suggestion)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                } header: {
                    Label("AI Capacity Warnings", systemImage: "sparkles")
                }
            }

            // 3-Year Timeline
            Section {
                ForEach(filteredTimelineMonths, id: \.id) { month in
                    Button {
                        if selectedMonthId == month.id {
                            selectedMonthId = nil
                        } else {
                            selectedMonthId = month.id
                        }
                    } label: {
                        MonthCapacityRow(month: month, isSelected: selectedMonthId == month.id)
                    }
                    .buttonStyle(.plain)
                }
            } header: {
                Text("Capacity by Month")
            }

            // Selected Month Detail
            if let month = selectedMonth, !month.jobs.isEmpty {
                Section {
                    ForEach(month.jobs, id: \.id) { job in
                        HStack {
                            Text(job.name)
                                .font(.subheadline)
                            Spacer()
                            if let days = job.estimatedDays {
                                Text("\(days) days")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            statusBadge(job.status)
                        }
                    }
                } header: {
                    Text("\(month.monthLabel) — \(month.jobs.count) jobs")
                }
            }
        }
        .listStyle(.insetGrouped)
    }

    // MARK: - Badges

    private func statusBadge(_ status: String) -> some View {
        let color: Color = switch status {
        case "active": .green
        case "scheduled": .blue
        case "pending": .orange
        case "bid": .purple
        default: .secondary
        }
        return Text(status.capitalized)
            .font(.system(.caption2, weight: .semibold))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Capsule().fill(color.opacity(0.15)))
            .foregroundStyle(color)
    }

    // MARK: - Data Loading

    private func loadData() {
        guard let service = appCore.schedulingService else {
            isLoading = false
            loadError = "Scheduling service not available."
            return
        }
        isLoading = timelineMonths.isEmpty
        loadError = nil
        do {
            timelineMonths = try service.getLongTermTimeline(months: 36)
            aiWarnings = service.getCapacityWarnings(timeline: timelineMonths)
        } catch {
            loadError = userFriendlyError(error, context: "load pipeline data")
        }
        isLoading = false
    }
}

// MARK: - Month Capacity Row

private struct MonthCapacityRow: View {
    let month: SchedulingService.MonthCapacity
    let isSelected: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(month.monthLabel)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                Spacer()
                Text("\(month.scheduledDays)/\(month.availableDays) days")
                    .font(.caption)
                    .foregroundStyle(month.utilizationPercent > 1.0 ? .red : .secondary)
            }

            // Capacity bar
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color(.systemGray5))
                    RoundedRectangle(cornerRadius: 3)
                        .fill(capacityColor(month.utilizationPercent))
                        .frame(width: geo.size.width * min(CGFloat(month.utilizationPercent), 1.0))
                }
            }
            .frame(height: 8)

            // Summary
            HStack {
                Text("\(month.jobCount) jobs")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                if month.pendingBidCount > 0 {
                    Text("+ \(month.pendingBidCount) bids pending")
                        .font(.caption2)
                        .foregroundStyle(.blue)
                }
                Spacer()
                if isSelected {
                    Image(systemName: "chevron.up")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 2)
    }

    private func capacityColor(_ percent: Double) -> Color {
        if percent > 1.0 { return .red }
        if percent > 0.8 { return .orange }
        if percent > 0.5 { return .blue }
        return .green
    }
}
