import SwiftUI
import WiredPartCore

struct ZoneGridCanvas: View {
    let rows: Int
    let cols: Int
    let zones: [WarehouseZone]
    let selectedZoneId: Int64?
    let zoom: CGFloat
    var onCreateZone: (String, Int, Int) -> Void
    var onMoveZone: (WarehouseZone, Int, Int) -> Void
    var onResizeZone: (WarehouseZone, Int, Int) -> Void
    var onSelectZone: (WarehouseZone?) -> Void

    private let baseCellSize: CGFloat = 64
    private let cellSpacing: CGFloat = 1
    private let gutter: CGFloat = 18

    private var cellSize: CGFloat { baseCellSize * zoom }
    private var cellStride: CGFloat { cellSize + cellSpacing }
    private var canvasSize: CGSize {
        CGSize(
            width: CGFloat(cols) * cellSize + CGFloat(max(cols - 1, 0)) * cellSpacing + gutter,
            height: CGFloat(rows) * cellSize + CGFloat(max(rows - 1, 0)) * cellSpacing + gutter
        )
    }
    private var gridSize: CGSize {
        CGSize(
            width: CGFloat(cols) * cellSize + CGFloat(max(cols - 1, 0)) * cellSpacing,
            height: CGFloat(rows) * cellSize + CGFloat(max(rows - 1, 0)) * cellSpacing
        )
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            grid

            ForEach(zones, id: \.id) { zone in
                zoneView(zone)
            }
        }
        .frame(width: canvasSize.width, height: canvasSize.height, alignment: .topLeading)
        .padding(.trailing, gutter)
        .padding(.bottom, gutter)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .contentShape(Rectangle())
        .dropDestination(for: String.self) { items, location in
            guard let item = items.first else { return false }
            return handleDrop(item, location: location)
        } isTargeted: { _ in }
        .accessibilityElement(children: .contain)
    }

    private var grid: some View {
        VStack(spacing: 1) {
            ForEach(0..<rows, id: \.self) { row in
                HStack(spacing: 1) {
                    ForEach(0..<cols, id: \.self) { col in
                        cell(row: row, col: col)
                    }
                }
            }
        }
        .background(Color(.systemGray4))
    }

    private func cell(row: Int, col: Int) -> some View {
        ZStack(alignment: .bottomTrailing) {
            Rectangle()
                .fill(Color(.systemBackground))
            Text("R\(row + 1)C\(col + 1)")
                .font(.caption2)
                .foregroundStyle(.secondary.opacity(0.55))
                .minimumScaleFactor(0.6)
                .lineLimit(1)
                .padding(3)
        }
        .frame(width: cellSize, height: cellSize)
        .dropDestination(for: String.self) { items, _ in
            guard let item = items.first else { return false }
            return handleDrop(item, row: row, col: col)
        } isTargeted: { _ in }
        .onTapGesture {
            onSelectZone(nil)
        }
        .accessibilityLabel("Empty zone cell R\(row + 1)C\(col + 1)")
    }

    private func zoneView(_ zone: WarehouseZone) -> some View {
        let clampedX = min(max(zone.gridX, 0), max(cols - 1, 0))
        let clampedY = min(max(zone.gridY, 0), max(rows - 1, 0))
        let maxWidth = max(cols - clampedX, 1)
        let maxHeight = max(rows - clampedY, 1)
        let width = min(max(zone.gridWidth, 1), maxWidth)
        let height = min(max(zone.gridHeight, 1), maxHeight)
        let isSelected = selectedZoneId == zone.id

        return ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 6)
                .fill(zoneColor(zone.zoneType).opacity(isSelected ? 0.34 : 0.22))
                .overlay {
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(zoneColor(zone.zoneType), lineWidth: isSelected ? 3 : 1.5)
                }

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 5) {
                    Image(systemName: zoneIcon(zone.zoneType))
                        .font(.caption)
                    Text(zoneTitle(zone))
                        .font(.caption)
                        .fontWeight(.semibold)
                        .lineLimit(2)
                        .minimumScaleFactor(0.65)
                }
                Text("\(width)x\(height)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .foregroundStyle(zoneColor(zone.zoneType))
            .padding(8)

            if isSelected {
                resizeHandle(zone, width: width, height: height)
                    .frame(width: 44, height: 44)
                    .position(
                        x: max(22, zoneExtent(width) - 10),
                        y: max(22, zoneExtent(height) - 10)
                    )
                    .zIndex(2)
            }
        }
        .frame(width: zoneExtent(width) - 1, height: zoneExtent(height) - 1)
        .contentShape(Rectangle())
        .onTapGesture {
            onSelectZone(zone)
        }
        .onLongPressGesture(minimumDuration: 0.35) {
            onSelectZone(zone)
        }
        .draggable("zone:\(zone.id ?? -1)") {
            zoneDragPreview(zone)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(zoneTitle(zone)), \(zone.zoneTypeDisplay), starts at R\(clampedY + 1)C\(clampedX + 1), \(width) by \(height) cells")
        .accessibilityHint("Tap to select. Long press and drag to move.")
        .position(
            x: CGFloat(clampedX) * cellStride + zoneExtent(width) / 2,
            y: CGFloat(clampedY) * cellStride + zoneExtent(height) / 2
        )
    }

    private func zoneDragPreview(_ zone: WarehouseZone) -> some View {
        Label(zoneTitle(zone), systemImage: zoneIcon(zone.zoneType))
            .font(.caption)
            .fontWeight(.semibold)
            .foregroundStyle(zoneColor(zone.zoneType))
            .padding(.horizontal, 10)
            .frame(minWidth: 88, minHeight: 44)
            .background(zoneColor(zone.zoneType).opacity(0.18), in: RoundedRectangle(cornerRadius: 8))
            .overlay {
                RoundedRectangle(cornerRadius: 8)
                    .stroke(zoneColor(zone.zoneType), lineWidth: 1.5)
            }
            .accessibilityHidden(true)
    }

    private func resizeHandle(_ zone: WarehouseZone, width: Int, height: Int) -> some View {
        Button {
            onResizeZone(zone, width + 1, height + 1)
        } label: {
            Circle()
                .fill(Color(.systemBackground))
                .overlay {
                    Image(systemName: "arrow.down.right.and.arrow.up.left")
                        .font(.caption)
                        .foregroundStyle(zoneColor(zone.zoneType))
                        .accessibilityHidden(true)
                }
                .shadow(color: .black.opacity(0.18), radius: 2, y: 1)
        }
            .buttonStyle(.plain)
            .contentShape(Rectangle())
            .highPriorityGesture(
                DragGesture(minimumDistance: 6)
                    .onEnded { value in
                        let deltaCols = Int(value.translation.width / cellStride)
                        let deltaRows = Int(value.translation.height / cellStride)
                        onResizeZone(zone, max(1, width + deltaCols), max(1, height + deltaRows))
                    }
            )
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Resize \(zoneTitle(zone))")
            .accessibilityHint("Tap to grow or drag to change the zone width and height")
    }

    private func handleDrop(_ item: String, row: Int, col: Int) -> Bool {
        if item.hasPrefix("new:") {
            onCreateZone(String(item.dropFirst(4)), col, row)
            return true
        }
        if item.hasPrefix("zone:"),
           let id = Int64(item.dropFirst(5)),
           let zone = zones.first(where: { $0.id == id }) {
            onMoveZone(zone, col, row)
            return true
        }
        return false
    }

    private func handleDrop(_ item: String, location: CGPoint) -> Bool {
        guard location.x >= 0, location.y >= 0,
              location.x <= gridSize.width, location.y <= gridSize.height
        else { return false }

        let col = min(max(Int(location.x / cellStride), 0), max(cols - 1, 0))
        let row = min(max(Int(location.y / cellStride), 0), max(rows - 1, 0))
        return handleDrop(item, row: row, col: col)
    }

    private func zoneExtent(_ cells: Int) -> CGFloat {
        CGFloat(cells) * cellSize + CGFloat(max(cells - 1, 0)) * cellSpacing
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

private extension WarehouseZone {
    var zoneTypeDisplay: String {
        zoneType.replacingOccurrences(of: "_", with: " ").capitalized
    }
}
