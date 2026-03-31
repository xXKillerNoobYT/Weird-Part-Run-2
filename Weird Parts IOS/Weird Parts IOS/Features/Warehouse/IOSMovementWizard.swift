import SwiftUI
import WiredPartCore

/// 5-step guided wizard for creating stock movements, matching the
/// Windows/React experience adapted for mobile:
///
/// 1. **Locations** — pick From → To with visual flow indicator
/// 2. **Select Parts** — search + add parts (batch up to 20)
/// 3. **Quantities** — set qty per part with +/- controls
/// 4. **Notes** — reason, notes, reference number
/// 5. **Preview & Execute** — summary table, confirm, execute
struct IOSMovementWizard: View {
    var onComplete: () -> Void = {}
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

    // QR scanning
    @State private var showPartScanner = false

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
                FirstVisitHint(pageId: "movementWizard", message: "Follow the 5 steps to move parts. The system guides you through each one.")

                wizardStepper
                Divider()
                ScrollView {
                    stepContent
                        .padding()
                }
                Divider()
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
            .sheet(isPresented: $showPartScanner) {
                QRScanSheet(expectedType: .part) { result in
                    if let partId = result.entityId, result.isFound {
                        addScannedPart(partId: partId, name: result.fields["name"] ?? result.code, code: result.fields["code"])
                    }
                }
                .environmentObject(appCore)
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
        case 1: "Location"
        case 2: "Parts"
        case 3: "Qty"
        case 4: "Notes"
        case 5: "Confirm"
        default: ""
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

            VStack(alignment: .leading, spacing: 8) {
                Text("FROM")
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundStyle(.blue)

                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                    ForEach(locationTypes, id: \.0) { type, label, icon in
                        locationButton(type: type, label: label, icon: icon, selected: fromLocationType == type) {
                            fromLocationType = type
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
            HStack {
                Text("Which parts are moving?")
                    .font(.title3)
                    .fontWeight(.semibold)
                Spacer()
                Button {
                    showPartScanner = true
                } label: {
                    Label("Scan", systemImage: "qrcode.viewfinder")
                        .font(.subheadline)
                }
                .buttonStyle(.bordered)
            }

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
                .onChange(of: partSearchText) {
                    searchParts(query: partSearchText)
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
                    .foregroundStyle(alreadyAdded ? .green : Color.accentColor)
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
                MovementWizardFlowLayout(spacing: 8) {
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
                VStack(spacing: 16) {
                    Image(systemName: "checkmark.circle.fill")
                        .decorativeIconFont(56)
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
                        onComplete()
                        dismiss()
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                }
                .frame(maxWidth: .infinity)
            } else if let error = executeError {
                VStack(spacing: 16) {
                    Image(systemName: "xmark.circle.fill")
                        .decorativeIconFont(56)
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
                Text("Review & Confirm")
                    .font(.title3)
                    .fontWeight(.semibold)

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
                    executeMovement()
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

    // MARK: - Part Search (via service layer)

    private func searchParts(query: String) {
        guard !query.isEmpty, query.count >= 1,
              let service = appCore.partsService else {
            partSearchResults = []
            return
        }

        do {
            let parts = try service.searchParts(query: query, limit: 15)
            partSearchResults = parts.map { part in
                let stock: Int
                if let pid = part.id {
                    stock = (try? service.getPartStockSummary(partId: pid).total) ?? 0
                } else {
                    stock = 0
                }
                return PartSearchRow(
                    id: part.id ?? 0,
                    name: part.name,
                    code: part.code,
                    availableQty: stock
                )
            }
        } catch {
            partSearchResults = []
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

    private func addScannedPart(partId: Int64, name: String, code: String?) {
        guard !selectedParts.contains(where: { $0.partId == partId }) else { return }
        guard selectedParts.count < 20 else { return }

        var availableQty = 999
        if let service = appCore.partsService {
            availableQty = (try? service.getPartStockSummary(partId: partId).total) ?? 999
        }

        selectedParts.append(WizardPart(
            partId: partId,
            name: name,
            code: code,
            qty: 1,
            availableQty: availableQty
        ))
    }

    // MARK: - Execute

    private func executeMovement() {
        guard let service = appCore.warehouseService else {
            executeError = "Service not available"
            return
        }
        guard let userId = appCore.currentUser?.id else {
            executeError = "User not available"
            return
        }

        isExecuting = true
        executeError = nil

        let fromType: String? = fromLocationType.isEmpty ? nil : fromLocationType
        let toType: String? = toLocationType.isEmpty ? nil : toLocationType

        let fromId: Int64?
        if fromType != nil {
            guard let parsed = Int64(fromLocationId) else {
                executeError = "Invalid From location ID"
                isExecuting = false
                return
            }
            fromId = parsed
        } else { fromId = nil }

        let toId: Int64?
        if toType != nil {
            guard let parsed = Int64(toLocationId) else {
                executeError = "Invalid To location ID"
                isExecuting = false
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
            isExecuting = false
            executeSuccess = true
            appCore.onboardingManager?.markCompleted("wh-movement-start")
        } catch {
            isExecuting = false
            executeError = userFriendlyError(error, context: "save movement")
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

private struct MovementWizardFlowLayout: Layout {
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
