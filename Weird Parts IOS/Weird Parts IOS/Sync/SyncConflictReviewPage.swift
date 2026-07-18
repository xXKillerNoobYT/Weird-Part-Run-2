import SwiftUI
import WiredPartCore

/// Review page for auto-resolved sync conflicts.
///
/// Shows each field-level conflict with its local value, remote value,
/// and which side "won" via Last-Writer-Wins. Users can accept the
/// auto-resolution or mark all as reviewed.
struct SyncConflictReviewPage: View {
    @EnvironmentObject private var appCore: AppCore
    @Environment(\.dismiss) private var dismiss

    @State private var conflicts: [ConflictLogEntry] = []
    @State private var isLoading = true
    @State private var aiResolutions: [Int64: AIConflictResolution] = [:]
    @State private var isRequestingAI = false
    @State private var activeAlert: ActiveAlert?

    private struct PendingCriticalResolution {
        let conflict: ConflictLogEntry
        let keepLocal: Bool

        var stableConflictKey: String {
            if let id = conflict.id {
                return String(id)
            }
            return "\(conflict.tableName)-\(conflict.recordId)-\(conflict.fieldName)"
        }
    }

    private enum ActiveAlert: Identifiable {
        case critical(PendingCriticalResolution)
        case actionError(String)

        var id: String {
            switch self {
            case .critical(let decision):
                return "critical-\(decision.stableConflictKey)-\(decision.keepLocal)"
            case .actionError:
                return "action-error"
            }
        }

        var title: String {
            switch self {
            case .critical: return "Confirm Critical Write Decision"
            case .actionError: return "Sync conflict action failed"
            }
        }
    }

    private var syncManager: IOSSyncManager { appCore.syncManager }

