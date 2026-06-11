import SwiftUI
import WiredPartCore

/// Pre-trip inspection checklist editor.
///
/// Manages per-vehicle-type checklists with sections and items.
/// Configuration is stored as a single JSON blob in the settings table.
struct IOSPreTripChecklistPage: View {
    @EnvironmentObject private var appCore: AppCore

    // MARK: - Types

    struct ChecklistItem: Identifiable, Codable, Equatable {
        var id: String
        var name: String
        var isCritical: Bool

        init(name: String, isCritical: Bool = false) {
            self.id = UUID().uuidString
            self.name = name
            self.isCritical = isCritical
        }
    }

    struct ChecklistSection: Identifiable, Codable, Equatable {
        var id: String
        var title: String
        var items: [ChecklistItem]

        init(title: String, items: [ChecklistItem]) {
            self.id = UUID().uuidString
            self.title = title
            self.items = items
        }
    }

    struct VehicleChecklist: Codable, Equatable {
        var useDefault: Bool
        var sections: [ChecklistSection]
    }

    // MARK: - State

    @State private var isLoading = true
    @State private var loadError: String?
    @State private var saveError: String?
    @State private var activeSheet: ActiveSheet?

    @State private var selectedVehicleType: String = "all"
    @State private var checklists: [String: VehicleChecklist] = [:]
    @State private var isDirty = false

    @State private var showAddItem = false
    @State private var addItemSectionId: String?
    @State private var newItemName = ""
    @State private var newItemCritical = false

    @State private var showAddSection = false
    @State private var newSectionName = ""

    @State private var showDeleteItemConfirm = false
    @State private var deleteItemSectionId: String?
    @State private var deleteItemOffsets: IndexSet?

    private enum ActiveSheet: Identifiable {
        case help
        var id: String { "help" }
    }

    private let vehicleTypes = ["all", "truck", "van", "car", "trailer"]
    private let vehicleLabels: [String: String] = [
        "all": "All Vehicles",
        "truck": "Truck",
        "van": "Van",
        "car": "Car",
        "trailer": "Trailer",
    ]

