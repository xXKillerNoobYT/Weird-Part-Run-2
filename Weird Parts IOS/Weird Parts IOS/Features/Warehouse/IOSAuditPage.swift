import SwiftUI
import WiredPartCore

/// Warehouse audit page for iOS.
///
/// Shows audit summary KPIs (total parts, counted, discrepancies) and
/// a list of discrepancy records with part name, expected vs. counted
/// quantities, and variance. Uses `WarehouseService` for audit data.
/// Supports recount action on discrepancies and audit setup.
///
/// // TODO: When certainty drops below 80% for a part, auto-add to audit queue
/// // This ties into the forecasting system (see docs/plans/ios-warehouse-pages.md)
struct IOSAuditPage: View {
    @EnvironmentObject private var appCore: AppCore

    // MARK: - State

    @State private var summary: WarehouseService.AuditSummary?
    @State private var discrepancies: [WarehouseService.AuditDiscrepancy] = []
    @State private var isLoading = true
    @State private var searchText = ""
    @State private var loadError: String?
    @State private var actionError: String?
    @State private var activeSheet: ActiveSheet?

    private enum ActiveSheet: Identifiable {
        case auditSetup
        case adjustDiscrepancy(WarehouseService.AuditDiscrepancy)

        var id: String {
            switch self {
            case .auditSetup: "setup"
            case .adjustDiscrepancy(let d): "adjust-\(d.partId)-\(d.locationId)"
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            if isLoading {
                ProgressView("Loading audit data...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error = loadError {
                ErrorStateView(message: error) { loadData() }
            } else {
                auditContent
            }
        }
        .navigationTitle("Warehouse Audit")
        .searchable(text: $searchText, prompt: "Search discrepancies...")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    activeSheet = .auditSetup
                } label: {
                    Label("Start Audit", systemImage: "plus")
                }
            }
        }
        .sheet(item: $activeSheet) { sheet in
            sheetContent(for: sheet)
        }
        .alert("Error", isPresented: .constant(actionError != nil)) {
            Button("OK") { actionError = nil }
        } message: {
            Text(actionError ?? "")
        }
        .refreshable { loadData() }
        .task { loadData() }
    }

    // MARK: - Sheet Content

    @ViewBuilder
    private func sheetContent(for sheet: ActiveSheet) -> some View {
        switch sheet {
        case .auditSetup:
            IOSAuditSetupView(onAuditCreated: { _ in
                loadData()
            })
            .environmentObject(appCore)
        case .adjustDiscrepancy(let disc):
            AdjustDiscrepancySheetFromAudit(discrepancy: disc) {
                loadData()
            }
            .environmentObject(appCore)
        }
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
                    VStack(spacing: 12) {
                        Image(systemName: "checkmark.seal")
                            .font(.title)
                            .foregroundStyle(.green)
                        Text("No Discrepancies")
                            .font(.subheadline)
                            .fontWeight(.medium)
                        Text("All counts match expected quantities.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                }
            } else {
                Section("Discrepancies (\(filteredDiscrepancies.count))") {
                    ForEach(filteredDiscrepancies, id: \.partId) { item in
                        discrepancyRow(item)
                            .swipeActions(edge: .trailing) {
                                Button {
                                    recountItem(item)
                                } label: {
                                    Label("Recount", systemImage: "arrow.clockwise")
                                }
                                .tint(.blue)

                                Button {
                                    activeSheet = .adjustDiscrepancy(item)
                                } label: {
                                    Label("Adjust", systemImage: "slider.horizontal.3")
                                }
                                .tint(.orange)
                            }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
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

    // MARK: - Actions

    private func recountItem(_ item: WarehouseService.AuditDiscrepancy) {
        guard let service = appCore.warehouseService else { return }
        do {
            // Re-record the audit count to refresh the timestamp
            // This effectively marks the item as "needs recount"
            let stockRows = try service.getLocationStock()
            if let stock = stockRows.first(where: {
                $0.partId == item.partId &&
                $0.locationType == item.locationType &&
                $0.locationId == item.locationId
            }) {
                try service.recordAuditCount(stockId: stock.id, countedQty: item.systemQty)
                loadData()
            }
        } catch {
            actionError = error.localizedDescription
        }
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

// MARK: - Adjust Discrepancy Sheet (from Audit Page)

private struct AdjustDiscrepancySheetFromAudit: View {
    @EnvironmentObject private var appCore: AppCore
    @Environment(\.dismiss) private var dismiss

    let discrepancy: WarehouseService.AuditDiscrepancy
    let onAdjust: () -> Void

    @State private var newQty: Int = 0
    @State private var reason = ""
    @State private var isSaving = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("Part Info") {
                    LabeledContent("Part", value: discrepancy.partName)
                    if let code = discrepancy.partCode {
                        LabeledContent("Code", value: code)
                    }
                    LabeledContent("Location", value: "\(discrepancy.locationType.capitalized) #\(discrepancy.locationId)")
                }

                Section("Quantities") {
                    LabeledContent("System Qty", value: "\(discrepancy.systemQty)")
                    LabeledContent("Counted Qty", value: "\(discrepancy.countedQty)")
                }

                Section("Adjust To") {
                    Stepper("New Quantity: \(newQty)", value: $newQty, in: 0...9999)
                    TextField("Reason for adjustment...", text: $reason, axis: .vertical)
                        .lineLimit(2...4)
                }

                if let error = errorMessage {
                    Section {
                        Text(error)
                            .foregroundStyle(.red)
                            .font(.caption)
                    }
                }
            }
            .navigationTitle("Adjust Count")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isSaving {
                        ProgressView()
                    } else {
                        Button("Apply") { applyAdjustment() }
                            .fontWeight(.semibold)
                    }
                }
            }
            .onAppear {
                newQty = discrepancy.countedQty
            }
        }
    }

    private func applyAdjustment() {
        guard let service = appCore.warehouseService else {
            errorMessage = "Warehouse service not available"
            return
        }
        isSaving = true
        errorMessage = nil
        do {
            try service.adjustAuditCount(
                partId: discrepancy.partId,
                locationType: discrepancy.locationType,
                locationId: discrepancy.locationId,
                newQty: newQty,
                reason: reason.isEmpty ? nil : reason,
                performedBy: appCore.currentUser?.id
            )
            onAdjust()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
        isSaving = false
    }
}
