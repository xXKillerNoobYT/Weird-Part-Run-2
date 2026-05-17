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
    @State private var completedHistoryExpanded = false

    // Date filter
    @State private var dateRange: ReportDateRange = .thisWeek
    @State private var customStart: Date = Date().addingTimeInterval(-7 * 86400)
    @State private var customEnd: Date = Date()

    private var effectiveStart: Date { dateRange.dateInterval?.start ?? customStart }
    private var effectiveEnd: Date { dateRange.dateInterval?.end ?? customEnd }

    private enum MovementFilter: String, CaseIterable {
        case all = "All"
        case transfers = "Transfer"
        case receives = "Received"
        case consumed = "Consumed"
        case returns = "Return"
        case adjustments = "Adjustment"

        var movementType: String? {
            switch self {
            case .all: nil
            case .transfers: "transfer"
            case .receives: "receive"
            case .consumed: "consume"
            case .returns: "return_to_supplier"
            case .adjustments: "adjustment"
            }
        }
    }

    private enum ActiveSheet: Identifiable {
        case movementDetail(WarehouseService.MovementRow)
        case newMovement
        case quickLog
        case qrScanner
        case help

        var id: String {
            switch self {
            case .movementDetail(let m): "detail-\(m.id)"
            case .newMovement: "newMovement"
            case .quickLog: "quickLog"
            case .qrScanner: "qrScanner"
            case .help: "help"
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            OnboardingBanner(pageId: "warehouse-movements")
            smartCardFilters
            StandardFilterBar(selectedRange: $dateRange, customStart: $customStart, customEnd: $customEnd)

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
                .accessibilityLabel("Scan QR code")
                Button { activeSheet = .quickLog } label: {
                    Image(systemName: "square.and.pencil")
                }
                .accessibilityLabel("Quick log movement")
                Button { activeSheet = .newMovement } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("New movement")
            }
            ToolbarItem(placement: .primaryAction) {
                Button { activeSheet = .help } label: {
                    Image(systemName: "questionmark.circle")
                }
                .accessibilityLabel("Help")
            }
        }
        .sheet(item: $activeSheet) { sheet in
            sheetContent(for: sheet)
        }
        .background(DS.Background.page)
        .task {
            loadData()
            appCore.onboardingManager?.markCompleted("wh-movements-view")
        }
        .onDisappear {
            NotificationCenter.default.post(name: .warehouseMovementsPageInactive, object: nil)
        }
        .onChange(of: dateRange) { loadData() }
        .onChange(of: customStart) { loadData() }
        .onChange(of: customEnd) { loadData() }
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
        case .quickLog:
            QuickLogMovementSheet(openFullMovementWizard: {
                activeSheet = .newMovement
            })
        case .qrScanner:
            QRScanSheet(expectedType: .part) { result in
                activeSheet = nil
            }
            .environmentObject(appCore)
        case .help:
            PageHelpSheet(
                title: "Movements Help",
                sections: [
                    ("Overview", "Track all stock movements: transfers, receiving, consumed-on-job, supplier returns, and inventory adjustments."),
                    ("Creating Movements", "Tap + to start a guided movement. Use Quick Log for an informal already-happened event that should be documented before entering exact stock details."),
                    ("Filtering", "Use the six smart cards to filter by movement type or return to All. Search by part name. Tap any movement for type-specific details."),
                    ("History", "Active movements are shown first, oldest to newest. Completed history keeps the last 7 days collapsed until you need it.")
                ]
            )
        }
    }

    // MARK: - Smart Card Filters

    private var smartCardFilters: some View {
        let transferCount = dateFilteredMovements.filter { $0.movementType == "transfer" }.count
        let receiveCount = dateFilteredMovements.filter { $0.movementType == "receive" }.count
        let consumedCount = dateFilteredMovements.filter { $0.movementType == "consume" }.count
        let returnCount = dateFilteredMovements.filter { $0.movementType == "return_to_supplier" }.count
        let adjustCount = dateFilteredMovements.filter { $0.movementType == "adjustment" }.count

        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                filterCard(.all, count: dateFilteredMovements.count, icon: "tray.full", color: .accentColor)
                filterCard(.transfers, count: transferCount, icon: "arrow.left.arrow.right", color: .blue)
                filterCard(.receives, count: receiveCount, icon: "arrow.down.circle", color: .green)
                filterCard(.consumed, count: consumedCount, icon: "flame", color: .orange)
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
            selectedFilter = filter == .all || isSelected ? nil : filter
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
        var result = dateFilteredMovements
        if let filter = selectedFilter, let movementType = filter.movementType {
            result = result.filter { $0.movementType == movementType }
        }
        if !searchText.isEmpty {
            let query = searchText.lowercased()
            result = result.filter { $0.partName.lowercased().contains(query) }
        }
        return result.sorted { ($0.createdAt ?? "") < ($1.createdAt ?? "") }
    }

    private var dateFilteredMovements: [WarehouseService.MovementRow] {
        movements.filter { movement in
            guard let date = movementDate(movement) else { return true }
            return date >= effectiveStart && date <= effectiveEnd
        }
    }

    // MARK: - Movements List

    private var activeMovements: [WarehouseService.MovementRow] {
        let cutoff = Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date()
        return filteredMovements.filter { movementDate($0) ?? Date.distantFuture >= cutoff }
    }

    private var completedHistoryMovements: [WarehouseService.MovementRow] {
        let cutoff = Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date()
        return filteredMovements.filter { movementDate($0) ?? Date.distantFuture < cutoff }
    }

    @ViewBuilder
    private var movementsList: some View {
        List {
            Section {
                Text("\(filteredMovements.count) movement\(filteredMovements.count == 1 ? "" : "s") • oldest to newest")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Active") {
                if activeMovements.isEmpty {
                    Text("No active movements in the selected range.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(activeMovements, id: \.id) { movementButton($0) }
                }
            }

            Section {
                DisclosureGroup(isExpanded: $completedHistoryExpanded) {
                    if completedHistoryMovements.isEmpty {
                        Text("No completed movements older than 7 days for this filter.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(completedHistoryMovements, id: \.id) { movementButton($0) }
                    }
                } label: {
                    Label("Completed History (7+ days)", systemImage: "clock.arrow.circlepath")
                        .font(.subheadline)
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollDismissesKeyboard(.interactively)
    }

    private func movementButton(_ movement: WarehouseService.MovementRow) -> some View {
        Button {
            activeSheet = .movementDetail(movement)
        } label: {
            movementRow(movement)
        }
        .buttonStyle(.plain)
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
                .frame(minWidth: 44, minHeight: 44)
                .contentShape(Rectangle())
                .accessibilityHidden(true)

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
                .accessibilityHidden(true)
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
            movements = try service.listMovements(limit: 200, sortOrder: .oldestFirst)
            postAIContext()
        } catch {
            loadError = userFriendlyError(error, context: "load movements")
        }
        isLoading = false
    }

    private func postAIContext() {
        let movementTypes = Dictionary(grouping: movements, by: \.movementType)
            .map { "\($0.key): \($0.value.count)" }
            .sorted()
            .joined(separator: ", ")
        let context = """
        Warehouse Movements page. Read-only context.
        Loaded movements: \(movements.count), visible after filters: \(filteredMovements.count), selected filter: \(selectedFilter?.rawValue ?? "none"), search active: \(!searchText.isEmpty).
        Date range: \(dateRange.rawValue), movement types: \(movementTypes.isEmpty ? "none" : movementTypes).
        Available read-only guidance: explain movement history, date range, filter chips, search, detail rows, QR scan entry, and new movement entry point. Do not create movements, launch scanners, or change filters directly.
        """
        NotificationCenter.default.post(
            name: .warehouseMovementsPageActive,
            object: nil,
            userInfo: ["context": context]
        )
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

    private func movementDate(_ movement: WarehouseService.MovementRow) -> Date? {
        guard let raw = movement.createdAt else { return nil }
        return Self.sqliteDateFormatter.date(from: raw)
            ?? ISO8601DateFormatter().date(from: raw)
    }

    private static let sqliteDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter
    }()
}

// MARK: - Quick Log Sheet

private struct QuickLogMovementSheet: View {
    let openFullMovementWizard: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Label("Quick Log", systemImage: "square.and.pencil")
                        .font(.headline)
                    Text("Use this for already-happened warehouse events that need a fast note before exact stock details are entered. The full movement wizard still records inventory-safe quantities and locations.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section("Common informal events") {
                    quickLogHint("Transfer", icon: "arrow.left.arrow.right", note: "Moved between warehouse locations")
                    quickLogHint("Received", icon: "arrow.down.circle", note: "Supplier or PO items arrived")
                    quickLogHint("Consumed", icon: "flame", note: "Used on a job or delivery")
                    quickLogHint("Return", icon: "arrow.uturn.left", note: "Return to supplier, manager approval required")
                    quickLogHint("Adjustment", icon: "plus.forwardslash.minus", note: "Inventory correction, audit trail required")
                }

                Section {
                    Button {
                        dismiss()
                        openFullMovementWizard()
                    } label: {
                        Label("Open full movement wizard", systemImage: "plus.circle.fill")
                    }
                }
            }
            .navigationTitle("Quick Log")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func quickLogHint(_ title: String, icon: String, note: String) -> some View {
        Label {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.medium)
                Text(note)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } icon: {
            Image(systemName: icon)
                .foregroundStyle(Color.accentColor)
        }
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