    var body: some View {
        Group {
            if isLoading {
                ProgressView("Loading checklist...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let loadError {
                ErrorStateView(message: loadError)
            } else {
                checklistEditor
            }
        }
        .navigationTitle("Pre-Trip Checklists")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { activeSheet = .help } label: {
                    Image(systemName: "questionmark.circle")
                }
                .accessibilityLabel("Help")
            }
        }
        .sheet(item: $activeSheet) { _ in
            PageHelpSheet(title: "Checklist Help", sections: [
                ("About Pre-Trip Checklists", "Define the inspection items drivers must check before starting their trip. Items marked as critical will fail the inspection if not OK."),
                ("Vehicle Types", "Each vehicle type can have its own checklist. Toggle 'Use Default' to inherit from the All Vehicles list."),
            ])
        }
        .task { loadSettings() }
    }

    // MARK: - Editor

    private var currentChecklist: VehicleChecklist {
        checklists[selectedVehicleType] ?? checklists["all"] ?? VehicleChecklist(useDefault: true, sections: [])
    }

    private var displaySections: [ChecklistSection] {
        let cl = checklists[selectedVehicleType]
        if selectedVehicleType != "all", let cl, cl.useDefault {
            return checklists["all"]?.sections ?? []
        }
        return cl?.sections ?? []
    }

    private var checklistEditor: some View {
        Form {
            if let saveError {
                Section {
                    Label(saveError, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                        .font(.caption)
                }
            }

            // Vehicle type picker
            Section {
                Picker("Vehicle Type", selection: $selectedVehicleType) {
                    ForEach(vehicleTypes, id: \.self) { type in
                        Text(vehicleLabels[type] ?? type.capitalized).tag(type)
                    }
                }
            }

            // Use Default toggle (not for "all")
            if selectedVehicleType != "all" {
                Section {
                    Toggle("Use Default Checklist", isOn: Binding(
                        get: { checklists[selectedVehicleType]?.useDefault ?? true },
                        set: { newValue in
                            ensureChecklist(for: selectedVehicleType)
                            checklists[selectedVehicleType]?.useDefault = newValue
                        }
                    ))
                } footer: {
                    Text("When enabled, this vehicle type inherits the All Vehicles checklist.")
                }
            }

            // Sections and items
            let isEditable = selectedVehicleType == "all" || !(checklists[selectedVehicleType]?.useDefault ?? true)

            if !displaySections.isEmpty {
                ForEach(displaySections) { section in
                    Section {
                        ForEach(section.items) { item in
                            HStack {
                                if item.isCritical {
                                    Image(systemName: "exclamationmark.triangle.fill")
                                        .foregroundStyle(.red)
                                        .font(.caption)
                                        .accessibilityHidden(true)
                                }
                                Text(item.name)
                                Spacer()
                                if item.isCritical {
                                    Text("Critical")
                                        .font(.caption2)
                                        .foregroundStyle(.red)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(.red.opacity(0.1), in: Capsule())
                                }
                            }
                        }
                        .onDelete { offsets in
                            if isEditable {
                                deleteItemSectionId = section.id
                                deleteItemOffsets = offsets
                                showDeleteItemConfirm = true
                            }
                        }

                        if isEditable {
                            Button {
                                addItemSectionId = section.id
                                newItemName = ""
                                newItemCritical = false
                                showAddItem = true
                            } label: {
                                Label("Add Item", systemImage: "plus.circle")
                                    .font(.subheadline)
                            }
                        }
                    } header: {
                        Text(section.title)
                    }
                }
            } else {
                Section {
                    Text("No checklist items configured.")
                        .foregroundStyle(.secondary)
                }
            }

            // Add Section button
            if isEditable {
                Section {
                    Button {
                        newSectionName = ""
                        showAddSection = true
                    } label: {
                        Label("Add Section", systemImage: "plus.rectangle.on.rectangle")
                    }
                }
            }

            // Save
            Section {
                Button { saveSettings() } label: {
                    Label("Save Checklist", systemImage: "checkmark.circle")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(!isDirty)
                .accessibilityHint(isDirty ? "" : "Make changes to the checklist to enable saving.")
            }
        }
        // Fix #149: dismiss keyboard when scrolling checklist editor
        .scrollDismissesKeyboard(.interactively)
        .onChange(of: checklists) { _, _ in isDirty = true }
        .alert("Add Item", isPresented: $showAddItem) {
            TextField("Item name", text: $newItemName)
            Toggle("Critical item", isOn: $newItemCritical)
            Button("Add") { addItem() }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("Enter the inspection item name.")
        }
        .alert("Add Section", isPresented: $showAddSection) {
            TextField("Section name", text: $newSectionName)
            Button("Add") { addSection() }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("Enter a name for the new section.")
        }
        .alert("Delete Item?", isPresented: $showDeleteItemConfirm) {
            Button("Cancel", role: .cancel) {
                deleteItemSectionId = nil
                deleteItemOffsets = nil
            }
            Button("Delete", role: .destructive) {
                if let sectionId = deleteItemSectionId, let offsets = deleteItemOffsets {
                    deleteItems(in: sectionId, at: offsets)
                }
                deleteItemSectionId = nil
                deleteItemOffsets = nil
            }
        } message: {
            Text("This checklist item will be removed.")
        }
    }

    // MARK: - Item Management

    private func ensureChecklist(for type: String) {
        if checklists[type] == nil {
            if type == "all" {
                checklists[type] = VehicleChecklist(useDefault: false, sections: Self.defaultSections)
            } else {
                // Copy from all as a starting point
                checklists[type] = VehicleChecklist(useDefault: true, sections: checklists["all"]?.sections ?? Self.defaultSections)
            }
        }
    }

    private func addItem() {
        guard !newItemName.trimmingCharacters(in: .whitespaces).isEmpty,
              let sectionId = addItemSectionId else { return }

        let editType = selectedVehicleType == "all" ? "all" : selectedVehicleType
        ensureChecklist(for: editType)

        if let sIdx = checklists[editType]?.sections.firstIndex(where: { $0.id == sectionId }) {
            checklists[editType]?.sections[sIdx].items.append(
                ChecklistItem(name: newItemName.trimmingCharacters(in: .whitespaces), isCritical: newItemCritical)
            )
        }
    }

    private func addSection() {
        guard !newSectionName.trimmingCharacters(in: .whitespaces).isEmpty else { return }

        let editType = selectedVehicleType == "all" ? "all" : selectedVehicleType
        ensureChecklist(for: editType)

        checklists[editType]?.sections.append(
            ChecklistSection(title: newSectionName.trimmingCharacters(in: .whitespaces), items: [])
        )
    }

    private func deleteItems(in sectionId: String, at offsets: IndexSet) {
        let editType = selectedVehicleType == "all" ? "all" : selectedVehicleType
        if let sIdx = checklists[editType]?.sections.firstIndex(where: { $0.id == sectionId }) {
            checklists[editType]?.sections[sIdx].items.remove(atOffsets: offsets)
        }
    }

    // MARK: - Persistence

    private func loadSettings() {
        guard let service = appCore.settingsService else {
            loadError = "Settings service unavailable"
            isLoading = false
            return
        }

        do {
            if let json = try service.getSettingValue("pretrip_checklist_config"),
               let data = json.data(using: .utf8) {
                checklists = try JSONDecoder().decode([String: VehicleChecklist].self, from: data)
            } else {
                // Seed defaults
                checklists = ["all": VehicleChecklist(useDefault: false, sections: Self.defaultSections)]
            }
        } catch {
            // If JSON is corrupt, reset to defaults
            checklists = ["all": VehicleChecklist(useDefault: false, sections: Self.defaultSections)]
        }
        isLoading = false
        isDirty = false
    }

    private func saveSettings() {
        guard let service = appCore.settingsService else {
            saveError = "Settings service unavailable"
            return
        }

        do {
            let data = try JSONEncoder().encode(checklists)
            let json = String(data: data, encoding: .utf8) ?? "{}"
            try service.upsertSetting(key: "pretrip_checklist_config", value: json, category: "pretrip")
            saveError = nil
            isDirty = false
        } catch {
            saveError = userFriendlyError(error, context: "save data")
        }
    }

    // MARK: - Defaults

    static let defaultSections: [ChecklistSection] = [
        ChecklistSection(title: "Exterior", items: [
            ChecklistItem(name: "Tires & wheels", isCritical: true),
            ChecklistItem(name: "Lights & signals", isCritical: true),
            ChecklistItem(name: "Mirrors"),
            ChecklistItem(name: "Body damage"),
            ChecklistItem(name: "Fluid leaks", isCritical: true),
            ChecklistItem(name: "Hitch/coupler"),
            ChecklistItem(name: "Safety chains"),
            ChecklistItem(name: "Mud flaps"),
        ]),
        ChecklistSection(title: "Interior", items: [
            ChecklistItem(name: "Seat & seatbelt", isCritical: true),
            ChecklistItem(name: "Horn", isCritical: true),
            ChecklistItem(name: "Wipers & washers"),
            ChecklistItem(name: "Gauges & warning lights", isCritical: true),
            ChecklistItem(name: "HVAC"),
            ChecklistItem(name: "Fire extinguisher", isCritical: true),
            ChecklistItem(name: "First aid kit"),
        ]),
        ChecklistSection(title: "Equipment", items: [
            ChecklistItem(name: "Ladder rack"),
            ChecklistItem(name: "Tool boxes secured"),
            ChecklistItem(name: "Load secured", isCritical: true),
            ChecklistItem(name: "PPE present"),
        ]),
    ]
}
