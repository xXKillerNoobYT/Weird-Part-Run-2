import SwiftUI
import WiredPartCore

/// Form sheet for creating a new trailer in the fleet.
struct IOSCreateTrailerSheet: View {
    @EnvironmentObject private var appCore: AppCore
    @Environment(\.dismiss) private var dismiss

    @State private var trailerNumber = ""
    @State private var trailerType = "flatbed"
    @State private var notes = ""
    @State private var isSaving = false
    @State private var errorMessage: String?

    private let trailerTypes = ["flatbed", "enclosed", "utility", "dump", "lowboy", "other"]

    var body: some View {
        NavigationStack {
            Form {
                Section("Required") {
                    TextField("Trailer Number", text: $trailerNumber)
                    Picker("Type", selection: $trailerType) {
                        ForEach(trailerTypes, id: \.self) { type in
                            Text(type.capitalized).tag(type)
                        }
                    }
                }

                Section("Notes") {
                    TextEditor(text: $notes)
                        .frame(minHeight: 60)
                }

                if let error = errorMessage {
                    Section {
                        Text(error)
                            .foregroundStyle(.red)
                            .font(.caption)
                    }
                }
            }
            .navigationTitle("New Trailer")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { saveTrailer() }
                        .disabled(isSaving || trailerNumber.isEmpty)
                        .fontWeight(.semibold)
                }
            }
        }
    }

    var onSaved: (() -> Void)?

    private func saveTrailer() {
        guard let fleet = appCore.fleetService else {
            errorMessage = "Fleet service not available."
            return
        }
        isSaving = true
        errorMessage = nil

        do {
            _ = try fleet.createTrailer(
                trailerNumber: trailerNumber.trimmingCharacters(in: .whitespaces),
                trailerType: trailerType,
                notes: notes.isEmpty ? nil : notes
            )
            onSaved?()
            dismiss()
        } catch {
            errorMessage = "Failed to create trailer: \(error.localizedDescription)"
        }
        isSaving = false
    }
}
