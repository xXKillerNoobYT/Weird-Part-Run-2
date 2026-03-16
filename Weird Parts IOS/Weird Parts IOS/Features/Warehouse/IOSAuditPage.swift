import SwiftUI
import WiredPartCore

/// Warehouse audit page for iOS.
///
/// Shows audit summary KPIs (total parts, counted, discrepancies) and
/// a list of discrepancy records with part name, expected vs. counted
/// quantities, and variance. Uses `WarehouseService` for audit data.
struct IOSAuditPage: View {
    @EnvironmentObject private var appCore: AppCore

    // MARK: - State

    @State private var summary: WarehouseService.AuditSummary?
    @State private var discrepancies: [WarehouseService.AuditDiscrepancy] = []
    @State private var isLoading = true
    @State private var searchText = ""

    var body: some View {
        VStack(spacing: 0) {
            if isLoading {
                ProgressView("Loading audit data...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                auditContent
            }
        }
        .navigationTitle("Warehouse Audit")
        .searchable(text: $searchText, prompt: "Search discrepancies...")
        .onChange(of: searchText) { /* local filter only */ }
        .refreshable { loadData() }
        .task { loadData() }
    }

    // MARK: - Content

    @ViewBuilder
    private var auditContent: some View {
        List {
            // Summary section
            if let summary = summary {
                Section("Audit Summary") {
                    summaryRow(label: "Total Parts", value: "\(summary.totalParts)", icon: "shippingbox", color: .blue)
                    summaryRow(label: "Counted", value: "\(summary.countedParts)", icon: "checkmark.circle", color: .green)
                    summaryRow(label: "Discrepancies", value: "\(summary.discrepancies)", icon: "exclamationmark.triangle", color: summary.discrepancies > 0 ? .red : .green)
                    if let lastDate = summary.lastAuditDate {
                        summaryRow(label: "Last Audit", value: formatDate(lastDate), icon: "calendar", color: .secondary)
                    }
                }
            }

            // Discrepancies section
            if filteredDiscrepancies.isEmpty {
                Section("Discrepancies") {
                    ContentUnavailableView {
                        Label("No Discrepancies", systemImage: "checkmark.seal")
                    } description: {
                        Text("All counts match expected quantities.")
                    }
                }
            } else {
                Section("Discrepancies (\(filteredDiscrepancies.count))") {
                    ForEach(filteredDiscrepancies, id: \.partId) { item in
                        discrepancyRow(item)
                    }
                }
            }
        }
        #if os(iOS)
        .listStyle(.insetGrouped)
        #endif
    }

    private func summaryRow(label: String, value: String, icon: String, color: Color) -> some View {
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

    private var filteredDiscrepancies: [WarehouseService.AuditDiscrepancy] {
        guard !searchText.isEmpty else { return discrepancies }
        let query = searchText.lowercased()
        return discrepancies.filter {
            $0.partName.lowercased().contains(query) ||
            ($0.partCode?.lowercased().contains(query) ?? false) ||
            $0.locationType.lowercased().contains(query)
        }
    }

    private func discrepancyRow(_ item: WarehouseService.AuditDiscrepancy) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.title3)
                .foregroundStyle(item.difference > 0 ? .orange : .red)
                .frame(width: 32)

            VStack(alignment: .leading, spacing: 4) {
                Text(item.partName)
                    .fontWeight(.medium)
                    .lineLimit(1)
                if let code = item.partCode, !code.isEmpty {
                    Text(code)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
                Text("\(item.locationType.capitalized) #\(item.locationId)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 4) {
                varianceBadge(item.difference)
                HStack(spacing: 8) {
                    VStack(alignment: .trailing, spacing: 1) {
                        Text("System")
                            .font(.system(size: 9))
                            .foregroundStyle(.tertiary)
                        Text("\(item.systemQty)")
                            .font(.caption)
                            .fontWeight(.medium)
                    }
                    VStack(alignment: .trailing, spacing: 1) {
                        Text("Counted")
                            .font(.system(size: 9))
                            .foregroundStyle(.tertiary)
                        Text("\(item.countedQty)")
                            .font(.caption)
                            .fontWeight(.medium)
                    }
                }
                if let date = item.lastCounted {
                    Text(formatDate(date))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .padding(.vertical, 4)
    }

    // MARK: - Badges

    private func varianceBadge(_ diff: Int) -> some View {
        let color: Color = diff > 0 ? .orange : .red
        let prefix = diff > 0 ? "+" : ""
        return Text("\(prefix)\(diff)")
            .font(.system(.caption2, weight: .semibold))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Capsule().fill(color.opacity(0.15)))
            .foregroundStyle(color)
    }

    // MARK: - Helpers

    private func formatDate(_ dateStr: String) -> String {
        if dateStr.count >= 10 { return String(dateStr.prefix(10)) }
        return dateStr
    }

    // MARK: - Data Loading

    private func loadData() {
        guard let service = appCore.warehouseService else { return }
        isLoading = summary == nil
        do {
            summary = try service.getAuditSummary()
            discrepancies = try service.getAuditDiscrepancies()
        } catch {
            print("[IOSAuditPage] Load error: \(error)")
        }
        isLoading = false
    }
}
