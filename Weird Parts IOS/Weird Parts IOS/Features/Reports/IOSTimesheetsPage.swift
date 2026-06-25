import SwiftUI
import WiredPartCore

/// Timesheets report page for iOS.
///
/// Displays a list of timesheet rows aggregated per user within the
/// selected date range. Shows name, regular hours, overtime hours,
/// total hours, and days worked. Supports pull-to-refresh, search
/// filtering, and date range selection.
struct IOSTimesheetsPage: View {
    @EnvironmentObject private var appCore: AppCore

    // MARK: - State

    @State private var rows: [ReportsService.TimesheetRow] = []
    @State private var segments: [ReportsService.TimesheetSegmentRow] = []
    @State private var isLoading = true
    @State private var searchText = ""
    @State private var dateRange: ReportDateRange = .thisPeriod
    @State private var startDate = Calendar.current.date(byAdding: .day, value: -13, to: Date()) ?? Date()
    @State private var endDate = Date()
    @State private var loadError: String?
    @State private var activeSheet: ActiveSheet?
    @State private var selectedRow: ReportsService.TimesheetRow?
    @State private var correctionHistory: [ReportsService.TimesheetCorrectionAuditRecord] = []

    private enum ActiveSheet: Identifiable {
        case help
        case correction(ReportsService.TimesheetSegmentRow)

        var id: String {
            switch self {
            case .help: return "help"
            case .correction(let segment): return "correction-\(segment.id)"
            }
        }
    }

    private var startDateString: String {
        Formatters.localDateFormatter.string(from: startDate)
    }

    private var endDateString: String {
        Formatters.localDateFormatter.string(from: endDate)
    }

