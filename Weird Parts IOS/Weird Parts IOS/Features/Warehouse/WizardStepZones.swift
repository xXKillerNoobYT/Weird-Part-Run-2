import SwiftUI
import WiredPartCore

/// Wizard Step 2: Define Zones on the saved floor-plan grid.
struct WizardStepZones: View {
    @EnvironmentObject private var appCore: AppCore
    let floorPlanId: Int64
    @Binding var stepError: String?

    @State private var floorPlan: WarehouseFloorPlan?
    @State private var zones: [WarehouseZone] = []
    @State private var selectedZoneId: Int64?
    @State private var selectedRows = 3
    @State private var selectedCols = 5
    @State private var gridDimensions: (rows: Int, cols: Int)?
    @State private var zoneBeingEdited: WarehouseZone?
    @State private var deleteTarget: WarehouseZone?
    @State private var isLoading = true
    @State private var zoom: CGFloat = 1.0

    private let zoneTypes: [(id: String, title: String, icon: String)] = [
        ("storage", "Storage", "cabinet.fill"),
        ("receiving", "Receiving", "arrow.down.circle.fill"),
        ("staging", "Staging", "shippingbox.and.arrow.backward.fill"),
        ("returns", "Returns", "arrow.uturn.backward.circle.fill"),
        ("office", "Office", "building.2.fill"),
        ("tool_storage", "Tool Storage", "wrench.and.screwdriver.fill"),
        ("custom", "Custom", "square.dashed"),
    ]

    var body: some View {
        Group {
            if isLoading {
                ProgressView("Loading zones...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let dims = gridDimensions {
                placementPhase(dims: dims)
            } else {
                dimensionsPhase
            }
        }
        .task { loadData() }
        .sheet(item: $zoneBeingEdited) { zone in
            AddZoneSheet(floorPlanId: floorPlanId, editingZone: zone) {
                loadData()
            }
        }
        .confirmationDialog(
            "Delete Zone?",
            isPresented: Binding(get: { deleteTarget != nil }, set: { if !$0 { deleteTarget = nil } }),
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                deleteSelectedZone()
            }
            Button("Cancel", role: .cancel) { deleteTarget = nil }
        } message: {
            Text("This zone will be permanently removed. Storage units in this zone won't be deleted.")
        }
    }

    private var dimensionsPhase: some View {
        VStack(spacing: 24) {
            Spacer()

            VStack(spacing: 8) {
                Image(systemName: "square.grid.3x3")
                    .font(.largeTitle)
                    .foregroundStyle(.blue)
                Text("Confirm Zone Grid")
                    .font(.title2)
                    .fontWeight(.semibold)
                Text("Zones and storage units share the same floor-plan grid. Confirm dimensions before placing zones.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }

            VStack(spacing: 16) {
                Stepper("Rows: \(selectedRows)", value: $selectedRows, in: 1...20)
                Stepper("Columns: \(selectedCols)", value: $selectedCols, in: 1...20)
                Text("\(selectedRows * selectedCols) grid positions")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding()
            .background(Color(.secondarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .padding(.horizontal)

            Button {
                confirmGrid(rows: selectedRows, cols: selectedCols)
            } label: {
                Text("Confirm Grid")
                    .fontWeight(.semibold)
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
            }
            .buttonStyle(.borderedProminent)
            .padding(.horizontal)

            Spacer()
        }
    }

    private func placementPhase(dims: (rows: Int, cols: Int)) -> some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let layout = zoneLayout(for: width)

            Group {
                switch layout {
                case .phone:
                    phonePlacement(dims: dims)
                case .tablet:
                    tabletPlacement(dims: dims, inspector: false)
                case .wideTablet:
                    tabletPlacement(dims: dims, inspector: true)
                case .desktop:
                    desktopPlacement(dims: dims)
                }
            }
        }
    }

    private func phonePlacement(dims: (rows: Int, cols: Int)) -> some View {
        VStack(spacing: 0) {
            palette
            canvasScroll(dims: dims)
            bottomInspector
        }
    }

    private func tabletPlacement(dims: (rows: Int, cols: Int), inspector: Bool) -> some View {
        HStack(spacing: 0) {
            palette
                .frame(width: 176)
            canvasScroll(dims: dims)
            if inspector {
                inspectorPanel
                    .frame(width: 260)
            }
        }
    }

    private func desktopPlacement(dims: (rows: Int, cols: Int)) -> some View {
        HStack(spacing: 0) {
            palette
                .frame(width: 190)
            VStack(spacing: 0) {
                HStack {
                    Text("Zoom")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Slider(value: $zoom, in: 0.75...1.35)
                        .frame(maxWidth: 260)
                    Spacer()
                    Button("Change Grid") { gridDimensions = nil }
                        .font(.caption)
                }
                .padding(.horizontal)
                .padding(.vertical, 8)
                canvasScroll(dims: dims)
            }
            inspectorPanel
                .frame(width: 280)
        }
    }

    private var palette: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                Text("Zones")
                    .font(.headline)
                    .padding(.horizontal)
                    .padding(.top)

                ForEach(zoneTypes, id: \.id) { type in
                    HStack(spacing: 8) {
                        Image(systemName: type.icon)
                            .frame(width: 24, height: 24)
                            .foregroundStyle(zoneColor(type.id))
                        Text(type.title)
                            .font(.subheadline)
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)
                        Spacer()
                    }
                    .frame(minHeight: 44)
                    .padding(.horizontal, 10)
                    .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 8))
                    .padding(.horizontal)
                    .draggable("new:\(type.id)")
                    .accessibilityLabel("Drag \(type.title) zone")
                }

