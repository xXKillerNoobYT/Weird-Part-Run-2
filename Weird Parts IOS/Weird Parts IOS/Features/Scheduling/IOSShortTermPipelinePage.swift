import SwiftUI
import WiredPartCore
import os

private let pipelineLog = Logger(subsystem: "com.wiredpart", category: "scheduling.pipeline")

struct IOSShortTermPipelineCallbackActionResult: Equatable {
    let errorMessage: String?
    let shouldDismissSheet: Bool
}

enum IOSShortTermPipelineCallbackActionHandler {
    static func perform(
        context: String,
        operation: () throws -> Void,
        reload: () -> Void,
        errorFormatter: (Error, String) -> String
    ) -> IOSShortTermPipelineCallbackActionResult {
        do {
            try operation()
            reload()
            return IOSShortTermPipelineCallbackActionResult(errorMessage: nil, shouldDismissSheet: true)
        } catch {
            return IOSShortTermPipelineCallbackActionResult(
                errorMessage: errorFormatter(error, context),
                shouldDismissSheet: false
            )
        }
    }
}

/// Short-term pipeline page showing jobs ready or near-ready for scheduling.
///
/// Categories: Start Anytime, Schedule Needed, Favorite GC, and Small Jobs.
/// Pipeline targets come from saved dispatch preferences. Includes callback
/// tracking with snooze and AI crew suggestion button.
struct IOSShortTermPipelinePage: View {
    @EnvironmentObject private var appCore: AppCore

    @State private var pipelineItems: [SchedulingService.PipelineItem] = []
    @State private var isLoading = true
    @State private var loadError: String?
    @State private var searchText = ""
    @State private var pipelineTargets = SchedulingService.PipelineTargets(
        startAnytime: 3,
        scheduleNeeded: 2,
        favoriteGC: 1
    )

    private enum ActiveSheet: String, Identifiable {
        case callback
        case schedule
        case help
        case aiSuggestions
        var id: String { rawValue }
    }
    @State private var activeSheet: ActiveSheet?
    @State private var selectedItem: SchedulingService.PipelineItem?
    @State private var targetedDropCategory: String?

    // AI Dispatch
    @State private var aiSuggestions: [AIDispatchService.DispatchSuggestion] = []
    @State private var isLoadingAI = false

    // Search-filtered base
    private var searchFilteredItems: [SchedulingService.PipelineItem] {
        if searchText.isEmpty { return pipelineItems }
        return pipelineItems.filter {
            $0.jobName.localizedCaseInsensitiveContains(searchText) ||
            $0.customerName.localizedCaseInsensitiveContains(searchText)
        }
    }

    // Filtered lists
    private var startAnytimeItems: [SchedulingService.PipelineItem] {
        searchFilteredItems.filter { $0.pipelineCategory == "start_anytime" }
    }
    private var scheduleNeededItems: [SchedulingService.PipelineItem] {
        searchFilteredItems.filter { $0.pipelineCategory == "schedule_needed" }
    }
    private var favoriteGCItems: [SchedulingService.PipelineItem] {
        searchFilteredItems.filter { $0.pipelineCategory == "favorite_gc" }
    }
    private var smallJobItems: [SchedulingService.PipelineItem] {
        searchFilteredItems.filter { $0.pipelineCategory == "small_job" }
    }
    private var callbacksDue: [SchedulingService.PipelineItem] {
        pipelineItems.filter { item in
            guard let cb = item.callbackDate, !cb.isEmpty else { return false }
            // Show if callback date <= today and not snoozed past today
            if let snoozed = item.callbackSnoozedUntil, !snoozed.isEmpty {
                return snoozed <= todayString
            }
            return cb <= todayString
        }
    }

    private var todayString: String {
        Formatters.localDateFormatter.string(from: Date())
    }

