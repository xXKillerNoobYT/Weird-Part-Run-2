import SwiftUI
import WiredPartCore

/// Warehouse movements listing with search, smart card filters, detail sheet,
/// and a multi-step movement wizard.
///
/// Shows a chronological list of stock movements with from/to locations,
/// part names, quantities, and movement types. Quick actions open the
/// movement wizard and QR scanner via ActiveSheet.
struct WarehouseMovementsPage: View {
    @EnvironmentObject private var appCore: AppCore
    @State private var movements: [WarehouseService.MovementRow] = []
    @State private var isLoading = true
    @State private var searchText = ""
    @State private var selectedFilter: MovementFilter?
    @State private var loadError: String?
    @State private var activeSheet: ActiveSheet?

    private enum MovementFilter: String, CaseIterable {
        case transfers = "Transfers"
        case receives = "Receives"
        case returns = "Returns"
        case adjustments = "Adjustments"

        var movementType: String {
            switch self {
            case .transfers: "transfer"
            case .receives: "receive"
            case .returns: "return_to_supplier"
            case .adjustments: "adjustment"
            }
        }
    }

    private enum ActiveSheet: Identifiable {
        case movementDetail(WarehouseService.MovementRow)
        case newMovement
        case qrScanner

        var id: String {
            switch self {
            case .movementDetail(let m): "detail-\(m.id)"
            case .newMovement: "newMovement"
            case .qrScanner: "qrScanner"
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            smartCardFilters

            if isLoading {
                ProgressView("Loading movements…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error = loadError {
                ErrorStateView(message: error) { loadData() }
            } else if filteredMovements.isEmpty {
                emptyState
            } else {
                movementsList
            }
        }
        .searchable(text: $searchText, prompt: "Search by part name…")
        .refreshable { loadData() }
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button { activeSheet = .qrScanner } label: {
                    Image(systemName: "qrcode.viewfinder")
                }
                Button { activeSheet = .newMovement } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .sheet(item: $activeSheet) { sheet in
            sheetContent(for: sheet)
        }
        .background(DS.Background.page)
        .task { loadData() }
    }

    // MARK: - Sheet Content

    @ViewBuilder
    private func sheetContent(for sheet: ActiveSheet) -> some View {
        switch sheet {
        case .movementDetail(let movement):
            MovementDetailSheet(movement: movement)
        case .newMovement:
            IOSMovementWizard(onComplete: { loadData() })
                .environmentObject(appCore)
        case .qrScanner:
            QRScanSheet(expectedType: .part) { result in
                activeSheet = nil
            }
            .environmentObject(appCore)
        }
    }

    // MARK: - Smart Card Filters

    private var smartCardFilters: some View {
        let transferCount = movements.filter { $0.movementType == "transfer" }.count
        let receiveCount = movements.filter { $0.movementType == "receive" }.count
        let returnCount = movements.filter { $0.movementType == "return_to_supplier" }.count
        let adjustCount = movements.filter { $0.movementType == "adjustment" }.count

        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                filterCard(.transfers, count: transferCount, icon: "arrow.left.arrow.right", color: .blue)
                filterCard(.receives, count: receiveCount, icon: "arrow.down.circle", color: .green)
                filterCard(.returns, count: returnCount, icon: "arrow.uturn.left", color: .purple)
                filterCard(.adjustments, count: adjustCount, icon: "plus.forwardslash.minus", color: .gray)
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
        }
        .background(Color(.secondarySystemGroupedBackground))
    }

    private func filterCard(_ filter: MovementFilter, count: Int, icon: String, color: Color) -> some View {
        let isSelected = selectedFilter == filter

        return Button {
            selectedFilter = isSelected ? nil : filter
        } label: {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.caption)
                Text("\(filter.rawValue) (\(count))")
                    .font(.caption)
                    .fontWeight(isSelected ? .bold : .regular)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                Capsule().fill(isSelected ? color.opacity(0.15) : Color.secondary.opacity(0.08))
            )
            .overlay(
                Capsule().stroke(isSelected ? color : Color.clear, lineWidth: 1.5)
            )
            .foregroundStyle(isSelected ? color : .primary)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Filtered Movements

    private var filteredMovements: [WarehouseService.MovementRow] {
        var result = movements
        if let filter = selectedFilter {
            result = result.filter { $0.movementType == filter.movementType }
        }
        if !searchText.isEmpty {
            let query = searchText.lowercased()
            result = result.filter { $0.partName.lowercased().contains(query) }
        }
        return result
    }

    // MARK: - Movements List

