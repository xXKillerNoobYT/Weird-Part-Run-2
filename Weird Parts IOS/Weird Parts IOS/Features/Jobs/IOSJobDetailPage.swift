import SwiftUI
import WiredPartCore

/// Job detail page for iOS.
///
/// Displays full information for a single job: name, status, priority, address,
/// notes, assigned team members, and a labor summary. Takes a `jobId` parameter
/// and loads data via `JobsService.getJob(id:)`.
struct IOSJobDetailPage: View {
    @EnvironmentObject private var appCore: AppCore

    let jobId: Int64

    // MARK: - State

    @State private var job: JobsService.JobDetail?
    @State private var teamMembers: [JobsService.TeamMemberRow] = []
    @State private var laborSummary: JobsService.LaborSummary?
    @State private var isLoading = true
    @State private var loadError: String?
    @State private var activeSheet: ActiveSheet?

    private enum ActiveSheet: Identifiable {
        case help
        case weeklyReview

        var id: String {
            switch self {
            case .help: "help"
            case .weeklyReview: "weeklyReview"
            }
        }
    }

    var body: some View {
        detailContent
            .navigationTitle(job?.jobName ?? "Job Detail")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    HStack(spacing: 12) {
                        Button { activeSheet = .weeklyReview } label: {
                            Image(systemName: "calendar.badge.clock")
                        }
                        .accessibilityLabel("Open weekly review")
                        Button { activeSheet = .help } label: {
                            Image(systemName: "questionmark.circle")
                        }
                        .accessibilityLabel("Help")
                    }
                }
            }
            .sheet(item: $activeSheet) { sheet in
                switch sheet {
                case .help:
                    PageHelpSheet(
                        title: "Job Detail Help",
                        sections: [
                            ("Overview", "Full details for this job including status, priority, customer, address, dates, and notes."),
                            ("Team & Labor", "See assigned team members and a summary of labor hours logged against this job."),
                            ("Weekly Review", "Tap the calendar icon to submit a weekly work review for this job."),
                            ("Actions", "Pull down to refresh. Use the tab view for deeper access to team, labor, parts, and orders.")
                        ]
                    )
                case .weeklyReview:
                    IOSWeeklyReviewSheet(
                        jobId: jobId,
                        jobName: job?.jobName ?? "Job \(jobId)"
                    )
                }
            }
            .refreshable { loadData() }
            .task { loadData() }
            .task { appCore.onboardingManager?.markCompleted("jobs-tap-detail") }
    }

    // MARK: - Content

    @ViewBuilder
    private var detailContent: some View {
        if isLoading {
            ProgressView("Loading job...")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let error = loadError {
            ErrorStateView(message: error) { loadData() }
        } else if let job {
            List {
                // Header section
                Section("Overview") {
                    labelRow("Job Number", value: job.jobNumber, icon: "number")
                    labelRow("Status", value: nil, icon: "circle.fill") {
                        statusBadge(job.status)
                    }
                    labelRow("Priority", value: nil, icon: "flag.fill") {
                        priorityBadge(job.priority)
                    }
                    labelRow("Type", value: job.jobType.capitalized, icon: "wrench.and.screwdriver")
                    if let customer = job.customerName, !customer.isEmpty {
                        labelRow("Customer", value: customer, icon: "person.crop.circle")
                    }
                }

                // Address section
                if hasAddress(job) {
                    Section("Address") {
                        VStack(alignment: .leading, spacing: 4) {
                            if let line1 = job.addressLine1, !line1.isEmpty {
                                Text(line1)
                            }
                            if let line2 = job.addressLine2, !line2.isEmpty {
                                Text(line2)
                            }
                            let cityStateZip = [job.city, job.state, job.zip]
                                .compactMap { $0 }
                                .filter { !$0.isEmpty }
                                .joined(separator: ", ")
                            if !cityStateZip.isEmpty {
                                Text(cityStateZip)
                            }
                        }
                        .font(.subheadline)
                    }
                }

                // Dates section
                if job.startDate != nil || job.dueDate != nil || job.completedDate != nil {
                    Section("Dates") {
                        if let start = job.startDate {
                            labelRow("Start", value: formatDate(start), icon: "calendar")
                        }
                        if let due = job.dueDate {
                            labelRow("Due", value: formatDate(due), icon: "calendar.badge.clock")
                        }
                        if let completed = job.completedDate {
                            labelRow("Completed", value: formatDate(completed), icon: "checkmark.circle")
                        }
                    }
                }

                // Notes section
                if let notes = job.notes, !notes.isEmpty {
                    Section("Notes") {
                        Text(notes)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }

                // Labor summary section
                if let labor = laborSummary {
                    Section("Labor Summary") {
                        HStack {
                            statBlock(
                                label: "Regular",
                                value: String(format: "%.1f hrs", labor.totalRegularHours)
                            )
                            Spacer()
                            statBlock(
                                label: "Overtime",
                                value: String(format: "%.1f hrs", labor.totalOvertimeHours)
                            )
                            Spacer()
                            statBlock(
                                label: "Workers",
                                value: "\(labor.uniqueWorkers)"
                            )
                            Spacer()
                            statBlock(
                                label: "Entries",
                                value: "\(labor.totalEntries)"
                            )
                        }
                        .padding(.vertical, 4)
                    }
                }

                // Team members section
                Section("Team (\(teamMembers.count))") {
                    if teamMembers.isEmpty {
                        Text("No team members assigned.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(teamMembers, id: \.id) { member in
                            HStack {
                                Image(systemName: "person.circle.fill")
                                    .foregroundStyle(Color.accentColor)
                                    .accessibilityHidden(true)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(member.userName)
                                        .fontWeight(.medium)
                                    Text(member.role.capitalized)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                if let joined = member.joinedAt {
                                    Text(formatDate(joined))
                                        .font(.caption2)
                                        .foregroundStyle(.tertiary)
                                }
                            }
                        }
                    }
                }

                // Budget section
                if job.budgetLimit != nil || job.billingRate != nil || job.estimatedHours != nil {
                    Section("Budget & Billing") {
                        if let rate = job.billingRate {
                            labelRow("Billing Rate", value: formatCurrency(rate), icon: "dollarsign.circle")
                        }
                        if let hours = job.estimatedHours {
                            labelRow("Estimated Hours", value: String(format: "%.0f hrs", hours), icon: "clock")
                        }
                        if let budget = job.budgetLimit {
                            labelRow("Budget Limit", value: formatCurrency(budget), icon: "creditcard")
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
        } else {
            ContentUnavailableView {
                Label("Job Not Found", systemImage: "hammer")
            } description: {
                Text("The requested job could not be loaded.")
            }
        }
    }

    // MARK: - Subviews

    private func labelRow(_ label: String, value: String?, icon: String) -> some View {
        HStack {
            Label(label, systemImage: icon)
                .foregroundStyle(.secondary)
                .font(.subheadline)
            Spacer()
            if let value {
                Text(value)
                    .font(.subheadline)
                    .fontWeight(.medium)
            }
        }
    }

    private func labelRow<Trailing: View>(
        _ label: String, value: String?, icon: String,
        @ViewBuilder trailing: () -> Trailing
    ) -> some View {
        HStack {
            Label(label, systemImage: icon)
                .foregroundStyle(.secondary)
                .font(.subheadline)
            Spacer()
            trailing()
        }
    }

    private func statBlock(label: String, value: String) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.system(.subheadline, design: .monospaced))
                .fontWeight(.semibold)
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Badges

    private func statusBadge(_ status: String) -> some View {
        let color: Color = switch status {
        case "active": .green
        case "completed": .blue
        case "on_hold": .orange
        case "cancelled": .red
        default: .secondary
        }
        return Text(status.replacingOccurrences(of: "_", with: " ").capitalized)
            .font(.system(.caption2, weight: .semibold))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Capsule().fill(color.opacity(0.15)))
            .foregroundStyle(color)
    }

    private func priorityBadge(_ priority: String) -> some View {
        let isCompleted = job?.status == "completed" || job?.status == "cancelled"
        let color: Color = TimelinePriorityColor.color(priority: priority, dueDateString: job?.dueDate, isCompleted: isCompleted)
        return Text(priority.capitalized)
            .font(.system(.caption2, weight: .semibold))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Capsule().fill(color.opacity(0.15)))
            .foregroundStyle(color)
    }

    // MARK: - Helpers

    private func hasAddress(_ job: JobsService.JobDetail) -> Bool {
        let parts = [job.addressLine1, job.addressLine2, job.city, job.state, job.zip]
        return parts.contains(where: { $0 != nil && !($0?.isEmpty ?? true) })
    }

    private func formatDate(_ iso: String) -> String {
        String(iso.prefix(10))
    }

    private func formatCurrency(_ value: Double) -> String {
        Formatters.formatCurrency(value)
    }

    // MARK: - Data Loading

    private func loadData() {
        guard let service = appCore.jobsService else {
            isLoading = false
            loadError = "Jobs service unavailable"
            return
        }
        isLoading = job == nil
        do {
            job = try service.getJob(id: jobId)
            teamMembers = try service.getTeamMembers(jobId: jobId)
            laborSummary = try service.getLaborSummary(jobId: jobId)
        } catch {
            loadError = userFriendlyError(error, context: "load job details")
        }
        isLoading = false
    }
}
