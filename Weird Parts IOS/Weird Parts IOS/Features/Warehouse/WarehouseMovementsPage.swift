import SwiftUI
import GRDB
import WiredPartCore

/// Warehouse movements listing with search, segment filter, detail sheet, and new-movement form.
///
/// Shows a chronological list of stock movements with from/to locations,
/// part names, quantities, and movement types. Supports filtering by
/// type (All, Transfers, Returns) and searching by part name. Tapping a
/// row opens a detail sheet; the toolbar button opens a new-movement form.
struct WarehouseMovementsPage: View {
    @EnvironmentObject private var appCore: AppCore
    @State private var movements: [WarehouseService.MovementRow] = []
    @State private var isLoading = true
    @State private var searchText = ""
    @State private var selectedFilter = "all"
    @State private var selectedMovement: WarehouseService.MovementRow?
    @State private var showNewMovement = false
    @State private var showDetail = false

    private let filters = ["all", "transfer", "return_to_supplier"]
    private let filterLabels = ["All", "Transfers", "Returns"]

    var body: some View {
        VStack(spacing: 0) {
            // Segment filter
            filterBar

            if isLoading {
                ProgressView("Loading movements...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if filteredMovements.isEmpty {
                emptyState
            } else {
                movementsList
            }
        }
        .searchable(text: $searchText, prompt: "Search by part name...")
        .refreshable { await loadData() }
        .toolbar {
            ToolbarItemGroup(placement: .automatic) {
                Button {
                    showNewMovement = true
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .sheet(isPresented: $showNewMovement) {
            NewMovementSheet { await loadData() }
        }
        .sheet(isPresented: $showDetail) {
            if let movement = selectedMovement {
                MovementDetailSheet(movement: movement)
            }
        }
        #if os(iOS)
        .background(Color(.systemGroupedBackground))
        #elseif os(macOS)
        .background(Color(.systemGroupedBackground))
        #endif
        .task { await loadData() }
    }

    // MARK: - Filter Bar

    @ViewBuilder
    private var filterBar: some View {
        Picker("Filter", selection: $selectedFilter) {
            ForEach(Array(zip(filters, filterLabels)), id: \.0) { value, label in
                Text(label).tag(value)
            }
        }
        .pickerStyle(.segmented)
        .padding(.horizontal)
        .padding(.vertical, 8)
        #if os(iOS)
        .background(Color(.secondarySystemGroupedBackground))
        #elseif os(macOS)
        .background(Color(.secondarySystemGroupedBackground))
        #endif
    }

    // MARK: - Filtered Movements

    private var filteredMovements: [WarehouseService.MovementRow] {
        var result = movements

        if selectedFilter != "all" {
            result = result.filter { $0.movementType == selectedFilter }
        }
        if !searchText.isEmpty {
            let query = searchText.lowercased()
            result = result.filter {
                $0.partName.lowercased().contains(query)
            }
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
                    selectedMovement = movement
                    showDetail = true
                } label: {
                    movementRow(movement)
                }
                .buttonStyle(.plain)
            }
        }
        #if os(iOS)
        .listStyle(.insetGrouped)
        #endif
    }

    @ViewBuilder
    private func movementRow(_ movement: WarehouseService.MovementRow) -> some View {
        HStack(spacing: 12) {
            // Type icon
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
                        Text("\(from.capitalized) -> \(to.capitalized)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 3) {
                Text("x\(movement.qty)")
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

    @ViewBuilder
    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "arrow.left.arrow.right")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text("No Movements Found")
                .font(.title3)
                .fontWeight(.semibold)
            Text("Stock movements will appear here as parts are transferred between locations.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Button {
                showNewMovement = true
            } label: {
                Label("New Movement", systemImage: "plus.circle.fill")
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Data Loading

    @Sendable
    private func loadData() async {
        isLoading = true
        do {
            guard let service = appCore.warehouseService else {
                await MainActor.run { isLoading = false }
                return
            }
            let fetched = try service.listMovements(limit: 200)
            await MainActor.run {
                movements = fetched
                isLoading = false
            }
        } catch {
            await MainActor.run { isLoading = false }
        }
    }

    // MARK: - Helpers

    private func movementIcon(_ type: String) -> String {
        switch type {
        case "transfer": return "arrow.left.arrow.right"
        case "receive": return "arrow.down.circle"
        case "consume": return "flame"
        case "return_to_supplier": return "arrow.uturn.left"
        case "adjustment": return "plus.forwardslash.minus"
        default: return "arrow.left.arrow.right"
        }
    }

    private func movementColor(_ type: String) -> Color {
        switch type {
        case "transfer": return .blue
        case "receive": return .green
        case "consume": return .orange
        case "return_to_supplier": return .purple
        case "adjustment": return .gray
        default: return .blue
        }
    }

    private func movementLabel(_ type: String) -> String {
        switch type {
        case "transfer": return "Transfer"
        case "receive": return "Received"
        case "consume": return "Consumed"
        case "return_to_supplier": return "Returned"
        case "adjustment": return "Adjustment"
        default: return type.capitalized
        }
    }

    private func formatDate(_ dateStr: String?) -> String {
        guard let dateStr else { return "" }
        if dateStr.count >= 10 {
            return String(dateStr.prefix(10))
        }
        return dateStr
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
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func movementLabel(_ type: String) -> String {
        switch type {
        case "transfer": return "Transfer"
        case "receive": return "Received"
        case "consume": return "Consumed"
        case "return_to_supplier": return "Returned"
        case "adjustment": return "Adjustment"
        default: return type.capitalized
        }
    }
}

// MARK: - New Movement Sheet

private struct NewMovementSheet: View {
    let onSave: () async -> Void
    @EnvironmentObject private var appCore: AppCore
    @Environment(\.dismiss) private var dismiss

    @State private var searchText = ""
    @State private var searchResults: [PartSearchRow] = []
    @State private var selectedPartId: Int64?
    @State private var selectedPartName = ""
    @State private var qty = ""
    @State private var movementType = "transfer"
    @State private var fromLocationType = "warehouse"
    @State private var fromLocationId = "1"
    @State private var toLocationType = "truck"
    @State private var toLocationId = "1"
    @State private var reason = ""
    @State private var notes = ""
    @State private var isSaving = false

    private let movementTypes = ["transfer", "receive", "consume", "adjustment", "return_to_supplier"]
    private let locationTypes = ["warehouse", "truck", "trailer", "job", "staging"]

    var body: some View {
        NavigationStack {
            Form {
                // Part selection
                Section("Part") {
                    if selectedPartId != nil {
                        HStack {
                            Text(selectedPartName)
                                .fontWeight(.medium)
                            Spacer()
                            Button("Change") {
                                selectedPartId = nil
                                selectedPartName = ""
                            }
                            .font(.caption)
                        }
                        .frame(minHeight: 44)
                    } else {
                        TextField("Search parts...", text: $searchText)
                            .frame(minHeight: 44)
                            #if os(iOS)
                            .textInputAutocapitalization(.never)
                            #endif
                            .onChange(of: searchText) { _, newValue in
                                Task { await searchParts(query: newValue) }
                            }

                        if !searchResults.isEmpty {
                            ForEach(searchResults, id: \.id) { part in
                                Button {
                                    selectedPartId = part.id
                                    selectedPartName = part.name
                                    searchResults = []
                                    searchText = ""
                                } label: {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(part.name)
                                            .font(.subheadline)
                                            .foregroundStyle(.primary)
                                        if let code = part.code {
                                            Text(code)
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        }
                                    }
                                }
                                .frame(minHeight: 44)
                            }
                        }
                    }
                }

                // Movement type
                Section("Type") {
                    Picker("Movement Type", selection: $movementType) {
                        ForEach(movementTypes, id: \.self) { t in
                            Text(t.replacingOccurrences(of: "_", with: " ").capitalized).tag(t)
                        }
                    }
                }

                // Quantity
                Section("Quantity") {
                    TextField("Quantity", text: $qty)
                        .frame(minHeight: 44)
                        #if os(iOS)
                        .keyboardType(.numberPad)
                        #endif
                }

                // From location
                if movementType == "transfer" || movementType == "consume" || movementType == "return_to_supplier" {
                    Section("From Location") {
                        Picker("Type", selection: $fromLocationType) {
                            ForEach(locationTypes, id: \.self) { t in
                                Text(t.capitalized).tag(t)
                            }
                        }
                        TextField("Location ID", text: $fromLocationId)
                            .frame(minHeight: 44)
                            #if os(iOS)
                            .keyboardType(.numberPad)
                            #endif
                    }
                }

                // To location
                if movementType == "transfer" || movementType == "receive" {
                    Section("To Location") {
                        Picker("Type", selection: $toLocationType) {
                            ForEach(locationTypes, id: \.self) { t in
                                Text(t.capitalized).tag(t)
                            }
                        }
                        TextField("Location ID", text: $toLocationId)
                            .frame(minHeight: 44)
                            #if os(iOS)
                            .keyboardType(.numberPad)
                            #endif
                    }
                }

                // Reason and notes
                Section("Details") {
                    TextField("Reason (optional)", text: $reason)
                        .frame(minHeight: 44)
                    TextField("Notes (optional)", text: $notes)
                        .frame(minHeight: 44)
                }
            }
            .navigationTitle("New Movement")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Execute") {
                        Task {
                            await executeMovement()
                        }
                    }
                    .disabled(selectedPartId == nil || qty.isEmpty || isSaving)
                }
            }
        }
    }

    // MARK: - Part Search

    @Sendable
    private func searchParts(query: String) async {
        guard !query.isEmpty else {
            await MainActor.run { searchResults = [] }
            return
        }
        do {
            let db = appCore.db!
            let pattern = "%\(query)%"
            let rows = try await db.writer.read { dbConn -> [PartSearchRow] in
                let results = try Row.fetchAll(
                    dbConn,
                    sql: """
                        SELECT id, name, code FROM parts
                        WHERE deleted_at IS NULL AND (name LIKE ? OR code LIKE ?)
                        ORDER BY name ASC LIMIT 10
                        """,
                    arguments: [pattern, pattern]
                )
                return results.map { row in
                    PartSearchRow(
                        id: row["id"] as Int64,
                        name: row["name"] as String,
                        code: row["code"] as String?
                    )
                }
            }
            await MainActor.run { searchResults = rows }
        } catch {
            await MainActor.run { searchResults = [] }
        }
    }

    // MARK: - Execute

    @Sendable
    private func executeMovement() async {
        guard let partId = selectedPartId, let quantity = Int(qty), quantity > 0 else { return }
        guard let service = appCore.warehouseService else { return }
        guard let userId = appCore.currentUser?.id else { return }

        await MainActor.run { isSaving = true }

        do {
            let fromType: String? = (movementType == "transfer" || movementType == "consume" || movementType == "return_to_supplier") ? fromLocationType : nil
            let fromId: Int64? = fromType != nil ? Int64(fromLocationId) : nil
            let toType: String? = (movementType == "transfer" || movementType == "receive") ? toLocationType : nil
            let toId: Int64? = toType != nil ? Int64(toLocationId) : nil

            try service.createMovement(
                partId: partId,
                qty: quantity,
                fromLocationType: fromType,
                fromLocationId: fromId,
                toLocationType: toType,
                toLocationId: toId,
                movementType: movementType,
                reason: reason.isEmpty ? nil : reason,
                notes: notes.isEmpty ? nil : notes,
                performedBy: userId
            )

            await onSave()
            await MainActor.run { dismiss() }
        } catch {
            await MainActor.run { isSaving = false }
        }
    }
}

// MARK: - Part Search Row

private struct PartSearchRow: Identifiable, Sendable {
    let id: Int64
    let name: String
    let code: String?
}
