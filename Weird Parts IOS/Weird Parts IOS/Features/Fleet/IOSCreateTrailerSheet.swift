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
    @State private var showDiscardConfirmation = false

    private let trailerTypes = ["flatbed", "enclosed", "utility", "dump", "lowboy", "other"]

    private var isDirty: Bool {
        !trailerNumber.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
        trailerType != "flatbed" ||
        !notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

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
                        .accessibilityLabel("Notes")
                        .accessibilityIdentifier("fleet-create-trailer-notes-field")
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
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { saveTrailer() }
                        .disabled(isSaving || trailerNumber.isEmpty)
                        .fontWeight(.semibold)
                }
            }
        }
        .presentationDetents([.large])
    }

    var onSaved: (() -> Void)?

    private func saveTrailer() {
        guard let fleet = appCore.fleetService else {
            errorMessage = "Fleet service not available."
            return
        }
        guard let actorId = appCore.currentUser?.id else {
            errorMessage = "Not signed in."
            return
        }
        isSaving = true
        errorMessage = nil

        do {
            _ = try fleet.createTrailer(
                actorId: actorId,
                trailerNumber: trailerNumber.trimmingCharacters(in: .whitespacesAndNewlines),
                trailerType: trailerType,
                notes: notes.isEmpty ? nil : notes
            )
            onSaved?()
            dismiss()
        } catch {
            errorMessage = userFriendlyError(error, context: "create trailer")
        }
        isSaving = false
    }
}