    var body: some View {
        Group {
            if isLoading {
                ProgressView("Loading pipeline...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error = loadError {
                ErrorStateView(message: error) { loadData() }
            } else {
                pipelineContent
            }
        }
        .navigationTitle("Short-Term Pipeline")
        .searchable(text: $searchText, prompt: "Search jobs...")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    loadAISuggestions()
                } label: {
                    if isLoadingAI {
                        ProgressView()
                    } else {
                        Label("AI Suggest", systemImage: "sparkles")
                    }
                }
                .disabled(isLoadingAI)
            }
            ToolbarItem(placement: .primaryAction) {
                Button { activeSheet = .help } label: {
                    Image(systemName: "questionmark.circle")
                }
                .accessibilityLabel("Help")
            }
        }
        .sheet(item: $activeSheet) { sheet in
            switch sheet {
            case .callback:
                if let item = selectedItem {
                    CallbackSheet(item: item, onComplete: { notes in
                        completeCallback(jobId: item.jobId, notes: notes)
                    }, onSnooze: { days in
                        snoozeCallback(jobId: item.jobId, days: days)
                    })
                }
            case .schedule:
                if let item = selectedItem {
                    CreateScheduleEntrySheet(
                        date: todayString,
                        initialJobId: item.jobId,
                        initialJobName: item.jobName,
                        onSave: { loadData() }
                    )
                    .environmentObject(appCore)
                }
            case .help:
                PageHelpSheet(title: "Short-Term Pipeline Help", sections: [
                    ("What This Page Does", "The Short-Term Pipeline shows jobs that are ready or nearly ready to be scheduled. Jobs are grouped into categories: Start Anytime, Schedule Needed, Favorite GC, and Small Jobs. Each category has a target count to keep your pipeline healthy."),
                    ("How to Use It", "Review the target cards at the top to see if your pipeline is balanced. Green checkmarks mean you are at or above target; red means you need more jobs in that category. Tap the calendar icon on any job to open a scheduling sheet already tied to that job. Tap the phone icon on callbacks to handle them."),
                    ("Callbacks", "When a callback is due, it appears in the Callbacks Due section. You can mark it complete with notes, or snooze it for 1 day, 3 days, or 1 week."),
                    ("Tips", "Keep each category at or above its target number for a healthy pipeline. 'Start Anytime' jobs are your safety net for crew that finishes early. Small Jobs are great gap fillers between bigger projects.")
                ])
            case .aiSuggestions:
                NavigationStack {
                    aiSuggestionsSheet
                        .navigationTitle("AI Dispatch Suggestions")
                        .navigationBarTitleDisplayMode(.inline)
                        .toolbar {
                            ToolbarItem(placement: .cancellationAction) {
                                Button("Done") { activeSheet = nil }
                            }
                        }
                }
            }
        }
        .refreshable { loadData() }
        .task { loadData() }
    }

    // MARK: - Content

    private var pipelineContent: some View {
        List {
            // Smart cards with targets
            Section {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        TargetCard(title: "Start Anytime", count: startAnytimeItems.count, target: pipelineTargets.startAnytime, color: .green)
                        TargetCard(title: "Need Schedule", count: scheduleNeededItems.count, target: pipelineTargets.scheduleNeeded, color: .blue)
                        TargetCard(title: "Favorite GC", count: favoriteGCItems.count, target: pipelineTargets.favoriteGC, color: .purple)
                        SmartCard(title: "Small Jobs", count: smallJobItems.count, color: .orange)
                    }
                    .padding(.horizontal, 4)
                }
                .listRowInsets(EdgeInsets(top: 8, leading: 0, bottom: 8, trailing: 0))
                .listRowBackground(Color.clear)
            }

            // Start Anytime
            pipelineSection(
                title: "Start Anytime", target: pipelineTargets.startAnytime,
                category: "start_anytime", items: startAnytimeItems,
                icon: "bolt.fill", color: .green
            )

            // Schedule Needed
            pipelineSection(
                title: "Schedule Needed", target: pipelineTargets.scheduleNeeded,
                category: "schedule_needed", items: scheduleNeededItems,
                icon: "calendar.badge.exclamationmark", color: .blue
            )

            // Favorite GC
            pipelineSection(
                title: "Favorite GC", target: pipelineTargets.favoriteGC,
                category: "favorite_gc", items: favoriteGCItems,
                icon: "star.fill", color: .purple
            )

            // Small Jobs
            pipelineSection(
                title: "Small Jobs", target: nil,
                category: "small_job", items: smallJobItems,
                icon: "rectangle.compress.vertical", color: .orange
            )

            // Callbacks Due
            if !callbacksDue.isEmpty {
                Section {
                    ForEach(callbacksDue, id: \.id) { item in
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(item.jobName)
                                    .fontWeight(.medium)
                                Text(item.customerName)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                if let cb = item.callbackDate {
                                    Text("Callback: \(cb)")
                                        .font(.caption)
                                        .foregroundStyle(.orange)
                                }
                            }
                            Spacer()
                            Button {
                                selectedItem = item
                                activeSheet = .callback
                            } label: {
                                Image(systemName: "phone.fill")
                            }
                            .buttonStyle(.bordered)
                            .tint(.orange)
                            .accessibilityLabel("Handle callback")
                        }
                    }
                } header: {
                    Label("Callbacks Due (\(callbacksDue.count))", systemImage: "phone.badge.waveform")
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollDismissesKeyboard(.interactively)
    }

    // MARK: - Pipeline Section

    private func pipelineSection(
        title: String, target: Int?,
        category: String,
        items: [SchedulingService.PipelineItem], icon: String, color: Color
    ) -> some View {
        Section {
            if items.isEmpty {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                        .font(.caption)
                        .accessibilityHidden(true)
                    Text("Below target — need more jobs here")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }
            ForEach(items, id: \.id) { item in
                pipelineRow(item)
                    .draggable(String(item.jobId)) {
                        Label(item.jobName, systemImage: "line.3.horizontal")
                            .padding(8)
                    }
            }
        } header: {
            HStack {
                Image(systemName: icon)
                    .foregroundStyle(color)
                    .accessibilityHidden(true)
                Text(title)
                Spacer()
                if let target {
                    Text("\(items.count)/\(target) target")
                        .font(.caption)
                        .foregroundStyle(items.count >= target ? .green : .red)
                }
            }
            .padding(.vertical, targetedDropCategory == category ? 6 : 0)
            .padding(.horizontal, targetedDropCategory == category ? 8 : 0)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(targetedDropCategory == category ? color.opacity(0.18) : Color.clear)
            )
        }
        .dropDestination(for: String.self) { droppedIds, _ in
            guard let rawId = droppedIds.first,
                  let jobId = Int64(rawId) else { return false }
            movePipelineItem(jobId: jobId, to: category)
            return true
        } isTargeted: { isTargeted in
            targetedDropCategory = isTargeted ? category : nil
        }
    }

    private func pipelineRow(_ item: SchedulingService.PipelineItem) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(item.jobName)
                    .fontWeight(.medium)
                Text(item.customerName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let days = item.estimatedDays {
                    Text("Est. \(days) day\(days == 1 ? "" : "s")")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
            Spacer()
            Button {
                selectedItem = item
                activeSheet = .schedule
            } label: {
                Image(systemName: "calendar.badge.plus")
            }
            .buttonStyle(.bordered)
            .tint(.blue)
            .accessibilityLabel("Schedule job")
        }
    }

    // MARK: - Actions

    private func completeCallback(jobId: Int64, notes: String?) {
        guard let service = appCore.schedulingService else {
            loadError = "Service not available"
            return
        }
        do {
            try service.markCallbackComplete(jobId: jobId, notes: notes)
            try refreshPipelineData()
            activeSheet = nil
        } catch {
            loadError = userFriendlyError(error, context: "complete callback")
        }
    }

    private func snoozeCallback(jobId: Int64, days: Int) {
        guard let service = appCore.schedulingService else {
            loadError = "Service not available"
            return
        }
        let target = Calendar.current.date(byAdding: .day, value: days, to: Date()) ?? Date()
        do {
            try service.snoozeCallback(jobId: jobId, until: Formatters.localDateFormatter.string(from: target))
            try refreshPipelineData()
            activeSheet = nil
        } catch {
            loadError = userFriendlyError(error, context: "snooze callback")
        }
    }

    private func movePipelineItem(jobId: Int64, to category: String) {
        guard let service = appCore.schedulingService else {
            loadError = "Scheduling service not available"
            return
        }
        guard let item = pipelineItems.first(where: { $0.jobId == jobId }) else { return }
        guard item.pipelineCategory != category else { return }

        do {
            try service.updateShortTermPipelineCategory(jobId: jobId, category: category)
            pipelineItems = pipelineItems.map { current in
                guard current.jobId == jobId else { return current }
                return SchedulingService.PipelineItem(
                    id: current.id,
                    jobId: current.jobId,
                    jobName: current.jobName,
                    customerName: current.customerName,
                    estimatedDays: current.estimatedDays,
                    pipelineCategory: category,
                    callbackDate: current.callbackDate,
                    callbackSnoozedUntil: current.callbackSnoozedUntil,
                    notes: current.notes
                )
            }
        } catch {
            loadError = userFriendlyError(error, context: "move pipeline job")
            loadData()
        }
    }

    // MARK: - Data Loading

    private func loadData() {
        guard let service = appCore.schedulingService else {
            isLoading = false
            loadError = "Scheduling service not available."
            return
        }
        isLoading = pipelineItems.isEmpty
        loadError = nil
        do {
            pipelineTargets = try service.getShortTermPipelineTargets()
            pipelineItems = try service.getShortTermPipeline()
        } catch {
            loadError = userFriendlyError(error, context: "load pipeline data")
        }
        isLoading = false
    }

    private func refreshPipelineData() throws {
        guard let service = appCore.schedulingService else {
            throw NSError(
                domain: "IOSShortTermPipelinePage",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Scheduling service not available."]
            )
        }
        pipelineTargets = try service.getShortTermPipelineTargets()
        pipelineItems = try service.getShortTermPipeline()
        loadError = nil
    }

    // MARK: - AI Dispatch

    private func loadAISuggestions() {
        guard let service = appCore.aiDispatchService else {
            aiSuggestions = []
            activeSheet = .aiSuggestions
            return
        }
        isLoadingAI = true
        do {
            aiSuggestions = try service.generateSuggestions(date: todayString)
        } catch {
            aiSuggestions = []
            loadError = userFriendlyError(error, context: "generate AI suggestions")
        }
        isLoadingAI = false
        activeSheet = .aiSuggestions
    }

    private func applyAISuggestion(_ suggestion: AIDispatchService.DispatchSuggestion) {
        guard let aiService = appCore.aiDispatchService else {
            loadError = "AI dispatch service not available"
            return
        }
        guard let schedService = appCore.schedulingService else {
            loadError = "Scheduling service not available"
            return
        }

        do {
            // Record the dispatcher's choice for AI learning
            try aiService.recordDispatcherChoice(
                date: todayString,
                chosenRank: suggestion.rank,
                wasModified: false
            )

            // Apply each assignment as a dispatch entry
            for assignment in suggestion.assignments {
                _ = try schedService.createDispatch(
                    jobId: assignment.jobId,
                    userId: assignment.employeeId,
                    date: todayString,
                    notes: "AI dispatch (option \(suggestion.rank), score \(assignment.matchScore))"
                )
            }

            activeSheet = nil
            loadData()
        } catch {
            loadError = userFriendlyError(error, context: "apply AI suggestion")
        }
    }

    private func dismissAISuggestions() {
        // Record that the dispatcher dismissed all suggestions (rank 0 = none chosen).
        // Fix #179: this is analytics — we don't want to alert the user on failure,
        // but we DO want the failure visible in unified logging instead of silently
        // dropped. os.Logger preserves the non-blocking behavior while surfacing the
        // error for ops/debug.
        if let aiService = appCore.aiDispatchService {
            do {
                try aiService.recordDispatcherChoice(
                    date: todayString,
                    chosenRank: 0,
                    wasModified: false
                )
            } catch {
                pipelineLog.error("recordDispatcherChoice (dismiss) failed: \(error.localizedDescription, privacy: .public)")
            }
        }
        activeSheet = nil
    }

    @ViewBuilder
    private var aiSuggestionsSheet: some View {
        NavigationStack {
            if aiSuggestions.isEmpty {
                VStack(spacing: 16) {
                    Image(systemName: "sparkles")
                        .font(.largeTitle)
                        .foregroundStyle(.secondary)
                        .accessibilityHidden(true)
                    Text("No Suggestions Available")
                        .font(.headline)
                    Text("AI dispatch needs available workers and jobs needing crew to generate suggestions.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(aiSuggestions) { suggestion in
                        Section("Option \(suggestion.rank)  —  \(suggestion.totalPoints) pts") {
                            ForEach(suggestion.assignments) { assignment in
                                HStack(spacing: 12) {
                                    Image(systemName: "person.fill")
                                        .foregroundStyle(.blue)
                                        .frame(width: 20)
                                        .accessibilityHidden(true)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(assignment.employeeName)
                                            .font(.subheadline)
                                            .fontWeight(.medium)
                                        Text(assignment.jobName)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Text(assignment.timeSlot)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    Text("\(assignment.matchScore)")
                                        .font(.caption)
                                        .fontWeight(.bold)
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 2)
                                        .background(Color.green.opacity(0.15))
                                        .foregroundStyle(.green)
                                        .clipShape(Capsule())
                                }
                            }
                            if !suggestion.reasoning.isEmpty {
                                DisclosureGroup("Reasoning") {
                                    ForEach(suggestion.reasoning) { factor in
                                        HStack {
                                            Text(factor.description)
                                                .font(.caption)
                                            Spacer()
                                            Text("\(factor.points > 0 ? "+" : "")\(factor.points)")
                                                .font(.caption)
                                                .fontWeight(.bold)
                                                .foregroundStyle(factor.isPositive ? .green : .red)
                                        }
                                    }
                                }
                                .font(.caption)
                            }
                            // Apply button for this suggestion
                            HStack(spacing: 12) {
                                Button {
                                    applyAISuggestion(suggestion)
                                } label: {
                                    Label("Apply This Plan", systemImage: "checkmark.circle.fill")
                                        .frame(maxWidth: .infinity)
                                }
                                .buttonStyle(.borderedProminent)
                                .tint(.green)
                            }
                            .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                        }
                    }
                    // Dismiss all suggestions
                    Section {
                        Button(role: .destructive) {
                            dismissAISuggestions()
                        } label: {
                            Label("Dismiss All Suggestions", systemImage: "xmark.circle")
                                .frame(maxWidth: .infinity)
                        }
                    }
                }
                .listStyle(.insetGrouped)
                .scrollDismissesKeyboard(.interactively)
            }
        }
        .navigationTitle("AI Suggestions")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Close") { activeSheet = nil }
            }
        }
    }
}

