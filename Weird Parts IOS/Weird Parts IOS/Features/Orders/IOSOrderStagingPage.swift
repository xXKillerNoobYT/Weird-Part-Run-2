import SwiftUI
import WiredPartCore

/// Job Stage Planner page for iOS.
///
/// Shows ALL parts across ALL JPOs for a selected job, grouped by construction
/// stage (Rough-in, Prep/Makeup, Trim-out). Parts for future stages are "held"
/// and auto-release when the current stage completes. Supports early release
/// and per-stage progress tracking.
struct IOSOrderStagingPage: View {
    @EnvironmentObject private var appCore: AppCore

    // MARK: - State

    @State private var stages: [OrdersService.JobStage] = []
    @State private var parts: [OrdersService.StagePart] = []
    @State private var jobs: [JobsService.JobListItem] = []
    @State private var selectedJobId: Int64?
    @State private var stageFilter: Int64? = nil  // nil = all stages
    @State private var isLoading = true
    @State private var loadError: String?
    @State private var actionError: String?
    @State private var searchText = ""
    @State private var activeSheet: ActiveSheet?

    private enum ActiveSheet: Identifiable {
        case help
        case stageSettings
        var id: String {
            switch self {
            case .help: "help"
            case .stageSettings: "stageSettings"
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            jobPicker
            if selectedJobId != nil {
                stageCardFilters
            }
            contentView
        }
        .navigationTitle("Job Stage Planner")
        .searchable(text: $searchText, prompt: "Search parts...")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { activeSheet = .stageSettings } label: {
                    Image(systemName: "gearshape")
                }
                .accessibilityLabel("Stage settings")
            }
            ToolbarItem(placement: .primaryAction) {
                Button { activeSheet = .help } label: {
                    Image(systemName: "questionmark.circle")
                }
                .accessibilityLabel("Help")
            }
        }
        .searchable(text: $searchText, prompt: "Search parts...")
        .refreshable { loadData() }
        .task { await loadInitialData() }
        .sheet(item: $activeSheet) { sheet in
            switch sheet {
            case .help:
                PageHelpSheet(
                    title: "Job Stage Planner Help",
                    sections: [
                        ("What This Page Does", "Shows all parts across all JPOs for a job, organized by construction stage (e.g., Rough-in, Prep/Makeup, Trim-out). Parts for future stages are held back and auto-release when the current stage completes."),
                        ("How to Use It", "Select a job from the picker at the top. Use the stage cards to filter by stage. Each part shows its JPO number, quantity, and current status. When a stage is done, tap 'Mark Stage Complete' to release the next stage's parts."),
                        ("Held Parts", "Parts with a lock icon are held for a future stage. They won't be ordered or pulled until their stage becomes active. If you need a held part early, tap 'Request Early' to override the hold."),
                        ("Stage Settings", "Tap the gear icon to configure stages and map part categories to specific stages. This controls which parts auto-assign to which construction phase."),
                        ("Tips", "Pull down to refresh. The stage cards show part counts so you can see at a glance how much work is in each phase. If your clocked-in job auto-selects, you can change it with the picker.")
                    ]
                )
            case .stageSettings:
                StageSettingsSheet(onSave: { loadData() })
                    .environmentObject(appCore)
            }
        }
        .alert("Error", isPresented: .constant(actionError != nil)) {
            Button("OK") { actionError = nil }
        } message: {
            Text(actionError ?? "")
        }
    }

    // MARK: - Job Picker

    private var jobPicker: some View {
        HStack {
            Picker("Job", selection: $selectedJobId) {
                Text("Select a job...").tag(nil as Int64?)
                ForEach(jobs, id: \.id) { job in
                    Text(job.jobName).tag(job.id as Int64?)
                }
            }
            .onChange(of: selectedJobId) { loadData() }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
    }

    // MARK: - Stage Card Filters

    private var stageCardFilters: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(stages) { stage in
                    let count = parts.filter { $0.stageId == stage.id }.count
                    stageCard(stage, count: count)
                }
                // "All" card
                let allCount = parts.count
                Button {
                    withAnimation { stageFilter = stageFilter == nil ? stageFilter : nil }
                } label: {
                    VStack(spacing: 4) {
                        Text("\(allCount)")
                            .font(.title3)
                            .fontWeight(.bold)
                        Text("All")
                            .font(.caption2)
                    }
                    .frame(minWidth: 70)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(stageFilter == nil ? Color.accentColor : Color.secondary.opacity(0.12))
                    )
                    .foregroundStyle(stageFilter == nil ? .white : .primary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
        }
    }

    private func stageCard(_ stage: OrdersService.JobStage, count: Int) -> some View {
        Button {
            withAnimation { stageFilter = stageFilter == stage.id ? nil : stage.id }
        } label: {
            VStack(spacing: 4) {
                Text("\(count)")
                    .font(.title3)
                    .fontWeight(.bold)
                Text(stage.name)
                    .font(.caption2)
                    .lineLimit(1)
            }
            .frame(minWidth: 70)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(stageFilter == stage.id ? stageColor(stage.sortOrder) : Color.secondary.opacity(0.12))
            )
            .foregroundStyle(stageFilter == stage.id ? .white : .primary)
        }
        .buttonStyle(.plain)
    }

    private func stageColor(_ sortOrder: Int) -> Color {
        switch sortOrder {
        case 1: return .blue
        case 2: return .orange
        case 3: return .green
        default: return Color.accentColor
        }
    }

    // MARK: - Content

    @ViewBuilder
    private var contentView: some View {
        if selectedJobId == nil {
            EmptyStateView(
                icon: "hammer",
                title: "Select a Job",
                message: "Choose a job to see its stage planner."
            )
        } else if isLoading {
            ProgressView("Loading stage data...")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let error = loadError {
            ErrorStateView(message: error) { loadData() }
        } else if parts.isEmpty {
            EmptyStateView(
                icon: "tray",
                title: "No Parts",
                message: "No JPO parts found for this job."
            )
        } else {
            stageList
        }
    }

    private var filteredParts: [OrdersService.StagePart] {
        var result = parts

        // Apply stage filter
        if let filter = stageFilter {
            result = result.filter { $0.stageId == filter }
        }

        // Apply search filter
        if !searchText.isEmpty {
            result = result.filter {
                $0.partName.localizedCaseInsensitiveContains(searchText) ||
                ($0.partCode?.localizedCaseInsensitiveContains(searchText) ?? false) ||
                $0.jpoNumber.localizedCaseInsensitiveContains(searchText)
            }
        }

        return result
    }

    private var stageList: some View {
        List {
            // Group by stage
            let grouped = Dictionary(grouping: filteredParts, by: { $0.stageId ?? 0 })
            let sortedKeys = grouped.keys.sorted { k1, k2 in
                let order1 = stages.first(where: { $0.id == k1 })?.sortOrder ?? 999
                let order2 = stages.first(where: { $0.id == k2 })?.sortOrder ?? 999
                return order1 < order2
            }

            ForEach(sortedKeys, id: \.self) { stageId in
                let stageParts = grouped[stageId] ?? []
                let stageName = stages.first(where: { $0.id == stageId })?.name ?? "Unassigned"
                let hasHeldParts = stageParts.contains(where: \.isHeld)

                Section {
                    ForEach(stageParts) { part in
                        stagePartRow(part)
                    }

                    // Stage complete button (if this is the current stage)
                    if let jobId = selectedJobId, !hasHeldParts, stageId > 0 {
                        Button {
                            markStageComplete(jobId: jobId, stageId: stageId)
                        } label: {
                            Label("Mark \(stageName) Complete", systemImage: "checkmark.circle")
                                .font(.subheadline)
                                .fontWeight(.medium)
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.green)
                    }
                } header: {
                    HStack {
                        Text(stageName)
                        Spacer()
                        Text("\(stageParts.count) parts")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        if hasHeldParts {
                            Image(systemName: "lock.fill")
                                .font(.caption2)
                                .foregroundStyle(.orange)
                                .accessibilityLabel("Has held parts")
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
    }

    private func stagePartRow(_ part: OrdersService.StagePart) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(part.partName)
                        .font(.subheadline)
                        .fontWeight(.medium)
                    if let code = part.partCode {
                        Text(code)
                            .font(.caption2)
                            .monospaced()
                            .foregroundStyle(.secondary)
                    }
                    Text(part.jpoNumber)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text("x\(part.quantity)")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .monospaced()
                    lineStatusBadge(part.lineStatus)
                }
            }

            // Held indicator + request early button
            if part.isHeld {
                HStack(spacing: 8) {
                    HStack(spacing: 4) {
                        Image(systemName: "lock.fill")
                            .font(.caption2)
                            .accessibilityHidden(true)
                        Text("HELD — releases after \(part.stageName ?? "stage") complete")
                            .font(.caption)
                    }
                    .foregroundStyle(.orange)

                    Spacer()

                    Button {
                        requestEarly(jpoLineId: part.id)
                    } label: {
                        Text("Request Early")
                            .font(.caption2)
                            .fontWeight(.medium)
                    }
                    .buttonStyle(.bordered)
                    .tint(.orange)
                }
            }
        }
        .padding(.vertical, 2)
    }

    private func lineStatusBadge(_ status: String) -> some View {
        let color: Color = switch status {
        case "pending": .secondary
        case "approved": .blue
        case "in_procurement": .purple
        case "ordered": .orange
        case "received": .green
        case "held": .orange
        case "on_hold": .yellow
        case "rejected": .red
        default: .secondary
        }
        return Text(status.replacingOccurrences(of: "_", with: " ").capitalized)
            .font(.system(.caption2, weight: .semibold))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Capsule().fill(color.opacity(0.15)))
            .foregroundStyle(color)
    }

    // MARK: - Actions

    private func markStageComplete(jobId: Int64, stageId: Int64) {
        guard let service = appCore.ordersService else {
            actionError = "Orders service not available"
            return
        }
        do {
            try service.markStageComplete(jobId: jobId, stageId: stageId)
            loadData()
        } catch {
            actionError = userFriendlyError(error, context: "update staging")
        }
    }

    private func requestEarly(jpoLineId: Int64) {
        guard let service = appCore.ordersService else {
            actionError = "Orders service not available"
            return
        }
        do {
            try service.requestEarlyRelease(jpoLineId: jpoLineId)
            loadData()
        } catch {
            actionError = userFriendlyError(error, context: "update staging")
        }
    }

    // MARK: - Data Loading

    private func loadInitialData() async {
        guard let jobsService = appCore.jobsService else {
            loadError = "Jobs service not available"
            isLoading = false
            return
        }
        do {
            jobs = try jobsService.listJobs(status: "active", limit: 100)
        } catch {
            loadError = userFriendlyError(error, context: "load order staging")
        }

        // Auto-select if user is clocked into a job
        if let userId = appCore.currentUser?.id {
            if let activeEntry = try? appCore.jobsService?.getActiveClockEntry(userId: userId) {
                selectedJobId = activeEntry.jobId
            }
        }

        loadData()
    }

    private func loadData() {
        guard let service = appCore.ordersService else {
            loadError = "Orders service not available"
            isLoading = false
            return
        }
        guard let jobId = selectedJobId else {
            isLoading = false
            return
        }

        isLoading = parts.isEmpty
        loadError = nil

        do {
            stages = try service.getJobStages()
            parts = try service.getJobStageParts(jobId: jobId)
        } catch {
            loadError = userFriendlyError(error, context: "load order staging")
        }
        isLoading = false
    }
}

