import SwiftUI
import CoreLocation
import GRDB
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

    // Sheets
    @State private var activeSheet: ActiveSheet?
    @State private var lastLaborEntryId: Int64?

    private enum ActiveSheet: Identifiable {
        case questionnaire(Int64)
        case jobScanner
        case help

        var id: String {
            switch self {
            case .questionnaire(let id): "questionnaire-\(id)"
            case .jobScanner: "jobScanner"
            case .help: "help"
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
                            ("QR Scan", "Use the QR scanner button in the toolbar to scan a job QR code and clock in directly.")
                        ]
                    )
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

                HStack {
                    Text("Job:")
                        .foregroundStyle(.secondary)
                    Text(entry.jobName)
                        .fontWeight(.medium)
                }
                .font(.subheadline)

                HStack {
                    Text("Since:")
                        .foregroundStyle(.secondary)
                    Text(formatTime(entry.clockIn))
                        .font(.system(.subheadline, design: .monospaced))
                }

                Button(role: .destructive) {
                    clockOut(entryId: entry.id)
                } label: {
                    Label("Clock Out", systemImage: "stop.circle.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
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

    // MARK: - Today's Hours

    private var todayHoursSection: some View {
        Section("Today's Hours") {
            HStack {
                Label("Total", systemImage: "chart.bar.fill")
                    .foregroundStyle(.primary)
                Spacer()
                Text(String(format: "%.1f hrs", todayHours))
                    .font(.system(.body, design: .monospaced))
                    .fontWeight(.semibold)
            }

            if todayEntries.isEmpty {
                Text("No time entries recorded today.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(todayEntries, id: \.id) { entry in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(entry.jobName)
                                .font(.subheadline)
                            Text("\(formatTime(entry.clockIn)) - \(entry.clockOut.map { formatTime($0) } ?? "now")")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(String(format: "%.1f", entry.regularHours + entry.overtimeHours))
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.secondary)
                        statusDot(entry.clockOut == nil)
                    }
                }
            }
        }
    }

    // MARK: - Status Dot

    private func statusDot(_ isActive: Bool) -> some View {
        Circle()
            .fill(isActive ? Color.green : Color.secondary.opacity(0.3))
            .frame(width: 8, height: 8)
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

    // MARK: - Helpers

    private func formatTime(_ iso: String) -> String {
        guard iso.count >= 16 else { return iso }
        let start = iso.index(iso.startIndex, offsetBy: 11)
        let end = iso.index(iso.startIndex, offsetBy: 16)
        return String(iso[start..<end])
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

            await MainActor.run {
                activeEntry = entry
                todayEntries = todayE
                todayHours = todayH
                sortedJobs = jobsWithDist
                activityStatus = currentActivity
                isLoading = false

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
