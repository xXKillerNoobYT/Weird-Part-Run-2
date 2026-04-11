import SwiftUI
import WiredPartCore

/// Wizard Step 4: Place Units on Floor Plan.
///
/// Two-phase UI (PE-040):
///   - Phase A: User enters grid dimensions (rows × cols) if not yet saved.
///   - Phase B: User drags storage unit chips onto the grid cells.
///
/// Phase transitions when the user taps "Confirm Grid" and persists `grid_rows`/`grid_cols`
/// to the floor plan row via `WarehouseService.updateFloorPlanGrid(...)`.
struct WizardStepPlacement: View {
    @EnvironmentObject private var appCore: AppCore
    let floorPlanId: Int64
    @Binding var stepError: String?

    @State private var zones: [WarehouseZone] = []
    @State private var units: [WarehouseStorageUnit] = []
    @State private var floorPlan: WarehouseFloorPlan?

    // Phase A — dimensions input
    @State private var selectedRows: Int = 3
    @State private var selectedCols: Int = 5
    @State private var gridDimensions: (rows: Int, cols: Int)?  // nil = Phase A

    // Phase B — drag-and-drop
    @State private var draggingUnitId: Int64?

    private let cellSize: CGFloat = 60

    var body: some View {
        Group {
            if let dims = gridDimensions {
                dragDropPhase(dims: dims)
            } else {
                dimensionsPhase
            }
        }
        .task { loadData() }
    }

    // MARK: - Phase A: Dimensions Input

