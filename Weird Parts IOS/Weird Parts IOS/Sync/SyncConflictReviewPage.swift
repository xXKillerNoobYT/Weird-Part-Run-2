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

    private var syncManager: IOSSyncManager { appCore.syncManager }

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
                if !conflicts.isEmpty {
                    ToolbarItem(placement: .primaryAction) {
                        Button("Accept All") {
                            syncManager.markAllConflictsReviewed()
                            conflicts = []
                        }
                    }
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
                // Critical: side-by-side human decision
                CriticalConflictView(
                    conflict: conflict,
                    onResolveLocal: {
                        withAnimation { markReviewed(conflict) }
                    },
                    onResolveRemote: {
                        withAnimation { markReviewed(conflict) }
                    }
                )

            case .hard:
                // Hard: show AI merge button or AI resolution if available
                if let resolution = aiResolutions[conflict.id ?? 0] {
                    AIConflictResolutionView(resolution: resolution) { _ in
                        withAnimation { markReviewed(conflict) }
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
                    .controlSize(.small)
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
            .controlSize(.small)
            .tint(.green)
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
        name.replacingOccurrences(of: "_", with: " ").capitalized
    }

    private func formatTimestamp(_ ts: String) -> String {
        // Show just date and time portion
        let clean = ts.prefix(19).replacingOccurrences(of: "T", with: " ")
        return String(clean)
    }

    private func markReviewed(_ conflict: ConflictLogEntry) {
        guard let id = conflict.id else { return }
        syncManager.markConflictReviewed(conflictId: id)
        conflicts.removeAll { $0.id == id }
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
        guard let conflictId = conflict.id else { return }
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
