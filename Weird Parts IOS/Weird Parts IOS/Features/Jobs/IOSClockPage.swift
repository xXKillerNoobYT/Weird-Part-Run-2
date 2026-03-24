import GRDB
import SwiftUI
import CoreLocation

import WiredPartCore

/// Clock in/out page for iOS.
///
/// Shows an inline GPS-sorted job list for clocking in, or current clock
/// status when already clocked in. "Shop / Warehouse" is always pinned first.
/// When clocked into Shop, an optional collapsible section lets the user link
/// time to a specific job without clocking out/in.
struct IOSClockPage: View {
    @EnvironmentObject private var appCore: AppCore
    @StateObject private var locationManager = LocationManager()
    @StateObject private var geofenceManager = GeofenceManager()

    // MARK: - State

    @State private var activeEntry: JobsService.LaborEntryRow?
    @State private var todayEntries: [JobsService.LaborEntryRow] = []
    @State private var todayHours: Double = 0.0
    @State private var isLoading = true
    @State private var errorMessage: String?

    // GPS + job list
    @State private var userLocation: CLLocation?
    @State private var sortedJobs: [JobWithDistance] = []
    @State private var isShopClockIn = false
    @State private var linkedJobId: Int64?
    @State private var linkedJobName: String?

    // Activity status (working, supply_run, etc.)
    @State private var activityStatus: String = "working"

    // To-do integration
    @State private var activeTodos: [JobsService.ClockTodoItem] = []
    @State private var currentTodo: JobsService.ClockTodoItem?
    @State private var workType: String = "new_work"

    // Live elapsed timer
    @State private var elapsedTimer: Timer?
    @State private var elapsedText: String = "0h 0m"

    // Today's grouped breakdown
    @State private var todayJobGroups: [JobsService.JobClockGroup] = []

    // Sheets
    @State private var activeSheet: ActiveSheet?
    @State private var lastLaborEntryId: Int64?

    private enum ActiveSheet: Identifiable {
        case questionnaire(Int64)
        case jobScanner
        case help
        case todoPicker
        case switchJobPicker

        var id: String {
            switch self {
            case .questionnaire(let id): "questionnaire-\(id)"
            case .jobScanner: "jobScanner"
            case .help: "help"
            case .todoPicker: "todoPicker"
            case .switchJobPicker: "switchJobPicker"
            }
        }
    }

    struct JobWithDistance: Identifiable {
        let id: Int64
        let jobName: String
        let jobNumber: String
        let address: String?
        let latitude: Double?
        let longitude: Double?
        let distanceMiles: Double?
        let status: String

        var distanceText: String {
            guard let d = distanceMiles else { return "" }
            if d < 0.1 { return "Nearby" }
            return String(format: "%.1f mi", d)
        }
    }

