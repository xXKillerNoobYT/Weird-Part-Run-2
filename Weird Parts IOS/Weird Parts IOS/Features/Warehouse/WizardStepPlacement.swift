import SwiftUI
import WiredPartCore

/// Wizard Step 4: Place Units on Floor Plan — visual drag-and-drop grid.
///
/// Shows a simplified warehouse grid with zones. Users tap a storage unit
/// from the sidebar, then tap a grid cell to place it. Records row+column
/// within the zone as the unit's address.
struct WizardStepPlacement: View {
    @EnvironmentObject private var appCore: AppCore
    let floorPlanId: Int64
    @Binding var stepError: String?

    @State private var zones: [WarehouseZone] = []
    @State private var units: [WarehouseStorageUnit] = []
    @State private var selectedUnitId: Int64?
    @State private var floorPlan: WarehouseFloorPlan?

    // Grid dimensions
    private let cellSize: CGFloat = 44
    private var gridCols: Int { max(1, (floorPlan?.widthInches ?? 480) / 60) } // 5ft cells
    private var gridRows: Int { max(1, (floorPlan?.lengthInches ?? 720) / 60) }

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 8) {
                Text("Tap a unit below, then tap a grid cell to place it on the floor plan.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding()

            // Unplaced units bar
            unplacedUnitsBar

            // Floor plan grid
            ScrollView([.horizontal, .vertical]) {
                floorPlanGrid
                    .padding()
            }

            // Legend
            placedUnitsList
        }
        .task { loadData() }
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
                    ForEach(unplaced, id: \.id) { unit in
                        Button {
                            selectedUnitId = unit.id
                        } label: {
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
                                selectedUnitId == unit.id
                                    ? Color.blue.opacity(0.2)
                                    : Color.secondary.opacity(0.1)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(selectedUnitId == unit.id ? .blue : .clear, lineWidth: 1.5)
                            )
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 6)
        }
        .background(Color(.secondarySystemBackground))
    }

    // MARK: - Floor Plan Grid

    private var floorPlanGrid: some View {
        VStack(spacing: 1) {
            ForEach(0..<gridRows, id: \.self) { row in
                HStack(spacing: 1) {
                    ForEach(0..<gridCols, id: \.self) { col in
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
            guard let zx = z.gridX, let zy = z.gridY,
                  let zw = z.gridWidth, let zh = z.gridHeight else { return false }
            return col >= zx && col < zx + zw && row >= zy && row < zy + zh
        }

        Button {
            placeUnit(row: row, col: col)
        } label: {
            ZStack {
                Rectangle()
                    .fill(cellBackground(zone: zone, placedUnit: placedUnit))

                if let unit = placedUnit {
                    VStack(spacing: 0) {
                        Image(systemName: iconForUnitType(unit.unitType))
                            .font(.caption2)
                        Text(unit.name)
                            .font(.system(size: 7))
                            .lineLimit(1)
                    }
                    .foregroundStyle(.white)
                }
            }
            .frame(width: cellSize, height: cellSize)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(placedUnit != nil ? "\(placedUnit!.name) at row \(row), column \(col)" : "Empty cell at row \(row), column \(col)")
    }

    private func cellBackground(zone: WarehouseZone?, placedUnit: WarehouseStorageUnit?) -> Color {
        if placedUnit != nil {
            return .blue
        }
        if let zone {
            return zoneColor(zone.zoneType).opacity(0.15)
        }
        return Color(.systemBackground)
    }

    // MARK: - Placed Units List

    private var placedUnitsList: some View {
        let placed = units.filter { $0.gridX != nil && $0.gridY != nil }

        return VStack(alignment: .leading, spacing: 4) {
            if !placed.isEmpty {
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
            }
        }
    }

    // MARK: - Actions

    private func placeUnit(row: Int, col: Int) {
        guard let unitId = selectedUnitId else { return }

        // Don't place on top of another unit
        if units.contains(where: { $0.gridX == col && $0.gridY == row && $0.id != unitId }) {
            stepError = "A unit is already placed at this position."
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
            selectedUnitId = nil
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
