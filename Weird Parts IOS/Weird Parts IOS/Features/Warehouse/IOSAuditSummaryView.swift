import SwiftUI
import WiredPartCore

/// Post-audit summary report view.
///
/// Displays audit results: total counted, matches, discrepancies, variance value,
/// and a breakdown of discrepancy items. Includes Finalize Audit action and
/// per-discrepancy adjustment capability.
struct IOSAuditSummaryView: View {
    @EnvironmentObject private var appCore: AppCore

    /// The audit session ID passed from the parent (e.g. IOSAuditPage after setup).
    let sessionId: Int64

    @State private var summary: WarehouseService.AuditSummary?
    @State private var discrepancies: [WarehouseService.AuditDiscrepancy] = []
    @State private var multiUserSummaries: [WarehouseService.MultiUserAuditPartSummary] = []
    @State private var isLoading = true
    @State private var loadError: String?
    @State private var accuracy: Double = 100.0
    @State private var actionError: String?
    @State private var showFinalizeConfirm = false
    @State private var selectedDiscrepancy: WarehouseService.AuditDiscrepancy?
    @State private var showResolveConfirm = false
    @State private var partToResolve: WarehouseService.MultiUserAuditPartSummary?

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
        .alert("Resolve Multi-User Audit?", isPresented: $showResolveConfirm) {
            Button("Cancel", role: .cancel) { }
            Button("Resolve") { resolveMultiUserAudit() }
        } message: {
            if let part = partToResolve, let consensus = part.consensusQuantity {
                Text("Accept consensus count of \(consensus) for \(part.partName)? This will update the system stock and adjust user ratings.")
            } else {
                Text("No consensus reached yet. All assigned users must submit their counts first.")
            }
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

            // Multi-user verification section
            if !multiUserSummaries.isEmpty {
                Section("Multi-User Verification (\(multiUserSummaries.count))") {
                    ForEach(multiUserSummaries, id: \.partId) { partSummary in
                        multiUserAuditRow(partSummary)
                    }
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

    private func multiUserAuditRow(_ partSummary: WarehouseService.MultiUserAuditPartSummary) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            // Part header
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(partSummary.partName)
                        .fontWeight(.medium)
                    if let bin = partSummary.binLocation, !bin.isEmpty {
                        Text(bin)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .monospaced()
                    }
                }
                Spacer()
                if let expected = partSummary.expectedQuantity {
                    Text("Expected: \(expected)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            // Individual assignment rows
            ForEach(partSummary.assignments, id: \.id) { assignment in
                HStack(spacing: 8) {
                    // Status indicator
                    Circle()
                        .fill(assignmentStatusColor(assignment.status))
                        .frame(width: 8, height: 8)

                    Text(assignment.assignedUserName ?? "User")
                        .font(.caption)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    if let qty = assignment.countedQuantity {
                        Text("Count: \(qty)")
                            .font(.caption)
                            .fontWeight(.semibold)
                    } else {
                        Text("Pending")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .italic()
                    }

                    Text(assignment.status.capitalized)
                        .font(.caption2)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(
                            Capsule().fill(assignmentStatusColor(assignment.status).opacity(0.15))
                        )
                        .foregroundStyle(assignmentStatusColor(assignment.status))
                }
            }

            // Consensus / Resolve row
            HStack {
                if partSummary.isResolved {
                    Label("Resolved", systemImage: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.green)
                } else if let consensus = partSummary.consensusQuantity {
                    Label("Consensus: \(consensus)", systemImage: "person.3.fill")
                        .font(.caption)
                        .foregroundStyle(.blue)
                    Spacer()
                    Button {
                        partToResolve = partSummary
                        showResolveConfirm = true
                    } label: {
                        Text("Resolve")
                            .font(.caption)
                            .fontWeight(.semibold)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.mini)
                } else {
                    let countedCount = partSummary.assignments.filter { $0.status == "counted" }.count
                    let totalCount = partSummary.assignments.count
                    Label("\(countedCount)/\(totalCount) counted — awaiting consensus", systemImage: "clock.fill")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }
            .padding(.top, 2)
        }
        .padding(.vertical, 4)
    }

    private func assignmentStatusColor(_ status: String) -> Color {
        switch status {
        case "pending": return .orange
        case "counted": return .blue
        case "resolved": return .green
        default: return .secondary
        }
    }

    // MARK: - Actions

    private func resolveMultiUserAudit() {
        guard let service = appCore.warehouseService,
              let part = partToResolve else {
            actionError = "Service not available"
            return
        }
        do {
            let result = try service.resolveMultiUserAudit(
                partId: part.partId,
                sessionId: sessionId,
                resolvedBy: appCore.currentUser?.id ?? 0
            )
            if result == nil {
                actionError = "No consensus could be reached. Ensure all users have submitted their counts."
            }
            partToResolve = nil
            loadData()
        } catch {
            actionError = error.localizedDescription
        }
    }

    private func finalizeAudit() {
        guard let service = appCore.warehouseService else {
            actionError = "Service not available"
            return
        }
        do {
            try service.finalizeAuditSession(sessionId: sessionId)
            loadData()
        } catch {
            actionError = error.localizedDescription
        }
    }

    private func loadData() {
        guard let service = appCore.warehouseService else {
            loadError = "Service not available"
            isLoading = false
            return
        }
        isLoading = summary == nil
        loadError = nil
        do {
            summary = try service.getAuditSummary()
            discrepancies = try service.getAuditDiscrepancies()
            accuracy = try service.getAuditAccuracy()
            multiUserSummaries = try service.getMultiUserAuditAssignments(sessionId: sessionId)
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