    var body: some View {
        clockContent
            .navigationTitle("Clock In / Out")
            .toolbar {
                if activeEntry == nil {
                    ToolbarItem(placement: .primaryAction) {
                        Button { activeSheet = .jobScanner } label: {
                            Label("Scan Job", systemImage: "qrcode.viewfinder")
                        }
                    }
                }
                ToolbarItem(placement: .secondaryAction) {
                    Button { activeSheet = .help } label: {
                        Image(systemName: "questionmark.circle")
                    }
                }
            }
            .refreshable { loadData() }
            .task {
                locationManager.requestPermission()
                loadData()
            }
            .onDisappear { elapsedTimer?.invalidate(); elapsedTimer = nil }
            .fullScreenCover(isPresented: $geofenceManager.didExitJobRegion) {
                GeofenceAlertView(
                    geofenceManager: geofenceManager,
                    onResolved: { loadData() }
                )
                .environmentObject(appCore)
                .interactiveDismissDisabled(true)
            }
            .sheet(item: $activeSheet) { sheet in
                switch sheet {
                case .questionnaire(let entryId):
                    IOSQuestionnairePage(laborEntryId: entryId, onComplete: { loadData() })
                case .jobScanner:
                    QRScanSheet(expectedType: .job) { result in
                        if let jobId = result.entityId, result.isFound {
                            clockIn(jobId: jobId, isShop: false)
                        }
                    }
                    .environmentObject(appCore)
                case .help:
                    PageHelpSheet(
                        title: "Clock In/Out Help",
                        sections: [
                            ("Clocking In", "Select a job from the GPS-sorted list to clock in. Jobs closest to you appear first. 'Shop / Warehouse' is always pinned at the top."),
                            ("Clocking Out", "When clocked in, tap the Clock Out button. You may be prompted to answer clock-out questions before the entry is saved."),
                            ("Elapsed Timer", "The large timer shows how long you've been on the current job. It updates every minute automatically."),
                            ("Switch Job", "Use the Switch Job button to clock out of the current job and immediately clock into a different one — no need to find the job list again."),
                            ("To-Do Tracking", "After clocking in, you can optionally pick a to-do to track what you're working on. Use 'Mark Done' to complete it and pick the next one."),
                            ("Today's Hours", "The hours breakdown shows your total time per job with optional per-to-do detail. Warranty entries are marked with a 'W' badge."),
                            ("QR Scan", "Use the QR scanner button in the toolbar to scan a job QR code and clock in directly.")
                        ]
                    )
                case .todoPicker:
                    TodoPickerSheet(todos: activeTodos) { todo in
                        selectTodo(todo)
                        activeSheet = nil
                    }
                case .switchJobPicker:
                    SwitchJobPickerSheet(jobs: sortedJobs) { jobId, isShop in
                        activeSheet = nil
                        clockIn(jobId: jobId, isShop: isShop)
                    }
                    .environmentObject(appCore)
                }
            }
    }

    // MARK: - Content

    @ViewBuilder
    private var clockContent: some View {
        if isLoading {
            ProgressView("Loading clock status...")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            List {
                // Error banner
                if let errorMessage {
                    Section {
                        Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                            .font(.caption)
                    }
                }

                if let entry = activeEntry {
                    // CLOCKED IN — show status + clock out button
                    clockedInSection(entry)
                    currentTaskSection(entry)
                    shopJobLinkSection
                    todayHoursSection
                } else {
                    // NOT CLOCKED IN — show inline job picker
                    jobPickerSection
                    todayHoursSection
                }
            }
            .listStyle(.insetGrouped)
        }
    }

    // MARK: - Clocked-In Section

