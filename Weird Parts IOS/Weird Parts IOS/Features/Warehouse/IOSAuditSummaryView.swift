import SwiftUI
import WiredPartCore

/// Post-audit summary report view.
///
/// Displays audit results: total counted, matches, discrepancies, variance value,
/// and a breakdown of discrepancy items with export capability.
struct IOSAuditSummaryView: View {
    @EnvironmentObject private var appCore: AppCore

    @State private var summary: WarehouseService.AuditSummary?
    @State private var discrepancies: [WarehouseService.AuditDiscrepancy] = []
    @State private var isLoading = true
    @State private var loadError: String?

    var body: some View {
        VStack(spacing: 0) {
            if isLoading {
                ProgressView("Loading audit results...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error = loadError {
                ErrorStateView(message: error) { loadData() }
            } else {
                summaryContent
            }
        }
        .navigationTitle("Audit Summary")
        .refreshable { loadData() }
        .task { loadData() }
    }

    @ViewBuilder
    private var summaryContent: some View {
        List {
            // Overview stats
            if let s = summary {
                Section("Overview") {
                    statRow(label: "Total Parts", value: "\(s.totalParts)", icon: "shippingbox.fill", color: .blue)
                    statRow(label: "Counted Today", value: "\(s.countedParts)", icon: "checkmark.circle.fill", color: .green)

                    let accuracy = s.totalParts > 0
                        ? Double(s.totalParts - s.discrepancies) / Double(s.totalParts) * 100
                        : 100.0
                    statRow(
                        label: "Accuracy",
                        value: String(format: "%.1f%%", accuracy),
                        icon: "target",
                        color: accuracy >= 95 ? .green : accuracy >= 85 ? .orange : .red
                    )

                    statRow(
                        label: "Discrepancies",
                        value: "\(s.discrepancies)",
                        icon: "exclamationmark.triangle.fill",
                        color: s.discrepancies > 0 ? .red : .green
                    )

                    if let date = s.lastAuditDate {
                        statRow(label: "Audit Date", value: String(date.prefix(10)), icon: "calendar", color: .secondary)
                    }
                }

                // Progress bar
                Section("Completion") {
                    VStack(alignment: .leading, spacing: 8) {
                        ProgressView(value: Double(s.countedParts), total: Double(max(s.totalParts, 1)))
                        HStack {
                            Text("\(s.countedParts) of \(s.totalParts) counted")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Spacer()
                            let pct = s.totalParts > 0 ? Int(Double(s.countedParts) / Double(s.totalParts) * 100) : 0
                            Text("\(pct)%")
                                .font(.caption)
                                .fontWeight(.medium)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }

            // Discrepancy breakdown
            if discrepancies.isEmpty {
                Section("Discrepancies") {
                    ContentUnavailableView {
                        Label("No Discrepancies", systemImage: "checkmark.seal.fill")
                    } description: {
                        Text("All counted items match system records.")
                    }
                }
            } else {
                Section("Discrepancies (\(discrepancies.count))") {
                    ForEach(discrepancies, id: \.partId) { item in
                        discrepancyRow(item)
                    }
                }
            }
        }
        #if os(iOS)
        .listStyle(.insetGrouped)
        #endif
    }

    private func statRow(label: String, value: String, icon: String, color: Color) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundStyle(color)
                .frame(width: 24)
            Text(label)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .fontWeight(.semibold)
        }
    }

    private func discrepancyRow(_ item: WarehouseService.AuditDiscrepancy) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(item.partName)
                    .fontWeight(.medium)
                if let code = item.partCode, !code.isEmpty {
                    Text(code)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .monospaced()
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                HStack(spacing: 8) {
                    Text("Sys: \(item.systemQty)")
                        .font(.caption)
                    Text("Cnt: \(item.countedQty)")
                        .font(.caption)
                }
                .foregroundStyle(.secondary)

                let diff = item.countedQty - item.systemQty
                Text(diff >= 0 ? "+\(diff)" : "\(diff)")
                    .font(.caption2)
                    .fontWeight(.semibold)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(diff == 0 ? Color.green.opacity(0.15) : Color.red.opacity(0.15)))
                    .foregroundStyle(diff == 0 ? .green : .red)
            }
        }
        .padding(.vertical, 2)
    }

    private func loadData() {
        guard let service = appCore.warehouseService else { return }
        isLoading = summary == nil
        loadError = nil
        do {
            summary = try service.getAuditSummary()
            discrepancies = try service.getAuditDiscrepancies()
        } catch {
            loadError = error.localizedDescription
        }
        isLoading = false
    }
}
