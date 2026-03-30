import SwiftUI
import UniformTypeIdentifiers
import WiredPartCore

// MARK: - Draggable Worker (Transferable)

/// Lightweight Codable wrapper representing a worker being dragged from the
/// "Unassigned Workers" section onto a job row. Uses `.json` content type so
/// no custom UTType registration in Info.plist is required.
struct DraggableWorker: Codable, Transferable {
    let id: Int64
    let name: String

    static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .json)
    }
}

/// Gantt-style dispatch board for iOS.
///
/// Shows job rows with daily columns across the week. Colored bars show who's
/// assigned where (AM=blue, PM=green, Full=orange). Unassigned workers section
/// at the bottom. Tap empty cell or unassigned worker to create assignment.
/// Drag an unassigned worker onto a job row to quickly assign them.
struct IOSDispatchPage: View {
    @EnvironmentObject private var appCore: AppCore

    // MARK: - State

    @State private var weekStartDate = Date()
    @State private var assignments: [SchedulingService.DispatchAssignment] = []
    @State private var jobRows: [SchedulingService.DispatchJobRow] = []
    @State private var unassignedWorkers: [SchedulingService.UnassignedWorker] = []
    @State private var isLoading = true
    @State private var loadError: String?

    // Assignment flow
    @State private var selectedJobId: Int64?
    @State private var selectedDate: String?
    @State private var selectedWorkerId: Int64?

    // Conflict alert
    @State private var showConflictAlert = false
    @State private var conflictMessage = ""
    @State private var pendingAssignJobId: Int64?
    @State private var pendingAssignDate: String?
    @State private var pendingAssignWorkerId: Int64?

    @State private var actionError: String?
    @State private var activeSheet: ActiveSheet?

    // Drag-and-drop: tracks which job row is currently targeted
    @State private var dropTargetJobId: Int64?

    private enum ActiveSheet: Identifiable {
        case help
        case assign
        var id: String {
            switch self {
            case .help: return "help"
            case .assign: return "assign"
            }
        }
    }

    private let calendar = Calendar.current

