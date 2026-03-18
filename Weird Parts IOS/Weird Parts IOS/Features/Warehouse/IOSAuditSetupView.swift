import SwiftUI
import WiredPartCore

/// Pre-audit configuration view for setting up a warehouse audit session.
///
/// Allows users to choose audit scope (full warehouse, specific zones, spot check),
/// select date, and start the audit process. Results feed into IOSAuditPage.
struct IOSAuditSetupView: View {
    @EnvironmentObject private var appCore: AppCore
    @Environment(\.dismiss) private var dismiss

    @State private var auditScope: AuditScope = .fullWarehouse
    @State private var selectedZone = ""
    @State private var spotCheckCount = 20
    @State private var includeZeroStock = false
    @State private var notes = ""
    @State private var isStarting = false
    @State private var auditSummary: WarehouseService.AuditSummary?

    enum AuditScope: String, CaseIterable, Identifiable {
        case fullWarehouse = "Full Warehouse"
        case specificZone = "Specific Zone"
        case spotCheck = "Spot Check"

        var id: String { rawValue }

        var description: String {
            switch self {
            case .fullWarehouse: return "Count every part in the warehouse"
            case .specificZone: return "Focus on a particular area"
            case .spotCheck: return "Random sample of items"
            }
        }

        var icon: String {
            switch self {
            case .fullWarehouse: return "building.2.fill"
            case .specificZone: return "map.fill"
            case .spotCheck: return "dice.fill"
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
            }
            .navigationTitle("Setup Audit")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Start Audit") {
                        startAudit()
                    }
                    .disabled(isStarting || (auditScope == .specificZone && selectedZone.isEmpty))
                    .fontWeight(.semibold)
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
        guard let service = appCore.warehouseService else { return }
        do {
            auditSummary = try service.getAuditSummary()
        } catch {
            print("[IOSAuditSetupView] Load summary error: \(error)")
        }
    }

    private func startAudit() {
        isStarting = true
        // Audit session creation — transitions to the main audit counting page
        dismiss()
    }
}
