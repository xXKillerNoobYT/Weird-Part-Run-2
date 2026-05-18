import SwiftUI
import WiredPartCore

struct WizardStepWalkingPath: View {
    @EnvironmentObject private var appCore: AppCore

    let floorPlanId: Int64
    @Binding var stepError: String?

    @State private var pathId: Int64?
    @State private var pathStops: [Int64] = []
    @State private var previewStops: [Int64]?
    @State private var allAreas: [WalkingPathAreaInfo] = []
    @State private var selectedAreaId: Int64?
    @State private var showingAddStops = false
    @State private var isLoading = true
    @State private var isSaving = false

    private var displayedStops: [Int64] { previewStops ?? pathStops }
    private var areaById: [Int64: WalkingPathAreaInfo] { Dictionary(uniqueKeysWithValues: allAreas.map { ($0.id, $0) }) }
    private var missingAreaCount: Int { max(allAreas.count - Set(pathStops).count, 0) }
    private var isPreviewing: Bool { previewStops != nil }

    var body: some View {
        GeometryReader { proxy in
            Group {
                if isLoading {
                    ProgressView("Loading walking path...")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if proxy.size.width >= 1100 {
                    HStack(spacing: 0) {
                        stopList
                            .frame(minWidth: 360, idealWidth: 420, maxWidth: 460)
                        Divider()
                        previewPanel
                            .frame(maxWidth: .infinity)
                        Divider()
                        inspectorPanel
                            .frame(width: 260)
                    }
                } else if proxy.size.width >= 700 {
                    HStack(spacing: 0) {
                        stopList
                            .frame(minWidth: 320, maxWidth: 420)
                        Divider()
                        previewPanel
                            .frame(maxWidth: .infinity)
                    }
                } else {
                    stopList
                }
            }
        }
        .task { loadData() }
        .sheet(isPresented: $showingAddStops) {
            AddPathStopsSheet(
                areas: allAreas,
                existingAreaIds: Set(pathStops),
                onAdd: addStops
            )
        }
    }

    private var stopList: some View {
        List {
            Section {
                if displayedStops.isEmpty {
                    ContentUnavailableView {
                        Label("No Walking Path", systemImage: "figure.walk")
                    } description: {
                        Text("Add stops or preview a suggested path before saving.")
                    }
                } else {
                    ForEach(Array(displayedStops.enumerated()), id: \.element) { index, areaId in
                        stopRow(areaId: areaId, index: index)
                    }
                    .onMove(perform: moveStops)
                    .disabled(isPreviewing)
                }
            } header: {
                HStack {
                    Text(isPreviewing ? "Suggested Preview" : "Path Stops")
                    Spacer()
                    Text("\(displayedStops.count)")
                }
            } footer: {
                Text("\(pathStops.count) stops saved · \(missingAreaCount) areas not on path")
            }

            Section {
                Button {
                    showingAddStops = true
                } label: {
                    Label("Add stop", systemImage: "plus.circle")
                }
                .disabled(isPreviewing)

                Button {
                    suggestPath()
                } label: {
                    Label("Suggest path", systemImage: "sparkles")
                }

                if isPreviewing {
                    Button {
                        applyPreview()
                    } label: {
                        Label("Use suggested order", systemImage: "checkmark.circle")
                    }
                    .disabled(isSaving)
                }

                Button(role: .destructive) {
                    clearPath()
                } label: {
                    Label(isPreviewing ? "Dismiss preview" : "Clear", systemImage: "trash")
                }
                .disabled(displayedStops.isEmpty)
            }
        }
        .listStyle(.insetGrouped)
        .toolbar { EditButton() }
    }

    private func stopRow(areaId: Int64, index: Int) -> some View {
        let area = areaById[areaId]
        return HStack(spacing: 12) {
            Text("\(index + 1)")
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(.white)
                .frame(width: 28, height: 28)
                .background(Circle().fill(.blue))

            Button {
                selectedAreaId = areaId
            } label: {
                VStack(alignment: .leading, spacing: 2) {
                    Text(area?.fullLocationCode ?? "Area #\(areaId)")
                        .font(.subheadline)
                        .fontWeight(.medium)
                    Text([area?.zoneName, area?.unitName, area?.levelCode].compactMap { $0 }.joined(separator: " · "))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .buttonStyle(.plain)

            Spacer()

            Button(role: .destructive) {
                removeStop(areaId)
            } label: {
                Label("Remove", systemImage: "trash")
                    .labelStyle(.iconOnly)
                    .frame(minWidth: 44, minHeight: 44)
            }
            .disabled(isPreviewing)
        }
        .contentShape(Rectangle())
        .onTapGesture { selectedAreaId = areaId }
    }

    private var previewPanel: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Path Preview")
                .font(.headline)
            if let selectedAreaId, let area = areaById[selectedAreaId] {
                areaPreview(area)
            } else if let first = displayedStops.first, let area = areaById[first] {
                areaPreview(area)
            } else {
                ContentUnavailableView("Select a Stop", systemImage: "rectangle.dashed", description: Text("Tap a stop to preview its location."))
            }
            Spacer()
        }
        .padding()
    }

    private var inspectorPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Inspector")
                .font(.headline)
            LabeledContent("Saved stops", value: "\(pathStops.count)")
            LabeledContent("Areas", value: "\(allAreas.count)")
            LabeledContent("Not on path", value: "\(missingAreaCount)")
            if isPreviewing {
                Text("Suggestion is a preview. Save it with Use suggested order.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding()
    }

    private func areaPreview(_ area: WalkingPathAreaInfo) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: "map")
                .font(.largeTitle)
                .foregroundStyle(.blue)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 24)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color(.systemGray6)))
            Text(area.fullLocationCode)
                .font(.title3)
                .fontWeight(.semibold)
            Text("\(area.zoneName) · \(area.unitName) · \(area.levelCode) · \(area.areaCode)")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private func loadData() {
        guard let service = appCore.warehouseService else {
            stepError = "Warehouse service unavailable"
            isLoading = false
            return
        }
        do {
            allAreas = try loadWalkingPathAreas(service: service)
            if let current = try service.getDefaultWalkingPath(floorPlanId: floorPlanId) {
                pathId = current.path.id
                pathStops = current.stops.map(\.areaId)
            }
        } catch {
            stepError = userFriendlyError(error, context: "load walking path")
        }
        isLoading = false
    }

    private func loadWalkingPathAreas(service: WarehouseService) throws -> [WalkingPathAreaInfo] {
        let zones = try service.listZones(floorPlanId: floorPlanId)
        let zoneById = Dictionary(uniqueKeysWithValues: zones.compactMap { zone -> (Int64, WarehouseZone)? in
            guard let id = zone.id else { return nil }
            return (id, zone)
        })
        let units = try service.listStorageUnits(floorPlanId: floorPlanId)
        var results: [WalkingPathAreaInfo] = []

        for unit in units {
            guard let unitId = unit.id else { continue }
            let zone = unit.zoneId.flatMap { zoneById[$0] }
            let zoneName = zone?.label ?? zone?.zoneType.capitalized ?? "Unzoned"
            for level in try service.listLevelsForUnit(unitId: unitId) {
                guard let levelId = level.id else { continue }
                for area in try service.listAreasForLevel(levelId: levelId) {
                    guard let areaId = area.id else { continue }
                    results.append(WalkingPathAreaInfo(
                        id: areaId,
                        areaCode: area.areaCode,
                        fullLocationCode: area.fullLocationCode ?? "\(unit.name)-\(level.levelCode)-\(area.areaCode)",
                        unitName: unit.name,
                        unitNumber: unit.unitNumber ?? "Unit",
                        levelCode: level.levelCode,
                        zoneName: zoneName
                    ))
                }
            }
        }

        return results.sorted { $0.fullLocationCode < $1.fullLocationCode }
    }

    private func addStops(_ areaIds: [Int64]) {
        pathStops.append(contentsOf: areaIds.filter { !pathStops.contains($0) })
        saveStops(pathStops)
    }

    private func moveStops(from source: IndexSet, to destination: Int) {
        pathStops.move(fromOffsets: source, toOffset: destination)
        saveStops(pathStops)
    }

    private func removeStop(_ areaId: Int64) {
        pathStops.removeAll { $0 == areaId }
        saveStops(pathStops)
    }

    private func suggestPath() {
        guard let service = appCore.warehouseService else {
            stepError = "Warehouse service not available"
            return
        }
        do {
            previewStops = try service.suggestWalkingPath(floorPlanId: floorPlanId)
        } catch {
            stepError = userFriendlyError(error, context: "suggest walking path")
        }
    }

    private func applyPreview() {
        guard let previewStops else { return }
        self.previewStops = nil
        pathStops = previewStops
        saveStops(pathStops)
    }

    private func clearPath() {
        if isPreviewing {
            previewStops = nil
        } else {
            pathStops = []
            saveStops([])
        }
    }

    private func saveStops(_ stops: [Int64]) {
        guard let service = appCore.warehouseService,
              let userId = appCore.currentUser?.id else {
            stepError = "Current user unavailable"
            return
        }
        isSaving = true
        defer { isSaving = false }
        do {
            let resolvedPathId: Int64
            if let pathId {
                resolvedPathId = pathId
            } else {
                let path = try service.createWalkingPath(floorPlanId: floorPlanId, name: "Default Audit Path", userId: userId)
                guard let id = path.id else { return }
                pathId = id
                resolvedPathId = id
            }
            try service.setWalkingPathStops(pathId: resolvedPathId, areaIds: stops)
        } catch {
            stepError = userFriendlyError(error, context: "save walking path")
        }
    }
}
