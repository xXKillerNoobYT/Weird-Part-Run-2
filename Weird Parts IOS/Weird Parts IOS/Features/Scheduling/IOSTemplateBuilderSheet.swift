import SwiftUI
import WiredPartCore

/// Visual dispatch template creation/editing sheet.
///
/// Allows building a dispatch template with name, description,
/// day assignments, and default crew configuration.
struct IOSTemplateBuilderSheet: View {
    @EnvironmentObject private var appCore: AppCore
    @Environment(\.dismiss) private var dismiss

    @State private var templateName = ""
    @State private var templateDescription = ""
    @State private var selectedDays: Set<String> = []
    @State private var crewSize = 2
    @State private var defaultJobId: Int64?
    @State private var isSaving = false
    @State private var actionError: String?

    private let weekdays = ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"]

    var body: some View {
        NavigationStack {
            Form {
                basicInfoSection
                daysSection
                crewSection
            }
            .navigationTitle("New Template")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { saveTemplate() }
                        .disabled(isSaving || templateName.isEmpty)
                        .fontWeight(.semibold)
                }
            }
            .alert("Save Failed", isPresented: Binding(get: { actionError != nil }, set: { if !$0 { actionError = nil } })) {
                Button("OK") { actionError = nil }
            } message: {
                Text(actionError ?? "")
            }
        }
    }

    private var basicInfoSection: some View {
        Section("Template Info") {
            TextField("Template Name", text: $templateName)
            TextField("Description (optional)", text: $templateDescription)
        }
    }

    private var daysSection: some View {
        Section("Active Days") {
            ForEach(weekdays, id: \.self) { day in
                Toggle(day, isOn: Binding(
                    get: { selectedDays.contains(day) },
                    set: { isOn in
                        if isOn { selectedDays.insert(day) }
                        else { selectedDays.remove(day) }
                    }
                ))
            }
        }
    }

    private var crewSection: some View {
        Section {
            Stepper("Default Crew Size: \(crewSize)", value: $crewSize, in: 1...20)
        } header: {
            Text("Crew")
        } footer: {
            Text("Number of workers to assign by default when using this template.")
        }
    }

    private func saveTemplate() {
        guard let service = appCore.settingsService else {
            actionError = "Settings service not available"
            isSaving = false
            return
        }
        isSaving = true
        do {
            // Store template as a settings entry until full template service is available
            let daysString = selectedDays.sorted().joined(separator: ",")
            let key = "template_\(templateName.lowercased().replacingOccurrences(of: " ", with: "_"))"
            try service.upsertSettingsMap([
                "\(key)_name": templateName,
                "\(key)_description": templateDescription,
                "\(key)_days": daysString,
                "\(key)_crew_size": "\(crewSize)",
            ], category: "dispatch_templates")
            isSaving = false
            dismiss()
        } catch {
            actionError = error.localizedDescription
            isSaving = false
        }
    }
}
