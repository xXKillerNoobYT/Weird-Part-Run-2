import SwiftUI
import WiredPartCore

/// Sheet for requesting time off.
struct RequestTimeOffSheet: View {
    @EnvironmentObject private var appCore: AppCore
    @Environment(\.dismiss) private var dismiss

    var onSave: () -> Void

    @State private var startDate = Date()
    @State private var endDate = Date()
    @State private var reason = ""
    @State private var isSaving = false
    @State private var saveError: String?
    @State private var isDirty = false
    @State private var showDiscardConfirmation = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Dates") {
                    DatePicker("Start", selection: $startDate, displayedComponents: .date)
                        .onChange(of: startDate) { _, _ in isDirty = true }
                    DatePicker("End", selection: $endDate, in: startDate..., displayedComponents: .date)
                        .onChange(of: endDate) { _, _ in isDirty = true }
                }

                Section("Reason (Optional)") {
                    TextEditor(text: $reason)
                        .frame(minHeight: 60)
                        .onChange(of: reason) { _, _ in isDirty = true }
                }

                if let error = saveError {
                    Section {
                        Text(error)
                            .foregroundStyle(.red)
                            .font(.caption)
                    }
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle("Request Time Off")
            .navigationBarTitleDisplayMode(.inline)
            .interactiveDismissDisabled(isDirty || isSaving)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        if isDirty { showDiscardConfirmation = true } else { dismiss() }
                    }
                        .disabled(isSaving)
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isSaving {
                        ProgressView()
                    } else {
                        Button("Submit") { submitRequest() }
                            .fontWeight(.semibold)
                    }
                }
            }
            .confirmationDialog(
                "Discard changes?",
                isPresented: $showDiscardConfirmation,
                titleVisibility: .visible
            ) {
                Button("Discard", role: .destructive) { dismiss() }
                Button("Keep Editing", role: .cancel) {}
            } message: {
                Text("Your unsaved time-off request will be lost.")
            }
        }
    }

    private func submitRequest() {
        guard let service = appCore.schedulingService,
              let userId = appCore.currentUser?.id else {
            saveError = "Scheduling service not available"
            return
        }
        isSaving = true
        saveError = nil
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd"
        do {
            _ = try service.createTimeOffRequest(
                userId: userId,
                startDate: fmt.string(from: startDate),
                endDate: fmt.string(from: endDate),
                reason: reason.isEmpty ? nil : reason
            )
            isDirty = false
            dismiss()
            onSave()
        } catch {
            saveError = userFriendlyError(error, context: "save data")
        }
        isSaving = false
    }
}