    private var dimensionsPhase: some View {
        VStack(spacing: 24) {
            Spacer()

            VStack(spacing: 8) {
                Image(systemName: "grid")
                    .font(.largeTitle)
                    .foregroundStyle(.blue)
                Text("Define Your Grid")
                    .font(.title2)
                    .fontWeight(.semibold)
                Text("Set how many rows and columns your warehouse floor plan should have.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }

            VStack(spacing: 16) {
                Stepper("Rows: \(selectedRows)", value: $selectedRows, in: 1...20)
                    .padding(.horizontal)

                Stepper("Columns: \(selectedCols)", value: $selectedCols, in: 1...20)
                    .padding(.horizontal)

                Text("Example: \(selectedRows) rows × \(selectedCols) columns = \(selectedRows * selectedCols) positions")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding()
            .background(Color(.secondarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 12))
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

    // MARK: - Phase B: Drag-and-Drop Grid

    private func dragDropPhase(dims: (rows: Int, cols: Int)) -> some View {
        VStack(spacing: 0) {
            // Unplaced units drag source
            unplacedUnitsBar

            // Grid
            ScrollView([.horizontal, .vertical]) {
                dropGrid(rows: dims.rows, cols: dims.cols)
                    .padding()
            }

            // Progress bar + placed list
            placedUnitsList

            // Allow re-setting grid dimensions
            Button("Change Grid Dimensions") {
                gridDimensions = nil
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(.bottom, 8)
        }
    }

    // MARK: - Unplaced Units Bar

    private var unplacedUnitsBar: some View {
        let unplaced = units.filter { $0.gridX == nil || $0.gridY == nil }
        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                if unplaced.isEmpty {
                    Text("All units placed!")
                        .font(.caption)
                        .foregroundStyle(.green)
                        .padding(.horizontal, 12)
                } else {
                    Text("Drag a unit onto the grid:")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    ForEach(unplaced, id: \.id) { unit in
                        unitChip(unit)
                    }
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
        }
        .background(Color(.secondarySystemBackground))
    }

    private func unitChip(_ unit: WarehouseStorageUnit) -> some View {
        HStack(spacing: 4) {
            Image(systemName: iconForUnitType(unit.unitType))
                .font(.caption)
            Text(unit.name)
                .font(.caption)
                .lineLimit(1)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            draggingUnitId == unit.id
                ? Color.blue.opacity(0.25)
                : Color.secondary.opacity(0.1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .onDrag {
            draggingUnitId = unit.id
            return NSItemProvider(object: String(unit.id ?? 0) as NSString)
        }
    }

    // MARK: - Drop Grid

    private func dropGrid(rows: Int, cols: Int) -> some View {
        VStack(spacing: 1) {
            ForEach(0..<rows, id: \.self) { row in
                HStack(spacing: 1) {
                    ForEach(0..<cols, id: \.self) { col in
                        gridCell(row: row, col: col)
                    }
                }
            }
        }
        .background(Color(.systemGray5))
    }

    @ViewBuilder
    private func gridCell(row: Int, col: Int) -> some View {
        let placedUnit = units.first { $0.gridX == col && $0.gridY == row }
        let zone = zones.first { z in
            guard z.gridWidth > 0, z.gridHeight > 0 else { return false }
            return col >= z.gridX && col < z.gridX + z.gridWidth
                && row >= z.gridY && row < z.gridY + z.gridHeight
        }

        ZStack {
            Rectangle()
                .fill(cellBackground(zone: zone, placedUnit: placedUnit))

            if let unit = placedUnit {
                VStack(spacing: 0) {
                    Image(systemName: iconForUnitType(unit.unitType))
                        .font(.caption2)
                    Text(unit.name)
                        .font(.caption2)
                        .minimumScaleFactor(0.4)
                        .lineLimit(1)
                }
                .foregroundStyle(.white)
                // Allow re-drag of placed units
                .onDrag {
                    draggingUnitId = unit.id
                    return NSItemProvider(object: String(unit.id ?? 0) as NSString)
                }
            }

            Text("R\(row + 1)C\(col + 1)")
                .font(.system(size: 7))
                .foregroundStyle(placedUnit != nil ? .white.opacity(0.5) : .secondary.opacity(0.5))
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                .padding(2)
        }
        .frame(width: cellSize, height: cellSize)
        .dropDestination(for: String.self) { providers, _ in
            guard let idString = providers.first, let unitId = Int64(idString) else { return false }
            placeUnit(unitId: unitId, row: row, col: col)
            draggingUnitId = nil
            return true
        } isTargeted: { _ in }
        .accessibilityLabel(
            placedUnit.map { "\($0.name) at R\(row + 1)C\(col + 1)" }
                ?? "Empty cell R\(row + 1)C\(col + 1)"
        )
    }

    private func cellBackground(zone: WarehouseZone?, placedUnit: WarehouseStorageUnit?) -> Color {
        if placedUnit != nil { return .blue }
        if let zone { return zoneColor(zone.zoneType).opacity(0.15) }
        return Color(.systemBackground)
    }

    // MARK: - Placed Units List

    private var placedUnitsList: some View {
        let placed = units.filter { $0.gridX != nil && $0.gridY != nil }
        guard !placed.isEmpty else { return AnyView(EmptyView()) }
        return AnyView(
            HStack {
                Text("\(placed.count) of \(units.count) units placed")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                ProgressView(value: Double(placed.count), total: Double(max(units.count, 1)))
                    .frame(width: 80)
            }
            .padding(.horizontal)
            .padding(.vertical, 6)
            .background(Color(.secondarySystemBackground))
        )
    }

    // MARK: - Actions

    private func confirmGrid(rows: Int, cols: Int) {
        guard let svc = appCore.warehouseService else {
            stepError = "Warehouse service not available"
            return
        }
        do {
            try svc.updateFloorPlanGrid(floorPlanId: floorPlanId, rows: rows, cols: cols)
            gridDimensions = (rows: rows, cols: cols)
            loadData()
        } catch {
            stepError = userFriendlyError(error, context: "save grid dimensions")
        }
    }

    private func placeUnit(unitId: Int64, row: Int, col: Int) {
        // Don't stack on top of another unit
        if units.contains(where: { $0.gridX == col && $0.gridY == row && $0.id != unitId }) {
            stepError = "A unit is already placed at R\(row + 1)C\(col + 1)."
            return
        }
        do {
            try appCore.warehouseService?.updateStorageUnit(
                id: unitId,
                gridX: col,
                gridY: row,
                gridWidth: 1,
                gridHeight: 1
            )
            loadData()
        } catch {
            stepError = userFriendlyError(error, context: "place unit")
        }
    }

    private func loadData() {
        do {
            floorPlan = try appCore.warehouseService?.getFloorPlan(id: floorPlanId)
            zones = try appCore.warehouseService?.listZones(floorPlanId: floorPlanId) ?? []
            units = try appCore.warehouseService?.listStorageUnits(floorPlanId: floorPlanId) ?? []

            // Restore Phase B if grid dimensions are already set in DB
            if let fp = floorPlan, let rows = fp.gridRows, let cols = fp.gridCols, gridDimensions == nil {
                selectedRows = rows
                selectedCols = cols
                gridDimensions = (rows: rows, cols: cols)
            }
        } catch {
            stepError = userFriendlyError(error, context: "load floor plan data")
        }
    }

    // MARK: - Helpers

    private func iconForUnitType(_ type: String) -> String {
        switch type {
        case "shelf": return "cabinet.fill"
        case "pipe_rack": return "line.3.horizontal"
        case "gang_box": return "shippingbox.fill"
        case "wall_mount": return "rectangle.portrait.on.rectangle.portrait.angled.fill"
        case "cabinet": return "door.left.hand.closed"
        case "pallet_rack": return "square.stack.3d.up.fill"
        case "floor_area": return "square.dashed"
        default: return "cube.fill"
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
}
