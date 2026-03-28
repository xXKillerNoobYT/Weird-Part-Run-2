import SwiftUI
import WiredPartCore

/// Warehouse Locations — floor plan grid editor + storage hierarchy drill-down.
///
/// Top level: Floor plan selector + grid view of storage units and features.
/// Drill in: Unit → Levels → Areas → Parts/Bins.
/// Long press: Rotate, edit, remove units on the grid.
struct WarehouseLocationsPage: View {
    @EnvironmentObject private var appCore: AppCore

    @State private var floorPlans: [WarehouseFloorPlan] = []
    @State private var selectedPlanId: Int64?
    @State private var storageUnits: [WarehouseStorageUnit] = []
    @State private var floorFeatures: [WarehouseFloorFeature] = []
    @State private var isLoading = true
    @State private var loadError: String?
    @State private var activeSheet: ActiveSheet?
    @State private var selectedUnitId: Int64?
    @State private var searchText = ""

    // Grid state
    @State private var gridScale: CGFloat = 1.0
    @State private var gridOffset: CGSize = .zero

    enum ActiveSheet: Identifiable {
        case addUnit(String)
        case editUnit(WarehouseStorageUnit)
        case unitDetail(WarehouseStorageUnit)
        case addFeature
        case createFloorPlan
        case help
        case stickerChecklist(Int64)

        var id: String {
            switch self {
            case .addUnit(let type): return "addUnit-\(type)"
            case .editUnit(let unit): return "editUnit-\(unit.id ?? 0)"
            case .unitDetail(let unit): return "unitDetail-\(unit.id ?? 0)"
            case .addFeature: return "addFeature"
            case .createFloorPlan: return "createFloorPlan"
            case .help: return "help"
            case .stickerChecklist(let id): return "sticker-\(id)"
            }
        }
    }

    private var selectedPlan: WarehouseFloorPlan? {
        floorPlans.first { $0.id == selectedPlanId }
    }

