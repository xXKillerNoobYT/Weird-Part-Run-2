import SwiftUI
import WiredPartCore

/// Reusable view showing the change history for a part.
/// Displays a timeline of who changed what and when.
struct PartHistoryView: View {
    @EnvironmentObject private var appCore: AppCore
    let partId: Int64

    @State private var entries: [PartsService.PartChangeEntry] = []
    @State private var isLoading = true
    @State private var loadError: String?

    var body: some View {
        Group {
            if isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity, alignment: .center)
            } else if entries.isEmpty {
                Text("No changes recorded")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 8)
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(entries) { entry in
                        historyRow(entry)
                        if entry.id != entries.last?.id {
                            Divider().padding(.leading, 20)
                        }
                    }
                }
            }
        }
        .task { loadHistory() }
    }

    @ViewBuilder
    private func historyRow(_ entry: PartsService.PartChangeEntry) -> some View {
        HStack(alignment: .top, spacing: 8) {
            // Timeline dot
            Circle()
                .fill(actionColor(entry.action))
                .frame(width: 8, height: 8)
                .padding(.top, 6)

            VStack(alignment: .leading, spacing: 2) {
                // Who + when
                HStack {
                    Text(entry.userName ?? "System")
                        .font(.caption)
                        .fontWeight(.medium)
                    Spacer()
                    if let date = entry.createdAt {
                        Text(formatDate(date))
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }

                // What changed
                switch entry.action {
                case "created":
                    Text("Created this part")
                        .font(.caption)
                        .foregroundStyle(.green)
                case "deleted":
                    Text("Deleted this part")
                        .font(.caption)
                        .foregroundStyle(.red)
                case "restored":
                    Text("Restored this part")
                        .font(.caption)
                        .foregroundStyle(.blue)
                case "updated":
                    if let field = entry.fieldName {
                        HStack(spacing: 4) {
                            Text(formatFieldName(field))
                                .font(.caption)
                                .fontWeight(.medium)
                            if let old = entry.oldValue, let new = entry.newValue {
                                Text("\(old) → \(new)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            } else if let new = entry.newValue {
                                Text("set to \(new)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                        }
                    }
                default:
                    Text(entry.action)
                        .font(.caption)
                }

                // Context
                if let ctx = entry.context {
                    Text(ctx)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 4)
    }

    private func actionColor(_ action: String) -> Color {
        switch action {
        case "created": .green
        case "deleted": .red
        case "restored": .blue
        case "updated": .orange
        default: .secondary
        }
    }

    private func formatFieldName(_ field: String) -> String {
        field.replacingOccurrences(of: "_", with: " ").capitalized
    }

    private func formatDate(_ iso: String) -> String {
        let prefix = String(iso.prefix(10))
        let formatter = ISO8601DateFormatter()
        let today = formatter.string(from: Date()).prefix(10)
        if prefix == String(today) { return "Today" }
        return prefix
    }

    private func loadHistory() {
        guard let service = appCore.partsService else {
            isLoading = false
            return
        }
        do {
            entries = try service.getPartChangeLog(partId: partId)
        } catch {
            loadError = error.localizedDescription
        }
        isLoading = false
    }
}