    var body: some View {
        VStack(spacing: 0) {
            StandardFilterBar(selectedRange: $dateRange, customStart: $startDate, customEnd: $endDate)
            timesheetList
        }
        .navigationTitle("Timesheets")
        .reportExportToolbar(
            title: "Timesheets",
            columns: ["Employee", "Job", "Clock In", "Clock Out", "Paid Break", "Paid Lunch", "Unpaid Lunch", "Regular", "Overtime", "Status"],
            rows: segments.map {
                [
                    $0.userName, jobLabel($0), formatTimestamp($0.clockIn),
                    $0.clockOut.map(formatTimestamp) ?? "Open",
                    "\($0.paidBreakMinutes)m", "\($0.paidLunchMinutes)m", "\($0.unpaidLunchMinutes)m",
                    String(format: "%.1f", $0.regularHours),
                    String(format: "%.1f", $0.overtimeHours),
                    $0.status
                ]
            }
        )
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { activeSheet = .help } label: {
                    Image(systemName: "questionmark.circle")
                }
                .accessibilityLabel("Help")
            }
        }
        .sheet(item: $activeSheet) { sheet in
            switch sheet {
            case .help:
                PageHelpSheet(title: "Timesheets Help", sections: [
                    ("What This Page Does", "Lists every employee's timesheet totals for the selected date range. Shows regular hours, overtime hours, total hours, and how many days each person worked."),
                    ("How to Use It", "Set the start and end dates to match the period you want to review. Use the search bar to find a specific employee. Each row shows their name, hours breakdown, and days worked. Export to PDF or CSV using the toolbar button."),
                    ("Tips", "Run this for each pay period before submitting payroll. If someone's hours seem too low, they may have forgotten to clock in. Compare against daily reports to catch missing entries.")
                ])
            case .correction(let segment):
                TimesheetCorrectionSheet(
                    segment: segment,
                    actorUserId: appCore.currentUser?.id,
                    actorName: appCore.currentUser?.displayName ?? "Current User",
                    reportsService: appCore.reportsService,
                    onSave: { record in
                        correctionHistory.removeAll { $0.id == record.id }
                        correctionHistory.insert(record, at: 0)
                        loadData()
                        activeSheet = nil
                    }
                )
            }
        }
        .searchable(text: $searchText, prompt: "Search employees...")
        .refreshable { loadData() }
        .task { loadData() }
        .onAppear { postPageContext() }
        .onChange(of: searchText) { postPageContext() }
        .onDisappear {
            NotificationCenter.default.post(name: .reportsTimesheetsPageInactive, object: nil)
        }
        .onChange(of: startDate) { _, _ in loadData() }
        .onChange(of: endDate) { _, _ in loadData() }
    }

    // MARK: - Timesheet List

    @ViewBuilder
    private var timesheetList: some View {
        if isLoading {
            ProgressView("Loading timesheets...")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let error = loadError {
            ErrorStateView(message: error) { loadData() }
        } else if filteredRows.isEmpty {
            EmptyStateView(icon: "clock", title: "No Timesheets", message: "No time entries were found for this period.")
        } else {
            List {
                Section("Manager Review") {
                    ForEach(filteredRows, id: \.id) { row in
                        Button {
                            selectedRow = row
                        } label: {
                            timesheetRow(row)
                        }
                        .buttonStyle(.plain)
                    }
                }

                if let selectedRow {
                    timesheetDetailSection(selectedRow)
                }
            }
            .listStyle(.insetGrouped)
            .safeAreaInset(edge: .bottom) {
                Color.clear
                    .frame(height: 96)
                    .allowsHitTesting(false)
            }
        }
    }

    private var filteredRows: [ReportsService.TimesheetRow] {
        guard !searchText.isEmpty else { return rows }
        let query = searchText.lowercased()
        return rows.filter {
            $0.userName.lowercased().contains(query)
        }
    }

    private func timesheetRow(_ row: ReportsService.TimesheetRow) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "person.circle")
                .font(.title2)
                .foregroundStyle(Color.accentColor)
                .frame(width: 36)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                Text(row.userName)
                    .fontWeight(.medium)
                HStack(spacing: 12) {
                    Label(String(format: "%.1f", row.regularHours), systemImage: "clock")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if row.overtimeHours > 0 {
                        Label(String(format: "%.1f OT", row.overtimeHours), systemImage: "clock.badge.exclamationmark")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                }
                Label("\(row.daysWorked) days worked", systemImage: "calendar")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 4) {
                Text(String(format: "%.1f", row.totalHours))
                    .font(.title3)
                    .fontWeight(.semibold)
                    .foregroundStyle(.primary)
                Text("total hrs")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }

    private func timesheetDetailSection(_ row: ReportsService.TimesheetRow) -> some View {
        Section {
            let rowSegments = segmentsFor(row)
            if rowSegments.isEmpty {
                Text("No job segments found for this employee in the selected period.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(groupedSegments(rowSegments), id: \.date) { group in
                    VStack(alignment: .leading, spacing: 10) {
                        Text(group.date)
                            .font(.headline)
                        ForEach(group.segments) { segment in
                            segmentCard(segment)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        } header: {
            Text("\(row.userName) Detail")
        } footer: {
            Text("Export CSV/PDF includes employee, job, raw timestamps, break/lunch minutes, regular/overtime hours, and review status.")
        }
    }

    private func segmentCard(_ segment: ReportsService.TimesheetSegmentRow) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(jobLabel(segment))
                        .font(.subheadline)
                        .fontWeight(.semibold)
                    Text("\(formatTimestamp(segment.clockIn)) - \(segment.clockOut.map(formatTimestamp) ?? "Open")")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text(segment.status)
                    .font(.caption)
                    .fontWeight(.semibold)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background((segment.clockOut == nil ? Color.orange : Color.blue).opacity(0.14))
                    .foregroundStyle(segment.clockOut == nil ? .orange : .blue)
                    .clipShape(Capsule())
            }

            if segment.clockOut == nil {
                Label("Active timer has not been clocked out.", systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }

            Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 6) {
                GridRow {
                    metric("Paid Break", "\(segment.paidBreakMinutes)m")
                    metric("Paid Lunch", "\(segment.paidLunchMinutes)m")
                    metric("Unpaid Lunch", "\(segment.unpaidLunchMinutes)m")
                }
                GridRow {
                    metric("Regular", String(format: "%.1fh", segment.regularHours))
                    metric("Overtime", String(format: "%.1fh", segment.overtimeHours))
                    metric("Sync", segment.syncStatus)
                }
            }

            let history = correctionHistory.filter { $0.segmentId == segment.id }
            if !history.isEmpty {
                Divider()
                Text("Correction History")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(.secondary)
                ForEach(history) { record in
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Corrected by \(record.actorName)")
                            .font(.caption)
                            .fontWeight(.medium)
                        Text("\(formatDateTime(record.changedAt)) · Reason: \(record.reason)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Text("\(record.employeeName) · \(jobLabel(record)) · \(formatTimestamp(record.originalClockIn)) to \(formatTimestamp(record.adjustedClockIn))")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                        Text("Original \(String(format: "%.1f", record.originalRegularHours))h regular / \(String(format: "%.1f", record.originalOvertimeHours))h overtime · Adjusted \(String(format: "%.1f", record.adjustedRegularHours))h regular / \(String(format: "%.1f", record.adjustedOvertimeHours))h overtime · \(approvalLabel(record))")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                            .accessibilityIdentifier("timesheetCorrectionHistoryAllocation")
                    }
                }
            }

            HStack {
                Button {
                    activeSheet = .correction(segment)
                } label: {
                    Label("Correct Entry", systemImage: "pencil.and.list.clipboard")
                }
                .accessibilityIdentifier("timesheetCorrectEntryButton-\(segment.id)")
                .buttonStyle(.bordered)
                .controlSize(.small)
                .hideWithoutPermission("manage_labor")

                Spacer()
            }
        }
        .padding(10)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 8))
    }

    private func metric(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.caption)
                .fontWeight(.medium)
        }
    }

    // MARK: - Data Loading

    private func loadData() {
        guard let service = appCore.reportsService else {
            isLoading = false
            loadError = "Reports service is not available."
            return
        }
        isLoading = rows.isEmpty
        loadError = nil
        do {
            rows = try service.getTimesheetData(
                startDate: startDateString,
                endDate: endDateString
            )
            segments = try service.getTimesheetSegments(
                startDate: startDateString,
                endDate: endDateString
            )
            correctionHistory = try service.getTimesheetCorrectionHistory(
                startDate: startDateString,
                endDate: endDateString
            )
            if selectedRow == nil {
                selectedRow = rows.first
            } else if let selected = selectedRow, !rows.contains(where: { $0.userId == selected.userId }) {
                selectedRow = rows.first
            }
        } catch {
            if ProcessInfo.processInfo.arguments.contains("-UITestingWEI3041Timesheets") {
                loadError = "Timesheets could not load. Try again. \(error.localizedDescription)"
            } else {
                loadError = "Timesheets could not load. Try again."
            }
        }
        isLoading = false
        postPageContext()
    }

    private func postPageContext() {
        let totalHours = rows.reduce(0) { $0 + $1.totalHours }
        let overtimeHours = rows.reduce(0) { $0 + $1.overtimeHours }
        NotificationCenter.default.post(
            name: .reportsTimesheetsPageActive,
            object: nil,
            userInfo: [
                "context": "Timesheets Report: \(startDateString) to \(endDateString), \(rows.count) employees, \(filteredRows.count) visible, \(String(format: "%.1f", totalHours)) total hours, \(String(format: "%.1f", overtimeHours)) overtime."
            ]
        )
    }

    private func segmentsFor(_ row: ReportsService.TimesheetRow) -> [ReportsService.TimesheetSegmentRow] {
        segments.filter { $0.userId == row.userId }
    }

    private func groupedSegments(_ segments: [ReportsService.TimesheetSegmentRow]) -> [(date: String, segments: [ReportsService.TimesheetSegmentRow])] {
        let groups = Dictionary(grouping: segments) { segment in
            String(segment.clockIn.prefix(10))
        }
        return groups.keys.sorted(by: >).map { key in
            (date: key, segments: groups[key] ?? [])
        }
    }

    private func jobLabel(_ segment: ReportsService.TimesheetSegmentRow) -> String {
        segment.jobNumber.isEmpty ? segment.jobName : "\(segment.jobName) (#\(segment.jobNumber))"
    }

    private func jobLabel(_ record: ReportsService.TimesheetCorrectionAuditRecord) -> String {
        record.jobNumber.isEmpty ? record.jobName : "\(record.jobName) (#\(record.jobNumber))"
    }

    private func formatTimestamp(_ value: String) -> String {
        guard value.count >= 16 else { return value }
        return "\(value.prefix(10)) \(value.dropFirst(11).prefix(5))"
    }

    private func formatDateTime(_ date: Date) -> String {
        Formatters.localDateTimeFormatter.string(from: date)
    }

    private func formatDateTime(_ value: String) -> String {
        guard let date = CoreFormatters.parseDateTime(value) else { return formatTimestamp(value) }
        return Formatters.localDateTimeFormatter.string(from: date)
    }

    private func approvalLabel(_ record: ReportsService.TimesheetCorrectionAuditRecord) -> String {
        let status = record.approvalStatus
            .replacingOccurrences(of: "_", with: " ")
            .capitalized
        if let approver = record.approverName, !approver.isEmpty {
            return "\(status) by \(approver)"
        }
        return status
    }
}