    private var weekStart: Date {
        calendar.date(from: calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: weekStartDate)) ?? weekStartDate
    }

    private var weekDays: [Date] {
        (0..<7).compactMap { offset in
            calendar.date(byAdding: .day, value: offset, to: weekStart)
        }
    }

    private func dateString(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: date)
    }

    private var weekStartStr: String { dateString(weekStart) }
    private var weekEndStr: String { dateString(weekDays.last ?? weekStart) }

    var body: some View {
        VStack(spacing: 0) {
            OnboardingBanner(pageId: "scheduling-dispatch")
            weekHeader
            boardContent
        }
        .task { appCore.onboardingManager?.markCompleted("dispatch-view") }
        .navigationTitle("Dispatch Board")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    selectedJobId = nil
                    selectedDate = dateString(Date())
                    selectedWorkerId = nil
                    activeSheet = .assign
                } label: {
                    Image(systemName: "plus")
                }
            }
            ToolbarItem(placement: .primaryAction) {
                Button { activeSheet = .help } label: {
                    Image(systemName: "questionmark.circle")
                }
            }
        }
        .sheet(item: $activeSheet) { sheet in
            switch sheet {
            case .assign:
                DispatchAssignSheet(
                    jobId: selectedJobId,
                    date: selectedDate ?? dateString(Date()),
                    workerId: selectedWorkerId,
                    jobRows: jobRows,
                    unassignedWorkers: unassignedWorkers,
                    onAssign: { jobId, userId, date, timeSlot in
                        createAssignment(jobId: jobId, userId: userId, date: date, timeSlot: timeSlot)
                    }
                )
                .environmentObject(appCore)
            case .help:
                PageHelpSheet(title: "Dispatch Board Help", sections: [
                    ("What This Page Does", "The Dispatch Board is a Gantt-style weekly view showing which workers are assigned to which jobs each day. Colored bars indicate time slots: blue for AM, green for PM, and orange for full day."),
                    ("How to Use It", "Navigate between weeks using the left/right arrows. Tap an empty cell on a job row to assign a worker to that job and day. Tap a worker in the Unassigned section to start an assignment for them. Use the + button to create a new assignment from scratch."),
                    ("Drag & Drop", "Press and hold an unassigned worker chip, then drag it onto a job row. The row highlights blue when targeted. Dropping creates a full-day assignment for today (or the week start if today is not in the displayed week). Time-off conflicts are checked automatically."),
                    ("Time-Off Conflicts", "If you assign someone who has approved time off that day, you will see a conflict warning. You can choose to assign them anyway or cancel."),
                    ("Tips", "Red 'Unassigned Workers' at the bottom means people have no work scheduled that week. Aim to keep this section empty by assigning everyone to jobs.")
                ])
            }
        }
        .alert("Time-Off Conflict", isPresented: $showConflictAlert) {
            Button("Assign Anyway", role: .destructive) {
                if let jid = pendingAssignJobId, let uid = pendingAssignWorkerId, let d = pendingAssignDate {
                    forceAssignment(jobId: jid, userId: uid, date: d)
                }
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text(conflictMessage)
        }
        .refreshable { loadData() }
        .task { loadData() }
        .onAppear {
            NotificationCenter.default.post(
                name: .dispatchPageActive,
                object: nil,
                userInfo: [
                    "context": "Dispatch Board: \(jobRows.count) job rows, \(assignments.count) assignments, \(unassignedWorkers.count) unassigned workers, week of \(weekStartStr)."
                ]
            )
        }
        .onDisappear {
            NotificationCenter.default.post(name: .dispatchPageInactive, object: nil)
        }
    }

    // MARK: - Week Header

    private var weekHeader: some View {
        HStack {
            Button {
                weekStartDate = calendar.date(byAdding: .weekOfYear, value: -1, to: weekStartDate) ?? weekStartDate
                loadData()
            } label: {
                Image(systemName: "chevron.left")
            }

            Spacer()

            Text("Week of \(weekStart, format: .dateTime.month().day())")
                .font(.headline)

            Spacer()

            Button {
                weekStartDate = calendar.date(byAdding: .weekOfYear, value: 1, to: weekStartDate) ?? weekStartDate
                loadData()
            } label: {
                Image(systemName: "chevron.right")
            }
        }
        .padding()
    }

    // MARK: - Board Content

    @ViewBuilder
    private var boardContent: some View {
        if isLoading {
            ProgressView("Loading dispatch board...")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let error = loadError {
            ErrorStateView(message: error) { loadData() }
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    // Day headers
                    dayHeaderRow

                    if jobRows.isEmpty {
                        Text("No active jobs")
                            .foregroundStyle(.secondary)
                            .padding()
                    } else {
                        // Job rows
                        ForEach(jobRows, id: \.id) { row in
                            jobRowView(row)
                            Divider()
                        }
                    }

                    // Unassigned workers section
                    if !unassignedWorkers.isEmpty {
                        unassignedSection
                    }

                    // Action error
                    if let error = actionError {
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(.red)
                            .padding()
                    }
                }
            }
        }
    }

    // MARK: - Day Header Row

    private var dayHeaderRow: some View {
        HStack(spacing: 1) {
            Text("Job")
                .frame(width: 100, alignment: .leading)
                .font(.caption)
                .fontWeight(.bold)

            ForEach(weekDays, id: \.self) { day in
                VStack(spacing: 2) {
                    Text(day, format: .dateTime.weekday(.abbreviated))
                        .font(.caption2)
                    Text(day, format: .dateTime.day())
                        .font(.caption)
                        .fontWeight(.bold)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 4)
                .background(
                    calendar.isDateInToday(day)
                        ? Color.blue.opacity(0.1)
                        : Color.clear
                )
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(Color(.systemGray6))
    }

    // MARK: - Job Row

    private func jobRowView(_ row: SchedulingService.DispatchJobRow) -> some View {
        let isDropTarget = dropTargetJobId == row.id

        return HStack(spacing: 1) {
            // Job name column
            VStack(alignment: .leading, spacing: 2) {
                Text(row.jobName)
                    .font(.caption)
                    .fontWeight(.semibold)
                    .lineLimit(2)
                if let stage = row.stageName {
                    Text(stage)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .frame(width: 100, alignment: .leading)
            .contextMenu {
                Text(row.jobName)
                if let stage = row.stageName {
                    Text("Stage: \(stage)")
                }
                let crewCount = assignments.filter { $0.jobId == row.id }.count
                Text("Assignments this week: \(crewCount)")
            }

            // Day cells
            ForEach(weekDays, id: \.self) { day in
                dayCellForJob(row: row, day: day)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isDropTarget ? Color.blue.opacity(0.15) : Color.clear)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .strokeBorder(isDropTarget ? Color.blue : Color.clear, lineWidth: 2)
        )
        .dropDestination(for: DraggableWorker.self) { workers, _ in
            guard let worker = workers.first else { return false }
            handleDrop(worker: worker, onJobId: row.id)
            return true
        } isTargeted: { targeted in
            dropTargetJobId = targeted ? row.id : (dropTargetJobId == row.id ? nil : dropTargetJobId)
        }
    }

    private func dayCellForJob(row: SchedulingService.DispatchJobRow, day: Date) -> some View {
        let dayStr = dateString(day)
        let workers = assignments.filter { $0.jobId == row.id && $0.date == dayStr }

        return VStack(spacing: 1) {
            if workers.isEmpty {
                // Empty cell — tap to assign
                Button {
                    selectedJobId = row.id
                    selectedDate = dayStr
                    selectedWorkerId = nil
                    activeSheet = .assign
                } label: {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color(.systemGray5))
                        .frame(height: 24)
                        .overlay {
                            Image(systemName: "plus")
                                .font(.caption2)
                                .foregroundStyle(.gray)
                        }
                }
                .buttonStyle(.plain)
            } else {
                ForEach(workers, id: \.id) { worker in
                    Text(worker.employeeInitials)
                        .font(.system(.caption2, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 20)
                        .background(
                            RoundedRectangle(cornerRadius: 3)
                                .fill(slotColor(worker.timeSlot))
                        )
                }
            }
        }
        .frame(maxWidth: .infinity, minHeight: 24)
    }

    private func slotColor(_ slot: String) -> Color {
        switch slot {
        case "am": .blue
        case "pm": .green
        default: .orange
        }
    }

    // MARK: - Unassigned Workers

    private var unassignedSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Divider().padding(.vertical, 4)

            Text("Unassigned Workers (\(unassignedWorkers.count))")
                .font(.caption)
                .fontWeight(.bold)
                .foregroundStyle(.red)
                .padding(.horizontal, 8)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(unassignedWorkers, id: \.id) { worker in
                        Button {
                            selectedWorkerId = worker.id
                            selectedJobId = nil
                            selectedDate = dateString(Date())
                            activeSheet = .assign
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "line.3.horizontal")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                Text(worker.name)
                                    .font(.caption)
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(Color.red.opacity(0.1))
                            .foregroundStyle(.primary)
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                        }
                        .buttonStyle(.plain)
                        .draggable(DraggableWorker(id: worker.id, name: worker.name))
                    }
                }
                .padding(.horizontal, 8)
            }
        }
        .padding(.bottom, 8)
    }

    // MARK: - Drag-and-Drop Handler

    /// Called when a `DraggableWorker` is dropped onto a job row.
    /// Defaults to today's date and "full" time slot. Checks for time-off
    /// conflicts before creating the assignment.
    private func handleDrop(worker: DraggableWorker, onJobId jobId: Int64) {
        // Use today if it falls within the displayed week; otherwise use the week's start date
        let today = Date()
        let todayStr = dateString(today)
        let dropDate: String
        if todayStr >= weekStartStr && todayStr <= weekEndStr {
            dropDate = todayStr
        } else {
            dropDate = weekStartStr
        }

        createAssignment(jobId: jobId, userId: worker.id, date: dropDate, timeSlot: "full")
    }

    // MARK: - Assignment Logic

    private func createAssignment(jobId: Int64, userId: Int64, date: String, timeSlot: String) {
        guard let service = appCore.schedulingService else {
            actionError = "Service not available"
            return
        }
        actionError = nil

        // Check for time-off conflict
        do {
            if let conflict = try service.checkTimeOffConflict(employeeId: userId, date: date) {
                conflictMessage = "\(conflict.employeeName) has time off on this date"
                if let reason = conflict.reason, !reason.isEmpty {
                    conflictMessage += " (\(reason))"
                }
                conflictMessage += ". Assign anyway?"
                pendingAssignJobId = jobId
                pendingAssignWorkerId = userId
                pendingAssignDate = date
                showConflictAlert = true
                return
            }
        } catch {
            // If conflict check fails, proceed anyway
        }

        forceAssignment(jobId: jobId, userId: userId, date: date, timeSlot: timeSlot)
    }

    private func forceAssignment(jobId: Int64, userId: Int64, date: String, timeSlot: String = "full") {
        guard let service = appCore.schedulingService else {
            actionError = "Service not available"
            return
        }
        do {
            _ = try service.createScheduleEntry(
                userId: userId,
                jobId: jobId,
                date: date,
                timeSlot: timeSlot
            )
            loadData()
        } catch {
            actionError = userFriendlyError(error, context: "complete action")
        }
    }

    // MARK: - Data Loading

    private func loadData() {
        guard let service = appCore.schedulingService else {
            isLoading = false
            loadError = "Scheduling service not available."
            return
        }
        isLoading = jobRows.isEmpty
        loadError = nil
        do {
            jobRows = try service.getDispatchJobRows()
            assignments = try service.getWeeklyDispatchAssignments(
                weekStart: weekStartStr,
                weekEnd: weekEndStr
            )
            unassignedWorkers = try service.getUnassignedWorkers(
                weekStart: weekStartStr,
                weekEnd: weekEndStr
            )
        } catch {
            loadError = userFriendlyError(error, context: "load dispatch data")
        }
        isLoading = false
    }
}