                if zones.isEmpty {
                    EmptyStateView(
                        icon: "rectangle.3.group",
                        title: "No Zones",
                        message: "Drag a zone type onto the grid."
                    )
                    .padding(.top, 24)
                }
            }
        }
        .background(Color(.systemGroupedBackground))
    }

    private func canvasScroll(dims: (rows: Int, cols: Int)) -> some View {
        ScrollView([.horizontal, .vertical]) {
            ZoneGridCanvas(
                rows: dims.rows,
                cols: dims.cols,
                zones: zones,
                selectedZoneId: selectedZoneId,
                zoom: zoom,
                onCreateZone: createZone,
                onMoveZone: moveZone,
                onResizeZone: resizeZone,
                onSelectZone: { selectedZoneId = $0?.id }
            )
            .padding()
        }
        .background(Color(.systemBackground))
        .overlay {
            if let error = stepError {
                VStack {
                    Spacer()
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.white)
                        .padding()
                        .frame(maxWidth: .infinity)
                        .background(Color.red)
                }
            }
        }
    }

    private var bottomInspector: some View {
        inspectorPanel
            .frame(maxHeight: 164)
            .background(Color(.secondarySystemBackground))
    }

    private var inspectorPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let zone = selectedZone {
                HStack {
                    Image(systemName: zoneIcon(zone.zoneType))
                        .foregroundStyle(zoneColor(zone.zoneType))
                    Text(zoneTitle(zone))
                        .font(.headline)
                        .lineLimit(1)
                    Spacer()
                }
                Text("\(zone.zoneTypeDisplay) at R\(zone.gridY + 1)C\(zone.gridX + 1), \(zone.gridWidth)x\(zone.gridHeight)")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                HStack {
                    Button {
                        resizeZone(zone, width: zone.gridWidth + 1, height: zone.gridHeight + 1)
                    } label: {
                        Label("Grow", systemImage: "arrow.down.right.and.arrow.up.left")
                    }
                    .buttonStyle(.bordered)

                    Button {
                        zoneBeingEdited = zone
                    } label: {
                        Label("Edit", systemImage: "pencil")
                    }
                    .buttonStyle(.bordered)

                    Button(role: .destructive) {
                        deleteTarget = zone
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                    .buttonStyle(.bordered)
                }
            } else {
                EmptyStateView(
                    icon: "cursorarrow.click.2",
                    title: "Select a Zone",
                    message: "Tap a placed zone to edit or delete it."
                )
            }

            Spacer(minLength: 0)
        }
        .padding()
        .background(Color(.secondarySystemBackground))
    }

    private var selectedZone: WarehouseZone? {
        zones.first { $0.id == selectedZoneId }
    }

    private func loadData() {
        do {
            floorPlan = try appCore.warehouseService?.getFloorPlan(id: floorPlanId)
            zones = try appCore.warehouseService?.listZones(floorPlanId: floorPlanId) ?? []
            if let fp = floorPlan, let rows = fp.gridRows, let cols = fp.gridCols {
                selectedRows = rows
                selectedCols = cols
                gridDimensions = (rows: rows, cols: cols)
            }
            isLoading = false
        } catch {
            isLoading = false
            stepError = userFriendlyError(error, context: "load zones")
        }
    }

    private func confirmGrid(rows: Int, cols: Int) {
        do {
            try appCore.warehouseService?.updateFloorPlanGrid(floorPlanId: floorPlanId, rows: rows, cols: cols)
            gridDimensions = (rows: rows, cols: cols)
            loadData()
        } catch {
            stepError = userFriendlyError(error, context: "save grid dimensions")
        }
    }

    private func createZone(type: String, col: Int, row: Int) {
        guard canPlaceZone(id: nil, col: col, row: row, width: 1, height: 1) else {
            stepError = "That spot is already occupied or outside the grid."
            return
        }
        do {
            let zone = try appCore.warehouseService?.addZone(
                floorPlanId: floorPlanId,
                zoneType: type,
                label: nil,
                gridX: col,
                gridY: row,
                gridWidth: 1,
                gridHeight: 1,
                zoneOrder: zones.count
            )
            selectedZoneId = zone?.id
            loadData()
        } catch {
            stepError = userFriendlyError(error, context: "place zone")
        }
    }

    private func moveZone(_ zone: WarehouseZone, col: Int, row: Int) {
        guard let zoneId = zone.id, let dims = gridDimensions else { return }
        let nextCol = min(col, max(dims.cols - zone.gridWidth, 0))
        let nextRow = min(row, max(dims.rows - zone.gridHeight, 0))
        guard canPlaceZone(id: zoneId, col: nextCol, row: nextRow, width: zone.gridWidth, height: zone.gridHeight) else {
            stepError = "That move would overlap another zone."
            return
        }
        do {
            try appCore.warehouseService?.updateZone(
                id: zoneId,
                gridX: nextCol,
                gridY: nextRow
            )
            selectedZoneId = zoneId
            loadData()
        } catch {
            stepError = userFriendlyError(error, context: "move zone")
        }
    }

    private func resizeZone(_ zone: WarehouseZone, width: Int, height: Int) {
        guard let zoneId = zone.id, let dims = gridDimensions else { return }
        let nextWidth = min(width, max(dims.cols - zone.gridX, 1))
        let nextHeight = min(height, max(dims.rows - zone.gridY, 1))
        guard canPlaceZone(id: zoneId, col: zone.gridX, row: zone.gridY, width: nextWidth, height: nextHeight) else {
            stepError = "That resize would overlap another zone."
            return
        }
        do {
            try appCore.warehouseService?.updateZone(
                id: zoneId,
                gridWidth: nextWidth,
                gridHeight: nextHeight
            )
            selectedZoneId = zoneId
            loadData()
        } catch {
            stepError = userFriendlyError(error, context: "resize zone")
        }
    }

    private func deleteSelectedZone() {
        guard let zoneId = deleteTarget?.id else { return }
        do {
            try appCore.warehouseService?.deleteZone(id: zoneId)
            deleteTarget = nil
            selectedZoneId = nil
            loadData()
        } catch {
            stepError = userFriendlyError(error, context: "delete zone")
        }
    }

    private func canPlaceZone(id: Int64?, col: Int, row: Int, width: Int, height: Int) -> Bool {
        guard let dims = gridDimensions,
              col >= 0,
              row >= 0,
              width > 0,
              height > 0,
              col + width <= dims.cols,
              row + height <= dims.rows
        else { return false }

        return !zones.contains { other in
            if let id, other.id == id { return false }
            return rectanglesOverlap(
                lhsX: col,
                lhsY: row,
                lhsWidth: width,
                lhsHeight: height,
                rhsX: other.gridX,
                rhsY: other.gridY,
                rhsWidth: other.gridWidth,
                rhsHeight: other.gridHeight
            )
        }
    }

    private func rectanglesOverlap(
        lhsX: Int,
        lhsY: Int,
        lhsWidth: Int,
        lhsHeight: Int,
        rhsX: Int,
        rhsY: Int,
        rhsWidth: Int,
        rhsHeight: Int
    ) -> Bool {
        lhsX < rhsX + rhsWidth &&
            lhsX + lhsWidth > rhsX &&
            lhsY < rhsY + rhsHeight &&
            lhsY + lhsHeight > rhsY
    }

    private func zoneLayout(for width: CGFloat) -> ZonePlacementLayout {
        if width >= 1180 { return .desktop }
        if width >= 900 { return .wideTablet }
        if width >= 700 { return .tablet }
        return .phone
    }

    private func zoneTitle(_ zone: WarehouseZone) -> String {
        let trimmed = zone.label?.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed?.isEmpty == false ? trimmed! : zone.zoneTypeDisplay
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

private enum ZonePlacementLayout {
    case phone
    case tablet
    case wideTablet
    case desktop
}

// MARK: - Add Zone Sheet

struct AddZoneSheet: View {
    @EnvironmentObject private var appCore: AppCore
    @Environment(\.dismiss) private var dismiss

    let floorPlanId: Int64
    var editingZone: WarehouseZone?
    var onSave: () -> Void

    @State private var zoneType: String
    @State private var zoneName: String
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

    init(floorPlanId: Int64, editingZone: WarehouseZone? = nil, onSave: @escaping () -> Void) {
        self.floorPlanId = floorPlanId
        self.editingZone = editingZone
        self.onSave = onSave
        _zoneType = State(initialValue: editingZone?.zoneType ?? "storage")
        _zoneName = State(initialValue: editingZone?.label ?? "")
    }

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
            .navigationTitle(editingZone == nil ? "Add Zone" : "Edit Zone")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(editingZone == nil ? "Add" : "Save") { saveZone() }
                }
            }
        }
    }

    private func saveZone() {
        do {
            let trimmed = zoneName.trimmingCharacters(in: .whitespacesAndNewlines)
            let label = trimmed.isEmpty ? nil : trimmed
            if let zoneId = editingZone?.id {
                try appCore.warehouseService?.updateZone(id: zoneId, zoneType: zoneType, label: label)
            } else {
                _ = try appCore.warehouseService?.addZone(
                    floorPlanId: floorPlanId,
                    zoneType: zoneType,
                    label: label
                )
            }
            dismiss()
            onSave()
        } catch {
            saveError = userFriendlyError(error, context: editingZone == nil ? "add zone" : "update zone")
        }
    }
}

private extension WarehouseZone {
    var zoneTypeDisplay: String {
        zoneType.replacingOccurrences(of: "_", with: " ").capitalized
    }
}
