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
    @State private var errorMessage: String?
    @State private var searchText = ""

    private enum ActiveSheet: Identifiable {
        case help
        case clockIn
        var id: String {
            switch self {
            case .help: return "help"
            case .clockIn: return "clockIn"
            }
        }
    }
    @State private var activeSheet: ActiveSheet?

    private var filteredActiveEntries: [JobsService.LaborEntryRow] {
        guard !searchText.isEmpty else { return activeEntries }
        let query = searchText.lowercased()
        return activeEntries.filter {
            $0.userName.lowercased().contains(query) ||
            $0.jobName.lowercased().contains(query)
        }
    }

    private var filteredRecentEntries: [JobsService.LaborEntryRow] {
        guard !searchText.isEmpty else { return recentEntries }
        let query = searchText.lowercased()
        return recentEntries.filter {
            $0.userName.lowercased().contains(query) ||
            $0.jobName.lowercased().contains(query)
        }
    }

    @State private var dateRange: ReportDateRange = .thisWeek
    @State private var customStart: Date = Calendar.current.date(byAdding: .day, value: -7, to: Date())!
    @State private var customEnd: Date = Date()

    // Clock-in form state
    @State private var selectedUserId: Int64?
    @State private var selectedJobId: Int64?
    @State private var clockInNote = ""
    @State private var users: [(id: Int64, name: String)] = []
    @State private var jobOptions: [JobsService.JobListItem] = []

    private var effectiveStart: Date { dateRange.dateInterval?.start ?? customStart }
    private var effectiveEnd: Date { dateRange.dateInterval?.end ?? customEnd }

    var body: some View {
        VStack(spacing: 0) {
            StandardFilterBar(selectedRange: $dateRange, customStart: $customStart, customEnd: $customEnd)
            laborContent
        }
            .navigationTitle("Labor")
            .searchable(text: $searchText, prompt: "Search by employee or job...")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        prepareClockIn()
                    } label: {
                        Label("Clock In", systemImage: "play.circle.fill")
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
                case .help:
                    PageHelpSheet(
                        title: "Labor Help",
                        sections: [
                            ("Overview", "Track all labor entries across jobs. Active clock-ins appear at the top with clock-out buttons. Recent history is shown below."),
                            ("Clock In", "Tap the play button in the toolbar to start a new clock-in for any employee and job."),
                            ("Search", "Use the search bar to filter entries by employee name or job name. Pull down to refresh.")
                        ]
                    )
                case .clockIn:
                    clockInSheet
                }
            }
            .onChange(of: activeSheet) { _, newValue in
                if newValue == nil { loadData() }
            }
            .refreshable { loadData() }
            .task { loadData() }
            .onChange(of: dateRange) { loadData() }
            .onChange(of: customStart) { loadData() }
            .onChange(of: customEnd) { loadData() }
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
                Section("Active (\(filteredActiveEntries.count))") {
                    if filteredActiveEntries.isEmpty {
                        Text("Nobody is currently clocked in")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(filteredActiveEntries, id: \.id) { entry in
                            activeEntryRow(entry)
                        }
                    }
                }

                // Recent entries section
                Section("Recent") {
                    if filteredRecentEntries.isEmpty {
                        Text("No recent labor entries")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(filteredRecentEntries, id: \.id) { entry in
                            recentEntryRow(entry)
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
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
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { activeSheet = nil }
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
        guard let service = appCore.jobsService, let auth = appCore.authService else {
            errorMessage = "Service not available"
            return
        }
        do {
            let activeUsers = try auth.getActiveUsers()
            users = activeUsers.compactMap { user in
                guard let id = user.id else { return nil }
                return (id, user.displayName)
            }
            jobOptions = try service.listJobs(status: "active")
            activeSheet = .clockIn
        } catch {
            errorMessage = "Failed to load options: \(error.localizedDescription)"
        }
    }

    private func performClockIn() {
        guard let service = appCore.jobsService,
              let userId = selectedUserId,
              let jobId = selectedJobId else {
            errorMessage = "Jobs service not available"
            return
        }
        do {
            try service.clockIn(userId: userId, jobId: jobId)
            activeSheet = nil
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
        guard let service = appCore.jobsService else {
            errorMessage = "Service not available"
            return
        }
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
        guard let service = appCore.jobsService else {
            errorMessage = "Service not available"
            isLoading = false
            return
        }
        isLoading = activeEntries.isEmpty && recentEntries.isEmpty
        errorMessage = nil
        do {
            let allEntries = try service.listLaborEntries(limit: 200)
            activeEntries = allEntries.filter { $0.clockOut == nil }
            recentEntries = Array(allEntries.prefix(50))
        } catch {
            errorMessage = "Failed to load labor data: \(error.localizedDescription)"
        }
        isLoading = false
    }
}
