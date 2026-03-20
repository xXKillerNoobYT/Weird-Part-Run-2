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

    var body: some View {
        NavigationStack {
            Form {
                Section("Dates") {
                    DatePicker("Start", selection: $startDate, displayedComponents: .date)
                    DatePicker("End", selection: $endDate, in: startDate..., displayedComponents: .date)
                }

                Section("Reason (Optional)") {
                    TextEditor(text: $reason)
                        .frame(minHeight: 60)
                }

                if let error = saveError {
                    Section {
                        Text(error)
                            .foregroundStyle(.red)
                            .font(.caption)
                    }
                }
            }
            .navigationTitle("Request Time Off")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Submit") { submitRequest() }
                        .disabled(isSaving)
                        .fontWeight(.semibold)
                }
            }
        }
    }

    private func submitRequest() {
        guard let service = appCore.schedulingService,
              let userId = appCore.currentUser?.id else { return }
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
            onSave()
            dismiss()
        } catch {
            saveError = error.localizedDescription
        }
        isSaving = false
    }
}
