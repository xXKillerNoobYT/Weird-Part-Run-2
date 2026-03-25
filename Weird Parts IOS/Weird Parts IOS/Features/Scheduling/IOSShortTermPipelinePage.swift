import SwiftUI
import WiredPartCore

/// Short-term pipeline page showing jobs ready or near-ready for scheduling.
///
/// Categories: Start Anytime (target: 3), Schedule Needed (target: 2),
/// Favorite GC (target: 1), Small Jobs (gap fillers). Includes callback
/// tracking with snooze and AI crew suggestion button.
struct IOSShortTermPipelinePage: View {
    @EnvironmentObject private var appCore: AppCore

    @State private var pipelineItems: [SchedulingService.PipelineItem] = []
    @State private var isLoading = true
    @State private var loadError: String?

    private enum ActiveSheet: String, Identifiable {
        case callback
        case schedule
        var id: String { rawValue }
    }
    @State private var activeSheet: ActiveSheet?
    @State private var selectedItem: SchedulingService.PipelineItem?

    // Filtered lists
    private var startAnytimeItems: [SchedulingService.PipelineItem] {
        pipelineItems.filter { $0.pipelineCategory == "start_anytime" }
    }
    private var scheduleNeededItems: [SchedulingService.PipelineItem] {
        pipelineItems.filter { $0.pipelineCategory == "schedule_needed" }
    }
    private var favoriteGCItems: [SchedulingService.PipelineItem] {
        pipelineItems.filter { $0.pipelineCategory == "favorite_gc" }
    }
    private var smallJobItems: [SchedulingService.PipelineItem] {
        pipelineItems.filter { $0.pipelineCategory == "small_job" }
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
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: Date())
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
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    // AI suggestion placeholder
                } label: {
                    Label("AI Suggest", systemImage: "sparkles")
                }
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
                if selectedItem != nil {
                    CreateScheduleEntrySheet(
                        date: todayString,
                        onSave: { loadData() }
                    )
                    .environmentObject(appCore)
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
                        TargetCard(title: "Start Anytime", count: startAnytimeItems.count, target: 3, color: .green)
                        TargetCard(title: "Need Schedule", count: scheduleNeededItems.count, target: 2, color: .blue)
                        TargetCard(title: "Favorite GC", count: favoriteGCItems.count, target: 1, color: .purple)
                        SmartCard(title: "Small Jobs", count: smallJobItems.count, color: .orange)
                    }
                    .padding(.horizontal, 4)
                }
                .listRowInsets(EdgeInsets(top: 8, leading: 0, bottom: 8, trailing: 0))
                .listRowBackground(Color.clear)
            }

            // Start Anytime
            pipelineSection(
                title: "Start Anytime", target: 3,
                items: startAnytimeItems, icon: "bolt.fill", color: .green
            )

            // Schedule Needed
            pipelineSection(
                title: "Schedule Needed", target: 2,
                items: scheduleNeededItems, icon: "calendar.badge.exclamationmark", color: .blue
            )

            // Favorite GC
            pipelineSection(
                title: "Favorite GC", target: 1,
                items: favoriteGCItems, icon: "star.fill", color: .purple
            )

            // Small Jobs
            pipelineSection(
                title: "Small Jobs", target: nil,
                items: smallJobItems, icon: "rectangle.compress.vertical", color: .orange
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
                        }
                    }
                } header: {
                    Label("Callbacks Due (\(callbacksDue.count))", systemImage: "phone.badge.waveform")
                }
            }
        }
        .listStyle(.insetGrouped)
    }

    // MARK: - Pipeline Section

    private func pipelineSection(
        title: String, target: Int?,
        items: [SchedulingService.PipelineItem], icon: String, color: Color
    ) -> some View {
        Section {
            if items.isEmpty {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                        .font(.caption)
                    Text("Below target — need more jobs here")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }
            ForEach(items, id: \.id) { item in
                pipelineRow(item)
            }
        } header: {
            HStack {
                Image(systemName: icon)
                    .foregroundStyle(color)
                Text(title)
                Spacer()
                if let target {
                    Text("\(items.count)/\(target) target")
                        .font(.caption)
                        .foregroundStyle(items.count >= target ? .green : .red)
                }
            }
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
            loadData()
        } catch {
            loadError = error.localizedDescription
        }
        activeSheet = nil
    }

    private func snoozeCallback(jobId: Int64, days: Int) {
        guard let service = appCore.schedulingService else {
            loadError = "Service not available"
            return
        }
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        let target = Calendar.current.date(byAdding: .day, value: days, to: Date()) ?? Date()
        do {
            try service.snoozeCallback(jobId: jobId, until: f.string(from: target))
            loadData()
        } catch {
            loadError = error.localizedDescription
        }
        activeSheet = nil
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
            pipelineItems = try service.getShortTermPipeline()
        } catch {
            loadError = error.localizedDescription
        }
        isLoading = false
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
            } else {
                Image(systemName: "exclamationmark.circle.fill")
                    .foregroundStyle(.red)
                    .font(.caption)
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
                        dismiss()
                    }
                    .fontWeight(.semibold)

                    Button("Snooze 1 Day") {
                        onSnooze(1)
                        dismiss()
                    }

                    Button("Snooze 3 Days") {
                        onSnooze(3)
                        dismiss()
                    }

                    Button("Snooze 1 Week") {
                        onSnooze(7)
                        dismiss()
                    }
                }
            }
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
