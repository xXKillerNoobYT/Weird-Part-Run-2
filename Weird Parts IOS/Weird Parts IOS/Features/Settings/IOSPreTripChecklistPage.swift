import SwiftUI
import WiredPartCore

/// Pre-trip inspection checklist editor backed by `inspection_templates`.
struct IOSPreTripChecklistPage: View {
    @EnvironmentObject private var appCore: AppCore
    @Environment(\.dismiss) private var dismiss

    private enum TemplateTab: String, CaseIterable, Identifiable {
        case vehicle
        case trailer

        var id: String { rawValue }
        var label: String { rawValue.capitalized }
    }

    struct ChecklistItem: Identifiable, Equatable {
        var id: String
        var name: String
        var description: String
        var isRequired: Bool
        var isCritical: Bool
    }

    struct ChecklistSection: Identifiable, Equatable {
        var id: String
        var title: String
        var items: [ChecklistItem]
    }

    @State private var isLoading = true
    @State private var loadError: String?
    @State private var saveError: String?
    @State private var activeSheet: ActiveSheet?
    @State private var isDirty = false
    @State private var hasLoadedSettings = false
    @State private var showDiscardConfirmation = false

    @State private var selectedTab: TemplateTab = .vehicle
    @State private var selectedVehicleType = "truck"
    @State private var drafts: [String: [ChecklistSection]] = [:]
    @State private var collapsedSectionIds: Set<String> = []

    @State private var showAddItem = false
    @State private var addItemSectionId: String?
    @State private var newItemName = ""
    @State private var newItemRequired = true
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

    private let vehicleTypes = ["truck", "van"]
    private let vehicleLabels = ["truck": "Truck", "van": "Van"]

    private var selectedTemplateKey: String {
        selectedTab == .trailer ? "trailer" : selectedVehicleType
    }

    private var currentSections: [ChecklistSection] {
        drafts[selectedTemplateKey] ?? []
    }