// MARK: - Dispatch Assign Sheet

private struct DispatchAssignSheet: View {
    @EnvironmentObject private var appCore: AppCore
    @Environment(\.dismiss) private var dismiss

    let jobId: Int64?
    let date: String
    let workerId: Int64?
    let jobRows: [SchedulingService.DispatchJobRow]
    let unassignedWorkers: [SchedulingService.UnassignedWorker]
    var onAssign: (Int64, Int64, String, String) -> Void

    @State private var selectedJobId: Int64?
    @State private var selectedWorkerId: Int64?
    @State private var entryDate: Date = Date()
    @State private var timeSlot = "full"
    @State private var allEmployees: [PeopleService.EmployeeListItem] = []

    var body: some View {
        NavigationStack {
            Form {
                Section("Employee") {
                    if workerId != nil {
                        let name = unassignedWorkers.first(where: { $0.id == workerId })?.name ?? "Selected Worker"
                        Text(name).foregroundStyle(.primary)
                    } else {
                        Picker("Employee", selection: $selectedWorkerId) {
                            Text("Select...").tag(nil as Int64?)
                            ForEach(allEmployees, id: \.id) { emp in
                                Text(emp.displayName).tag(emp.id as Int64?)
                            }
                        }
                    }
                }

                Section("Job") {
                    if jobId != nil {
                        let name = jobRows.first(where: { $0.id == jobId })?.jobName ?? "Selected Job"
                        Text(name).foregroundStyle(.primary)
                    } else {
                        Picker("Job", selection: $selectedJobId) {
                            Text("Select...").tag(nil as Int64?)
                            ForEach(jobRows, id: \.id) { job in
                                Text(job.jobName).tag(job.id as Int64?)
                            }
                        }
                    }
                }

                Section("Date") {
                    DatePicker("Date", selection: $entryDate, displayedComponents: .date)
                }

                Section("Time Slot") {
                    Picker("Time Slot", selection: $timeSlot) {
                        Text("Full Day").tag("full")
                        Text("AM Only").tag("am")
                        Text("PM Only").tag("pm")
                    }
                    .pickerStyle(.segmented)
                }
            }
            .navigationTitle("Assign Worker")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Assign") {
                        let jid = jobId ?? selectedJobId
                        let uid = workerId ?? selectedWorkerId
                        guard let jid, let uid else { return }
                        let fmt = DateFormatter()
                        fmt.dateFormat = "yyyy-MM-dd"
                        onAssign(jid, uid, fmt.string(from: entryDate), timeSlot)
                        dismiss()
                    }
                    .disabled((jobId ?? selectedJobId) == nil || (workerId ?? selectedWorkerId) == nil)
                    .fontWeight(.semibold)
                }
            }
            .onAppear {
                selectedJobId = jobId
                selectedWorkerId = workerId
                // Parse initial date
                let fmt = DateFormatter()
                fmt.dateFormat = "yyyy-MM-dd"
                if let d = fmt.date(from: date) { entryDate = d }
                // Load employees
                if let service = appCore.peopleService {
                    allEmployees = (try? service.listEmployees()) ?? []
                }
            }
        }
    }
}
