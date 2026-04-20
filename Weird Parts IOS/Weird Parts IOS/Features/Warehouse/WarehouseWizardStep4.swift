import SwiftUI
import WiredPartCore

/// Step 4: Walk the Floor — per-area part assignment.
///
/// The user walks through areas one-by-one, searching and assigning parts.
/// Areas come from the floor plan created in Steps 1-2.
struct WarehouseWizardStep4: View {
    @EnvironmentObject private var appCore: AppCore
    let floorPlanId: Int64
    @Binding var stepError: String?

    @State private var allAreas: [WizardAreaInfo] = []
    @State private var walkAreaIndex = 0
    @State private var walkPartSearch = ""
    @State private var searchResults: [Part] = []
    @State private var assignedParts: [WarehouseService.AreaContentsItem] = []
    @State private var emptyAreas: Set<Int64> = []

    private var currentArea: WizardAreaInfo? {
        guard walkAreaIndex >= 0, walkAreaIndex < allAreas.count else { return nil }
        return allAreas[walkAreaIndex]
    }

    var body: some View {
        VStack(spacing: 0) {
            if allAreas.isEmpty {
                ContentUnavailableView {
                    Label("No Areas Yet", systemImage: "figure.walk")
                } description: {
                    Text("Add storage units in Step 2 first.")
                }
            } else if let area = currentArea {
                areaContent(area)
            }
        }
        .task { loadAllData() }
    }

    // MARK: - Area Content

    @ViewBuilder
    private func areaContent(_ area: WizardAreaInfo) -> some View {
        // Current area header
        VStack(spacing: 4) {
            Text("You are at:")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(area.fullLocationCode)
                .font(.title3)
                .fontWeight(.bold)
                .monospaced()
            Text("\(area.unitName) • \(area.levelCode)")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding()
        .frame(maxWidth: .infinity)
        .background(Color.blue.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .padding()

        // Search bar
        HStack {
            TextField("Search parts to assign here...", text: $walkPartSearch)
                .textFieldStyle(.roundedBorder)
                .onChange(of: walkPartSearch) { _, newValue in
                    searchParts(query: newValue)
                }
        }
        .padding(.horizontal)

        // Search results
        if !walkPartSearch.isEmpty && !searchResults.isEmpty {
            List {
                Section("Search Results") {
                    ForEach(searchResults, id: \.id) { part in
                        Button {
                            assignPart(part, to: area)
                        } label: {
                            HStack {
                                Image(systemName: "plus.circle")
                                    .foregroundStyle(.blue)
                                Text(part.name)
                                    .font(.subheadline)
                                Spacer()
                                if let code = part.code {
                                    Text(code)
                                        .font(.caption)
                                        .monospaced()
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .listStyle(.insetGrouped)
            .scrollDismissesKeyboard(.interactively)
        }

        // Assigned parts
        if !assignedParts.isEmpty {
            List {
                Section("Assigned to This Area") {
                    ForEach(assignedParts, id: \.partId) { part in
                        HStack {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                                .accessibilityHidden(true)
                            Text(part.partName)
                                .font(.subheadline)
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .scrollDismissesKeyboard(.interactively)
        }

        Spacer()

        // Area navigation
        areaNavigationControls(area)
    }

    // MARK: - Navigation Controls

    @ViewBuilder
    private func areaNavigationControls(_ area: WizardAreaInfo) -> some View {
        HStack {
            Button {
                walkAreaIndex = max(0, walkAreaIndex - 1)
                loadAreaData()
            } label: {
                Label("Prev", systemImage: "chevron.left")
            }
            .disabled(walkAreaIndex <= 0)

            Spacer()
            Text("Area \(walkAreaIndex + 1) of \(allAreas.count)")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()

            Button {
                walkAreaIndex = min(allAreas.count - 1, walkAreaIndex + 1)
                loadAreaData()
            } label: {
                Label("Next", systemImage: "chevron.right")
            }
            .disabled(walkAreaIndex >= allAreas.count - 1)
        }
        .padding(.horizontal)

        // Quick actions
        HStack(spacing: 12) {
            Button("Mark Empty") {
                emptyAreas.insert(area.id)
                advanceArea()
            }
            .buttonStyle(.bordered)

            Button("Skip Area") {
                advanceArea()
            }
            .buttonStyle(.bordered)
            .tint(.secondary)
        }
        .padding()
    }

    // MARK: - Data Loading

    private func loadAllData() {
        do {
            guard let service = appCore.warehouseService else { stepError = "Warehouse service not available"; return }
            allAreas = try loadAllWizardAreas(floorPlanId: floorPlanId, service: service)
            loadAreaData()
        } catch {
            stepError = userFriendlyError(error, context: "load areas")
        }
    }

    private func loadAreaData() {
        guard let area = currentArea else {
            assignedParts = []
            return
        }
        walkPartSearch = ""
        searchResults = []
        do {
            assignedParts = try appCore.warehouseService?.getAreaContents(areaId: area.id) ?? []
        } catch {
            stepError = userFriendlyError(error, context: "load area contents")
        }
    }

    private func searchParts(query: String) {
        guard !query.isEmpty else {
            searchResults = []
            return
        }
        do {
            searchResults = try appCore.partsService?.searchParts(query: query, limit: 15) ?? []
        } catch {
            // Search is best-effort; don't block the wizard
        }
    }

    private func assignPart(_ part: Part, to area: WizardAreaInfo) {
        guard let partId = part.id else { return }
        do {
            _ = try appCore.warehouseService?.assignPartToArea(
                partId: partId, areaId: area.id, isHome: true
            )
            walkPartSearch = ""
            searchResults = []
            loadAreaData()
        } catch {
            stepError = userFriendlyError(error, context: "assign part")
        }
    }

    private func advanceArea() {
        if walkAreaIndex < allAreas.count - 1 {
            walkAreaIndex += 1
            loadAreaData()
        }
    }
}
