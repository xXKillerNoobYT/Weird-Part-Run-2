import SwiftUI
import GRDB
import WiredPartCore

/// Clock in/out page for labor tracking.
///
/// Shows currently active clock entries at the top, followed by recent
/// labor history. Provides clock-in (pick user + job) and clock-out actions.
struct ClockPage: View {
    @EnvironmentObject private var appCore: AppCore

    // MARK: - State

    @State private var activeEntries: [JobsService.LaborEntryRow] = []
    @State private var recentEntries: [JobsService.LaborEntryRow] = []
    @State private var isLoading = true

    // Clock-in form
    @State private var showClockIn = false
    @State private var clockInUserId: Int64?
    @State private var clockInJobId: Int64?
    @State private var clockInNote = ""
    @State private var users: [(id: Int64, name: String)] = []
    @State private var jobOptions: [JobsService.JobListItem] = []
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            clockContent
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task { loadData() }
        .sheet(isPresented: $showClockIn) { clockInSheet }
    }

    // MARK: - Toolbar

    private var toolbar: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Clock In / Out")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                Text("\(activeEntries.count) currently clocked in")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button {
                prepareClockIn()
            } label: {
                Label("Clock In", systemImage: "play.circle")
            }
            .buttonStyle(.borderedProminent)

            Button {
                loadData()
            } label: {
                Label("Refresh", systemImage: "arrow.clockwise")
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 16)
    }

    // MARK: - Content

    @ViewBuilder
    private var clockContent: some View {
        if isLoading {
            ProgressView("Loading clock data...")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    if let errorMessage {
                        Text(errorMessage)
                            .foregroundStyle(.red)
                            .padding()
                            .background(RoundedRectangle(cornerRadius: 8).fill(.red.opacity(0.1)))
                    }

                    activeSection
                    recentSection
                }
                .padding(24)
            }
        }
    }

    private var activeSection: some View {
        GroupBox("Active Clock Entries") {
            if activeEntries.isEmpty {
                Text("Nobody is currently clocked in")
                    .foregroundStyle(.secondary)
                    .padding(12)
            } else {
                VStack(spacing: 8) {
                    ForEach(activeEntries, id: \.id) { entry in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(entry.userName)
                                    .fontWeight(.semibold)
                                Text("\(entry.jobName)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text("Since \(formatTime(entry.clockIn))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(String(format: "%.1f hrs", entry.regularHours))
                                .font(.system(.caption, design: .monospaced))
                                .fontWeight(.bold)
                            Button("Clock Out") {
                                clockOut(entryId: entry.id)
                            }
                            .buttonStyle(.bordered)
                            .tint(.red)
                        }
                        .padding(8)
                        .background(RoundedRectangle(cornerRadius: 8).fill(.green.opacity(0.05)))
                    }
                }
                .padding(8)
            }
        }
    }

    private var recentSection: some View {
        GroupBox("Recent Labor Entries") {
            if recentEntries.isEmpty {
                Text("No recent labor entries")
                    .foregroundStyle(.secondary)
                    .padding(12)
            } else {
                VStack(spacing: 4) {
                    ForEach(recentEntries, id: \.id) { entry in
                        HStack {
                            Text(entry.userName)
                                .fontWeight(.medium)
                                .frame(width: 120, alignment: .leading)
                            Text(entry.jobName)
                                .frame(width: 140, alignment: .leading)
                                .foregroundStyle(.secondary)
                            Text(formatTime(entry.clockIn))
                                .font(.caption)
                                .frame(width: 60)
                            Text(entry.clockOut.map(formatTime) ?? "Active")
                                .font(.caption)
                                .foregroundStyle(entry.clockOut == nil ? .green : .secondary)
                                .frame(width: 60)
                            Text(String(format: "%.1f hrs", entry.regularHours + entry.overtimeHours))
                                .font(.system(.caption, design: .monospaced))
                                .frame(width: 60, alignment: .trailing)
                            Spacer()
                        }
                        .padding(.vertical, 4)
                        Divider()
                    }
                }
                .padding(8)
            }
        }
    }

    // MARK: - Clock-In Sheet

    private var clockInSheet: some View {
        VStack(spacing: 16) {
            Text("Clock In")
                .font(.title2)
                .fontWeight(.bold)

            Picker("Employee", selection: $clockInUserId) {
                Text("Select employee...").tag(nil as Int64?)
                ForEach(users, id: \.id) { user in
                    Text(user.name).tag(user.id as Int64?)
                }
            }
            .pickerStyle(.menu)

            Picker("Job", selection: $clockInJobId) {
                Text("Select job...").tag(nil as Int64?)
                ForEach(jobOptions, id: \.id) { job in
                    Text("\(job.jobNumber) — \(job.jobName)").tag(job.id as Int64?)
                }
            }
            .pickerStyle(.menu)

            TextField("Notes (optional)", text: $clockInNote)
                .textFieldStyle(.roundedBorder)

            HStack {
                Button("Cancel") {
                    showClockIn = false
                }
                .keyboardShortcut(.cancelAction)

                Spacer()

                Button("Clock In") {
                    performClockIn()
                }
                .buttonStyle(.borderedProminent)
                .disabled(clockInUserId == nil || clockInJobId == nil)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 400)
    }

    // MARK: - Actions

    private func prepareClockIn() {
        guard let service = appCore.jobsService, let auth = appCore.authService else { return }
        do {
            let activeUsers = try auth.getActiveUsers()
            users = activeUsers.map { ($0.id!, $0.displayName ?? $0.email ?? "User") }
            jobOptions = try service.listJobs(status: "active")
            showClockIn = true
        } catch {
            errorMessage = "Failed to load options: \(error.localizedDescription)"
        }
    }

    private func performClockIn() {
        guard let service = appCore.jobsService,
              let userId = clockInUserId,
              let jobId = clockInJobId else { return }
        do {
            try service.clockIn(userId: userId, jobId: jobId)
            showClockIn = false
            clockInNote = ""
            clockInUserId = nil
            clockInJobId = nil
            errorMessage = nil
            loadData()
        } catch {
            errorMessage = "Clock in failed: \(error.localizedDescription)"
        }
    }

    private func clockOut(entryId: Int64) {
        guard let service = appCore.jobsService else { return }
        do {
            try service.clockOut(laborEntryId: entryId)
            errorMessage = nil
            loadData()
        } catch {
            errorMessage = "Clock out failed: \(error.localizedDescription)"
        }
    }

    // MARK: - Helpers

    private func formatTime(_ iso: String) -> String {
        // Simple display: show last 5 chars (HH:MM) or truncate
        if iso.count >= 16 {
            let startIdx = iso.index(iso.startIndex, offsetBy: 11)
            let endIdx = iso.index(iso.startIndex, offsetBy: 16)
            return String(iso[startIdx..<endIdx])
        }
        return iso
    }

    // MARK: - Data Loading

    private func loadData() {
        guard let service = appCore.jobsService else { return }
        isLoading = true
        do {
            // Filter active entries client-side (those with no clock_out)
            let allEntries = try service.listLaborEntries(limit: 200)
            activeEntries = allEntries.filter { $0.clockOut == nil }
            recentEntries = Array(allEntries.prefix(50))
        } catch {
            print("[ClockPage] Load error: \(error)")
        }
        isLoading = false
    }
}