    var body: some View {
        Group {
            if isLoading {
                ProgressView("Loading checklist...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let loadError {
                ContentUnavailableView("Unable to Load", systemImage: "exclamationmark.triangle", description: Text(loadError))
            } else {
                checklistEditor
            }
        }
        .navigationTitle("Pre-Trip Checklists")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(isDirty)
        .toolbar {
            if isDirty {
                ToolbarItem(placement: .topBarLeading) {
                    Button { showDiscardConfirmation = true } label: {
                        Label("Back", systemImage: "chevron.left")
                    }
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button { activeSheet = .help } label: {
                    Image(systemName: "questionmark.circle")
                }
                .accessibilityLabel("Help")
            }
        }
        .sheet(item: $activeSheet) { _ in
            PageHelpSheet(title: "Checklist Help", sections: [
                ("About Pre-Trip Checklists", "Edit the inspection templates drivers use for pre-trip inspections. Required items must be answered before submit. Critical items fail the inspection when marked as an issue."),
                ("Vehicle and Trailer Templates", "Vehicle templates apply to trucks and vans. Trailer templates are added when an inspection includes a trailer."),
                ("Ordering", "Drag items inside a section to control their runtime inspection order."),
            ])
            .presentationDetents([.medium, .large])
        }
        .task { loadSettings() }
        .interactiveDismissDisabled(isDirty)
        .alert("Discard changes?", isPresented: $showDiscardConfirmation) {
            Button("Discard", role: .destructive) { dismiss() }
            Button("Keep Editing", role: .cancel) {}
        } message: {
            Text("You have unsaved changes that will be lost.")
        }
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

            Section {
                Picker("Template", selection: $selectedTab) {
                    ForEach(TemplateTab.allCases) { tab in
                        Text(tab.label).tag(tab)
                    }
                }
                .pickerStyle(.segmented)

                if selectedTab == .vehicle {
                    Picker("Vehicle Type", selection: $selectedVehicleType) {
                        ForEach(vehicleTypes, id: \.self) { type in
                            Text(vehicleLabels[type] ?? type.capitalized).tag(type)
                        }
                    }
                }
            }

            if !currentSections.isEmpty {
                ForEach(sectionBindings) { $section in
                    Section {
                        Button {
                            toggleSection(section.id)
                        } label: {
                            HStack {
                                Label(section.title.capitalized, systemImage: sectionIcon(section.title))
                                Spacer()
                                Text("\(section.items.count)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Image(systemName: collapsedSectionIds.contains(section.id) ? "chevron.right" : "chevron.down")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .buttonStyle(.plain)

                        if !collapsedSectionIds.contains(section.id) {
                            ForEach($section.items) { $item in
                                ChecklistItemEditor(item: $item)
                            }
                            .onMove { source, destination in
                                moveItems(in: section.id, from: source, to: destination)
                            }
                            .onDelete { offsets in
                                deleteItemSectionId = section.id
                                deleteItemOffsets = offsets
                                showDeleteItemConfirm = true
                            }

                            Button {
                                addItemSectionId = section.id
                                newItemName = ""
                                newItemRequired = true
                                newItemCritical = false
                                showAddItem = true
                            } label: {
                                Label("Add Item", systemImage: "plus.circle")
                                    .font(.subheadline)
                            }
                        }
                    }
                }
            } else {
                Section {
                    Text("No checklist items configured.")
                        .foregroundStyle(.secondary)
                }
            }

            Section {
                Button {
                    newSectionName = ""
                    showAddSection = true
                } label: {
                    Label("Add Section", systemImage: "plus.rectangle.on.rectangle")
                }
            }

            Section {
                Button { saveSettings() } label: {
                    Label("Save Checklist", systemImage: "checkmark.circle")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(!isDirty)
                .accessibilityHint(isDirty ? "Saves pre-trip checklist changes" : "Make a checklist change before saving")
            }
        }
        .scrollDismissesKeyboard(.interactively)
        .onChange(of: drafts) { _, _ in markDirty() }
        .alert("Add Item", isPresented: $showAddItem) {
            TextField("Item name", text: $newItemName)
            Toggle("Required", isOn: $newItemRequired)
            Toggle("Critical failure item", isOn: $newItemCritical)
            Button("Add") { addItem() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Required controls completion. Critical controls pass/fail result.")
        }
        .alert("Add Section", isPresented: $showAddSection) {
            TextField("Section name", text: $newSectionName)
            Button("Add") { addSection() }
            Button("Cancel", role: .cancel) {}
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
            Text("This checklist item will be removed from future inspections.")
        }
    }

    private var sectionBindings: Binding<[ChecklistSection]> {
        Binding(
            get: { drafts[selectedTemplateKey] ?? [] },
            set: { drafts[selectedTemplateKey] = $0 }
        )
    }

    private func toggleSection(_ id: String) {
        if collapsedSectionIds.contains(id) {
            collapsedSectionIds.remove(id)
        } else {
            collapsedSectionIds.insert(id)
        }
    }

    private func addItem() {
        let itemName = newItemName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !itemName.isEmpty, let sectionId = addItemSectionId else { return }
        guard let sectionIndex = drafts[selectedTemplateKey]?.firstIndex(where: { $0.id == sectionId }) else { return }

        drafts[selectedTemplateKey]?[sectionIndex].items.append(
            ChecklistItem(
                id: UUID().uuidString,
                name: itemName,
                description: "",
                isRequired: newItemRequired,
                isCritical: newItemCritical
            )
        )
    }

    private func addSection() {
        let sectionName = newSectionName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !sectionName.isEmpty else { return }
        drafts[selectedTemplateKey, default: []].append(
            ChecklistSection(id: UUID().uuidString, title: normalizedSection(sectionName), items: [])
        )
    }

    private func deleteItems(in sectionId: String, at offsets: IndexSet) {
        guard let sectionIndex = drafts[selectedTemplateKey]?.firstIndex(where: { $0.id == sectionId }) else { return }
        drafts[selectedTemplateKey]?[sectionIndex].items.remove(atOffsets: offsets)
    }

    private func moveItems(in sectionId: String, from source: IndexSet, to destination: Int) {
        guard let sectionIndex = drafts[selectedTemplateKey]?.firstIndex(where: { $0.id == sectionId }) else { return }
        drafts[selectedTemplateKey]?[sectionIndex].items.move(fromOffsets: source, toOffset: destination)
    }

    private func markDirty() {
        guard hasLoadedSettings else { return }
        isDirty = true
    }

    private func loadSettings() {
        guard let service = appCore.fleetService else {
            loadError = "Fleet service unavailable"
            isLoading = false
            return
        }

        hasLoadedSettings = false
        do {
            var loaded: [String: [ChecklistSection]] = [:]
            for type in vehicleTypes + ["trailer"] {
                loaded[type] = sections(from: try service.getInspectionChecklist(vehicleType: type))
            }
            drafts = loaded
            loadError = nil
        } catch {
            loadError = userFriendlyError(error, context: "load inspection templates")
        }

        isLoading = false
        isDirty = false
        Task { @MainActor in
            hasLoadedSettings = true
        }
    }

    private func saveSettings() {
        guard let service = appCore.fleetService else {
            saveError = "Fleet service unavailable"
            return
        }

        do {
            try service.replaceInspectionTemplate(
                vehicleType: selectedTemplateKey,
                items: draftItems(from: currentSections)
            )
            saveError = nil
            isDirty = false
        } catch {
            saveError = userFriendlyError(error, context: "save inspection templates")
        }
    }

    private func sections(from templates: [FleetService.InspectionTemplateItem]) -> [ChecklistSection] {
        var sections: [ChecklistSection] = []
        for template in templates {
            let sectionTitle = normalizedSection(template.section)
            if let index = sections.firstIndex(where: { $0.title == sectionTitle }) {
                sections[index].items.append(item(from: template))
            } else {
                sections.append(ChecklistSection(
                    id: sectionTitle,
                    title: sectionTitle,
                    items: [item(from: template)]
                ))
            }
        }
        return sections
    }

    private func item(from template: FleetService.InspectionTemplateItem) -> ChecklistItem {
        ChecklistItem(
            id: String(template.id),
            name: template.itemName,
            description: template.itemDescription ?? "",
            isRequired: template.isRequired,
            isCritical: template.isCritical
        )
    }

    private func draftItems(from sections: [ChecklistSection]) -> [FleetService.InspectionTemplateDraftItem] {
        sections.flatMap { section in
            section.items.enumerated().map { index, item in
                FleetService.InspectionTemplateDraftItem(
                    section: normalizedSection(section.title),
                    itemName: item.name,
                    itemDescription: item.description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : item.description,
                    isRequired: item.isRequired,
                    isCritical: item.isCritical,
                    sortOrder: index
                )
            }
        }
    }

    private func normalizedSection(_ section: String) -> String {
        section.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private func sectionIcon(_ section: String) -> String {
        switch normalizedSection(section) {
        case "exterior": return "car.side"
        case "interior": return "steeringwheel"
        case "equipment": return "wrench.and.screwdriver"
        default: return "checklist"
        }
    }
}

private struct ChecklistItemEditor: View {
    @Binding var item: IOSPreTripChecklistPage.ChecklistItem

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField("Item name", text: $item.name)
                .textInputAutocapitalization(.words)

            TextField("Description", text: $item.description, axis: .vertical)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1...3)

            Toggle("Required", isOn: $item.isRequired)
            Toggle("Critical failure item", isOn: $item.isCritical)
        }
        .padding(.vertical, 4)
    }
}