    var body: some View {
        VStack(spacing: 0) {
            OnboardingBanner(pageId: "warehouse-locations")

            if isLoading {
                ProgressView("Loading floor plans...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error = loadError {
                ErrorStateView(message: error) { loadData() }
            } else if floorPlans.isEmpty {
                noFloorPlanState
            } else {
                floorPlanContent
            }
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button { activeSheet = .createFloorPlan } label: {
                        Label("New Floor Plan", systemImage: "plus.rectangle")
                    }
                    Button { activeSheet = .addFeature } label: {
                        Label("Add Feature", systemImage: "door.left.hand.open")
                    }
                } label: {
                    Image(systemName: "plus")
                }
            }
            ToolbarItem(placement: .primaryAction) {
                Button { activeSheet = .help } label: {
                    Image(systemName: "questionmark.circle")
                }
            }
        }
        .sheet(item: $activeSheet) { sheet in
            sheetContent(for: sheet)
                .environmentObject(appCore)
        }
        .searchable(text: $searchText, prompt: "Search locations...")
        .refreshable { loadData() }
        .background(DS.Background.page)
        .task {
            loadData()
            appCore.onboardingManager?.markCompleted("wh-locations-view")
        }
    }

    // MARK: - Floor Plan Content

    @ViewBuilder
    private var floorPlanContent: some View {
        VStack(spacing: 0) {
            // Floor plan selector
            if floorPlans.count > 1 {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(floorPlans, id: \.id) { plan in
                            Button {
                                selectedPlanId = plan.id
                                loadPlanData()
                            } label: {
                                Text(plan.name)
                                    .font(.subheadline)
                                    .fontWeight(selectedPlanId == plan.id ? .bold : .regular)
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 8)
                                    .background(selectedPlanId == plan.id ? Color.blue : Color.gray.opacity(0.15))
                                    .foregroundStyle(selectedPlanId == plan.id ? .white : .primary)
                                    .clipShape(Capsule())
                            }
                        }
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 8)
                }
            }

            if let plan = selectedPlan {
                // Unit type toolbar
                unitTypeToolbar

                // Floor plan grid
                floorPlanGrid(plan: plan)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                // Movable storage section
                movableStorageSection
            }
        }
    }

    // MARK: - Unit Type Toolbar

    @ViewBuilder
    private var unitTypeToolbar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                unitTypeButton("Shelf", type: "shelving", icon: "cabinet.fill")
                unitTypeButton("Pipe Rack", type: "pipe_rack", icon: "lines.measurement.horizontal")
                unitTypeButton("Gang Box", type: "gang_box", icon: "shippingbox.fill")
                unitTypeButton("Wall Mount", type: "wall_mount", icon: "rectangle.portrait.and.arrow.right")
                unitTypeButton("Cabinet", type: "cabinet", icon: "cabinet.fill")
                unitTypeButton("Pallet Rack", type: "pallet_rack", icon: "square.stack.3d.up.fill")
                unitTypeButton("Floor Area", type: "floor_area", icon: "square.dashed")
                unitTypeButton("Custom", type: "custom", icon: "plus.square")
            }
            .padding(.horizontal)
            .padding(.vertical, 6)
        }
        .background(Color(.secondarySystemBackground))
    }

    @ViewBuilder
    private func unitTypeButton(_ label: String, type: String, icon: String) -> some View {
        Button { activeSheet = .addUnit(type) } label: {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.caption2)
                Text(label)
                    .font(.caption)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color.blue.opacity(0.1))
            .foregroundStyle(.blue)
            .clipShape(Capsule())
        }
    }

    // MARK: - Floor Plan Grid

    @ViewBuilder
    private func floorPlanGrid(plan: WarehouseFloorPlan) -> some View {
        let gridCols = plan.widthInches / 24  // 1 cell = 2ft
        let gridRows = plan.lengthInches / 24
        let cellSize: CGFloat = 40

        GeometryReader { geo in
            ScrollView([.horizontal, .vertical], showsIndicators: true) {
                ZStack(alignment: .topLeading) {
                    // Grid background
                    Canvas { context, size in
                        for col in 0...gridCols {
                            let x = CGFloat(col) * cellSize
                            var path = Path()
                            path.move(to: CGPoint(x: x, y: 0))
                            path.addLine(to: CGPoint(x: x, y: CGFloat(gridRows) * cellSize))
                            context.stroke(path, with: .color(.gray.opacity(0.2)), lineWidth: 0.5)
                        }
                        for row in 0...gridRows {
                            let y = CGFloat(row) * cellSize
                            var path = Path()
                            path.move(to: CGPoint(x: 0, y: y))
                            path.addLine(to: CGPoint(x: CGFloat(gridCols) * cellSize, y: y))
                            context.stroke(path, with: .color(.gray.opacity(0.2)), lineWidth: 0.5)
                        }
                    }
                    .frame(width: CGFloat(gridCols) * cellSize, height: CGFloat(gridRows) * cellSize)

                    // Floor features
                    ForEach(floorFeatures, id: \.id) { feature in
                        featureView(feature, cellSize: cellSize)
                    }

                    // Storage units
                    ForEach(storageUnits.filter({ $0.gridX != nil && $0.gridY != nil }), id: \.id) { unit in
                        storageUnitView(unit, cellSize: cellSize)
                    }
                }
                .frame(
                    width: max(CGFloat(gridCols) * cellSize, geo.size.width),
                    height: max(CGFloat(gridRows) * cellSize, geo.size.height)
                )
            }
        }
    }

    @ViewBuilder
    private func featureView(_ feature: WarehouseFloorFeature, cellSize: CGFloat) -> some View {
        let x = CGFloat(feature.gridX) * cellSize
        let y = CGFloat(feature.gridY) * cellSize
        let w = CGFloat(feature.gridWidth) * cellSize
        let h = CGFloat(feature.gridHeight) * cellSize

        RoundedRectangle(cornerRadius: 4)
            .fill(featureColor(feature.featureType).opacity(0.2))
            .overlay(
                RoundedRectangle(cornerRadius: 4)
                    .strokeBorder(featureColor(feature.featureType).opacity(0.5), style: StrokeStyle(lineWidth: 1, dash: [4]))
            )
            .overlay {
                VStack(spacing: 1) {
                    Image(systemName: featureIcon(feature.featureType))
                        .font(.caption2)
                    if let label = feature.label {
                        Text(label)
                            .font(.system(size: 8))
                    }
                }
                .foregroundStyle(featureColor(feature.featureType))
            }
            .frame(width: w, height: h)
            .offset(x: x, y: y)
    }

    @ViewBuilder
    private func storageUnitView(_ unit: WarehouseStorageUnit, cellSize: CGFloat) -> some View {
        let x = CGFloat(unit.gridX ?? 0) * cellSize
        let y = CGFloat(unit.gridY ?? 0) * cellSize
        let w = CGFloat(unit.gridWidth ?? 1) * cellSize
        let h = CGFloat(unit.gridHeight ?? 1) * cellSize

        RoundedRectangle(cornerRadius: 4)
            .fill(unitColor(unit.unitType))
            .overlay(
                RoundedRectangle(cornerRadius: 4)
                    .strokeBorder(.white.opacity(0.3), lineWidth: 1)
            )
            .overlay {
                VStack(spacing: 1) {
                    Text(unit.name)
                        .font(.system(size: 9, weight: .bold))
                        .lineLimit(1)
                    Text(unitTypeLabel(unit.unitType))
                        .font(.system(size: 7))
                }
                .foregroundStyle(.white)
            }
            .frame(width: w - 2, height: h - 2)
            .offset(x: x + 1, y: y + 1)
            .onTapGesture {
                activeSheet = .unitDetail(unit)
            }
            .contextMenu {
                Button { rotateUnit(unit) } label: {
                    Label("Rotate 90\u{00B0}", systemImage: "rotate.right")
                }
                Button { activeSheet = .editUnit(unit) } label: {
                    Label("Edit", systemImage: "pencil")
                }
                if let unitId = unit.id {
                    Button { activeSheet = .stickerChecklist(unitId) } label: {
                        Label("Sticker Checklist", systemImage: "tag")
                    }
                }
                Divider()
                Button(role: .destructive) { deleteUnit(unit) } label: {
                    Label("Remove", systemImage: "trash")
                }
            }
    }

    // MARK: - Movable Storage Section

    @ViewBuilder
    private var movableStorageSection: some View {
        let movable = storageUnits.filter { $0.isMovable }
        if !movable.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Text("Movable Storage")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(movable, id: \.id) { unit in
                            Button { activeSheet = .unitDetail(unit) } label: {
                                VStack(spacing: 4) {
                                    Image(systemName: unitIcon(unit.unitType))
                                        .font(.title3)
                                    Text(unit.name)
                                        .font(.caption)
                                        .fontWeight(.medium)
                                    Text(unit.currentLocationType?.capitalized ?? "Shop")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                                .frame(width: 80, height: 70)
                                .background(Color(.tertiarySystemBackground))
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal)
                }
            }
            .padding(.vertical, 8)
            .background(Color(.secondarySystemBackground))
        }
    }

    // MARK: - No Floor Plan State

    @ViewBuilder
    private var noFloorPlanState: some View {
        VStack(spacing: 16) {
            Image(systemName: "map")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text("No Floor Plans")
                .font(.title3)
                .fontWeight(.semibold)
            Text("Create a floor plan to start mapping your warehouse layout.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
            Button {
                activeSheet = .createFloorPlan
            } label: {
                Label("Create Floor Plan", systemImage: "plus.rectangle")
                    .fontWeight(.medium)
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Sheet Content

    @ViewBuilder
    private func sheetContent(for sheet: ActiveSheet) -> some View {
        switch sheet {
        case .createFloorPlan:
            CreateFloorPlanSheet { loadData() }
        case .addUnit(let unitType):
            if let planId = selectedPlanId {
                AddStorageUnitSheet(floorPlanId: planId, unitType: unitType) { loadPlanData() }
            }
        case .editUnit(let unit):
            EditStorageUnitSheet(unit: unit) { loadPlanData() }
        case .unitDetail(let unit):
            StorageUnitDetailSheet(unit: unit)
        case .addFeature:
            if let planId = selectedPlanId {
                AddFloorFeatureSheet(floorPlanId: planId) { loadPlanData() }
            }
        case .help:
            PageHelpSheet(
                title: "Floor Plan Help",
                sections: [
                    ("Overview", "Visually map your warehouse with a grid-based floor plan. Place storage units, mark features like doors and walkways."),
                    ("Adding Units", "Tap a unit type from the toolbar to add it. Configure dimensions, levels, and areas in the sheet."),
                    ("Navigation", "Tap a unit to drill into its levels and areas. Long press for rotate, edit, and remove options."),
                    ("Stickers", "After configuring a unit, use the sticker checklist to label all location codes (e.g. R01-U01-S02-A04).")
                ]
            )
        case .stickerChecklist(let unitId):
            StickerChecklistSheet(unitId: unitId)
        }
    }

    // MARK: - Actions

    private func rotateUnit(_ unit: WarehouseStorageUnit) {
        guard let service = appCore.warehouseService, let unitId = unit.id else {
            loadError = "Service not available"
            return
        }
        let newRotation = (unit.rotation + 90) % 360
        // Swap grid width/height on rotation
        let newW = unit.gridHeight
        let newH = unit.gridWidth
        do {
            try service.updateStorageUnit(id: unitId, gridWidth: newW, gridHeight: newH, rotation: newRotation)
            loadPlanData()
        } catch {
            loadError = userFriendlyError(error, context: "load locations")
        }
    }

    private func deleteUnit(_ unit: WarehouseStorageUnit) {
        guard let service = appCore.warehouseService, let unitId = unit.id else {
            loadError = "Service not available"
            return
        }
        do {
            try service.deleteStorageUnit(id: unitId)
            loadPlanData()
        } catch {
            loadError = userFriendlyError(error, context: "load locations")
        }
    }

    // MARK: - Data Loading

    private func loadData() {
        guard let service = appCore.warehouseService else {
            loadError = "Warehouse service unavailable"
            isLoading = false
            return
        }

        isLoading = floorPlans.isEmpty
        loadError = nil

        do {
            floorPlans = try service.listFloorPlans()
            if selectedPlanId == nil {
                selectedPlanId = floorPlans.first?.id
            }
            loadPlanData()
        } catch {
            loadError = userFriendlyError(error, context: "load locations")
        }
        isLoading = false
    }

    private func loadPlanData() {
        guard let service = appCore.warehouseService, let planId = selectedPlanId else {
            loadError = "Service not available"
            isLoading = false
            return
        }
        do {
            storageUnits = try service.listStorageUnits(floorPlanId: planId)
            floorFeatures = try service.listFloorFeatures(floorPlanId: planId)
        } catch {
            loadError = userFriendlyError(error, context: "load locations")
        }
    }

    // MARK: - Helpers

    private func unitColor(_ type: String) -> Color {
        switch type {
        case "shelving": .blue
        case "pipe_rack": .orange
        case "gang_box": .green
        case "pallet_rack": .purple
        case "wall_mount": .teal
        case "cabinet": .indigo
        case "floor_area": .brown
        default: .gray
        }
    }

    private func unitIcon(_ type: String) -> String {
        switch type {
        case "shelving": "cabinet.fill"
        case "pipe_rack": "lines.measurement.horizontal"
        case "gang_box": "shippingbox.fill"
        case "pallet_rack": "square.stack.3d.up.fill"
        case "wall_mount": "rectangle.portrait.and.arrow.right"
        case "cabinet": "cabinet.fill"
        case "floor_area": "square.dashed"
        case "tool_bag": "bag.fill"
        case "packout": "archivebox.fill"
        default: "square.fill"
        }
    }

    private func unitTypeLabel(_ type: String) -> String {
        switch type {
        case "shelving": "Shelf"
        case "pipe_rack": "Pipe Rack"
        case "gang_box": "Gang Box"
        case "pallet_rack": "Pallet Rack"
        case "wall_mount": "Wall Mount"
        case "cabinet": "Cabinet"
        case "floor_area": "Floor Area"
        case "packout": "Packout"
        case "tool_bag": "Tool Bag"
        case "parts_bin": "Parts Bin"
        case "crate": "Crate"
        default: type.replacingOccurrences(of: "_", with: " ").capitalized
        }
    }

    private func featureColor(_ type: String) -> Color {
        switch type {
        case "door", "loading_dock": .brown
        case "walkway": .gray
        case "office": .blue
        case "bathroom": .cyan
        case "electrical_panel": .red
        case "staging", "incoming": .orange
        case "returns": .pink
        default: .gray
        }
    }

    private func featureIcon(_ type: String) -> String {
        switch type {
        case "door": "door.left.hand.open"
        case "loading_dock": "truck.box.fill"
        case "walkway": "figure.walk"
        case "office": "desktopcomputer"
        case "bathroom": "drop.fill"
        case "electrical_panel": "bolt.fill"
        case "staging": "tray.full.fill"
        case "incoming": "arrow.down.to.line"
        case "returns": "arrow.uturn.left"
        default: "mappin"
        }
    }
}

// MARK: - Create Floor Plan Sheet

private struct CreateFloorPlanSheet: View {
    @EnvironmentObject private var appCore: AppCore
    @Environment(\.dismiss) private var dismiss
    let onCreated: () -> Void

    @State private var name = ""
    @State private var widthFeet = 40
    @State private var lengthFeet = 60
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("Floor Plan Details") {
                    TextField("Name", text: $name)
                    Stepper("Width: \(widthFeet) ft", value: $widthFeet, in: 10...500, step: 5)
                    Stepper("Length: \(lengthFeet) ft", value: $lengthFeet, in: 10...500, step: 5)
                }

                if let error {
                    Section {
                        Text(error).foregroundStyle(.red).font(.caption)
                    }
                }
            }
            .navigationTitle("New Floor Plan")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") { createPlan() }
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }

    private func createPlan() {
        guard let service = appCore.warehouseService else {
            error = "Warehouse service unavailable"
            return
        }
        do {
            _ = try service.createFloorPlan(
                name: name.trimmingCharacters(in: .whitespaces),
                widthInches: widthFeet * 12,
                lengthInches: lengthFeet * 12
            )
            onCreated()
            dismiss()
        } catch {
            self.error = userFriendlyError(error, context: "load locations")
        }
    }
}

// MARK: - Add Storage Unit Sheet

private struct AddStorageUnitSheet: View {
    @EnvironmentObject private var appCore: AppCore
    @Environment(\.dismiss) private var dismiss
    let floorPlanId: Int64
    let unitType: String
    let onCreated: () -> Void

    @State private var name = ""
    @State private var rowNumber = ""
    @State private var unitNumber = ""
    @State private var widthInches = 48
    @State private var depthInches = 24
    @State private var heightInches = 72
    @State private var levelCount = 4
    @State private var areasPerLevel = 4
    @State private var gridX = 0
    @State private var gridY = 0
    @State private var gridWidth = 2
    @State private var gridHeight = 1
    @State private var frontFace = "south"
    @State private var isMovable = false
    @State private var isJobReady = false
    @State private var error: String?

    private let faceOptions = ["north", "south", "east", "west"]

    var body: some View {
        NavigationStack {
            Form {
                Section("Identity") {
                    TextField("Name", text: $name)
                    TextField("Row (e.g. R01)", text: $rowNumber)
                    TextField("Unit (e.g. U01)", text: $unitNumber)
                }

                Section("Dimensions") {
                    Stepper("Width: \(widthInches)\"", value: $widthInches, in: 6...240, step: 6)
                    Stepper("Depth: \(depthInches)\"", value: $depthInches, in: 6...120, step: 6)
                    Stepper("Height: \(heightInches)\"", value: $heightInches, in: 12...240, step: 6)
                }

                Section("Grid Placement") {
                    Stepper("X: \(gridX)", value: $gridX, in: 0...100)
                    Stepper("Y: \(gridY)", value: $gridY, in: 0...100)
                    Stepper("Width: \(gridWidth) cells", value: $gridWidth, in: 1...10)
                    Stepper("Height: \(gridHeight) cells", value: $gridHeight, in: 1...10)
                }

                Section("Configuration") {
                    Stepper("Levels: \(levelCount)", value: $levelCount, in: 1...20)
                    Stepper("Areas/Level: \(areasPerLevel)", value: $areasPerLevel, in: 1...24)
                    Picker("Front Face", selection: $frontFace) {
                        ForEach(faceOptions, id: \.self) { Text($0.capitalized) }
                    }
                }

                Section("Options") {
                    Toggle("Movable", isOn: $isMovable)
                    Toggle("Job-Ready", isOn: $isJobReady)
                }

                if let error {
                    Section { Text(error).foregroundStyle(.red).font(.caption) }
                }
            }
            .navigationTitle("Add \(unitType.replacingOccurrences(of: "_", with: " ").capitalized)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") { create() }
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }

    private func create() {
        guard let service = appCore.warehouseService else {
            error = "Warehouse service unavailable"
            return
        }
        do {
            let unit = try service.addStorageUnit(
                floorPlanId: floorPlanId,
                name: name.trimmingCharacters(in: .whitespaces),
                unitType: unitType,
                rowNumber: rowNumber.isEmpty ? nil : rowNumber,
                unitNumber: unitNumber.isEmpty ? nil : unitNumber,
                widthInches: widthInches,
                depthInches: depthInches,
                heightInches: heightInches,
                gridX: gridX,
                gridY: gridY,
                gridWidth: gridWidth,
                gridHeight: gridHeight,
                frontFace: frontFace,
                isMovable: isMovable,
                isJobReady: isJobReady
            )

            // Auto-create levels and areas
            if let unitId = unit.id {
                for i in 0..<levelCount {
                    let code: String
                    let levelName: String
                    if i == 0 {
                        code = "G0"
                        levelName = "Ground Zero"
                    } else if i == levelCount - 1 && levelCount > 2 {
                        code = "ST"
                        levelName = "Top"
                    } else {
                        code = String(format: "S%02d", i)
                        levelName = "Shelf \(i)"
                    }
                    let level = try service.addStorageLevel(
                        unitId: unitId, levelCode: code, levelName: levelName,
                        order: i, areaCount: areasPerLevel
                    )
                    if let levelId = level.id {
                        for a in 1...areasPerLevel {
                            _ = try service.addStorageArea(levelId: levelId, areaNumber: a)
                        }
                    }
                }
                try service.updateStorageUnit(id: unitId, isConfigured: true)
            }

            onCreated()
            dismiss()
        } catch {
            self.error = userFriendlyError(error, context: "load locations")
        }
    }
}

// MARK: - Edit Storage Unit Sheet

private struct EditStorageUnitSheet: View {
    @EnvironmentObject private var appCore: AppCore
    @Environment(\.dismiss) private var dismiss
    let unit: WarehouseStorageUnit
    let onUpdated: () -> Void

    @State private var name: String
    @State private var rowNumber: String
    @State private var unitNumber: String
    @State private var gridX: Int
    @State private var gridY: Int
    @State private var gridWidth: Int
    @State private var gridHeight: Int
    @State private var frontFace: String
    @State private var error: String?

    private let faceOptions = ["north", "south", "east", "west"]

    init(unit: WarehouseStorageUnit, onUpdated: @escaping () -> Void) {
        self.unit = unit
        self.onUpdated = onUpdated
        _name = State(initialValue: unit.name)
        _rowNumber = State(initialValue: unit.rowNumber ?? "")
        _unitNumber = State(initialValue: unit.unitNumber ?? "")
        _gridX = State(initialValue: unit.gridX ?? 0)
        _gridY = State(initialValue: unit.gridY ?? 0)
        _gridWidth = State(initialValue: unit.gridWidth ?? 1)
        _gridHeight = State(initialValue: unit.gridHeight ?? 1)
        _frontFace = State(initialValue: unit.frontFace ?? "south")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Identity") {
                    TextField("Name", text: $name)
                    TextField("Row (e.g. R01)", text: $rowNumber)
                    TextField("Unit (e.g. U01)", text: $unitNumber)
                }

                Section("Grid Placement") {
                    Stepper("X: \(gridX)", value: $gridX, in: 0...100)
                    Stepper("Y: \(gridY)", value: $gridY, in: 0...100)
                    Stepper("Width: \(gridWidth) cells", value: $gridWidth, in: 1...10)
                    Stepper("Height: \(gridHeight) cells", value: $gridHeight, in: 1...10)
                }

                Section("Orientation") {
                    Picker("Front Face", selection: $frontFace) {
                        ForEach(faceOptions, id: \.self) { Text($0.capitalized) }
                    }
                }

                if let error {
                    Section { Text(error).foregroundStyle(.red).font(.caption) }
                }
            }
            .navigationTitle("Edit Unit")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                }
            }
        }
    }

    private func save() {
        guard let service = appCore.warehouseService, let unitId = unit.id else {
            error = "Service unavailable"
            return
        }
        do {
            try service.updateStorageUnit(
                id: unitId,
                name: name,
                rowNumber: rowNumber.isEmpty ? nil : rowNumber,
                unitNumber: unitNumber.isEmpty ? nil : unitNumber,
                gridX: gridX, gridY: gridY,
                gridWidth: gridWidth, gridHeight: gridHeight,
                frontFace: frontFace
            )
            onUpdated()
            dismiss()
        } catch {
            self.error = userFriendlyError(error, context: "load locations")
        }
    }
}

