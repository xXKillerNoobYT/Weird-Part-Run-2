import SwiftUI
import WiredPartCore

/// Post-audit summary report view.
///
/// Displays audit results: total counted, matches, discrepancies, variance value,
/// and a breakdown of discrepancy items. Includes Finalize Audit action and
/// per-discrepancy adjustment capability.
struct IOSAuditSummaryView: View {
    @EnvironmentObject private var appCore: AppCore

    @State private var summary: WarehouseService.AuditSummary?
    @State private var discrepancies: [WarehouseService.AuditDiscrepancy] = []
    @State private var isLoading = true
    @State private var loadError: String?
    @State private var accuracy: Double = 100.0
    @State private var actionError: String?
    @State private var showFinalizeConfirm = false
    @State private var selectedDiscrepancy: WarehouseService.AuditDiscrepancy?

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
        .alert("Finalize Audit?", isPresented: $showFinalizeConfirm) {
            Button("Cancel", role: .cancel) { }
            Button("Finalize") { finalizeAudit() }
        } message: {
            Text("This will close the current audit session. Outstanding discrepancies will be recorded for follow-up.")
        }
        .alert("Error", isPresented: .constant(actionError != nil)) {
            Button("OK") { actionError = nil }
        } message: {
            Text(actionError ?? "")
        }
        .sheet(item: $selectedDiscrepancy) { disc in
            AdjustDiscrepancySheet(discrepancy: disc) { loadData() }
                .environmentObject(appCore)
        }
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

                // Finalize button
                Section {
                    Button {
                        showFinalizeConfirm = true
                    } label: {
                        Label("Finalize Audit", systemImage: "checkmark.seal")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                }
            }

            // Discrepancy breakdown
            if discrepancies.isEmpty {
                Section("Discrepancies") {
                    VStack(spacing: 12) {
                        Image(systemName: "checkmark.seal.fill")
                            .font(.title)
                            .foregroundStyle(.green)
                        Text("No Discrepancies")
                            .font(.subheadline)
                            .fontWeight(.medium)
                        Text("All counted items match system records.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                }
            } else {
                Section("Discrepancies (\(discrepancies.count))") {
                    ForEach(discrepancies, id: \.partId) { item in
                        Button {
                            selectedDiscrepancy = item
                        } label: {
                            discrepancyRow(item)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
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
                Text("\(item.locationType.capitalized) #\(item.locationId)")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
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

            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 2)
    }

    // MARK: - Actions

    private func finalizeAudit() {
        guard let service = appCore.warehouseService else { return }
        do {
            // Use session ID 0 as a general finalize — in production this would track the active session
            try service.finalizeAuditSession(sessionId: 0)
            loadData()
        } catch {
            actionError = error.localizedDescription
        }
    }

    private func loadData() {
        guard let service = appCore.warehouseService else { return }
        isLoading = summary == nil
        loadError = nil
        do {
            summary = try service.getAuditSummary()
            discrepancies = try service.getAuditDiscrepancies()
            accuracy = try service.getAuditAccuracy()
        } catch {
            loadError = error.localizedDescription
        }
        isLoading = false
    }
}

// MARK: - Adjust Discrepancy Sheet

private struct AdjustDiscrepancySheet: View {
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
                    LabeledContent("Variance", value: "\(discrepancy.difference)")
                        .foregroundStyle(discrepancy.difference == 0 ? .green : .red)
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

// MARK: - AuditDiscrepancy Identifiable

extension WarehouseService.AuditDiscrepancy: @retroactive Identifiable {
    public var id: String { "\(partId)-\(locationType)-\(locationId)" }
}
