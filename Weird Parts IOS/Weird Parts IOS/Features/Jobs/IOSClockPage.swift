import SwiftUI
import CoreLocation
import WiredPartCore

/// Clock in/out page for iOS.
///
/// Shows the current user's clock status (clocked in or out), the active job
/// name when clocked in, clock-in / clock-out action buttons, and a summary
/// of today's hours worked. Uses pull-to-refresh and auto-loads on appear.
///
/// Improvements:
///   - GPS coordinates captured on clock in and clock out
///   - "Shop / Warehouse" always appears as a clock-in option
///   - Locked to the currently logged-in user (no cross-user data)
///   - Gated by `clock_in_out` permission (enforced by parent navigation)
struct IOSClockPage: View {
    @EnvironmentObject private var appCore: AppCore
    @StateObject private var locationManager = LocationManager()

    // MARK: - State

    @State private var activeEntry: JobsService.LaborEntryRow?
    @State private var todayEntries: [JobsService.LaborEntryRow] = []
    @State private var todayHours: Double = 0.0
    @State private var isLoading = true
    @State private var errorMessage: String?

    // Clock-in sheet
    @State private var showClockInSheet = false
    @State private var jobOptions: [JobsService.JobListItem] = []
    @State private var selectedJobId: Int64?

    var body: some View {
        clockContent
            .navigationTitle("Clock In / Out")
            .refreshable { loadData() }
            .task {
                locationManager.requestPermission()
                loadData()
            }
            .sheet(isPresented: $showClockInSheet) { clockInSheet }
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

                // Current status card
                Section("Current Status") {
                    if let entry = activeEntry {
                        VStack(alignment: .leading, spacing: 8) {
                            Label("Clocked In", systemImage: "clock.fill")
                                .font(.headline)
                                .foregroundStyle(.green)

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
                        }
                        .padding(.vertical, 4)
                    } else {
                        VStack(alignment: .leading, spacing: 8) {
                            Label("Not Clocked In", systemImage: "clock")
                                .font(.headline)
                                .foregroundStyle(.secondary)

                            Text("Tap below to start tracking time on a job.")
                                .font(.caption)
                                .foregroundStyle(.tertiary)

                            Button {
                                prepareClockIn()
                            } label: {
                                Label("Clock In", systemImage: "play.circle.fill")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.large)
                            .padding(.top, 4)
                        }
                        .padding(.vertical, 4)
                    }
                }

                // Today's summary
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
            #if os(iOS)
            .listStyle(.insetGrouped)
            #endif
        }
    }

    // MARK: - Clock-In Sheet

    /// Jobs with type "shop" shown at the top as permanent options.
    private var shopJobs: [JobsService.JobListItem] {
        jobOptions.filter { $0.jobType == "shop" }
    }

    /// Regular field jobs (non-shop).
    private var fieldJobs: [JobsService.JobListItem] {
        jobOptions.filter { $0.jobType != "shop" }
    }

    private var clockInSheet: some View {
        NavigationStack {
            Form {
                // Shop / Warehouse section — always visible if any shop jobs exist
                if !shopJobs.isEmpty {
                    Section("Shop / Warehouse") {
                        ForEach(shopJobs, id: \.id) { job in
                            Button {
                                selectedJobId = job.id
                            } label: {
                                HStack {
                                    Label(job.jobName, systemImage: "building.fill")
                                    Spacer()
                                    if selectedJobId == job.id {
                                        Image(systemName: "checkmark")
                                            .foregroundStyle(.tint)
                                    }
                                }
                            }
                            .tint(.primary)
                        }
                    }
                }

                // Field jobs
                Section("Select Job") {
                    if fieldJobs.isEmpty && shopJobs.isEmpty {
                        Text("No active jobs available.")
                            .foregroundStyle(.secondary)
                    } else if fieldJobs.isEmpty {
                        Text("No field jobs available.")
                            .foregroundStyle(.secondary)
                    } else {
                        Picker("Job", selection: $selectedJobId) {
                            if selectedJobId == nil || shopJobs.contains(where: { $0.id == selectedJobId }) == false {
                                Text("Choose a job...").tag(nil as Int64?)
                            }
                            ForEach(fieldJobs, id: \.id) { job in
                                Text("\(job.jobNumber) — \(job.jobName)").tag(job.id as Int64?)
                            }
                        }
                        .pickerStyle(.inline)
                    }
                }

                // Location status
                Section {
                    HStack {
                        Image(systemName: locationIcon)
                            .foregroundStyle(locationColor)
                        Text(locationStatusText)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } footer: {
                    Text("Your GPS location will be recorded when you clock in.")
                }
            }
            .navigationTitle("Clock In")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { showClockInSheet = false }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Start") {
                        Task { await performClockIn() }
                    }
                    .disabled(selectedJobId == nil)
                }
            }
        }
    }

    // MARK: - Location Status Display

    private var locationIcon: String {
        switch locationManager.authorizationStatus {
        case .authorizedWhenInUse, .authorizedAlways: "location.fill"
        case .denied, .restricted: "location.slash.fill"
        default: "location"
        }
    }

    private var locationColor: Color {
        switch locationManager.authorizationStatus {
        case .authorizedWhenInUse, .authorizedAlways: .green
        case .denied, .restricted: .red
        default: .secondary
        }
    }

    private var locationStatusText: String {
        switch locationManager.authorizationStatus {
        case .authorizedWhenInUse, .authorizedAlways: "Location access enabled"
        case .denied, .restricted: "Location access denied — GPS won't be recorded"
        case .notDetermined: "Location permission not yet requested"
        @unknown default: "Unknown location status"
        }
    }

    // MARK: - Status Dot

    private func statusDot(_ isActive: Bool) -> some View {
        Circle()
            .fill(isActive ? Color.green : Color.secondary.opacity(0.3))
            .frame(width: 8, height: 8)
    }

    // MARK: - Actions

    private func prepareClockIn() {
        guard let service = appCore.jobsService else { return }
        do {
            jobOptions = try service.listJobs(status: "active")
            selectedJobId = nil
            showClockInSheet = true
        } catch {
            errorMessage = "Failed to load jobs: \(error.localizedDescription)"
        }
    }

    private func performClockIn() async {
        guard let service = appCore.jobsService,
              let userId = appCore.currentUser?.id,
              let jobId = selectedJobId else { return }

        // Capture GPS (non-blocking — nil if denied/unavailable)
        let location = await locationManager.getCurrentLocation()

        do {
            try service.clockIn(
                userId: userId,
                jobId: jobId,
                gpsLat: location?.coordinate.latitude,
                gpsLng: location?.coordinate.longitude
            )
            showClockInSheet = false
            errorMessage = nil
            loadData()
        } catch {
            errorMessage = "Clock in failed: \(error.localizedDescription)"
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
                errorMessage = nil
                loadData()
            } catch {
                errorMessage = "Clock out failed: \(error.localizedDescription)"
            }
        }
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
        guard let service = appCore.jobsService else { return }
        guard let userId = appCore.currentUser?.id else { return }
        isLoading = activeEntry == nil && todayEntries.isEmpty
        do {
            activeEntry = try service.getActiveClockEntry(userId: userId)
            let entries = try service.listLaborEntries(userId: userId, limit: 50)
            let todayPrefix = ISO8601DateFormatter().string(from: Date()).prefix(10)
            todayEntries = entries.filter { $0.clockIn.hasPrefix(String(todayPrefix)) }
            todayHours = todayEntries.reduce(0) { $0 + $1.regularHours + $1.overtimeHours }
        } catch {
            let msg = String(describing: error)
            if !msg.contains("no such table") {
                print("[IOSClockPage] Load error: \(error)")
            }
        }
        isLoading = false
    }
}