    private func clockedInSection(_ entry: JobsService.LaborEntryRow) -> some View {
        Section("Current Status") {
            VStack(alignment: .leading, spacing: 8) {
                Label(activityStatus == "supply_run" ? "On Supply Run" : "Clocked In",
                      systemImage: activityStatus == "supply_run" ? "car.fill" : "clock.fill")
                    .font(.headline)
                    .foregroundStyle(activityStatus == "supply_run" ? .orange : .green)

                // Live elapsed timer — large, readable display
                VStack(spacing: 2) {
                    Text(elapsedText)
                        .font(.system(size: 48, weight: .bold, design: .rounded))
                        .monospacedDigit()
                    Text("on \(entry.jobName)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 4)

                HStack {
                    Text("Since:")
                        .foregroundStyle(.secondary)
                    Text(formatTime(entry.clockIn))
                        .font(.system(.subheadline, design: .monospaced))
                }

                // Clock Out + Switch Job buttons
                HStack(spacing: 12) {
                    Button(role: .destructive) {
                        clockOut(entryId: entry.id)
                    } label: {
                        Label("Clock Out", systemImage: "stop.circle.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)

                    Button {
                        Task { await switchJob(entryId: entry.id) }
                    } label: {
                        Label("Switch Job", systemImage: "arrow.triangle.swap")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                    .tint(.blue)
                }
                .padding(.top, 4)

                Divider()

                // Lunch / Break / Supply Run buttons
                HStack(spacing: 12) {
                    Button {
                        Task { await startBreak(type: "lunch", entryId: entry.id) }
                    } label: {
                        Label("Lunch", systemImage: "fork.knife")
                    }
                    .buttonStyle(.bordered)

                    Button {
                        Task { await startBreak(type: "break", entryId: entry.id) }
                    } label: {
                        Label("Break", systemImage: "cup.and.saucer")
                    }
                    .buttonStyle(.bordered)

                    Button {
                        Task { await toggleSupplyRun(entryId: entry.id) }
                    } label: {
                        Label(
                            activityStatus == "supply_run" ? "End Run" : "Supply Run",
                            systemImage: activityStatus == "supply_run" ? "checkmark.circle" : "car.fill"
                        )
                    }
                    .buttonStyle(.bordered)
                    .tint(activityStatus == "supply_run" ? .green : .orange)
                }
            }
            .padding(.vertical, 4)
        }
    }

    // MARK: - Job Picker (inline, no sheet)

    @ViewBuilder
    private var jobPickerSection: some View {
        Section {
            // Shop / Warehouse — always first, pinned
            Button {
                clockIn(jobId: nil, isShop: true)
            } label: {
                HStack(spacing: DS.Space.md) {
                    Image(systemName: "building.fill")
                        .font(.title3)
                        .foregroundStyle(.blue)
                        .frame(width: 40, height: 40)
                        .background(Color.blue.opacity(0.1))
                        .clipShape(RoundedRectangle(cornerRadius: 8))

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Shop / Warehouse")
                            .font(.body)
                            .fontWeight(.semibold)
                        Text("Office, ordering, design work")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Image(systemName: "clock.badge.checkmark.fill")
                        .foregroundStyle(.green)
                }
                .frame(minHeight: 56)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        } header: {
            Text("Clock In To")
        }

        // Active Jobs sorted by distance
        if !sortedJobs.isEmpty {
            Section {
                ForEach(sortedJobs) { job in
                    Button {
                        clockIn(jobId: job.id, isShop: false)
                    } label: {
                        HStack(spacing: DS.Space.md) {
                            Image(systemName: "mappin.circle.fill")
                                .font(.title3)
                                .foregroundStyle(.orange)
                                .frame(width: 40, height: 40)
                                .background(Color.orange.opacity(0.1))
                                .clipShape(RoundedRectangle(cornerRadius: 8))

                            VStack(alignment: .leading, spacing: 2) {
                                Text(job.jobName)
                                    .font(.body)
                                    .fontWeight(.medium)
                                HStack(spacing: 8) {
                                    if !job.jobNumber.isEmpty {
                                        Text("#\(job.jobNumber)")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    if let addr = job.address, !addr.isEmpty {
                                        Text(addr)
                                            .font(.caption)
                                            .foregroundStyle(.tertiary)
                                            .lineLimit(1)
                                    }
                                }
                            }

                            Spacer()

                            if !job.distanceText.isEmpty {
                                Text(job.distanceText)
                                    .font(.caption)
                                    .fontWeight(.medium)
                                    .foregroundStyle(
                                        (job.distanceMiles ?? 999) < 1 ? .green : .secondary
                                    )
                            }

                            Image(systemName: "clock.badge.checkmark.fill")
                                .foregroundStyle(.green)
                        }
                        .frame(minHeight: 56)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            } header: {
                HStack {
                    Text("Job Sites")
                    Spacer()
                    if userLocation != nil {
                        Label("Sorted by distance", systemImage: "location.fill")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    // MARK: - Shop Job Link

    @ViewBuilder
    private var shopJobLinkSection: some View {
        if isShopClockIn {
            Section {
                DisclosureGroup("Link time to a job (optional)") {
                    if let linkedName = linkedJobName {
                        // Currently linked
                        HStack {
                            Image(systemName: "link.circle.fill")
                                .foregroundStyle(.blue)
                            Text("Linked to: \(linkedName)")
                                .font(.subheadline)
                            Spacer()
                            Button("End Link") {
                                endJobLink()
                            }
                            .font(.caption)
                            .buttonStyle(.bordered)
                            .tint(.red)
                        }
                        .padding(.vertical, 4)

                        Button("Change Job") {
                            linkedJobId = nil
                            linkedJobName = nil
                        }
                        .font(.caption)
                    } else {
                        // Not linked — show job list
                        ForEach(sortedJobs) { job in
                            Button {
                                startJobLink(jobId: job.id, jobName: job.jobName)
                            } label: {
                                HStack {
                                    Text(job.jobName)
                                        .font(.subheadline)
                                    if !job.distanceText.isEmpty {
                                        Spacer()
                                        Text(job.distanceText)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                .frame(minHeight: 40)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            } header: {
                Text("Job Link")
            }
        }
    }

    // MARK: - Today's Hours (Per-Job + Per-Todo Breakdown)

    private var todayHoursSection: some View {
        Section {
            if todayJobGroups.isEmpty {
                Text("No hours logged today.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                // Per-job breakdown
                ForEach(todayJobGroups) { jobGroup in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(jobGroup.jobName).font(.headline)
                            Spacer()
                            Text(formatDuration(jobGroup.totalDuration))
                                .font(.headline).monospacedDigit()
                        }
                        // Per-entry breakdown within job (shows to-do if linked)
                        ForEach(jobGroup.entries) { entry in
                            HStack {
                                if let todo = entry.todoName {
                                    Text("  \(todo)")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                } else {
                                    Text("  General")
                                        .font(.caption)
                                        .foregroundStyle(.tertiary)
                                }
                                if entry.workType == "warranty" {
                                    Text("W")
                                        .font(.caption2)
                                        .fontWeight(.bold)
                                        .padding(.horizontal, 4)
                                        .padding(.vertical, 1)
                                        .background(Color.orange.opacity(0.2))
                                        .clipShape(Capsule())
                                }
                                Spacer()
                                Text(formatDuration(entry.duration))
                                    .font(.caption).monospacedDigit()
                                    .foregroundStyle(.secondary)
                                statusDot(entry.endTime == nil)
                            }
                        }
                    }
                }

                // Total
                HStack {
                    Text("Today Total").font(.headline).bold()
                    Spacer()
                    Text(formatDuration(todaysTotal))
                        .font(.headline).bold().monospacedDigit()
                }
                .padding(.top, 4)
            }
        } header: {
            Text("Today's Hours")
        }
    }

    /// Total duration across all today's entries.
    private var todaysTotal: TimeInterval {
        todayJobGroups.reduce(0) { $0 + $1.totalDuration }
    }

    // MARK: - Status Dot

    private func statusDot(_ isActive: Bool) -> some View {
        Circle()
            .fill(isActive ? Color.green : Color.secondary.opacity(0.3))
            .frame(width: 8, height: 8)
    }

    // MARK: - Current Task Section

    @ViewBuilder
    private func currentTaskSection(_ entry: JobsService.LaborEntryRow) -> some View {
        // Only show if this job has to-dos
        if !activeTodos.isEmpty || currentTodo != nil {
            Section {
                // Work type picker
                Picker("Work Type", selection: $workType) {
                    Text("New Work").tag("new_work")
                    Text("Warranty").tag("warranty")
                }
                .pickerStyle(.segmented)
                .onChange(of: workType) { _, newValue in
                    guard let service = appCore.jobsService else { return }
                    try? service.setClockEntryWorkType(clockEntryId: entry.id, workType: newValue)
                }

                if let todo = currentTodo {
                    // Current to-do display
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Image(systemName: "checkmark.circle")
                                .foregroundStyle(.blue)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(todo.title)
                                    .font(.headline)
                                Text("Working on this")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                        }

                        HStack(spacing: 12) {
                            Button {
                                Task { await markTodoDoneAndPickNext(entry: entry) }
                            } label: {
                                Label("Mark Done", systemImage: "checkmark.circle.fill")
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(.green)
                            .controlSize(.small)

                            Button {
                                activeSheet = .todoPicker
                            } label: {
                                Label("Switch", systemImage: "arrow.triangle.swap")
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        }
                    }
                } else {
                    // No to-do selected
                    Button {
                        activeSheet = .todoPicker
                    } label: {
                        Label("Pick a To-Do", systemImage: "checklist")
                    }
                }
            } header: {
                Text("Current Task")
            }
        }
    }

    // MARK: - Actions

    private func clockIn(jobId: Int64?, isShop: Bool) {
        guard let service = appCore.jobsService,
              let userId = appCore.currentUser?.id else {
            errorMessage = "Not logged in"
            return
        }

        Task {
            let location = await locationManager.getCurrentLocation()
            let lat = location?.coordinate.latitude
            let lng = location?.coordinate.longitude

            do {
                if isShop {
                    // Clock in to Shop/Warehouse (jobId = 0 or a special "shop" job)
                    try service.clockIn(userId: userId, jobId: jobId ?? 0, gpsLat: lat, gpsLng: lng)
                    isShopClockIn = true
                    geofenceManager.stopMonitoring()
                } else if let jid = jobId {
                    try service.clockIn(userId: userId, jobId: jid, gpsLat: lat, gpsLng: lng)
                    isShopClockIn = false
                    // Start geofence monitoring if job has coordinates
                    if let job = sortedJobs.first(where: { $0.id == jid }),
                       let jobLat = job.latitude, let jobLng = job.longitude,
                       jobLat != 0, jobLng != 0 {
                        geofenceManager.startMonitoring(jobId: jid, jobName: job.jobName, latitude: jobLat, longitude: jobLng)
                    }
                }
                errorMessage = nil
                loadData()
            } catch {
                errorMessage = "Clock in failed: \(error.localizedDescription)"
            }
        }
    }

    private func clockOut(entryId: Int64) {
        guard let service = appCore.jobsService else { return }

        Task {
            let location = await locationManager.getCurrentLocation()

            do {
                try service.clockOut(
                    laborEntryId: entryId,
                    gpsLat: location?.coordinate.latitude,
                    gpsLng: location?.coordinate.longitude
                )
                geofenceManager.stopMonitoring()
                errorMessage = nil
                linkedJobId = nil
                linkedJobName = nil
                isShopClockIn = false
                lastLaborEntryId = entryId
                activeSheet = .questionnaire(entryId)
                loadData()
            } catch {
                errorMessage = "Clock out failed: \(error.localizedDescription)"
            }
        }
    }

    /// Start a lunch or break — clocks the user out and triggers the questionnaire.
    private func startBreak(type: String, entryId: Int64) async {
        guard let service = appCore.jobsService,
              let db = appCore.db else { return }

        let location = await locationManager.getCurrentLocation()

        do {
            // Record the break type in the labor entry notes before clocking out
            try await db.writer.write { conn in
                let existingNotes = try String.fetchOne(
                    conn,
                    sql: "SELECT notes FROM labor_entries WHERE id = ?",
                    arguments: [entryId]
                ) ?? ""
                let breakNote = existingNotes.isEmpty
                    ? "[\(type)]"
                    : "\(existingNotes) [\(type)]"
                try conn.execute(
                    sql: "UPDATE labor_entries SET notes = ? WHERE id = ?",
                    arguments: [breakNote, entryId]
                )
            }

            // Clock out (same as normal clock-out, triggers questionnaire)
            try service.clockOut(
                laborEntryId: entryId,
                gpsLat: location?.coordinate.latitude,
                gpsLng: location?.coordinate.longitude
            )
            geofenceManager.stopMonitoring()
            await MainActor.run {
                errorMessage = nil
                linkedJobId = nil
                linkedJobName = nil
                isShopClockIn = false
                activityStatus = "working"
                lastLaborEntryId = entryId
                activeSheet = .questionnaire(entryId)
            }
            loadData()
        } catch {
            await MainActor.run {
                errorMessage = "\(type.capitalized) failed: \(error.localizedDescription)"
            }
        }
    }

    /// Toggle supply run status — keeps the user clocked in, changes activity status.
    private func toggleSupplyRun(entryId: Int64) async {
        guard let db = appCore.db else { return }

        let newStatus = activityStatus == "supply_run" ? "working" : "supply_run"

        do {
            try await db.writer.write { conn in
                let existingNotes = try String.fetchOne(
                    conn,
                    sql: "SELECT notes FROM labor_entries WHERE id = ?",
                    arguments: [entryId]
                ) ?? ""
                let timestamp = ISO8601DateFormatter().string(from: Date())
                let note: String
                if newStatus == "supply_run" {
                    note = existingNotes.isEmpty
                        ? "[supply_run_start:\(timestamp)]"
                        : "\(existingNotes) [supply_run_start:\(timestamp)]"
                } else {
                    note = "\(existingNotes) [supply_run_end:\(timestamp)]"
                }
                try conn.execute(
                    sql: "UPDATE labor_entries SET notes = ? WHERE id = ?",
                    arguments: [note, entryId]
                )
            }
            await MainActor.run {
                activityStatus = newStatus
                errorMessage = nil
            }
        } catch {
            await MainActor.run {
                errorMessage = "Supply run toggle failed: \(error.localizedDescription)"
            }
        }
    }

    private func startJobLink(jobId: Int64, jobName: String) {
        linkedJobId = jobId
        linkedJobName = jobName
    }

    private func endJobLink() {
        linkedJobId = nil
        linkedJobName = nil
    }

    // MARK: - Switch Job

    /// Clock out of current job and immediately show job picker for new clock-in.
    private func switchJob(entryId: Int64) async {
        guard let service = appCore.jobsService else { return }
        let location = await locationManager.getCurrentLocation()

        do {
            try service.clockOut(
                laborEntryId: entryId,
                gpsLat: location?.coordinate.latitude,
                gpsLng: location?.coordinate.longitude
            )
            geofenceManager.stopMonitoring()
            await MainActor.run {
                errorMessage = nil
                linkedJobId = nil
                linkedJobName = nil
                isShopClockIn = false
                activeEntry = nil
                currentTodo = nil
                elapsedTimer?.invalidate()
                elapsedTimer = nil
                // Show job picker immediately for new clock-in
                activeSheet = .switchJobPicker
            }
            loadData()
        } catch {
            await MainActor.run {
                errorMessage = "Switch failed: \(error.localizedDescription)"
            }
        }
    }

    // MARK: - Elapsed Timer

    private func startElapsedTimer(clockInISO: String) {
        updateElapsedText(clockInISO: clockInISO)
        elapsedTimer?.invalidate()
        elapsedTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { _ in
            Task { @MainActor in
                updateElapsedText(clockInISO: clockInISO)
            }
        }
    }

    private func updateElapsedText(clockInISO: String) {
        let isoFormatter = ISO8601DateFormatter()
        isoFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let isoBasic = ISO8601DateFormatter()
        isoBasic.formatOptions = [.withInternetDateTime]

        guard let clockInDate = isoFormatter.date(from: clockInISO)
                ?? isoBasic.date(from: clockInISO) else {
            elapsedText = "0h 0m"
            return
        }
        let elapsed = Date().timeIntervalSince(clockInDate)
        let hours = Int(elapsed) / 3600
        let minutes = (Int(elapsed) % 3600) / 60
        elapsedText = "\(hours)h \(minutes)m"
    }

    // MARK: - To-Do Actions

    private func selectTodo(_ todo: JobsService.ClockTodoItem) {
        guard let service = appCore.jobsService,
              let entry = activeEntry else { return }
        currentTodo = todo
        try? service.linkClockEntryToTodo(clockEntryId: entry.id, todoId: todo.id)
    }

    private func markTodoDoneAndPickNext(entry: JobsService.LaborEntryRow) async {
        guard let todo = currentTodo,
              let notebooksService = appCore.notebooksService,
              let jobsService = appCore.jobsService else { return }

        do {
            try notebooksService.completeEntry(entryId: todo.id)
            let remaining = try jobsService.getActiveJobTodos(jobId: entry.jobId)

            await MainActor.run {
                activeTodos = remaining
                currentTodo = nil
                // Unlink the completed to-do
                try? jobsService.linkClockEntryToTodo(clockEntryId: entry.id, todoId: nil)
            }

            if !remaining.isEmpty {
                await MainActor.run {
                    activeSheet = .todoPicker
                }
            }
        } catch {
            await MainActor.run {
                errorMessage = "Failed to complete to-do: \(error.localizedDescription)"
            }
        }
    }

    private func loadTodosForJob(jobId: Int64) {
        guard let service = appCore.jobsService else { return }
        do {
            activeTodos = try service.getActiveJobTodos(jobId: jobId)
        } catch {
            activeTodos = []
        }
    }

    // MARK: - Helpers

    private func formatTime(_ iso: String) -> String {
        guard iso.count >= 16 else { return iso }
        let start = iso.index(iso.startIndex, offsetBy: 11)
        let end = iso.index(iso.startIndex, offsetBy: 16)
        return String(iso[start..<end])
    }

    private func formatDuration(_ interval: TimeInterval) -> String {
        let hours = Int(interval) / 3600
        let minutes = (Int(interval) % 3600) / 60
        return "\(hours)h \(minutes)m"
    }

    // MARK: - Data Loading

    private func loadData() {
        isLoading = activeEntry == nil && todayEntries.isEmpty
        errorMessage = nil

        Task {
            userLocation = await locationManager.getCurrentLocation()
            await loadJobsAndClockStatus()
        }
    }

    private func loadJobsAndClockStatus() async {
        guard let db = appCore.db,
              let userId = appCore.currentUser?.id else {
            await MainActor.run {
                isLoading = false
                errorMessage = "Not logged in"
            }
            return
        }

        do {
            guard let service = appCore.jobsService else {
                await MainActor.run { isLoading = false }
                return
            }

            // Load active clock entry
            let entry = try service.getActiveClockEntry(userId: userId)

            // Load today's entries
            let entries = try service.listLaborEntries(userId: userId, limit: 50)
            let todayPrefix = ISO8601DateFormatter().string(from: Date()).prefix(10)
            let todayE = entries.filter { $0.clockIn.hasPrefix(String(todayPrefix)) }
            let todayH = todayE.reduce(0.0) { $0 + $1.regularHours + $1.overtimeHours }

            // Load active jobs via JobsService (avoids raw SQL column issues)
            let clockJobs = try service.listActiveJobsForClock()

            // Calculate distances and sort
            let userLoc = userLocation
            var jobsWithDist: [JobWithDistance] = clockJobs.map { job in
                let lat = job.latitude
                let lng = job.longitude
                var dist: Double? = nil

                if let userLoc, let lat, let lng,
                   lat != 0, lng != 0 {
                    let jobLoc = CLLocation(latitude: lat, longitude: lng)
                    dist = userLoc.distance(from: jobLoc) / 1609.34
                }

                return JobWithDistance(
                    id: job.id,
                    jobName: job.jobName,
                    jobNumber: job.jobNumber,
                    address: job.address,
                    latitude: lat,
                    longitude: lng,
                    distanceMiles: dist,
                    status: job.status
                )
            }

            // Sort: jobs with distance first (nearest first), then jobs without distance
            jobsWithDist.sort { a, b in
                switch (a.distanceMiles, b.distanceMiles) {
                case let (ad?, bd?): return ad < bd
                case (_?, nil): return true
                case (nil, _?): return false
                case (nil, nil): return a.jobName < b.jobName
                }
            }

            // Check activity status from notes (supply_run tracking)
            var currentActivity = "working"
            if let entry {
                let notes = try? await db.writer.read { conn in
                    try String.fetchOne(
                        conn,
                        sql: "SELECT notes FROM labor_entries WHERE id = ?",
                        arguments: [entry.id]
                    )
                }
                if let notes, notes.contains("[supply_run_start:") {
                    // Check if the most recent supply_run marker is a start (not an end)
                    let lastStart = notes.range(of: "[supply_run_start:", options: .backwards)
                    let lastEnd = notes.range(of: "[supply_run_end:", options: .backwards)
                    if let start = lastStart {
                        if let end = lastEnd {
                            // Both exist — supply run is active if start came after end
                            if start.lowerBound > end.lowerBound {
                                currentActivity = "supply_run"
                            }
                        } else {
                            // Only start exists, no end — supply run is active
                            currentActivity = "supply_run"
                        }
                    }
                }
            }

            // Load to-dos for the active job
            var todos: [JobsService.ClockTodoItem] = []
            var linkedTodo: JobsService.ClockTodoItem?
            var currentWorkType = "new_work"
            if let entry {
                todos = try service.getActiveJobTodos(jobId: entry.jobId)
                currentWorkType = entry.workType ?? "new_work"
                if let todoId = entry.linkedTodoId {
                    linkedTodo = todos.first(where: { $0.id == todoId })
                }
            }

            // Load today's grouped clock entries
            let groups = try service.getTodaysClockEntries(userId: userId)

            await MainActor.run {
                activeEntry = entry
                todayEntries = todayE
                todayHours = todayH
                todayJobGroups = groups
                sortedJobs = jobsWithDist
                activityStatus = currentActivity
                activeTodos = todos
                currentTodo = linkedTodo
                workType = currentWorkType
                isLoading = false

                // Start/stop elapsed timer based on clock-in state
                if let entry {
                    startElapsedTimer(clockInISO: entry.clockIn)
                } else {
                    elapsedTimer?.invalidate()
                    elapsedTimer = nil
                    elapsedText = "0h 0m"
                }

                // Check if current clock-in is to shop
                if let entry, entry.jobName.lowercased().contains("shop") || entry.jobName.lowercased().contains("warehouse") {
                    isShopClockIn = true
                } else {
                    isShopClockIn = false
                }
            }
        } catch {
            await MainActor.run {
                errorMessage = error.localizedDescription
                isLoading = false
            }
        }
    }
}

// MARK: - Switch Job Picker Sheet

private struct SwitchJobPickerSheet: View {
    @Environment(\.dismiss) private var dismiss
    let jobs: [IOSClockPage.JobWithDistance]
    let onSelect: (Int64?, Bool) -> Void

    var body: some View {
        NavigationStack {
            List {
                // Shop option
                Button {
                    onSelect(nil, true)
                } label: {
                    HStack(spacing: DS.Space.md) {
                        Image(systemName: "building.fill")
                            .font(.title3)
                            .foregroundStyle(.blue)
                            .frame(width: 36, height: 36)
                            .background(Color.blue.opacity(0.1))
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Shop / Warehouse").font(.body).fontWeight(.semibold)
                            Text("Office, ordering, design work").font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                // Job sites
                ForEach(jobs) { job in
                    Button {
                        onSelect(job.id, false)
                    } label: {
                        HStack(spacing: DS.Space.md) {
                            Image(systemName: "mappin.circle.fill")
                                .font(.title3)
                                .foregroundStyle(.orange)
                                .frame(width: 36, height: 36)
                                .background(Color.orange.opacity(0.1))
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                            VStack(alignment: .leading, spacing: 2) {
                                Text(job.jobName).font(.body).fontWeight(.medium)
                                if !job.jobNumber.isEmpty {
                                    Text("#\(job.jobNumber)").font(.caption).foregroundStyle(.secondary)
                                }
                            }
                            Spacer()
                            if !job.distanceText.isEmpty {
                                Text(job.distanceText)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .navigationTitle("Switch to…")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}

// MARK: - To-Do Picker Sheet

private struct TodoPickerSheet: View {
    @Environment(\.dismiss) private var dismiss
    let todos: [JobsService.ClockTodoItem]
    let onSelect: (JobsService.ClockTodoItem) -> Void

    var body: some View {
        NavigationStack {
            List {
                if todos.isEmpty {
                    ContentUnavailableView(
                        "No To-Dos",
                        systemImage: "checklist",
                        description: Text("This job has no active to-dos. Add to-dos in the job's notebook.")
                    )
                } else {
                    ForEach(todos) { todo in
                        Button {
                            onSelect(todo)
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(todo.title)
                                    .font(.headline)
                                    .foregroundStyle(.primary)
                                if let content = todo.content, !content.isEmpty {
                                    Text(content)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(2)
                                }
                                if let status = todo.taskStatus, status != "pending" {
                                    Text(status.capitalized)
                                        .font(.caption2)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(Color.orange.opacity(0.2))
                                        .clipShape(Capsule())
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("What are you working on?")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Skip") { dismiss() }
                }
            }
        }
    }
}