// MARK: - Storage Unit Detail Sheet (Drill-Down)

private struct StorageUnitDetailSheet: View {
    @EnvironmentObject private var appCore: AppCore
    @Environment(\.dismiss) private var dismiss
    let unit: WarehouseStorageUnit

    @State private var levels: [WarehouseStorageLevel] = []
    @State private var expandedLevelId: Int64?
    @State private var areasForLevel: [Int64: [WarehouseStorageArea]] = [:]
    @State private var areaContents: [Int64: [WarehouseService.AreaContentsItem]] = [:]
    @State private var loadError: String?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    LabeledContent("Type", value: unit.unitType.replacingOccurrences(of: "_", with: " ").capitalized)
                    if let row = unit.rowNumber { LabeledContent("Row", value: row) }
                    if let un = unit.unitNumber { LabeledContent("Unit", value: un) }
                    if unit.isMovable {
                        LabeledContent("Location", value: unit.currentLocationType?.capitalized ?? "Shop")
                    }
                }

                Section("Levels") {
                    if levels.isEmpty {
                        Text("No levels configured")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(levels, id: \.id) { level in
                        DisclosureGroup(
                            isExpanded: Binding(
                                get: { expandedLevelId == level.id },
                                set: { expanded in
                                    expandedLevelId = expanded ? level.id : nil
                                    if expanded, let levelId = level.id {
                                        loadAreas(levelId: levelId)
                                    }
                                }
                            )
                        ) {
                            if let levelId = level.id, let areas = areasForLevel[levelId] {
                                ForEach(areas, id: \.id) { area in
                                    areaRow(area)
                                }
                            }
                        } label: {
                            HStack {
                                Text(level.levelName ?? level.levelCode)
                                    .fontWeight(.medium)
                                Text("(\(level.levelCode))")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Spacer()
                                Text("\(level.areaCount) areas")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }

                if let error = loadError {
                    Section {
                        Text(error).foregroundStyle(.red).font(.caption)
                    }
                }
            }
            .navigationTitle(unit.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .task { loadLevels() }
        }
    }

    @ViewBuilder
    private func areaRow(_ area: WarehouseStorageArea) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(area.areaCode)
                    .font(.subheadline)
                    .fontWeight(.medium)
                if let code = area.fullLocationCode {
                    Text(code)
                        .font(.caption2)
                        .monospaced()
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if area.hasQrCode { Image(systemName: "qrcode").font(.caption).foregroundStyle(.blue) }
                if area.hasSticker { Image(systemName: "tag.fill").font(.caption).foregroundStyle(.green) }
            }

            if let areaId = area.id, let contents = areaContents[areaId] {
                if contents.isEmpty {
                    Text("(empty)")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                } else {
                    ForEach(contents, id: \.partId) { item in
                        HStack(spacing: 4) {
                            Circle()
                                .fill(item.isHome ? Color.green : Color.gray)
                                .frame(width: 6, height: 6)
                            Text(item.partName)
                                .font(.caption)
                            if let pn = item.partNumber {
                                Text("(\(pn))")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
        }
        .task {
            if let areaId = area.id {
                loadAreaContents(areaId: areaId)
            }
        }
    }

    private func loadLevels() {
        guard let service = appCore.warehouseService, let unitId = unit.id else {
            loadError = "Service unavailable"
            return
        }
        do {
            levels = try service.listLevelsForUnit(unitId: unitId)
        } catch {
            loadError = userFriendlyError(error, context: "load locations")
        }
    }

    private func loadAreas(levelId: Int64) {
        guard let service = appCore.warehouseService else {
            loadError = "Service not available"
            return
        }
        do {
            areasForLevel[levelId] = try service.listAreasForLevel(levelId: levelId)
        } catch {
            loadError = userFriendlyError(error, context: "load locations")
        }
    }

    private func loadAreaContents(areaId: Int64) {
        guard let service = appCore.warehouseService else {
            loadError = "Warehouse service not available"
            return
        }
        guard areaContents[areaId] == nil else { return }
        do {
            areaContents[areaId] = try service.getAreaContents(areaId: areaId)
        } catch {
            // Non-critical — just don't show contents
        }
    }
}

// MARK: - Add Floor Feature Sheet

private struct AddFloorFeatureSheet: View {
    @EnvironmentObject private var appCore: AppCore
    @Environment(\.dismiss) private var dismiss
    let floorPlanId: Int64
    let onCreated: () -> Void

    @State private var featureType = "door"
    @State private var label = ""
    @State private var gridX = 0
    @State private var gridY = 0
    @State private var gridWidth = 1
    @State private var gridHeight = 1
    @State private var error: String?

    private let featureTypes = [
        "door", "loading_dock", "walkway", "office", "bathroom",
        "electrical_panel", "staging", "incoming", "returns", "custom"
    ]

    var body: some View {
        NavigationStack {
            Form {
                Section("Feature") {
                    Picker("Type", selection: $featureType) {
                        ForEach(featureTypes, id: \.self) { type in
                            Text(type.replacingOccurrences(of: "_", with: " ").capitalized)
                        }
                    }
                    TextField("Label (optional)", text: $label)
                }

                Section("Grid Placement") {
                    Stepper("X: \(gridX)", value: $gridX, in: 0...100)
                    Stepper("Y: \(gridY)", value: $gridY, in: 0...100)
                    Stepper("Width: \(gridWidth) cells", value: $gridWidth, in: 1...20)
                    Stepper("Height: \(gridHeight) cells", value: $gridHeight, in: 1...20)
                }

                if let error {
                    Section { Text(error).foregroundStyle(.red).font(.caption) }
                }
            }
            .navigationTitle("Add Feature")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") { addFeature() }
                }
            }
        }
    }

    private func addFeature() {
        guard let service = appCore.warehouseService else {
            error = "Service unavailable"
            return
        }
        do {
            _ = try service.addFloorFeature(
                floorPlanId: floorPlanId,
                featureType: featureType,
                label: label.isEmpty ? nil : label,
                gridX: gridX, gridY: gridY,
                gridWidth: gridWidth, gridHeight: gridHeight
            )
            onCreated()
            dismiss()
        } catch {
            self.error = userFriendlyError(error, context: "load locations")
        }
    }
}

// MARK: - Sticker Checklist Sheet

private struct StickerChecklistSheet: View {
    @EnvironmentObject private var appCore: AppCore
    @Environment(\.dismiss) private var dismiss
    let unitId: Int64

    @State private var levels: [WarehouseStorageLevel] = []
    @State private var areasForLevel: [Int64: [WarehouseStorageArea]] = [:]
    @State private var checkedCodes: Set<String> = []
    @State private var loadError: String?

    var body: some View {
        NavigationStack {
            List {
                if let error = loadError {
                    Section {
                        Label(error, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                            .font(.subheadline)
                    }
                }

                Section {
                    Text("Write these codes on stickers and place them on each location.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                ForEach(levels, id: \.id) { level in
                    Section(level.levelName ?? level.levelCode) {
                        if let levelId = level.id, let areas = areasForLevel[levelId] {
                            ForEach(areas, id: \.id) { area in
                                if let code = area.fullLocationCode {
                                    HStack {
                                        Button {
                                            if checkedCodes.contains(code) {
                                                checkedCodes.remove(code)
                                            } else {
                                                checkedCodes.insert(code)
                                            }
                                        } label: {
                                            Image(systemName: checkedCodes.contains(code)
                                                  ? "checkmark.circle.fill" : "circle")
                                                .foregroundStyle(checkedCodes.contains(code) ? .green : .gray)
                                        }

                                        VStack(alignment: .leading) {
                                            Text(code)
                                                .font(.subheadline)
                                                .monospaced()
                                                .fontWeight(.medium)
                                            Text("Write this on a sticker: \(code)")
                                                .font(.caption2)
                                                .foregroundStyle(.secondary)
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Sticker Checklist")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .task { loadData() }
        }
    }

    private func loadData() {
        guard let service = appCore.warehouseService else {
            loadError = "Warehouse service not available"
            return
        }
        do {
            levels = try service.listLevelsForUnit(unitId: unitId)
            for level in levels {
                if let levelId = level.id {
                    areasForLevel[levelId] = try service.listAreasForLevel(levelId: levelId)
                }
            }
        } catch {
            // Non-critical
        }
    }
}
