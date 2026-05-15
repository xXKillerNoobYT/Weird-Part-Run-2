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
    @State private var showCompletedHistory = false

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

        var movementTypes: [String] {
            switch self {
            case .all: []
            case .transfers: ["transfer"]
            case .receives: ["receive"]
            case .consumed: ["consume"]
            case .returns: ["return_to_supplier"]
            case .adjustments: ["adjustment"]
            }
        }

        var icon: String {
            switch self {
            case .all: "tray.full"
            case .transfers: "arrow.left.arrow.right"
            case .receives: "arrow.down.circle"
            case .consumed: "flame"
            case .returns: "arrow.uturn.left"
            case .adjustments: "plus.forwardslash.minus"
            }
        }

        var color: Color {
            switch self {
            case .all: .indigo
            case .transfers: .blue
            case .receives: .green
            case .consumed: .orange
            case .returns: .purple
            case .adjustments: .gray
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
                Button { activeSheet = .newMovement } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("New movement")
                Button { activeSheet = .quickLog } label: {
                    Image(systemName: "square.and.pencil")
                }
                .accessibilityLabel("Quick log movement")
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
            QuickLogMovementSheet(onComplete: { loadData() })
                .environmentObject(appCore)
        case .qrScanner:
            QRScanSheet(expectedType: .part) { result in
                activeSheet = nil
            }
            .environmentObject(appCore)
        case .help:
            PageHelpSheet(
                title: "Movements Help",
                sections: [
                    ("Overview", "Track all stock movements: transfers between locations, receiving from suppliers, returns, and adjustments."),
                    ("Creating Movements", "Tap + to start a new guided movement. The wizard walks you through selecting parts, quantities, and locations."),
                    ("Quick Log", "Use the pencil action to record an already-completed movement with the date it happened."),
                    ("Filtering", "Use the smart cards to filter by movement type. Active movements and completed seven-day history are grouped separately.")
                ]
            )
        }
    }

    // MARK: - Smart Card Filters

    private var smartCardFilters: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(MovementFilter.allCases, id: \.self) { filter in
                    filterCard(filter, count: count(for: filter))
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
        }
        .background(Color(.secondarySystemGroupedBackground))
    }

    private func filterCard(_ filter: MovementFilter, count: Int) -> some View {
        let isSelected = selectedFilter == filter || (filter == .all && selectedFilter == nil)

        return Button {
            selectedFilter = filter == .all || isSelected ? nil : filter
        } label: {
            HStack(spacing: 6) {
                Image(systemName: filter.icon)
                    .font(.caption)
                Text("\(filter.rawValue) (\(count))")
                    .font(.caption)
                    .fontWeight(isSelected ? .bold : .regular)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                Capsule().fill(isSelected ? filter.color.opacity(0.15) : Color.secondary.opacity(0.08))
            )
            .overlay(
                Capsule().stroke(isSelected ? filter.color : Color.clear, lineWidth: 1.5)
            )
            .foregroundStyle(isSelected ? filter.color : .primary)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Filtered Movements

    private var filteredMovements: [WarehouseService.MovementRow] {
        var result = movements
        if let filter = selectedFilter {
            let requestedTypes = Set(filter.movementTypes)
            result = result.filter { requestedTypes.contains(normalizedMovementType($0.movementType)) }
        }
        if !searchText.isEmpty {
            let query = searchText.lowercased()
            result = result.filter { $0.partName.lowercased().contains(query) }
        }
        return result
    }

    private var activeMovements: [WarehouseService.MovementRow] {
        filteredMovements.filter { normalizedMovementType($0.movementType) == "receiving_staged" }
    }

    private var completedHistory: [WarehouseService.MovementRow] {
        let sevenDaysAgo = Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date()
        return filteredMovements.filter { movement in
            normalizedMovementType(movement.movementType) != "receiving_staged" && movementDate(movement) >= sevenDaysAgo
        }
    }

    private func count(for filter: MovementFilter) -> Int {
        guard filter != .all else { return movements.count }
        let requestedTypes = Set(filter.movementTypes)
        return movements.filter { requestedTypes.contains(normalizedMovementType($0.movementType)) }.count
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

            if !activeMovements.isEmpty {
                Section("Active") {
                    ForEach(activeMovements, id: \.id) { movement in
                        movementButton(movement)
                    }
                }
            }

            Section {
                DisclosureGroup(isExpanded: $showCompletedHistory) {
                    if completedHistory.isEmpty {
                        Text("No completed movements in the last 7 days.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(.vertical, 4)
                    } else {
                        ForEach(completedHistory, id: \.id) { movement in
                            movementButton(movement)
                        }
                    }
                } label: {
                    Text("Completed History (7 days)")
                    Text("\(completedHistory.count)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
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
            actionLabel: "Quick Log"
        ) {
            activeSheet = .quickLog
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
            movements = try service.listMovements(
                search: searchText.isEmpty ? nil : searchText,
                startDate: effectiveStart,
                endDate: effectiveEnd,
                sortDirection: .ascending,
                limit: 200
            )
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

    private func normalizedMovementType(_ type: String) -> String {
        WarehouseService.normalizeMovementType(type)
    }

    private func movementDate(_ movement: WarehouseService.MovementRow) -> Date {
        guard let createdAt = movement.createdAt else { return .distantPast }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter.date(from: createdAt) ?? .distantPast
    }

    private func movementIcon(_ type: String) -> String {
        switch normalizedMovementType(type) {
        case "transfer": "arrow.left.arrow.right"
        case "receive": "arrow.down.circle"
        case "consume": "flame"
        case "return_to_supplier": "arrow.uturn.left"
        case "adjustment": "plus.forwardslash.minus"
        default: "arrow.left.arrow.right"
        }
    }

    private func movementColor(_ type: String) -> Color {
        switch normalizedMovementType(type) {
        case "transfer": .blue
        case "receive": .green
        case "consume": .orange
        case "return_to_supplier": .purple
        case "adjustment": .gray
        default: .blue
        }
    }

    private func movementLabel(_ type: String) -> String {
        switch normalizedMovementType(type) {
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
                Section {
                    Label(detailSummary, systemImage: movementIcon(movement.movementType))
                        .foregroundStyle(movementColor(movement.movementType))
                }

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

                Section(typeSpecificTitle) {
                    ForEach(typeSpecificRows, id: \.label) { row in
                        LabeledContent(row.label, value: row.value)
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

    private var detailSummary: String {
        switch normalizedMovementType(movement.movementType) {
        case "transfer":
            "Stock moved between warehouse locations."
        case "receive":
            "Stock received into inventory."
        case "consume":
            "Stock consumed or pulled for work."
        case "return_to_supplier":
            "Stock returned out of inventory."
        case "adjustment":
            "Manual quantity adjustment recorded."
        default:
            "Warehouse movement entry."
        }
    }

    private var typeSpecificTitle: String {
        switch normalizedMovementType(movement.movementType) {
        case "receive": "Receiving Details"
        case "consume": "Consumption Details"
        case "return_to_supplier": "Return Details"
        case "adjustment": "Adjustment Details"
        default: "Transfer Details"
        }
    }

    private var typeSpecificRows: [(label: String, value: String)] {
        let source = locationLabel(type: movement.fromLocationType, id: movement.fromLocationId)
        let destination = locationLabel(type: movement.toLocationType, id: movement.toLocationId)
        switch normalizedMovementType(movement.movementType) {
        case "receive":
            return [
                ("Received Into", destination),
                ("Scan Confirmed", movement.scanConfirmed ? "Yes" : "No")
            ]
        case "consume":
            return [
                ("Consumed From", source),
                ("Job or Use", movement.reason?.isEmpty == false ? movement.reason! : "Not specified")
            ]
        case "return_to_supplier":
            return [
                ("Returned From", source),
                ("Supplier Route", destination)
            ]
        case "adjustment":
            return [
                ("Adjusted Location", destination == "Not specified" ? source : destination),
                ("Audit Verified", movement.verifiedBy == nil ? "No" : "Yes")
            ]
        default:
            return [
                ("Source", source),
                ("Destination", destination)
            ]
        }
    }

    private func normalizedMovementType(_ type: String) -> String {
        WarehouseService.normalizeMovementType(type)
    }

    private func locationLabel(type: String?, id: Int64?) -> String {
        guard let type, !type.isEmpty else { return "Not specified" }
        if let id {
            return "\(type.capitalized) #\(id)"
        }
        return type.capitalized
    }

    private func movementIcon(_ type: String) -> String {
        switch normalizedMovementType(type) {
        case "transfer": "arrow.left.arrow.right"
        case "receive": "arrow.down.circle"
        case "consume": "flame"
        case "return_to_supplier": "arrow.uturn.left"
        case "adjustment": "plus.forwardslash.minus"
        default: "arrow.left.arrow.right"
        }
    }

    private func movementColor(_ type: String) -> Color {
        switch normalizedMovementType(type) {
        case "transfer": .blue
        case "receive": .green
        case "consume": .orange
        case "return_to_supplier": .purple
        case "adjustment": .gray
        default: .blue
        }
    }

    private func movementLabel(_ type: String) -> String {
        switch normalizedMovementType(type) {
        case "transfer": "Transfer"
        case "receive": "Received"
        case "consume": "Consumed"
        case "return_to_supplier": "Returned"
        case "adjustment": "Adjustment"
        default: type.capitalized
        }
    }
}

// MARK: - Quick Log

private struct QuickLogMovementSheet: View {
    @EnvironmentObject private var appCore: AppCore
    @Environment(\.dismiss) private var dismiss

    let onComplete: () -> Void

    @State private var partSearch = ""
    @State private var parts: [QuickLogPartItem] = []
    @State private var selectedPartId: Int64 = 0
    @State private var selectedType: QuickLogMovementType = .transfer
    @State private var quantity = 1
    @State private var occurredAt = Date()
    @State private var fromLocationType = ""
    @State private var fromLocationId = ""
    @State private var toLocationType = ""
    @State private var toLocationId = ""
    @State private var reason = ""
    @State private var notes = ""
    @State private var saveError: String?
    @State private var isSaving = false

    var body: some View {
        NavigationStack {
            Form {
                if let saveError {
                    Section {
                        Label(saveError, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                    }
                }

                Section("Part") {
                    TextField("Search parts", text: $partSearch)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    Picker("Part", selection: $selectedPartId) {
                        Text("Select...").tag(Int64(0))
                        ForEach(parts) { part in
                            Text(part.displayName).tag(part.id)
                        }
                    }
                }

                Section("Movement") {
                    Picker("Type", selection: $selectedType) {
                        ForEach(QuickLogMovementType.allCases, id: \.self) { type in
                            Label(type.label, systemImage: type.icon).tag(type)
                        }
                    }
                    Stepper("Quantity: \(quantity)", value: $quantity, in: 1...999)
                    DatePicker("Occurred", selection: $occurredAt, displayedComponents: [.date, .hourAndMinute])
                }

                Section("Optional Location") {
                    TextField("From type", text: $fromLocationType)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    TextField("From ID", text: $fromLocationId)
                        .keyboardType(.numberPad)
                    TextField("To type", text: $toLocationType)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    TextField("To ID", text: $toLocationId)
                        .keyboardType(.numberPad)
                }

                Section("Notes") {
                    TextField("Reason", text: $reason)
                    TextField("Notes", text: $notes, axis: .vertical)
                        .lineLimit(2...4)
                }
            }
            .navigationTitle("Quick Log")
            .navigationBarTitleDisplayMode(.inline)
            .interactiveDismissDisabled(isSaving)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .disabled(isSaving)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isSaving ? "Saving..." : "Save") { save() }
                        .disabled(selectedPartId == 0 || isSaving)
                }
            }
            .task { loadParts() }
            .onChange(of: partSearch) { loadParts() }
        }
    }

    private func loadParts() {
        guard let service = appCore.partsService else {
            saveError = "Parts service not available"
            return
        }

        do {
            let rows = try service.listParts(search: partSearch.isEmpty ? nil : partSearch, limit: 30)
            parts = rows.compactMap { row in
                guard let id = row.part.id else { return nil }
                return QuickLogPartItem(id: id, name: row.part.name, code: row.part.code)
            }
            if !parts.contains(where: { $0.id == selectedPartId }) {
                selectedPartId = 0
            }
        } catch {
            saveError = userFriendlyError(error, context: "load parts")
        }
    }

    private func save() {
        guard let service = appCore.warehouseService else {
            saveError = "Warehouse service not available"
            return
        }
        guard let userId = appCore.currentUser?.id else {
            saveError = "User not available"
            return
        }

        do {
            isSaving = true
            saveError = nil
            try service.createQuickLogMovement(
                partId: selectedPartId,
                qty: quantity,
                movementType: selectedType.rawValue,
                occurredAt: occurredAt,
                fromLocationType: optionalText(fromLocationType),
                fromLocationId: optionalId(fromLocationId),
                toLocationType: optionalText(toLocationType),
                toLocationId: optionalId(toLocationId),
                reason: optionalText(reason),
                notes: optionalText(notes),
                performedBy: userId
            )
            isSaving = false
            onComplete()
            dismiss()
        } catch {
            isSaving = false
            saveError = userFriendlyError(error, context: "quick log movement")
        }
    }

    private func optionalText(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func optionalId(_ value: String) -> Int64? {
        guard let text = optionalText(value) else { return nil }
        return Int64(text)
    }
}

private enum QuickLogMovementType: String, CaseIterable {
    case transfer
    case receive
    case consume
    case returnToSupplier = "return_to_supplier"
    case adjustment

    var label: String {
        switch self {
        case .transfer: "Transfer"
        case .receive: "Received"
        case .consume: "Consumed"
        case .returnToSupplier: "Return"
        case .adjustment: "Adjustment"
        }
    }

    var icon: String {
        switch self {
        case .transfer: "arrow.left.arrow.right"
        case .receive: "arrow.down.circle"
        case .consume: "flame"
        case .returnToSupplier: "arrow.uturn.left"
        case .adjustment: "plus.forwardslash.minus"
        }
    }
}

private struct QuickLogPartItem: Identifiable {
    let id: Int64
    let name: String
    let code: String?

    var displayName: String {
        guard let code, !code.isEmpty else { return name }
        return "\(name) (\(code))"
    }
}
