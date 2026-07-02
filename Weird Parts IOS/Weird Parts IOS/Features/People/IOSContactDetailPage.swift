import SwiftUI
import WiredPartCore

/// Detail view for a single contact, showing all info with edit capability.
struct IOSContactDetailPage: View {
    @EnvironmentObject private var appCore: AppCore
    @Environment(\.dismiss) private var dismiss

    let contactId: Int64

    @State private var contact: PeopleService.ContactListItem?
    @State private var isLoading = true
    @State private var loadError: String?

    private enum ActiveSheet: Identifiable {
        case editContact
        case help
        var id: String { String(describing: self) }
    }
    @State private var activeSheet: ActiveSheet?

    var body: some View {
        Group {
            if isLoading {
                ProgressView("Loading contact...")
            } else if let error = loadError {
                ErrorStateView(message: error) { loadData() }
            } else if let contact {
                contactDetail(contact)
            } else {
                EmptyStateView(
                    icon: "person.crop.circle.badge.questionmark",
                    title: "Contact Not Found",
                    message: "This contact may have been deleted."
                )
            }
        }
        .navigationTitle(contact.map { "\($0.firstName) \($0.lastName)" } ?? "Contact")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { loadData() }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                if contact != nil {
                    Button("Edit") { activeSheet = .editContact }
                }
            }
            ToolbarItem(placement: .secondaryAction) {
                Button { activeSheet = .help } label: {
                    Image(systemName: "questionmark.circle")
                }
                .accessibilityLabel("Help")
            }
        }
        .task { loadData() }
        .sheet(item: $activeSheet) { sheet in
            switch sheet {
            case .editContact:
                EditContactSheet(contactId: contactId) { loadData() }
                    .environmentObject(appCore)
                    .presentationDetents([.large])
                    .presentationDragIndicator(.visible)
            case .help:
                PageHelpSheet(
                    title: "Contact Detail Help",
                    sections: [
                        ("Overview", "View and manage contact details including name, type, company, phone, email, and notes."),
                        ("Editing", "Tap Edit to update contact information. Changes are saved immediately.")
                    ]
                )
            }
        }
    }

    // MARK: - Detail Content

    private func contactDetail(_ c: PeopleService.ContactListItem) -> some View {
        List {
            Section("Contact Information") {
                LabeledContent("Name", value: "\(c.firstName) \(c.lastName)")
                if let type = c.contactType {
                    LabeledContent("Type") {
                        ContactTypeBadge(type: type)
                    }
                }
                if let company = c.company, !company.isEmpty {
                    LabeledContent("Role / Company", value: company)
                }
            }

            Section("Contact Methods") {
                if let phone = c.phone, !phone.isEmpty,
                   let phoneURL = URL(string: "tel:\(phone.filter { $0.isNumber || $0 == "+" })") {
                    LabeledContent("Phone") {
                        Link(phone, destination: phoneURL)
                    }
                }
                if let email = c.email, !email.isEmpty,
                   let mailURL = URL(string: "mailto:\(email)") {
                    LabeledContent("Email") {
                        Link(email, destination: mailURL)
                    }
                }
                if c.phone == nil && c.email == nil {
                    Text("No contact methods on file")
                        .foregroundStyle(.secondary)
                        .italic()
                }
            }
        }
        // Fix #149: dismiss keyboard when scrolling contact detail
        .scrollDismissesKeyboard(.interactively)
        .listStyle(.insetGrouped)
    }

    // MARK: - Data Loading

    private func loadData() {
        guard let service = appCore.peopleService else {
            loadError = "Service not available"
            isLoading = false
            return
        }
        do {
            contact = try service.getContact(id: contactId)
            if contact == nil {
                loadError = "Contact not found"
            }
        } catch {
            loadError = userFriendlyError(error, context: "load contact")
        }
        isLoading = false
    }
}

// MARK: - Contact Type Badge

/// Color-coded badge for contact type (matches the list page pattern).
struct ContactTypeBadge: View {
    let type: String

    private var color: Color {
        switch type.lowercased() {
        case "gc": return .blue
        case "supplier": return .purple
        case "contractor": return .orange
        case "owner": return .green
        case "vendor": return .teal
        default: return .gray
        }
    }

    var body: some View {
        Text(type.uppercased())
            .font(.caption2)
            .fontWeight(.semibold)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(color.opacity(0.15))
            .foregroundStyle(color)
            .clipShape(Capsule())
    }
}

// MARK: - Edit Contact Sheet

/// Simple edit sheet for updating contact info.
private struct EditContactSheet: View {
    @EnvironmentObject private var appCore: AppCore
    @Environment(\.dismiss) private var dismiss

    let contactId: Int64
    let onSave: () -> Void

    @State private var firstName = ""
    @State private var lastName = ""
    @State private var phone = ""
    @State private var email = ""
    @State private var role = ""
    @State private var errorMessage: String?
    @State private var isDirty = false
    @State private var showDiscardAlert = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Name") {
                    TextField("First Name", text: $firstName)
                        .onChange(of: firstName) { _, _ in isDirty = true }
                    TextField("Last Name", text: $lastName)
                        .onChange(of: lastName) { _, _ in isDirty = true }
                }
                Section("Contact") {
                    TextField("Phone", text: $phone)
                        .keyboardType(.phonePad)
                        .onChange(of: phone) { _, _ in isDirty = true }
                    TextField("Email", text: $email)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .onChange(of: email) { _, _ in isDirty = true }
                }
                Section("Details") {
                    TextField("Role / Company", text: $role)
                        .onChange(of: role) { _, _ in isDirty = true }
                }
                if let error = errorMessage {
                    Section {
                        Text(error)
                            .foregroundStyle(.red)
                    }
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle("Edit Contact")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        if isDirty { showDiscardAlert = true } else { dismiss() }
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { saveContact() }
                        .disabled(firstName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .alert("Discard changes?", isPresented: $showDiscardAlert) {
                Button("Discard", role: .destructive) { dismiss() }
                Button("Keep Editing", role: .cancel) {}
            } message: {
                Text("Your unsaved changes will be lost.")
            }
            .task { loadContact() }
        }
        .interactiveDismissDisabled(isDirty)
    }

    private func loadContact() {
        guard let service = appCore.peopleService else {
            errorMessage = "People service unavailable"
            return
        }
        do {
            if let c = try service.getContact(id: contactId) {
                firstName = c.firstName
                lastName = c.lastName
                phone = c.phone ?? ""
                email = c.email ?? ""
                role = c.company ?? ""
                isDirty = false
            }
        } catch {
            errorMessage = "Could not load contact"
        }
    }

    private func saveContact() {
        guard let service = appCore.peopleService else {
            errorMessage = "Service not available"
            return
        }
        do {
            try service.updateContact(
                id: contactId,
                firstName: firstName.trimmingCharacters(in: .whitespacesAndNewlines),
                lastName: lastName.trimmingCharacters(in: .whitespacesAndNewlines),
                phone: phone.trimmingCharacters(in: .whitespacesAndNewlines),
                email: email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : email.trimmingCharacters(in: .whitespacesAndNewlines),
                role: role.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : role.trimmingCharacters(in: .whitespacesAndNewlines)
            )
            dismiss()
            onSave()
        } catch {
            errorMessage = userFriendlyError(error, context: "save contact")
        }
    }
}
