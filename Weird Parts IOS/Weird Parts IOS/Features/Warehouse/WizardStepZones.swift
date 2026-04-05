import SwiftUI
import WiredPartCore

/// Wizard Step 2: Define Zones — label zones on the warehouse grid.
///
/// Zone types: staging, storage, receiving, returns, office, tool_storage, custom.
/// Uses a simplified grid-tap UI where the user taps cells to mark them as a zone.
struct WizardStepZones: View {
    @EnvironmentObject private var appCore: AppCore
    let floorPlanId: Int64
    @Binding var stepError: String?

    @State private var zones: [WarehouseZone] = []
    @State private var showAddZone = false
    @State private var deleteTarget: WarehouseZone?

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 8) {
                Text("Define the zones in your warehouse — areas like storage, receiving, staging, etc.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                Text("Each zone groups storage units by function.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .padding()

            Button {
                showAddZone = true
            } label: {
                Label("Add Zone", systemImage: "plus.circle.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .padding(.horizontal)

            if zones.isEmpty {
                ContentUnavailableView {
                    Label("No Zones", systemImage: "rectangle.3.group")
                } description: {
                    Text("Add zones to organize your warehouse into functional areas.")
                }
            } else {
                List {
                    ForEach(zones, id: \.id) { zone in
                        HStack(spacing: 12) {
                            Circle()
                                .fill(zoneColor(zone.zoneType))
                                .frame(width: 12, height: 12)
                                .accessibilityHidden(true)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(zone.label ?? zone.zoneType.replacingOccurrences(of: "_", with: " ").capitalized)
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                                Text(zone.zoneType.replacingOccurrences(of: "_", with: " ").capitalized)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }

                            Spacer()

                            Image(systemName: zoneIcon(zone.zoneType))
                                .foregroundStyle(zoneColor(zone.zoneType))
                                .accessibilityHidden(true)
                        }
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) {
                                deleteTarget = zone
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                    }
                }
                .listStyle(.insetGrouped)
            }
        }
        .task { loadZones() }
        .sheet(isPresented: $showAddZone) {
            AddZoneSheet(floorPlanId: floorPlanId) {
                loadZones()
            }
        }
        .confirmationDialog(
            "Delete Zone?",
            isPresented: Binding(get: { deleteTarget != nil }, set: { if !$0 { deleteTarget = nil } }),
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                if let zone = deleteTarget, let zoneId = zone.id {
                    do {
                        try appCore.warehouseService?.deleteZone(id: zoneId)
                        loadZones()
                    } catch {
                        stepError = userFriendlyError(error, context: "delete zone")
                    }
                }
            }
            Button("Cancel", role: .cancel) { deleteTarget = nil }
        } message: {
            Text("This zone will be permanently removed. Storage units in this zone won't be deleted.")
        }
    }

    private func loadZones() {
        do {
            zones = try appCore.warehouseService?.listZones(floorPlanId: floorPlanId) ?? []
        } catch {
            stepError = userFriendlyError(error, context: "load zones")
        }
    }

    private func zoneColor(_ type: String) -> Color {
        switch type {
        case "storage": return .blue
        case "receiving": return .green
        case "staging": return .orange
        case "returns": return .red
        case "office": return .purple
        case "tool_storage": return .teal
        default: return .gray
        }
    }

    private func zoneIcon(_ type: String) -> String {
        switch type {
        case "storage": return "cabinet.fill"
        case "receiving": return "arrow.down.circle.fill"
        case "staging": return "shippingbox.and.arrow.backward.fill"
        case "returns": return "arrow.uturn.backward.circle.fill"
        case "office": return "building.2.fill"
        case "tool_storage": return "wrench.and.screwdriver.fill"
        default: return "square.dashed"
        }
    }
}

// MARK: - Add Zone Sheet

struct AddZoneSheet: View {
    @EnvironmentObject private var appCore: AppCore
    @Environment(\.dismiss) private var dismiss

    let floorPlanId: Int64
    var onSave: () -> Void

    @State private var zoneType = "storage"
    @State private var zoneName = ""
    @State private var saveError: String?

    private let zoneTypes: [(String, String, String)] = [
        ("storage", "Storage", "cabinet.fill"),
        ("receiving", "Receiving", "arrow.down.circle.fill"),
        ("staging", "Staging", "shippingbox.and.arrow.backward.fill"),
        ("returns", "Returns", "arrow.uturn.backward.circle.fill"),
        ("office", "Office", "building.2.fill"),
        ("tool_storage", "Tool Storage", "wrench.and.screwdriver.fill"),
        ("custom", "Custom", "square.dashed"),
    ]

    var body: some View {
        NavigationStack {
            Form {
                Section("Zone Type") {
                    Picker("Type", selection: $zoneType) {
                        ForEach(zoneTypes, id: \.0) { type in
                            Label(type.1, systemImage: type.2).tag(type.0)
                        }
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                }

                Section("Zone Name") {
                    TextField("Name (e.g., Main Storage, Receiving Dock)", text: $zoneName)
                }

                if let error = saveError {
                    Section {
                        Text(error)
                            .foregroundStyle(.red)
                            .font(.caption)
                    }
                }
            }
            .navigationTitle("Add Zone")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") { saveZone() }
                }
            }
        }
    }

    private func saveZone() {
        do {
            let label = zoneName.trimmingCharacters(in: .whitespaces).isEmpty ? nil : zoneName.trimmingCharacters(in: .whitespaces)
            _ = try appCore.warehouseService?.addZone(
                floorPlanId: floorPlanId,
                zoneType: zoneType,
                label: label
            )
            dismiss()
            onSave()
        } catch {
            saveError = userFriendlyError(error, context: "add zone")
        }
    }
}
