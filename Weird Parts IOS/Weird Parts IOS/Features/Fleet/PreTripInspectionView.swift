import SwiftUI
import WiredPartCore

/// Pre-trip vehicle inspection checklist with 4 sections, 3-state items,
/// pass/fail/conditional result calculation, and odometer + fuel readings.
///
/// Uses FleetService methods: getInspectionChecklist, saveInspection.
/// Critical items (is_critical=true) auto-FAIL the inspection if marked "issue".
struct PreTripInspectionView: View {
    @EnvironmentObject private var appCore: AppCore
    @Environment(\.dismiss) private var dismiss

    let vehicleId: Int64
    let vehicleType: String
    let trailerId: Int64?
    let onComplete: ((String) -> Void)?

    // MARK: - State

    @State private var checklistItems: [InspectionCheckItem] = []
    @State private var generalNotes: String = ""
    @State private var odometerReading: String = ""
    @State private var fuelLevel: Double = 1.0
    @State private var isSaving = false
    @State private var saveError: String?
    @State private var isLoading = true
    @State private var loadError: String?
    @State private var showDiscardConfirmation = false

    private var isDirty: Bool {
        !generalNotes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
        !odometerReading.trimmingCharacters(in: .whitespaces).isEmpty ||
        fuelLevel != 1.0 ||
        checklistItems.contains { !$0.status.isEmpty || !$0.notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }

    // MARK: - Init

    init(vehicleId: Int64, vehicleType: String, trailerId: Int64? = nil,
         onComplete: ((String) -> Void)? = nil) {
        self.vehicleId = vehicleId
        self.vehicleType = vehicleType
        self.trailerId = trailerId
        self.onComplete = onComplete
    }

    // MARK: - Model

    struct InspectionCheckItem: Identifiable {
        let id: Int64
        let templateItemId: Int64
        let section: String
        let itemName: String
        let itemDescription: String?
        let isCritical: Bool
        var status: String  // "", "ok", "issue", "na"
        var notes: String
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    ProgressView("Loading checklist...")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let error = loadError {
                    ErrorStateView(message: error)
                } else {
                    inspectionForm
                }
            }
            .navigationTitle("Pre-Trip Inspection")
            .navigationBarTitleDisplayMode(.inline)
            .dismissSafety(
                isDirty: isDirty,
                isSaving: isSaving,
                showDiscardConfirmation: $showDiscardConfirmation,
                onDiscard: { dismiss() }
            )
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        DismissSafety.cancelOrConfirm(
                            isDirty: isDirty,
                            isSaving: isSaving,
                            dismiss: dismiss,
                            showDiscardConfirmation: $showDiscardConfirmation
                        )
                    }
                        .disabled(isSaving)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Submit") { submitInspection() }
                        .disabled(!allItemsChecked || isSaving)
                        .fontWeight(.semibold)
                }
            }
            .task { loadChecklist() }
        }
    }

    // MARK: - Form

    private var inspectionForm: some View {
        List {
            // Progress section
            progressSection

            // Exterior
            let exterior = checklistItems.filter { $0.section == "exterior" }
            if !exterior.isEmpty {
                Section {
                    ForEach($checklistItems) { $item in
                        if item.section == "exterior" {
                            InspectionItemRow(item: $item)
                        }
                    }
                } header: {
                    sectionHeader("Exterior", icon: "car.side", count: exterior.count,
                                  checked: exterior.filter { $0.status != "" }.count)
                }
            }

            // Interior
            let interior = checklistItems.filter { $0.section == "interior" }
            if !interior.isEmpty {
                Section {
                    ForEach($checklistItems) { $item in
                        if item.section == "interior" {
                            InspectionItemRow(item: $item)
                        }
                    }
                } header: {
                    sectionHeader("Interior", icon: "steeringwheel", count: interior.count,
                                  checked: interior.filter { $0.status != "" }.count)
                }
            }

            // Equipment
            let equipment = checklistItems.filter { $0.section == "equipment" }
            if !equipment.isEmpty {
                Section {
                    ForEach($checklistItems) { $item in
                        if item.section == "equipment" {
                            InspectionItemRow(item: $item)
                        }
                    }
                } header: {
                    sectionHeader("Equipment", icon: "wrench.and.screwdriver", count: equipment.count,
                                  checked: equipment.filter { $0.status != "" }.count)
                }
            }

            // Readings
            readingsSection

            // Notes
            notesSection

            // Error
            if let error = saveError {
                Section {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                        .font(.subheadline)
                }
            }
        }
        .listStyle(.insetGrouped)
        .refreshable { loadChecklist() }
    }

    // MARK: - Progress Section

    private var progressSection: some View {
        Section {
            let checked = checklistItems.filter { $0.status != "" }.count
            let total = checklistItems.count

            VStack(alignment: .leading, spacing: 6) {
                ProgressView(value: Double(checked), total: Double(total))
                    .tint(progressColor(checked: checked, total: total))

                HStack {
                    Text("\(checked)/\(total) items checked")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    if allItemsChecked {
                        let result = calculatedResult
                        HStack(spacing: 4) {
                            Image(systemName: resultIcon(result))
                            Text(result.capitalized)
                        }
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundStyle(resultColor(result))
                    }
                }
            }
        }
    }

    // MARK: - Readings

    private var readingsSection: some View {
        Section("Readings") {
            HStack {
                Label("Odometer", systemImage: "gauge.open.with.lines.needle.33percent")
                    .font(.subheadline)
                Spacer()
                TextField("Miles", text: $odometerReading)
                    .keyboardType(.numberPad)
                    .multilineTextAlignment(.trailing)
                    .frame(maxWidth: 120)
            }

            VStack(spacing: 8) {
                HStack {
                    Label("Fuel Level", systemImage: "fuelpump")
                        .font(.subheadline)
                    Spacer()
                    Text("\(Int(fuelLevel * 100))%")
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .monospacedDigit()
                        .foregroundStyle(fuelColor)
                }
                Slider(value: $fuelLevel, in: 0...1, step: 0.05)
                    .tint(fuelColor)
            }
        }
    }

    // MARK: - Notes

    private var notesSection: some View {
        Section("Notes") {
            TextField("General observations...", text: $generalNotes, axis: .vertical)
                .lineLimit(3...6)
        }
    }

    // MARK: - Section Header

    private func sectionHeader(_ title: String, icon: String, count: Int, checked: Int) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .accessibilityHidden(true)
            Text(title)
            Spacer()
            Text("\(checked)/\(count)")
                .font(.caption2)
                .fontWeight(.medium)
                .foregroundStyle(checked == count ? .green : .secondary)
        }
    }

    // MARK: - Computed

    private var allItemsChecked: Bool {
        checklistItems.allSatisfy { $0.status != "" }
    }

    private var calculatedResult: String {
        let hasCriticalIssue = checklistItems.contains { $0.isCritical && $0.status == "issue" }
        let hasAnyIssue = checklistItems.contains { $0.status == "issue" }
        if hasCriticalIssue { return "fail" }
        if hasAnyIssue { return "conditional" }
        return "pass"
    }

    // MARK: - Colors

    private func progressColor(checked: Int, total: Int) -> Color {
        guard total > 0 else { return .gray }
        let pct = Double(checked) / Double(total)
        if pct < 0.5 { return .orange }
        if pct < 1.0 { return .blue }
        return resultColor(calculatedResult)
    }

    private var fuelColor: Color {
        if fuelLevel < 0.15 { return .red }
        if fuelLevel < 0.3 { return .orange }
        return .green
    }

    private func resultColor(_ result: String) -> Color {
        switch result {
        case "pass": return .green
        case "fail": return .red
        case "conditional": return .orange
        default: return .gray
        }
    }

    private func resultIcon(_ result: String) -> String {
        switch result {
        case "pass": return "checkmark.seal.fill"
        case "fail": return "xmark.seal.fill"
        case "conditional": return "exclamationmark.triangle.fill"
        default: return "questionmark.circle"
        }
    }

    // MARK: - Data Loading

    private func loadChecklist() {
        guard let service = appCore.fleetService else {
            loadError = "Fleet service not available"
            isLoading = false
            return
        }

        do {
            let templates = try service.getInspectionChecklist(
                vehicleType: vehicleType,
                includeTrailer: trailerId != nil
            )

            checklistItems = templates.map { tmpl in
                InspectionCheckItem(
                    id: tmpl.id,
                    templateItemId: tmpl.id,
                    section: tmpl.section,
                    itemName: tmpl.itemName,
                    itemDescription: tmpl.itemDescription,
                    isCritical: tmpl.isCritical,
                    status: "",
                    notes: ""
                )
            }

            if checklistItems.isEmpty {
                loadError = "No checklist items found for vehicle type \"\(vehicleType)\""
            }
        } catch {
            loadError = userFriendlyError(error, context: "load inspection data")
        }

        isLoading = false
    }

    // MARK: - Submit

    private func submitInspection() {
        guard let service = appCore.fleetService else {
            saveError = "Fleet service not available"
            return
        }
        guard let userId = appCore.currentUser?.id else {
            saveError = "No current user"
            return
        }

        let parsedOdometer: Int?
        do {
            parsedOdometer = try FleetNumericFieldParser.optionalWholeNumber(
                odometerReading,
                fieldName: "Odometer"
            )
        } catch {
            saveError = error.localizedDescription
            return
        }

        isSaving = true
        saveError = nil

        let result = calculatedResult

        do {
            try service.saveInspection(
                vehicleId: vehicleId,
                trailerId: trailerId,
                inspectorId: userId,
                result: result,
                items: checklistItems.map { item in
                    FleetService.InspectionItemResult(
                        templateItemId: item.templateItemId,
                        status: item.status,
                        notes: item.notes.isEmpty ? nil : item.notes
                    )
                },
                notes: generalNotes.isEmpty ? nil : generalNotes,
                odometerReading: parsedOdometer,
                fuelLevel: fuelLevel
            )

            onComplete?(result)
            dismiss()
        } catch {
            saveError = userFriendlyError(error, context: "save inspection")
        }

        isSaving = false
    }
}