private struct TimesheetCorrectionSheet: View {
    @Environment(\.dismiss) private var dismiss
    let segment: ReportsService.TimesheetSegmentRow
    let actorUserId: Int64?
    let actorName: String
    let reportsService: ReportsService?
    let onSave: (ReportsService.TimesheetCorrectionAuditRecord) -> Void

    @State private var adjustedClockIn: Date
    @State private var adjustedClockOut: Date
    @State private var reason = ""
    @State private var validationMessage: String?
    @State private var isSaving = false

    init(
        segment: ReportsService.TimesheetSegmentRow,
        actorUserId: Int64?,
        actorName: String,
        reportsService: ReportsService?,
        onSave: @escaping (ReportsService.TimesheetCorrectionAuditRecord) -> Void
    ) {
        self.segment = segment
        self.actorUserId = actorUserId
        self.actorName = actorName
        self.reportsService = reportsService
        self.onSave = onSave
        let clockIn = CoreFormatters.parseDateTime(segment.clockIn) ?? Date()
        let clockOut = segment.clockOut.flatMap(CoreFormatters.parseDateTime) ?? clockIn.addingTimeInterval(3600)
        _adjustedClockIn = State(initialValue: clockIn)
        _adjustedClockOut = State(initialValue: clockOut)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Original Values") {
                    labeledValue("Employee", segment.userName)
                    labeledValue("Job", jobLabel)
                    labeledValue("Original Clock In", formatTimestamp(segment.clockIn))
                    labeledValue("Original Clock Out", segment.clockOut.map(formatTimestamp) ?? "Open")
                    labeledValue("Original Regular", String(format: "%.1fh", segment.regularHours))
                    labeledValue("Original Overtime", String(format: "%.1fh", segment.overtimeHours))
                }

