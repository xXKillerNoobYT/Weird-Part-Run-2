import SwiftUI
import WiredPartCore

/// Labor tracking page for iOS.
///
/// Shows currently active clock entries at the top with clock-out buttons,
/// followed by recent labor history. Provides a clock-in action sheet
/// for starting new entries.
struct LaborPage: View {
    @EnvironmentObject private var appCore: AppCore

    // MARK: - State

    @State private var activeEntries: [JobsService.LaborEntryRow] = []
    @State private var recentEntries: [JobsService.LaborEntryRow] = []
    @State private var isLoading = true
    @State private var showClockIn = false
    @State private var errorMessage: String?

    // Clock-in form state
    @State private var selectedUserId: Int64?
    @State private var selectedJobId: Int64?
    @State private var clockInNote = ""
    @State private var users: [(id: Int64, name: String)] = []
    @State private var jobOptions: [JobsService.JobListItem] = []

    var body: some View {
        NavigationStack {
            laborContent
                .navigationTitle("Labor")
                .toolbar {
                    ToolbarItem(placement: .primaryAction) {
                        Button {
                            prepareClockIn()
                        } label: {
                            Label("Clock In", systemImage: "play.circle.fill")
                        }
                    }
                }
                .refreshable { loadData() }
                .task { loadData() }
                .sheet(isPresented: $showClockIn) { clockInSheet }
        }
    }

    // MARK: - Content

    @ViewBuilder
    private var laborContent: some View {
        if isLoading {
            ProgressView("Loading labor data...")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            List {
                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .foregroundStyle(.red)
                    }
                }

                // Active entries section
                Section("Active (\(activeEntries.count))") {
                    if activeEntries.isEmpty {
                        Text("Nobody is currently clocked in")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(activeEntries, id: \.id) { entry in
                            activeEntryRow(entry)
                        }
                    }
                }

                // Recent entries section
                Section("Recent") {
                    if recentEntries.isEmpty {
                        Text("No recent labor entries")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(recentEntries, id: \.id) { entry in
                            recentEntryRow(entry)
                        }
                    }
                }
            }
            #if os(iOS)
            .listStyle(.insetGrouped)
            #endif
        }
    }

    // MARK: - Entry Rows

    private func activeEntryRow(_ entry: JobsService.LaborEntryRow) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(entry.userName)
                    .fontWeight(.semibold)
                Text(entry.jobName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("Since \(formatTime(entry.clockIn))")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 4) {
                Text(String(format: "%.1f hrs", entry.regularHours + entry.overtimeHours))
                    .font(.system(.caption, design: .monospaced))
                    .fontWeight(.bold)
                Button("Clock Out") {
                    clockOut(entryId: entry.id)
                }
                .font(.caption)
                .buttonStyle(.bordered)
                .tint(.red)
            }
        }
        .padding(.vertical, 4)
    }

    private func recentEntryRow(_ entry: JobsService.LaborEntryRow) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.userName)
                    .fontWeight(.medium)
                Text(entry.jobName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text(String(format: "%.1f hrs", entry.regularHours + entry.overtimeHours))
                    .font(.system(.caption, design: .monospaced))
                Text(entry.clockOut != nil ? "Completed" : "Active")
                    .font(.caption2)
                    .foregroundColor(entry.clockOut != nil ? .secondary : .green)
            }
        }
    }

    // MARK: - Clock-In Sheet

    private var clockInSheet: some View {
        NavigationStack {
            Form {
                Section("Employee") {
                    Picker("Employee", selection: $selectedUserId) {
                        Text("Select employee...").tag(nil as Int64?)
                        ForEach(users, id: \.id) { user in
                            Text(user.name).tag(user.id as Int64?)
                        }
                    }
                }

                Section("Job") {
                    Picker("Job", selection: $selectedJobId) {
                        Text("Select job...").tag(nil as Int64?)
                        ForEach(jobOptions, id: \.id) { job in
                            Text("\(job.jobNumber) — \(job.jobName)").tag(job.id as Int64?)
                        }
                    }
                }

                Section("Notes") {
                    TextField("Optional notes...", text: $clockInNote)
                }
            }
            .navigationTitle("Clock In")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { showClockIn = false }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Clock In") { performClockIn() }
                        .disabled(selectedUserId == nil || selectedJobId == nil)
                }
            }
        }
    }

    // MARK: - Actions

    private func prepareClockIn() {
        guard let service = appCore.jobsService, let auth = appCore.authService else { return }
        do {
            let activeUsers = try auth.getActiveUsers()
            users = activeUsers.map { ($0.id!, $0.displayName) }
            jobOptions = try service.listJobs(status: "active")
            showClockIn = true
        } catch {
            errorMessage = "Failed to load options: \(error.localizedDescription)"
        }
    }

    private func performClockIn() {
        guard let service = appCore.jobsService,
              let userId = selectedUserId,
              let jobId = selectedJobId else { return }
        do {
            try service.clockIn(userId: userId, jobId: jobId)
            showClockIn = false
            clockInNote = ""
            selectedUserId = nil
            selectedJobId = nil
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
        isLoading = activeEntries.isEmpty && recentEntries.isEmpty
        do {
            let allEntries = try service.listLaborEntries(limit: 200)
            activeEntries = allEntries.filter { $0.clockOut == nil }
            recentEntries = Array(allEntries.prefix(50))
        } catch {
            print("[LaborPage] Load error: \(error)")
        }
        isLoading = false
    }
}
