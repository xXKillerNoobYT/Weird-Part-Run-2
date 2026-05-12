import SwiftUI
import WiredPartCore

/// Form sheet for creating a new vehicle in the fleet.
struct IOSCreateVehicleSheet: View {
    @EnvironmentObject private var appCore: AppCore
    @Environment(\.dismiss) private var dismiss

    @State private var vehicleNumber = ""
    @State private var vehicleName = ""
    @State private var vehicleType = "truck"
    @State private var make = ""
    @State private var model = ""
    @State private var yearText = ""
    @State private var color = ""
    @State private var vin = ""
    @State private var licensePlate = ""
    @State private var notes = ""
    @State private var isSaving = false
    @State private var errorMessage: String?

    private let vehicleTypes = ["truck", "van", "car", "suv", "trailer", "other"]

    var body: some View {
        NavigationStack {
            Form {
                requiredSection
                vehicleDetailsSection
                registrationSection
                notesSection

                if let error = errorMessage {
                    Section {
                        Text(error)
                            .foregroundStyle(.red)
                            .font(.caption)
                    }
                }
            }
            .navigationTitle("New Vehicle")
            .navigationBarTitleDisplayMode(.inline)
            .interactiveDismissDisabled(isSaving)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { saveVehicle() }
                        .disabled(isSaving || vehicleNumber.isEmpty || vehicleName.isEmpty)
                        .fontWeight(.semibold)
                }
            }
        }
        .presentationDetents([.large])
    }

    // MARK: - Sections

    private var requiredSection: some View {
        Section("Required") {
            TextField("Vehicle Number", text: $vehicleNumber)
            TextField("Vehicle Name", text: $vehicleName)
            Picker("Type", selection: $vehicleType) {
                ForEach(vehicleTypes, id: \.self) { type in
                    Text(type.capitalized).tag(type)
                }
            }
        }
    }

    private var vehicleDetailsSection: some View {
        Section("Details") {
            TextField("Make", text: $make)
            TextField("Model", text: $model)
            TextField("Year", text: $yearText)
                .keyboardType(.numberPad)
            TextField("Color", text: $color)
        }
    }

    private var registrationSection: some View {
        Section("Registration") {
            TextField("VIN", text: $vin)
            TextField("License Plate", text: $licensePlate)
        }
    }

    private var notesSection: some View {
        Section("Notes") {
            TextEditor(text: $notes)
                .frame(minHeight: 60)
        }
    }

    // MARK: - Save

    var onSaved: (() -> Void)?

    private func saveVehicle() {
        guard let fleet = appCore.fleetService else {
            errorMessage = "Fleet service not available."
            return
        }
        isSaving = true
        errorMessage = nil

        do {
            _ = try fleet.createVehicle(
                vehicleNumber: vehicleNumber.trimmingCharacters(in: .whitespaces),
                vehicleName: vehicleName.trimmingCharacters(in: .whitespaces),
                vehicleType: vehicleType,
                make: make.isEmpty ? nil : make,
                model: model.isEmpty ? nil : model,
                year: Int(yearText),
                color: color.isEmpty ? nil : color,
                vin: vin.isEmpty ? nil : vin,
                licensePlate: licensePlate.isEmpty ? nil : licensePlate,
                notes: notes.isEmpty ? nil : notes
            )
            onSaved?()
            dismiss()
        } catch {
            errorMessage = userFriendlyError(error, context: "create vehicle")
        }
        isSaving = false
    }
}