                Section("Adjusted Values") {
                    DatePicker("Clock In", selection: $adjustedClockIn)
                    DatePicker("Clock Out", selection: $adjustedClockOut)
                    labeledValue("Paid Time Preview", String(format: "%.1fh", adjustedTotalHours))
                        .accessibilityIdentifier("timesheetCorrectionPaidTimePreview")
                    Label("Regular and overtime hours are calculated from the current overtime policy when saved.", systemImage: "clock.badge.exclamationmark")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("timesheetCorrectionPolicyAllocationCopy")
                }

                Section {
                    TextField("Explain why this time entry changed.", text: $reason, axis: .vertical)
                        .lineLimit(3...6)
                        .accessibilityIdentifier("timesheetCorrectionReasonField")
                } header: {
                    Text("Correction Reason")
                }

                if let validationMessage {
                    Section {
                        Label(validationMessage, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                            .accessibilityElement(children: .combine)
                    }
                }
            }
            .navigationTitle("Correct Entry")
            .navigationBarTitleDisplayMode(.inline)
            .accessibilityIdentifier("timesheetCorrectionSheet")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        save()
                    } label: {
                        if isSaving {
                            ProgressView()
                        } else {
                            Text("Save Correction")
                        }
                    }
                    .accessibilityIdentifier("timesheetCorrectionSaveButton")
                    .disabled(isSaving)
                }
            }
        }
    }

    private var jobLabel: String {
        segment.jobNumber.isEmpty ? segment.jobName : "\(segment.jobName) (#\(segment.jobNumber))"
    }

    private var adjustedTotalHours: Double {
        max(0, adjustedClockOut.timeIntervalSince(adjustedClockIn) / 3600)
    }

    private func labeledValue(_ title: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .multilineTextAlignment(.trailing)
        }
    }

    private func save() {
        let trimmedReason = reason.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedReason.isEmpty else {
            validationMessage = "Reason is required before save."
            return
        }
        guard let reportsService else {
            validationMessage = "Reports service is not available."
            return
        }
        guard let actorUserId else {
            validationMessage = "Current user is required to save corrections."
            return
        }
        guard adjustedClockOut >= adjustedClockIn else {
            validationMessage = "Adjusted clock out cannot be before adjusted clock in."
            return
        }

        validationMessage = nil
        isSaving = true
        do {
            let request = ReportsService.TimesheetCorrectionRequest(
                laborEntryId: segment.id,
                adjustedClockIn: CoreFormatters.iso8601.string(from: adjustedClockIn),
                adjustedClockOut: CoreFormatters.iso8601.string(from: adjustedClockOut),
                clientPreviewRegularHours: segment.regularHours,
                clientPreviewOvertimeHours: segment.overtimeHours,
                reason: trimmedReason,
                actorUserId: actorUserId
            )
            let record = try reportsService.saveTimesheetCorrection(request)
            onSave(record)
        } catch {
            validationMessage = userFriendlyError(error, context: "save timesheet correction")
            isSaving = false
        }
    }

    private func formatTimestamp(_ value: String) -> String {
        guard value.count >= 16 else { return value }
        return "\(value.prefix(10)) \(value.dropFirst(11).prefix(5))"
    }
}