    private var autoResolvableConflicts: [ConflictLogEntry] {
        conflicts.filter { SyncConflictClassifier.isAutoResolvable(SyncConflictClassifier.classify($0)) }
    }

    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    ProgressView("Loading conflicts...")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if conflicts.isEmpty {
                    EmptyStateView(
                        icon: "checkmark.circle",
                        title: "No Unreviewed Conflicts",
                        message: "All sync conflicts have been reviewed."
                    )
                } else {
                    conflictList
                }
            }
            .navigationTitle("Sync Conflicts")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
                if !autoResolvableConflicts.isEmpty {
                    ToolbarItem(placement: .primaryAction) {
                        Button("Accept Auto-Resolved") {
                            if syncManager.markAllConflictsReviewed() {
                                loadConflicts()
                            } else {
                                presentActionError(syncManager.errorMessage ?? "Sync conflicts could not be marked reviewed.")
                            }
                        }
                    }
                }
            }
            .alert(
                Text(activeAlert?.title ?? "Sync conflict action"),
                isPresented: Binding(
                    get: { activeAlert != nil },
                    set: { if !$0 { activeAlert = nil } }
                ),
                presenting: activeAlert
            ) { alert in
                switch alert {
                case .critical(let decision):
                    Button("Cancel", role: .cancel) {
                        activeAlert = nil
                    }
                    Button("Confirm", role: .destructive) {
                        activeAlert = nil
                        Task { @MainActor in
                            await Task.yield()
                            withAnimation {
                                resolve(decision.conflict, keepLocal: decision.keepLocal)
                            }
                        }
                    }
                case .actionError:
                    Button("OK", role: .cancel) { activeAlert = nil }
                }
            } message: { alert in
                switch alert {
                case .critical(let decision):
                    let selectedLabel = decision.keepLocal ? "This Device" : "Remote"
                    Text(
                        "You are about to apply the \(selectedLabel) value for \(decision.conflict.tableName).\(decision.conflict.fieldName). This affects financial or inventory data."
                    )
                case .actionError(let message):
                    Text(message)
                }
            }
            .onAppear { loadConflicts() }
        }
    }

    // MARK: - Conflict List

    @ViewBuilder
    private var conflictList: some View {
        List {
            Section {
                PanelQualityInstructionBanner(
                    message: "Review conflicts before accepting: critical rows let you choose the exact value, while lower-risk rows keep the highlighted winner.",
                    icon: "arrow.triangle.merge",
                    tint: .orange,
                    accessibilityIdentifier: "syncConflictReviewInstructionBanner"
                )
                .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
            }

            Section {
                HStack(spacing: 12) {
                    summaryCard(title: "Total", value: "\(conflicts.count)", color: .orange)
                    summaryCard(title: "Tables", value: "\(uniqueTables)", color: .blue)
                    summaryCard(title: "Records", value: "\(uniqueRecords)", color: .purple)
                }
                .padding(.vertical, 4)
            }

            // Group conflicts by table + record
            ForEach(groupedConflicts, id: \.key) { group in
                Section(group.key) {
                    ForEach(group.conflicts, id: \.id) { conflict in
                        conflictRow(conflict)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
    }

    // MARK: - Conflict Row (severity-aware)

    @ViewBuilder
    private func conflictRow(_ conflict: ConflictLogEntry) -> some View {
        let severity = SyncConflictClassifier.classify(conflict)

        VStack(alignment: .leading, spacing: 8) {
            // Header with field name and severity badge
            HStack {
                Text(friendlyFieldName(conflict.fieldName))
                    .font(.subheadline)
                    .fontWeight(.medium)
                Spacer()
                severityBadge(severity)
                winnerBadge(conflict.winner)
            }

            switch severity {
            case .critical:
                // Critical: side-by-side human decision. These APPLY the chosen
                // value (writing back the LWW loser when picked, change-logged so
                // the decision syncs) — they are not review-only dismissals.
                CriticalConflictView(
                    conflict: conflict,
                    onResolveLocal: {
                        requestCriticalResolution(conflict, keepLocal: true)
                    },
                    onResolveRemote: {
                        requestCriticalResolution(conflict, keepLocal: false)
                    }
                )

            case .hard:
                // Hard: show AI merge button or AI resolution if available
                if let conflictId = conflict.id, let resolution = aiResolutions[conflictId] {
                    AIConflictResolutionView(resolution: resolution) { selectedValue in
                        withAnimation { resolveText(conflict, selectedValue: selectedValue) }
                    }
                } else {
                    // Standard view with AI merge button
                    standardConflictContent(conflict)

                    Button {
                        Task { await requestAIMerge(conflict) }
                    } label: {
                        Label("AI Merge", systemImage: "sparkles")
                    }
                    .font(.caption)
                    .buttonStyle(.bordered)
                    .tint(.purple)
                    .dsMinTapTarget()
                    .disabled(isRequestingAI)
                }

            default:
                // Trivial/simple/moderate: standard view
                standardConflictContent(conflict)
            }
        }
        .padding(.vertical, 4)
    }

    /// Standard conflict content for simple/moderate conflicts.
    private func standardConflictContent(_ conflict: ConflictLogEntry) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            // Local vs Remote values
            HStack(spacing: 12) {
                valueBox(
                    label: "This device",
                    value: conflict.localValue ?? "(empty)",
                    isWinner: conflict.winner == "local",
                    color: .blue
                )
                valueBox(
                    label: "Remote",
                    value: conflict.remoteValue ?? "(empty)",
                    isWinner: conflict.winner == "remote",
                    color: .purple
                )
            }

            // Timestamps
            HStack {
                Text("Local: \(formatTimestamp(conflict.localTs))")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                Spacer()
                Text("Remote: \(formatTimestamp(conflict.remoteTs))")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            // Accept button
            Button("Accept") {
                withAnimation { markReviewed(conflict) }
            }
            .font(.caption)
            .buttonStyle(.borderedProminent)
            .tint(.green)
            .dsMinTapTarget()
        }
    }

    // MARK: - Value Box

    private func valueBox(label: String, value: String, isWinner: Bool, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.caption)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
                .padding(6)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(isWinner ? color.opacity(0.1) : Color(.tertiarySystemFill))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(isWinner ? color : Color.clear, lineWidth: 1)
                )
        }
    }

    // MARK: - Summary Card

    private func summaryCard(title: String, value: String, color: Color) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.system(.title3, design: .monospaced))
                .fontWeight(.bold)
                .foregroundStyle(color)
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Winner Badge

    private func winnerBadge(_ winner: String) -> some View {
        Text(winner == "local" ? "Kept local" : "Kept remote")
            .font(.caption2)
            .fontWeight(.medium)
            .foregroundStyle(winner == "local" ? .blue : .purple)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(
                Capsule()
                    .fill((winner == "local" ? Color.blue : Color.purple).opacity(0.12))
            )
    }

    // MARK: - Helpers

    private var uniqueTables: Int {
        Set(conflicts.map(\.tableName)).count
    }

    private var uniqueRecords: Int {
        Set(conflicts.map { "\($0.tableName):\($0.recordId)" }).count
    }

    private struct ConflictGroup {
        let key: String
        let conflicts: [ConflictLogEntry]
    }

    private var groupedConflicts: [ConflictGroup] {
        let dict = Dictionary(grouping: conflicts) { "\($0.tableName) #\($0.recordId)" }
        return dict.map { ConflictGroup(key: $0.key, conflicts: $0.value) }
            .sorted { $0.key < $1.key }
    }

    private func friendlyFieldName(_ name: String) -> String {
        if name == "company_cost_price" { return "Unit Cost" }
        return name.replacingOccurrences(of: "_", with: " ").capitalized
    }

    private func formatTimestamp(_ ts: String) -> String {
        // Show just date and time portion
        let clean = ts.prefix(19).replacingOccurrences(of: "T", with: " ")
        return String(clean)
    }

    /// Apply the reviewer's chosen side (writing the value when it differs from
    /// the LWW winner), then drop the row from the list on success.
    private func requestCriticalResolution(_ conflict: ConflictLogEntry, keepLocal: Bool) {
        activeAlert = .critical(PendingCriticalResolution(
            conflict: conflict,
            keepLocal: keepLocal
        ))
    }

    private func presentActionError(_ message: String) {
        activeAlert = .actionError(message)
    }

    private func resolve(_ conflict: ConflictLogEntry, keepLocal: Bool) {
        guard let id = conflict.id else {
            let message = "This sync conflict cannot be resolved because its conflict id is missing. Reload conflicts and try again."
            presentActionError(message)
            syncManager.surfaceConflictReviewActionFailure(message)
            return
        }
        if syncManager.resolveConflict(conflict, keepLocal: keepLocal) {
            conflicts.removeAll { $0.id == id }
        } else {
            presentActionError(syncManager.errorMessage ?? "Sync conflict could not be resolved.")
        }
    }

    /// Persist the exact AI/device/manual String selected for a hard conflict.
    /// The row remains visible unless the atomic live-write + audit + review
    /// transaction succeeds.
    private func resolveText(_ conflict: ConflictLogEntry, selectedValue: String) {
        guard let id = conflict.id else {
            let message = "This sync text conflict cannot be resolved because its conflict id is missing. Reload conflicts and try again."
            presentActionError(message)
            syncManager.surfaceConflictReviewActionFailure(message)
            return
        }
        if syncManager.resolveTextConflict(conflict, selectedValue: selectedValue) {
            aiResolutions[id] = nil
            conflicts.removeAll { $0.id == id }
        } else {
            presentActionError(syncManager.errorMessage ?? "Sync text conflict could not be resolved.")
        }
    }

    private func markReviewed(_ conflict: ConflictLogEntry) {
        guard let id = conflict.id else {
            let message = "This sync conflict cannot be reviewed because its conflict id is missing. Reload conflicts and try again."
            presentActionError(message)
            syncManager.surfaceConflictReviewActionFailure(message)
            return
        }
        if syncManager.markConflictReviewed(conflictId: id) {
            conflicts.removeAll { $0.id == id }
        } else {
            presentActionError(syncManager.errorMessage ?? "Sync conflict could not be marked reviewed.")
        }
    }

    private func loadConflicts() {
        conflicts = syncManager.getUnreviewedConflicts()
        isLoading = false
    }

    // MARK: - Severity Badge

    private func severityBadge(_ severity: ConflictSeverity) -> some View {
        let (label, color): (String, Color) = {
            switch severity {
            case .trivial: return ("Auto", .gray)
            case .simple: return ("Simple", .green)
            case .moderate: return ("Moderate", .orange)
            case .hard: return ("AI Merge", .purple)
            case .critical: return ("Critical", .red)
            }
        }()

        return Text(label)
            .font(.caption2)
            .fontWeight(.medium)
            .foregroundStyle(color)
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .background(Capsule().fill(color.opacity(0.12)))
    }

    // MARK: - AI Merge

    private func requestAIMerge(_ conflict: ConflictLogEntry) async {
        guard let conflictId = conflict.id else {
            let message = "AI merge cannot start because this sync conflict id is missing. Reload conflicts and try again."
            presentActionError(message)
            syncManager.surfaceConflictReviewActionFailure(message)
            return
        }
        isRequestingAI = true

        let aiService = FoundationModelsService()

        let context: [String: String] = [
            "Entity": conflict.tableName,
            "Field": conflict.fieldName,
            "Device A Edit": conflict.localValue ?? "",
            "Device A Device": conflict.localDevice,
            "Device A Time": conflict.localTs,
            "Device B Edit": conflict.remoteValue ?? "",
            "Device B Device": conflict.remoteDevice,
            "Device B Time": conflict.remoteTs,
        ]

        // Primary merge
        let mergeResult = await aiService.generatePreFill(
            fieldType: """
                Merge two conflicting edits of the '\(conflict.fieldName)' field into one. \
                Both users edited the same field. Combine both edits if possible — don't lose \
                information from either side. If they contradict, include both perspectives clearly. \
                Keep the result concise. Return ONLY the merged text.
                """,
            contextData: context
        )

        // Alternative 1: prioritize Device A
        let alt1Result = await aiService.generatePreFill(
            fieldType: "Merge prioritizing Device A's edit but including Device B's additions. Return ONLY the merged text.",
            contextData: context
        )

        // Alternative 2: prioritize Device B
        let alt2Result = await aiService.generatePreFill(
            fieldType: "Merge prioritizing Device B's edit but including Device A's additions. Return ONLY the merged text.",
            contextData: context
        )

        let resolution = AIConflictResolution(
            original: nil,
            deviceAEdit: conflict.localValue ?? "",
            deviceBEdit: conflict.remoteValue ?? "",
            aiMerge: mergeResult.text ?? conflict.remoteValue ?? "",
            aiAlternative1: alt1Result.text ?? conflict.localValue ?? "",
            aiAlternative2: alt2Result.text ?? conflict.remoteValue ?? "",
            deviceALabel: "This device",
            deviceBLabel: "Remote"
        )

        aiResolutions[conflictId] = resolution
        isRequestingAI = false
    }
}