// MARK: - Stage Settings Sheet

private struct StageSettingsSheet: View {
    @EnvironmentObject private var appCore: AppCore
    @Environment(\.dismiss) private var dismiss
    let onSave: () -> Void

    @State private var stages: [OrdersService.JobStage] = []
    @State private var mappings: [(categoryId: Int64, categoryName: String, stageId: Int64?, stageName: String?)] = []
    @State private var isLoading = true
    @State private var saveError: String?

    var body: some View {
        NavigationStack {
            Form {
                // Stages list
                Section("Stages") {
                    if isLoading {
                        ProgressView()
                    } else {
                        ForEach(stages) { stage in
                            HStack {
                                Text(stage.name)
                                Spacer()
                                Text("Order: \(stage.sortOrder)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }

                // Category → Stage mappings
                Section("Category → Stage Mapping") {
                    if isLoading {
                        ProgressView()
                    } else {
                        ForEach(mappings.indices, id: \.self) { idx in
                            HStack {
                                Text(mappings[idx].categoryName)
                                    .font(.subheadline)
                                Spacer()
                                Picker("Stage", selection: Binding(
                                    get: { mappings[idx].stageId ?? 0 },
                                    set: { newValue in
                                        let stageId: Int64? = newValue == 0 ? nil : newValue
                                        mappings[idx].stageId = stageId
                                        mappings[idx].stageName = stages.first(where: { $0.id == newValue })?.name
                                        saveMapping(categoryId: mappings[idx].categoryId, stageId: stageId)
                                    }
                                )) {
                                    Text("None").tag(Int64(0))
                                    ForEach(stages) { stage in
                                        Text(stage.name).tag(stage.id)
                                    }
                                }
                                .pickerStyle(.menu)
                            }
                        }
                    }
                }

                if let error = saveError {
                    Section {
                        Text(error)
                            .foregroundStyle(.red)
                            .font(.caption)
                    }
                }
            }
            .navigationTitle("Stage Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        onSave()
                        dismiss()
                    }
                }
            }
            .task { loadSettings() }
        }
    }

    private func loadSettings() {
        guard let service = appCore.ordersService else {
            saveError = "Service not available"
            isLoading = false
            return
        }
        do {
            stages = try service.getJobStages()
            mappings = try service.getCategoryStageMappings()
        } catch {
            saveError = userFriendlyError(error, context: "save staging")
        }
        isLoading = false
    }

    private func saveMapping(categoryId: Int64, stageId: Int64?) {
        guard let service = appCore.ordersService else {
            saveError = "Service not available"
            return
        }
        do {
            try service.updateCategoryStageMapping(categoryId: categoryId, stageId: stageId)
        } catch {
            saveError = userFriendlyError(error, context: "save staging")
        }
    }
}