// MARK: - Inspection Item Row

private struct InspectionItemRow: View {
    @Binding var item: PreTripInspectionView.InspectionCheckItem

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Item name + critical indicator
            HStack(spacing: 6) {
                Text(item.itemName)
                    .font(.subheadline)
                if item.isCritical {
                    Image(systemName: "exclamationmark.circle.fill")
                        .foregroundStyle(.red)
                        .font(.caption)
                        .accessibilityLabel("Critical item")
                }
                Spacer()
            }

            // Description (if provided)
            if let desc = item.itemDescription, !desc.isEmpty {
                Text(desc)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            // Status buttons
            HStack(spacing: 8) {
                InspectionStatusButton(label: "OK", systemImage: "checkmark.circle.fill",
                                       color: .green, isSelected: item.status == "ok") {
                    item.status = "ok"
                    item.notes = ""
                }
                InspectionStatusButton(label: "Issue", systemImage: "xmark.circle.fill",
                                       color: .red, isSelected: item.status == "issue") {
                    item.status = "issue"
                }
                InspectionStatusButton(label: "N/A", systemImage: "minus.circle.fill",
                                       color: .gray, isSelected: item.status == "na") {
                    item.status = "na"
                    item.notes = ""
                }
            }

            // Notes field when issue is selected
            if item.status == "issue" {
                TextField("Describe the issue...", text: $item.notes)
                    .font(.caption)
                    .textFieldStyle(.roundedBorder)
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Status Button

private struct InspectionStatusButton: View {
    let label: String
    let systemImage: String
    let color: Color
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: systemImage)
                Text(label)
            }
            .font(.caption)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(isSelected ? color.opacity(0.2) : Color.clear)
            .clipShape(Capsule())
            .overlay(Capsule().stroke(isSelected ? color : .secondary.opacity(0.3)))
        }
        .buttonStyle(.plain)
        .foregroundStyle(isSelected ? color : .secondary)
    }
}