    @ViewBuilder
    private var movementsList: some View {
        List {
            Section {
                Text("\(filteredMovements.count) movement\(filteredMovements.count == 1 ? "" : "s")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            ForEach(filteredMovements, id: \.id) { movement in
                Button {
                    activeSheet = .movementDetail(movement)
                } label: {
                    movementRow(movement)
                }
                .buttonStyle(.plain)
            }
        }
        .listStyle(.insetGrouped)
    }

    @ViewBuilder
    private func movementRow(_ movement: WarehouseService.MovementRow) -> some View {
        HStack(spacing: 12) {
            Image(systemName: movementIcon(movement.movementType))
                .font(.title3)
                .foregroundStyle(movementColor(movement.movementType))
                .frame(width: 36, height: 36)
                .background(movementColor(movement.movementType).opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 3) {
                Text(movement.partName)
                    .font(.body)
                    .fontWeight(.medium)
                    .lineLimit(1)

                HStack(spacing: 6) {
                    Text(movementLabel(movement.movementType))
                        .font(.caption2)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(movementColor(movement.movementType).opacity(0.1))
                        .clipShape(Capsule())

                    if let from = movement.fromLocationType, let to = movement.toLocationType {
                        Text("\(from.capitalized) → \(to.capitalized)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 3) {
                Text("×\(movement.qty)")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                Text(formatDate(movement.createdAt))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .frame(minHeight: 56)
    }

    // MARK: - Empty State

    private var emptyState: some View {
        EmptyStateView(
            icon: "arrow.left.arrow.right",
            title: "No Movements Found",
            message: searchText.isEmpty && selectedFilter == nil
                ? "Stock movements will appear here as parts are transferred."
                : "No movements match your criteria.",
            actionLabel: "New Movement"
        ) {
            activeSheet = .newMovement
        }
    }

    // MARK: - Data Loading

    private func loadData() {
        guard let service = appCore.warehouseService else {
            loadError = "Warehouse service not available"
            isLoading = false
            return
        }
        isLoading = movements.isEmpty
        loadError = nil
        do {
            movements = try service.listMovements(limit: 200)
        } catch {
            loadError = error.localizedDescription
        }
        isLoading = false
    }

    // MARK: - Helpers

    private func movementIcon(_ type: String) -> String {
        switch type {
        case "transfer": "arrow.left.arrow.right"
        case "receive": "arrow.down.circle"
        case "consume": "flame"
        case "return_to_supplier": "arrow.uturn.left"
        case "adjustment": "plus.forwardslash.minus"
        default: "arrow.left.arrow.right"
        }
    }

    private func movementColor(_ type: String) -> Color {
        switch type {
        case "transfer": .blue
        case "receive": .green
        case "consume": .orange
        case "return_to_supplier": .purple
        case "adjustment": .gray
        default: .blue
        }
    }

    private func movementLabel(_ type: String) -> String {
        switch type {
        case "transfer": "Transfer"
        case "receive": "Received"
        case "consume": "Consumed"
        case "return_to_supplier": "Returned"
        case "adjustment": "Adjustment"
        default: type.capitalized
        }
    }

    private func formatDate(_ dateStr: String?) -> String {
        guard let dateStr else { return "" }
        return dateStr.count >= 10 ? String(dateStr.prefix(10)) : dateStr
    }
}

// MARK: - Movement Detail Sheet

private struct MovementDetailSheet: View {
    let movement: WarehouseService.MovementRow
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section("Part") {
                    LabeledContent("Name", value: movement.partName)
                    LabeledContent("Quantity", value: "\(movement.qty)")
                }

                Section("Movement") {
                    LabeledContent("Type", value: movementLabel(movement.movementType))
                    if let from = movement.fromLocationType {
                        LabeledContent("From", value: "\(from.capitalized) #\(movement.fromLocationId ?? 0)")
                    }
                    if let to = movement.toLocationType {
                        LabeledContent("To", value: "\(to.capitalized) #\(movement.toLocationId ?? 0)")
                    }
                }

                Section("Details") {
                    if let reason = movement.reason, !reason.isEmpty {
                        LabeledContent("Reason", value: reason)
                    }
                    if let notes = movement.notes, !notes.isEmpty {
                        LabeledContent("Notes", value: notes)
                    }
                    if let name = movement.performedByName {
                        LabeledContent("Performed By", value: name)
                    }
                    if let date = movement.createdAt {
                        LabeledContent("Date", value: date)
                    }
                }
            }
            .navigationTitle("Movement Details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func movementLabel(_ type: String) -> String {
        switch type {
        case "transfer": "Transfer"
        case "receive": "Received"
        case "consume": "Consumed"
        case "return_to_supplier": "Returned"
        case "adjustment": "Adjustment"
        default: type.capitalized
        }
    }
}
