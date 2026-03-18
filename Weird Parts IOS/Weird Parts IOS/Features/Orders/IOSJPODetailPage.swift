import SwiftUI
import WiredPartCore

/// JPO (Job Purchase Order) detail page.
///
/// Shows all JPO info including line items, approval status,
/// and actions to approve or generate a PO.
struct IOSJPODetailPage: View {
    @EnvironmentObject private var appCore: AppCore

    let jpoId: Int64

    @State private var jpo: OrdersService.JPODetail?
    @State private var isLoading = true
    @State private var loadError: String?

    var body: some View {
        Group {
            if isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error = loadError {
                ErrorStateView(message: error) { loadData() }
            } else if let jpo {
                jpoContent(jpo)
            }
        }
        .navigationTitle("JPO #\(jpoId)")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .task { loadData() }
    }

    @ViewBuilder
    private func jpoContent(_ jpo: OrdersService.JPODetail) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Header
                HStack(spacing: 8) {
                    StatusBadge(text: jpo.status.capitalized, color: statusColor(jpo.status))
                    StatusBadge(text: jpo.priority.capitalized, color: priorityColor(jpo.priority))
                    Spacer()
                }

                // Info
                DetailField(label: "Job", value: jpo.jobName)
                DetailField(label: "Requested By", value: jpo.requestedByName)
                if let approved = jpo.approvedByName {
                    DetailField(label: "Approved By", value: approved)
                }
                if let notes = jpo.notes, !notes.isEmpty {
                    DetailField(label: "Notes", value: notes)
                }

                // Line Items
                VStack(alignment: .leading, spacing: 8) {
                    Text("Line Items (\(jpo.lines.count))")
                        .font(.headline)

                    if jpo.lines.isEmpty {
                        Text("No line items")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(jpo.lines, id: \.id) { line in
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(line.partName ?? "Unknown Part")
                                        .font(.subheadline)
                                        .fontWeight(.medium)
                                    Text("Qty: \(line.quantity)")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                if let price = line.unitPrice {
                                    Text(formatCurrency(price * Double(line.quantity)))
                                        .font(.subheadline)
                                        .fontWeight(.medium)
                                }
                            }
                            .padding(10)
                            .dsCard()
                        }
                    }
                }
            }
            .padding()
        }
    }

    // MARK: - Helpers

    private func statusColor(_ status: String) -> Color {
        switch status {
        case "pending": .orange
        case "approved": .green
        case "rejected": .red
        case "ordered": .blue
        default: .secondary
        }
    }

    private func priorityColor(_ priority: String) -> Color {
        switch priority {
        case "urgent": .red
        case "high": .orange
        case "normal": .blue
        default: .secondary
        }
    }

    private func formatCurrency(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "USD"
        return formatter.string(from: NSNumber(value: value)) ?? "$0.00"
    }

    private func loadData() {
        guard let service = appCore.ordersService else { return }
        isLoading = jpo == nil
        loadError = nil
        do {
            jpo = try service.getJPODetail(id: jpoId)
        } catch {
            loadError = error.localizedDescription
        }
        isLoading = false
    }
}

// MARK: - Detail Field

private struct DetailField: View {
    let label: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.body)
        }
    }
}
