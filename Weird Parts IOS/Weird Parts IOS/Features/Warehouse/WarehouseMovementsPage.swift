import SwiftUI
import GRDB
import WiredPartCore

/// Warehouse movements listing with search, segment filter, detail sheet,
/// and a multi-step movement wizard.
///
/// Shows a chronological list of stock movements with from/to locations,
/// part names, quantities, and movement types. The "+" toolbar button
/// opens a guided 5-step wizard (matching the Windows flow).
struct WarehouseMovementsPage: View {
    @EnvironmentObject private var appCore: AppCore
    @State private var movements: [WarehouseService.MovementRow] = []
    @State private var isLoading = true
    @State private var searchText = ""
    @State private var selectedFilter = "all"
    @State private var selectedMovement: WarehouseService.MovementRow?
    @State private var showNewMovement = false
    @State private var showDetail = false
    @State private var loadError: String?

    private let filters = ["all", "transfer", "return_to_supplier"]
    private let filterLabels = ["All", "Transfers", "Returns"]

    var body: some View {
        VStack(spacing: 0) {
            filterBar

            if isLoading {
                ProgressView("Loading movements…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error = loadError {
                ErrorStateView(message: error) { Task { await loadData() } }
            } else if filteredMovements.isEmpty {
                emptyState
            } else {
                movementsList
            }
        }
        .searchable(text: $searchText, prompt: "Search by part name…")
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
        .fullScreenCover(isPresented: $showNewMovement) {
            MovementWizard { await loadData() }
                .environmentObject(appCore)
        }
        .sheet(isPresented: $showDetail) {
            if let movement = selectedMovement {
                MovementDetailSheet(movement: movement)
            }
        }
        .background(DS.Background.page)
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
        .background(Color(.secondarySystemGroupedBackground))
    }

    // MARK: - Filtered Movements

    private var filteredMovements: [WarehouseService.MovementRow] {
        var result = movements
        if selectedFilter != "all" {
            result = result.filter { $0.movementType == selectedFilter }
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
                    selectedMovement = movement
                    showDetail = true
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
        isLoading = movements.isEmpty
        do {
            guard let service = appCore.warehouseService else {
                await MainActor.run { isLoading = false }
                return
            }
            let fetched = try service.listMovements(limit: 200)
            await MainActor.run {
                movements = fetched
                loadError = nil
                isLoading = false
            }
        } catch {
            print("[WarehouseMovementsPage] Load error: \(error)")
            await MainActor.run {
                loadError = "Failed to load movements: \(error.localizedDescription)"
                isLoading = false
            }
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
        case "transfer": return "Transfer"
        case "receive": return "Received"
        case "consume": return "Consumed"
        case "return_to_supplier": return "Returned"
        case "adjustment": return "Adjustment"
        default: return type.capitalized
        }
    }
}

// ═══════════════════════════════════════════════════════════════════════
// MARK: - Movement Wizard (Multi-Step)
// ═══════════════════════════════════════════════════════════════════════

/// 5-step guided wizard for creating stock movements, matching the
/// Windows/React experience adapted for mobile:
///
/// 1. **Locations** — pick From → To with visual flow indicator
/// 2. **Select Parts** — search + add parts (batch up to 20)
/// 3. **Quantities** — set qty per part with +/- controls
/// 4. **Notes** — reason, notes, reference number
/// 5. **Preview & Execute** — summary table, confirm, execute
///
/// Verification (photos) from the Windows wizard is deferred to a
/// future update since iOS camera integration requires additional setup.
private struct MovementWizard: View {
    let onComplete: () async -> Void
    @EnvironmentObject private var appCore: AppCore
    @Environment(\.dismiss) private var dismiss

    // Wizard state
    @State private var currentStep = 1
    private let totalSteps = 5

    // Step 1: Locations
    @State private var fromLocationType = ""
    @State private var fromLocationId: String = "1"
    @State private var toLocationType = ""
    @State private var toLocationId: String = "1"

    // Step 2: Parts
    @State private var selectedParts: [WizardPart] = []
    @State private var partSearchText = ""
    @State private var partSearchResults: [PartSearchRow] = []

    // Step 3: Quantities (stored in selectedParts[].qty)

    // Step 4: Notes
    @State private var reason = ""
    @State private var notes = ""
    @State private var referenceNumber = ""

    // Step 5: Execute
    @State private var isExecuting = false
    @State private var executeError: String?
    @State private var executeSuccess = false

    // Derived
    private var movementType: String {
        switch (fromLocationType, toLocationType) {
        case ("job", _): return "return_to_supplier"
        case (_, "job"): return "consume"
        default: return "transfer"
        }
    }

    private var canAdvance: Bool {
        switch currentStep {
        case 1: return !fromLocationType.isEmpty && !toLocationType.isEmpty
        case 2: return !selectedParts.isEmpty
        case 3: return selectedParts.allSatisfy { $0.qty > 0 && $0.qty <= $0.availableQty }
        case 4: return true // notes are optional
        case 5: return false // final step
        default: return false
        }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Step indicator
                wizardStepper

                Divider()

                // Step content
                ScrollView {
                    stepContent
                        .padding()
                }

                Divider()

                // Navigation buttons
                navigationBar
            }
            .navigationTitle("New Movement")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .disabled(isExecuting)
                }
            }
        }
    }

    // MARK: - Stepper

    private var wizardStepper: some View {
        HStack(spacing: 0) {
            ForEach(1...totalSteps, id: \.self) { step in
                HStack(spacing: 4) {
                    ZStack {
                        Circle()
                            .fill(step < currentStep ? Color.green : step == currentStep ? Color.accentColor : Color(.systemGray4))
                            .frame(width: 28, height: 28)

                        if step < currentStep {
                            Image(systemName: "checkmark")
                                .font(.caption2)
                                .fontWeight(.bold)
                                .foregroundStyle(.white)
                        } else {
                            Text("\(step)")
                                .font(.caption2)
                                .fontWeight(.semibold)
                                .foregroundStyle(step == currentStep ? .white : .secondary)
                        }
                    }

                    Text(stepLabel(step))
                        .font(.caption2)
                        .foregroundStyle(step == currentStep ? .primary : .secondary)
                        .lineLimit(1)
                }

                if step < totalSteps {
                    Rectangle()
                        .fill(step < currentStep ? Color.green : Color(.systemGray4))
                        .frame(height: 2)
                        .frame(maxWidth: .infinity)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color(.secondarySystemGroupedBackground))
    }

    private func stepLabel(_ step: Int) -> String {
        switch step {
        case 1: return "Location"
        case 2: return "Parts"
        case 3: return "Qty"
        case 4: return "Notes"
        case 5: return "Confirm"
        default: return ""
        }
    }

    // MARK: - Step Content

    @ViewBuilder
    private var stepContent: some View {
        switch currentStep {
        case 1: stepLocations
        case 2: stepSelectParts
        case 3: stepQuantities
        case 4: stepNotes
        case 5: stepPreview
        default: EmptyView()
        }
    }

    // MARK: - Step 1: Locations

    private let locationTypes = [
        ("warehouse", "Warehouse", "building.2.fill"),
        ("staging", "Staging", "tray.2.fill"),
        ("truck", "Truck", "truck.box.fill"),
        ("trailer", "Trailer", "box.truck.fill"),
        ("job", "Job Site", "hammer.fill"),
    ]

    @ViewBuilder
    private var stepLocations: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Where is stock moving?")
                .font(.title3)
                .fontWeight(.semibold)

            // Flow indicator
            if !fromLocationType.isEmpty && !toLocationType.isEmpty {
                HStack {
                    Spacer()
                    flowBadge(fromLocationType, color: .blue)
                    Image(systemName: "arrow.right")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                    flowBadge(toLocationType, color: .green)
                    Spacer()
                }
                .padding(.vertical, 8)
            }

            // From
            VStack(alignment: .leading, spacing: 8) {
                Text("FROM")
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundStyle(.blue)

                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                    ForEach(locationTypes, id: \.0) { type, label, icon in
                        locationButton(type: type, label: label, icon: icon, selected: fromLocationType == type) {
                            fromLocationType = type
                            // Reset TO if same as FROM
                            if toLocationType == type { toLocationType = "" }
                        }
                    }
                }

                if !fromLocationType.isEmpty && fromLocationType != "warehouse" {
                    TextField("\(fromLocationType.capitalized) ID", text: $fromLocationId)
                        .keyboardType(.numberPad)
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: 200)
                }
            }

            Divider()

            // To
            VStack(alignment: .leading, spacing: 8) {
                Text("TO")
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundStyle(.green)

                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                    ForEach(locationTypes, id: \.0) { type, label, icon in
                        locationButton(
                            type: type, label: label, icon: icon,
                            selected: toLocationType == type,
                            disabled: type == fromLocationType
                        ) {
                            toLocationType = type
                        }
                    }
                }

                if !toLocationType.isEmpty && toLocationType != "warehouse" {
                    TextField("\(toLocationType.capitalized) ID", text: $toLocationId)
                        .keyboardType(.numberPad)
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: 200)
                }
            }

            // Movement type indicator
            if !fromLocationType.isEmpty && !toLocationType.isEmpty {
                HStack(spacing: 8) {
                    Image(systemName: "info.circle.fill")
                        .foregroundStyle(.blue)
                    Text("Movement type: **\(movementType.replacingOccurrences(of: "_", with: " ").capitalized)**")
                        .font(.subheadline)
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.blue.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 10))
            }
        }
    }

    @ViewBuilder
    private func locationButton(type: String, label: String, icon: String, selected: Bool, disabled: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.title2)
                Text(label)
                    .font(.caption)
                    .fontWeight(.medium)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(selected ? Color.accentColor.opacity(0.15) : Color(.tertiarySystemGroupedBackground))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(selected ? Color.accentColor : Color.clear, lineWidth: 2)
            )
            .foregroundStyle(disabled ? Color(.tertiaryLabel) : selected ? Color.accentColor : Color.primary)
        }
        .buttonStyle(.plain)
        .disabled(disabled)
    }

    @ViewBuilder
    private func flowBadge(_ locType: String, color: Color) -> some View {
        let info = locationTypes.first { $0.0 == locType }
        HStack(spacing: 4) {
            Image(systemName: info?.2 ?? "questionmark")
                .font(.caption)
            Text(info?.1 ?? locType)
                .font(.caption)
                .fontWeight(.medium)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(color.opacity(0.15))
        .clipShape(Capsule())
        .foregroundStyle(color)
    }

    // MARK: - Step 2: Select Parts

    @ViewBuilder
    private var stepSelectParts: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Which parts are moving?")
                .font(.title3)
                .fontWeight(.semibold)

            partSearchBar
            partSearchResultsList
            selectedPartsList

            if selectedParts.count >= 20 {
                Text("Maximum 20 parts per movement")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
    }

    @ViewBuilder
    private var partSearchBar: some View {
        HStack {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("Search by name or code…", text: $partSearchText)
                .textInputAutocapitalization(.never)
                .onChange(of: partSearchText) { _, newValue in
                    Task { await searchParts(query: newValue) }
                }
            if !partSearchText.isEmpty {
                Button {
                    partSearchText = ""
                    partSearchResults = []
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(10)
        .background(Color(.tertiarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    @ViewBuilder
    private var partSearchResultsList: some View {
        if !partSearchResults.isEmpty {
            VStack(spacing: 0) {
                ForEach(partSearchResults, id: \.id) { part in
                    searchResultRow(part)
                    if part.id != partSearchResults.last?.id {
                        Divider().padding(.leading, 12)
                    }
                }
            }
            .background(Color(.secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 10))
        }
    }

    @ViewBuilder
    private func searchResultRow(_ part: PartSearchRow) -> some View {
        let alreadyAdded = selectedParts.contains(where: { $0.partId == part.id })
        Button {
            addPart(part)
        } label: {
            HStack {
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
                Spacer()
                if let stock = part.availableQty {
                    Text("\(stock) avail")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Image(systemName: alreadyAdded ? "checkmark.circle.fill" : "plus.circle")
                    .foregroundStyle(alreadyAdded ? .green : .accentColor)
            }
            .padding(.vertical, 10)
            .padding(.horizontal, 12)
        }
        .buttonStyle(.plain)
        .disabled(alreadyAdded)
    }

    @ViewBuilder
    private var selectedPartsList: some View {
        if !selectedParts.isEmpty {
            Divider()

            Text("Selected (\(selectedParts.count))")
                .font(.subheadline)
                .fontWeight(.semibold)

            VStack(spacing: 0) {
                ForEach(selectedParts) { part in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(part.name)
                                .font(.subheadline)
                            if let code = part.code {
                                Text(code)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        Button {
                            removePart(part.partId)
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.red.opacity(0.7))
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.vertical, 10)
                    .padding(.horizontal, 12)

                    if part.id != selectedParts.last?.id {
                        Divider().padding(.leading, 12)
                    }
                }
            }
            .background(Color(.secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 10))
        }
    }

    // MARK: - Step 3: Quantities

    @ViewBuilder
    private var stepQuantities: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("How many of each?")
                .font(.title3)
                .fontWeight(.semibold)

            ForEach($selectedParts) { $part in
                quantityCard(part: $part)
            }

            // Total
            let totalQty = selectedParts.reduce(0) { $0 + $1.qty }
            HStack {
                Spacer()
                Text("\(totalQty) unit\(totalQty == 1 ? "" : "s") across \(selectedParts.count) part\(selectedParts.count == 1 ? "" : "s")")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .padding(.top, 4)
        }
    }

    @ViewBuilder
    private func quantityCard(part: Binding<WizardPart>) -> some View {
        let isOverLimit = part.wrappedValue.qty > part.wrappedValue.availableQty
        let bgColor: Color = isOverLimit ? Color.red.opacity(0.08) : Color(.secondarySystemGroupedBackground)
        let borderColor: Color = isOverLimit ? Color.red.opacity(0.5) : Color.clear

        VStack(spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(part.wrappedValue.name)
                        .font(.subheadline)
                        .fontWeight(.medium)
                    Text("Available: \(part.wrappedValue.availableQty)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }

            HStack(spacing: 12) {
                Button {
                    if part.wrappedValue.qty > 1 { part.wrappedValue.qty -= 1 }
                } label: {
                    Image(systemName: "minus.circle.fill")
                        .font(.title2)
                        .foregroundStyle(part.wrappedValue.qty > 1 ? Color.accentColor : Color.secondary)
                }
                .buttonStyle(.plain)
                .disabled(part.wrappedValue.qty <= 1)

                Text("\(part.wrappedValue.qty)")
                    .font(.title2)
                    .fontWeight(.bold)
                    .monospacedDigit()
                    .frame(minWidth: 50)

                Button {
                    if part.wrappedValue.qty < part.wrappedValue.availableQty { part.wrappedValue.qty += 1 }
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.title2)
                        .foregroundStyle(part.wrappedValue.qty < part.wrappedValue.availableQty ? Color.accentColor : Color.secondary)
                }
                .buttonStyle(.plain)
                .disabled(part.wrappedValue.qty >= part.wrappedValue.availableQty)
            }
            .frame(maxWidth: .infinity)

            if isOverLimit {
                Text("Exceeds available stock!")
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 10).fill(bgColor))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(borderColor, lineWidth: 1))
    }

    // MARK: - Step 4: Notes

    @ViewBuilder
    private var stepNotes: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Any additional details?")
                .font(.title3)
                .fontWeight(.semibold)

            Text("All fields are optional.")
                .font(.caption)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 6) {
                Text("Reason")
                    .font(.subheadline)
                    .fontWeight(.medium)

                let reasons = ["Restocking", "Job requirement", "Return/defect", "Inventory correction", "Consolidation"]
                FlowLayout(spacing: 8) {
                    ForEach(reasons, id: \.self) { r in
                        Button {
                            reason = reason == r ? "" : r
                        } label: {
                            Text(r)
                                .font(.subheadline)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(reason == r ? Color.accentColor.opacity(0.15) : Color(.tertiarySystemGroupedBackground))
                                .clipShape(Capsule())
                                .overlay(Capsule().stroke(reason == r ? Color.accentColor : Color.clear, lineWidth: 1))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Reference #")
                    .font(.subheadline)
                    .fontWeight(.medium)
                TextField("PO number, RMA, etc.", text: $referenceNumber)
                    .textFieldStyle(.roundedBorder)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Notes")
                    .font(.subheadline)
                    .fontWeight(.medium)
                TextEditor(text: $notes)
                    .frame(minHeight: 80)
                    .padding(4)
                    .background(Color(.tertiarySystemGroupedBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color(.separator), lineWidth: 0.5))
            }
        }
    }

    // MARK: - Step 5: Preview & Execute

    @ViewBuilder
    private var stepPreview: some View {
        VStack(alignment: .leading, spacing: 16) {
            if executeSuccess {
                // Success state
                VStack(spacing: 16) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 56))
                        .foregroundStyle(.green)
                    Text("Movement Complete!")
                        .font(.title2)
                        .fontWeight(.bold)

                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(selectedParts) { part in
                            HStack {
                                Text(part.name)
                                    .font(.subheadline)
                                Spacer()
                                Text("×\(part.qty)")
                                    .font(.subheadline)
                                    .fontWeight(.semibold)
                            }
                        }
                    }
                    .padding()
                    .background(Color(.secondarySystemGroupedBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 10))

                    Button("Done") {
                        Task {
                            await onComplete()
                            dismiss()
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                }
                .frame(maxWidth: .infinity)
            } else if let error = executeError {
                // Error state
                VStack(spacing: 16) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 56))
                        .foregroundStyle(.red)
                    Text("Movement Failed")
                        .font(.title2)
                        .fontWeight(.bold)
                    Text(error)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                    Button("Retry") {
                        executeError = nil
                    }
                    .buttonStyle(.borderedProminent)
                }
                .frame(maxWidth: .infinity)
            } else {
                // Preview
                Text("Review & Confirm")
                    .font(.title3)
                    .fontWeight(.semibold)

                // Route
                HStack {
                    flowBadge(fromLocationType, color: .blue)
                    Image(systemName: "arrow.right")
                        .foregroundStyle(.secondary)
                    flowBadge(toLocationType, color: .green)
                    Spacer()
                    Text(movementType.replacingOccurrences(of: "_", with: " ").capitalized)
                        .font(.caption)
                        .fontWeight(.medium)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.accentColor.opacity(0.12))
                        .clipShape(Capsule())
                }

                // Parts table
                VStack(spacing: 0) {
                    HStack {
                        Text("Part")
                            .font(.caption)
                            .fontWeight(.bold)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Text("Qty")
                            .font(.caption)
                            .fontWeight(.bold)
                            .frame(width: 50, alignment: .trailing)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color(.tertiarySystemGroupedBackground))

                    ForEach(selectedParts) { part in
                        HStack {
                            VStack(alignment: .leading, spacing: 1) {
                                Text(part.name)
                                    .font(.subheadline)
                                if let code = part.code {
                                    Text(code)
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            Text("\(part.qty)")
                                .font(.subheadline)
                                .fontWeight(.semibold)
                                .monospacedDigit()
                                .frame(width: 50, alignment: .trailing)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        Divider().padding(.leading, 12)
                    }
                }
                .background(Color(.secondarySystemGroupedBackground))
                .clipShape(RoundedRectangle(cornerRadius: 10))

                // Summary
                let totalQty = selectedParts.reduce(0) { $0 + $1.qty }
                Text("\(totalQty) unit\(totalQty == 1 ? "" : "s") across \(selectedParts.count) part\(selectedParts.count == 1 ? "" : "s")")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                if !reason.isEmpty {
                    LabeledContent("Reason", value: reason)
                        .font(.subheadline)
                }
                if !referenceNumber.isEmpty {
                    LabeledContent("Reference", value: referenceNumber)
                        .font(.subheadline)
                }
                if !notes.isEmpty {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Notes")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(notes)
                            .font(.subheadline)
                    }
                }

                // Warning
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                    Text("This action cannot be undone.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.orange.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
        }
    }

    // MARK: - Navigation Bar

    private var navigationBar: some View {
        HStack {
            if currentStep > 1 && !executeSuccess {
                Button {
                    withAnimation { currentStep -= 1 }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left")
                        Text("Back")
                    }
                    .font(.subheadline)
                }
                .disabled(isExecuting)
            }

            Spacer()

            if currentStep < totalSteps {
                Button {
                    withAnimation { currentStep += 1 }
                } label: {
                    HStack(spacing: 4) {
                        Text("Next")
                        Image(systemName: "chevron.right")
                    }
                    .font(.subheadline)
                    .fontWeight(.semibold)
                }
                .buttonStyle(.borderedProminent)
                .disabled(!canAdvance)
            } else if !executeSuccess && executeError == nil {
                Button {
                    Task { await executeMovement() }
                } label: {
                    HStack(spacing: 4) {
                        if isExecuting {
                            ProgressView()
                                .controlSize(.small)
                        }
                        Text(isExecuting ? "Executing…" : "Execute Movement")
                    }
                    .font(.subheadline)
                    .fontWeight(.semibold)
                }
                .buttonStyle(.borderedProminent)
                .tint(.green)
                .disabled(isExecuting)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color(.secondarySystemGroupedBackground))
    }

    // MARK: - Part Search

    @Sendable
    private func searchParts(query: String) async {
        guard !query.isEmpty, query.count >= 1 else {
            await MainActor.run { partSearchResults = [] }
            return
        }
        guard let db = appCore.db else { return }

        do {
            let pattern = "%\(query)%"
            let rows = try await db.writer.read { conn -> [PartSearchRow] in
                let results = try Row.fetchAll(
                    conn,
                    sql: """
                        SELECT p.id, p.name, p.code,
                               COALESCE((SELECT SUM(se.quantity) FROM stock_entries se
                                         WHERE se.part_id = p.id AND se.deleted_at IS NULL), 0) AS available_qty
                        FROM parts p
                        WHERE p.deleted_at IS NULL AND (p.name LIKE ? OR p.code LIKE ?)
                        ORDER BY p.name ASC LIMIT 15
                        """,
                    arguments: [pattern, pattern]
                )
                return results.map { row in
                    PartSearchRow(
                        id: row["id"] as Int64,
                        name: row["name"] as String,
                        code: row["code"] as String?,
                        availableQty: row["available_qty"] as Int?
                    )
                }
            }
            await MainActor.run { partSearchResults = rows }
        } catch {
            await MainActor.run { partSearchResults = [] }
        }
    }

    private func addPart(_ part: PartSearchRow) {
        guard !selectedParts.contains(where: { $0.partId == part.id }) else { return }
        guard selectedParts.count < 20 else { return }
        selectedParts.append(WizardPart(
            partId: part.id,
            name: part.name,
            code: part.code,
            qty: 1,
            availableQty: part.availableQty ?? 999
        ))
    }

    private func removePart(_ partId: Int64) {
        selectedParts.removeAll { $0.partId == partId }
    }

    // MARK: - Execute

    @Sendable
    private func executeMovement() async {
        guard let service = appCore.warehouseService else { return }
        guard let userId = appCore.currentUser?.id else { return }

        await MainActor.run {
            isExecuting = true
            executeError = nil
        }

        let fromType: String? = fromLocationType.isEmpty ? nil : fromLocationType
        let toType: String? = toLocationType.isEmpty ? nil : toLocationType

        let fromId: Int64?
        if fromType != nil {
            guard let parsed = Int64(fromLocationId) else {
                await MainActor.run { executeError = "Invalid From location ID"; isExecuting = false }
                return
            }
            fromId = parsed
        } else { fromId = nil }

        let toId: Int64?
        if toType != nil {
            guard let parsed = Int64(toLocationId) else {
                await MainActor.run { executeError = "Invalid To location ID"; isExecuting = false }
                return
            }
            toId = parsed
        } else { toId = nil }

        let combinedNotes: String? = {
            var parts: [String] = []
            if !referenceNumber.isEmpty { parts.append("Ref: \(referenceNumber)") }
            if !notes.isEmpty { parts.append(notes) }
            return parts.isEmpty ? nil : parts.joined(separator: " | ")
        }()

        do {
            for part in selectedParts {
                try service.createMovement(
                    partId: part.partId,
                    qty: part.qty,
                    fromLocationType: fromType,
                    fromLocationId: fromId,
                    toLocationType: toType,
                    toLocationId: toId,
                    movementType: movementType,
                    reason: reason.isEmpty ? nil : reason,
                    notes: combinedNotes,
                    performedBy: userId
                )
            }
            await MainActor.run {
                isExecuting = false
                executeSuccess = true
            }
        } catch {
            await MainActor.run {
                isExecuting = false
                executeError = error.localizedDescription
            }
        }
    }
}

// MARK: - Wizard Part Model

private struct WizardPart: Identifiable, Sendable {
    let id = UUID()
    let partId: Int64
    let name: String
    let code: String?
    var qty: Int
    let availableQty: Int
}

// MARK: - Part Search Row

private struct PartSearchRow: Identifiable, Sendable {
    let id: Int64
    let name: String
    let code: String?
    let availableQty: Int?
}

// MARK: - Flow Layout (for reason chips)

private struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = layout(proposal: proposal, subviews: subviews)
        return result.size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = layout(proposal: proposal, subviews: subviews)
        for (index, origin) in result.origins.enumerated() {
            subviews[index].place(at: CGPoint(x: bounds.minX + origin.x, y: bounds.minY + origin.y), proposal: .unspecified)
        }
    }

    private func layout(proposal: ProposedViewSize, subviews: Subviews) -> (size: CGSize, origins: [CGPoint]) {
        let maxWidth = proposal.width ?? .infinity
        var origins: [CGPoint] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > maxWidth && x > 0 {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            origins.append(CGPoint(x: x, y: y))
            rowHeight = max(rowHeight, size.height)
            x += size.width + spacing
        }

        return (CGSize(width: maxWidth, height: y + rowHeight), origins)
    }
}
