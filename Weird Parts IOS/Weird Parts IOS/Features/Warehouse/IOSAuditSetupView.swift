import SwiftUI
import WiredPartCore

/// Pre-audit configuration view for setting up a warehouse audit session.
///
/// Allows users to choose audit scope (full warehouse, specific zones, spot check),
/// select date, and start the audit process. Results feed into IOSAuditPage.
struct IOSAuditSetupView: View {
    @EnvironmentObject private var appCore: AppCore
    @Environment(\.dismiss) private var dismiss

    var onAuditCreated: ((Int64) -> Void)?

    @State private var auditScope: AuditScope = .fullWarehouse
    @State private var selectedZone = ""
    @State private var spotCheckCount = 20
    @State private var includeZeroStock = false
    @State private var notes = ""
    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var auditSummary: WarehouseService.AuditSummary?

    enum AuditScope: String, CaseIterable, Identifiable {
        case fullWarehouse = "Full Warehouse"
        case specificZone = "Specific Zone"
        case spotCheck = "Spot Check"

        var id: String { rawValue }

        var description: String {
            switch self {
            case .fullWarehouse: "Count every part in the warehouse"
            case .specificZone: "Focus on a particular area"
            case .spotCheck: "Random sample of items"
            }
        }

        var icon: String {
            switch self {
            case .fullWarehouse: "building.2.fill"
            case .specificZone: "map.fill"
            case .spotCheck: "dice.fill"
            }
        }

        var scopeKey: String {
            switch self {
            case .fullWarehouse: "full"
            case .specificZone: "zone"
            case .spotCheck: "spot_check"
            }
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                scopeSection
                scopeOptionsSection
                optionsSection
                notesSection
                summarySection

                if let error = errorMessage {
                    Section {
                        Label(error, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.red)
                            .font(.caption)
                    }
                }
            }
            .navigationTitle("Setup Audit")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isSaving {
                        ProgressView()
                    } else {
                        Button("Start Audit") {
                            startAudit()
                        }
                        .disabled(auditScope == .specificZone && selectedZone.isEmpty)
                        .fontWeight(.semibold)
                    }
                }
            }
            .task { loadSummary() }
        }
    }

    // MARK: - Sections

    private var scopeSection: some View {
        Section("Audit Scope") {
            ForEach(AuditScope.allCases) { scope in
                scopeRow(scope)
            }
        }
    }

    private func scopeRow(_ scope: AuditScope) -> some View {
        Button {
            auditScope = scope
        } label: {
            HStack(spacing: 12) {
                Image(systemName: scope.icon)
                    .foregroundStyle(auditScope == scope ? Color.accentColor : .secondary)
                    .frame(width: 28)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 2) {
                    Text(scope.rawValue)
                        .foregroundStyle(.primary)
                        .fontWeight(auditScope == scope ? .semibold : .regular)
                    Text(scope.description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if auditScope == scope {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(Color.accentColor)
                        .accessibilityLabel("Selected")
                }
            }
        }
    }

    @ViewBuilder
    private var scopeOptionsSection: some View {
        if auditScope == .specificZone {
            Section("Zone") {
                TextField("Zone name or location", text: $selectedZone)
            }
        }

        if auditScope == .spotCheck {
            Section("Sample Size") {
                Stepper("Items to check: \(spotCheckCount)", value: $spotCheckCount, in: 5...100, step: 5)
            }
        }
    }

    private var optionsSection: some View {
        Section("Options") {
            Toggle("Include zero-stock items", isOn: $includeZeroStock)
        }
    }

    private var notesSection: some View {
        Section("Notes") {
            TextEditor(text: $notes)
                .frame(minHeight: 60)
        }
    }

    private var summarySection: some View {
        Section("Summary") {
            HStack {
                Text("Parts to audit")
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(auditSummary?.totalParts ?? 0)")
                    .fontWeight(.semibold)
            }
            if let lastDate = auditSummary?.lastAuditDate {
                HStack {
                    Text("Last audit")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(String(lastDate.prefix(10)))
                        .fontWeight(.semibold)
                }
            }
        }
    }

    // MARK: - Actions

    private func loadSummary() {
        guard let service = appCore.warehouseService else {
            errorMessage = "Warehouse service not available"
            return
        }
        do {
            auditSummary = try service.getAuditSummary()
        } catch {
            // Non-critical — summary display is informational
        }
    }

    private func startAudit() {
        guard let service = appCore.warehouseService else {
            errorMessage = "Warehouse service not available"
            return
        }
        isSaving = true
        errorMessage = nil
        do {
            let sessionId = try service.createAuditSession(
                scope: auditScope.scopeKey,
                zone: selectedZone.isEmpty ? nil : selectedZone,
                sampleSize: auditScope == .spotCheck ? spotCheckCount : nil,
                includeZeroStock: includeZeroStock,
                notes: notes.isEmpty ? nil : notes,
                userId: appCore.currentUser?.id ?? 1
            )
            onAuditCreated?(sessionId)
            dismiss()
        } catch {
            errorMessage = userFriendlyError(error, context: "start audit")
        }
        isSaving = false
    }
}