// MARK: - Target Card

private struct TargetCard: View {
    let title: String
    let count: Int
    let target: Int
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text("\(count)")
                    .font(.title2)
                    .fontWeight(.bold)
                Text("/\(target)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if count >= target {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .font(.caption)
                    .accessibilityLabel("Status: Target met")
            } else {
                Image(systemName: "exclamationmark.circle.fill")
                    .foregroundStyle(.red)
                    .font(.caption)
                    .accessibilityLabel("Status: Below target")
            }
        }
        .padding(10)
        .frame(minWidth: 100)
        .background(color.opacity(count >= target ? 0.1 : 0.2))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}

// MARK: - Smart Card (no target)

private struct SmartCard: View {
    let title: String
    let count: Int
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text("\(count)")
                .font(.title2)
                .fontWeight(.bold)
            Image(systemName: "wrench.fill")
                .foregroundStyle(color)
                .font(.caption)
                .accessibilityHidden(true)
        }
        .padding(10)
        .frame(minWidth: 100)
        .background(color.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}

// MARK: - Callback Sheet

private struct CallbackSheet: View {
    let item: SchedulingService.PipelineItem
    var onComplete: (String?) -> Void
    var onSnooze: (Int) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var notes = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("Callback for \(item.jobName)") {
                    Text(item.customerName)
                        .foregroundStyle(.secondary)
                    if let date = item.callbackDate {
                        LabeledContent("Scheduled", value: date)
                    }
                }

                Section("Notes") {
                    TextEditor(text: $notes)
                        .frame(minHeight: 80)
                }

                Section {
                    Button("Mark Complete") {
                        onComplete(notes.isEmpty ? nil : notes)
                    }
                    .fontWeight(.semibold)

                    Button("Snooze 1 Day") {
                        onSnooze(1)
                    }

                    Button("Snooze 3 Days") {
                        onSnooze(3)
                    }

                    Button("Snooze 1 Week") {
                        onSnooze(7)
                    }
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle("Callback")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}
