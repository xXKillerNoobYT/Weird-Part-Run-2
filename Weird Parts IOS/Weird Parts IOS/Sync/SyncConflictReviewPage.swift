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

    private var syncManager: IOSSyncManager { appCore.syncManager }

    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    ProgressView("Loading conflicts...")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if conflicts.isEmpty {
                    ContentUnavailableView(
                        "No Unreviewed Conflicts",
                        systemImage: "checkmark.circle",
                        description: Text("All sync conflicts have been reviewed.")
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

    // MARK: - Conflict Row

    private func conflictRow(_ conflict: ConflictLogEntry) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            // Field name
            HStack {
                Text(friendlyFieldName(conflict.fieldName))
                    .font(.subheadline)
                    .fontWeight(.medium)
                Spacer()
                winnerBadge(conflict.winner)
            }

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

            // Actions
            HStack(spacing: 8) {
                Button("Accept") {
                    withAnimation {
                        markReviewed(conflict)
                    }
                }
                .font(.caption)
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .tint(.green)
            }
        }
        .padding(.vertical, 4)
    }

    // MARK: - Value Box

    private func valueBox(label: String, value: String, isWinner: Bool, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(truncateValue(value))
                .font(.caption)
                .lineLimit(3)
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

    private func truncateValue(_ value: String) -> String {
        if value.count > 120 {
            return String(value.prefix(120)) + "..."
        }
        return value
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
}
