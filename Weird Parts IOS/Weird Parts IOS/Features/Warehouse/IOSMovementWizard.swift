import SwiftUI
import WiredPartCore

/// 7-step movement wizard for warehouse part transfers.
///
/// Steps:
/// 1. Select source location
/// 2. Select destination location
/// 3. Select parts to move
/// 4. Enter quantities
/// 5. Add notes/reason
/// 6. Preview summary
/// 7. Execute movement
struct IOSMovementWizard: View {
    @EnvironmentObject private var appCore: AppCore
    @Environment(\.dismiss) private var dismiss

    // Wizard state
    @State private var currentStep = 1
    @State private var sourceLocation = ""
    @State private var destinationLocation = ""
    @State private var selectedParts: [String] = []
    @State private var quantities: [String: Int] = [:]
    @State private var reason = ""
    @State private var notes = ""
    @State private var isExecuting = false
    @State private var errorMessage: String?
    @State private var isComplete = false

    private let totalSteps = 7

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Progress bar
                stepIndicator

                // Content
                ScrollView {
                    stepContent
                        .padding()
                }

                // Navigation buttons
                navigationButtons
            }
            .navigationTitle("Movement Wizard")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .disabled(isExecuting)
                }
            }
        }
    }

    // MARK: - Step Indicator

    private var stepIndicator: some View {
        VStack(spacing: 8) {
            ProgressView(value: Double(currentStep), total: Double(totalSteps))
                .progressViewStyle(.linear)

            Text("Step \(currentStep) of \(totalSteps)")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
    }

    // MARK: - Step Content

    @ViewBuilder
    private var stepContent: some View {
        switch currentStep {
        case 1:
            stepSourceLocation
        case 2:
            stepDestination
        case 3:
            stepSelectParts
        case 4:
            stepQuantities
        case 5:
            stepNotesReason
        case 6:
            stepPreview
        case 7:
            stepExecute
        default:
            Text("Unknown step")
        }
    }

    // Step 1: Source Location
    private var stepSourceLocation: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Source Location")
                .font(.title2)
                .fontWeight(.bold)
            Text("Where are the parts moving from?")
                .foregroundStyle(.secondary)
            TextField("e.g. Warehouse A, Shelf 3", text: $sourceLocation)
                .textFieldStyle(.roundedBorder)
        }
    }

    // Step 2: Destination
    private var stepDestination: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Destination Location")
                .font(.title2)
                .fontWeight(.bold)
            Text("Where are the parts going?")
                .foregroundStyle(.secondary)
            TextField("e.g. Job Site, Truck 5", text: $destinationLocation)
                .textFieldStyle(.roundedBorder)
        }
    }

    // Step 3: Select Parts
    private var stepSelectParts: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Select Parts")
                .font(.title2)
                .fontWeight(.bold)
            Text("Choose which parts to move. You can add part names manually.")
                .foregroundStyle(.secondary)

            ForEach(selectedParts.indices, id: \.self) { index in
                HStack {
                    TextField("Part name", text: Binding(
                        get: { selectedParts[index] },
                        set: { selectedParts[index] = $0 }
                    ))
                    .textFieldStyle(.roundedBorder)

                    Button(role: .destructive) {
                        selectedParts.remove(at: index)
                    } label: {
                        Image(systemName: "trash")
                            .foregroundStyle(.red)
                    }
                }
            }

            Button {
                selectedParts.append("")
            } label: {
                Label("Add Part", systemImage: "plus.circle.fill")
            }
        }
    }

    // Step 4: Quantities
    private var stepQuantities: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Quantities")
                .font(.title2)
                .fontWeight(.bold)

            let validParts = selectedParts.filter { !$0.isEmpty }
            if validParts.isEmpty {
                Text("No parts selected. Go back and add parts.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(validParts, id: \.self) { part in
                    HStack {
                        Text(part)
                            .font(.subheadline)
                        Spacer()
                        TextField("Qty", value: Binding(
                            get: { quantities[part] ?? 1 },
                            set: { quantities[part] = $0 }
                        ), format: .number)
                        .textFieldStyle(.roundedBorder)
                        #if os(iOS)
                        .keyboardType(.numberPad)
                        #endif
                        .frame(width: 80)
                    }
                }
            }
        }
    }

    // Step 5: Notes & Reason
    private var stepNotesReason: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Notes & Reason")
                .font(.title2)
                .fontWeight(.bold)

            VStack(alignment: .leading, spacing: 8) {
                Text("Reason")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TextField("e.g. Job requirement, restocking", text: $reason)
                    .textFieldStyle(.roundedBorder)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Additional Notes")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TextEditor(text: $notes)
                    .frame(minHeight: 80)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.secondary.opacity(0.3))
                    )
            }
        }
    }

    // Step 6: Preview
    private var stepPreview: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Review Movement")
                .font(.title2)
                .fontWeight(.bold)

            VStack(alignment: .leading, spacing: 8) {
                PreviewField(label: "From", value: sourceLocation)
                PreviewField(label: "To", value: destinationLocation)
                PreviewField(label: "Reason", value: reason.isEmpty ? "None" : reason)

                Text("Parts:")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.top, 4)

                let validParts = selectedParts.filter { !$0.isEmpty }
                ForEach(validParts, id: \.self) { part in
                    HStack {
                        Text("• \(part)")
                            .font(.subheadline)
                        Spacer()
                        Text("×\(quantities[part] ?? 1)")
                            .font(.subheadline)
                            .fontWeight(.medium)
                    }
                }
            }
            .padding()
            .dsCard()

            if let error = errorMessage {
                Text(error)
                    .foregroundStyle(.red)
                    .font(.caption)
            }
        }
    }

    // Step 7: Execute
    private var stepExecute: some View {
        VStack(spacing: 24) {
            if isComplete {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 64))
                    .foregroundStyle(.green)
                Text("Movement Complete!")
                    .font(.title2)
                    .fontWeight(.bold)
                Text("Parts have been transferred successfully.")
                    .foregroundStyle(.secondary)
            } else if isExecuting {
                ProgressView()
                    .controlSize(.large)
                Text("Processing movement...")
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 32)
    }

    // MARK: - Navigation Buttons

    private var navigationButtons: some View {
        HStack {
            if currentStep > 1 && !isComplete {
                Button("Back") {
                    withAnimation { currentStep -= 1 }
                }
                .buttonStyle(.bordered)
                .disabled(isExecuting)
            }

            Spacer()

            if currentStep < 6 {
                Button("Next") {
                    withAnimation { currentStep += 1 }
                }
                .buttonStyle(.borderedProminent)
                .disabled(!canProceed)
            } else if currentStep == 6 {
                Button("Execute Movement") {
                    executeMovement()
                }
                .buttonStyle(.borderedProminent)
                .disabled(isExecuting)
            } else if isComplete {
                Button("Done") { dismiss() }
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding()
    }

    private var canProceed: Bool {
        switch currentStep {
        case 1: return !sourceLocation.isEmpty
        case 2: return !destinationLocation.isEmpty
        case 3: return !selectedParts.filter({ !$0.isEmpty }).isEmpty
        case 4: return true
        case 5: return true
        default: return true
        }
    }

    // MARK: - Execute

    private func executeMovement() {
        guard let warehouseService = appCore.warehouseService,
              let partsService = appCore.partsService,
              let userId = appCore.currentUser?.id else {
            errorMessage = "Service unavailable. Please use the full movement form from Warehouse → Movements."
            return
        }

        isExecuting = true
        errorMessage = nil
        currentStep = 7

        // This wizard uses text-based part names, so we look up part IDs via PartsService
        do {
            let allParts = try partsService.listParts(limit: 500)
            for partName in selectedParts where !partName.isEmpty {
                let qty = quantities[partName] ?? 1
                if let match = allParts.first(where: { $0.part.name.lowercased() == partName.lowercased() }),
                   let partId = match.part.id {
                    try warehouseService.createMovement(
                        partId: partId,
                        qty: qty,
                        fromLocationType: sourceLocation.isEmpty ? nil : sourceLocation,
                        fromLocationId: nil,
                        toLocationType: destinationLocation.isEmpty ? nil : destinationLocation,
                        toLocationId: nil,
                        movementType: "transfer",
                        reason: reason.isEmpty ? nil : reason,
                        notes: notes.isEmpty ? nil : notes,
                        performedBy: userId
                    )
                } else {
                    throw NSError(domain: "IOSMovementWizard", code: 404, userInfo: [
                        NSLocalizedDescriptionKey: "Part '\(partName)' not found in catalog."
                    ])
                }
            }
            isExecuting = false
            isComplete = true
        } catch {
            isExecuting = false
            errorMessage = error.localizedDescription
        }
    }
}

// MARK: - Preview Field

private struct PreviewField: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 60, alignment: .leading)
            Text(value)
                .font(.subheadline)
        }
    }
}
