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
                ContentUnavailableView(
                    "Contact Not Found",
                    systemImage: "person.crop.circle.badge.questionmark",
                    description: Text("This contact may have been deleted.")
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

// MARK: - Edit Contact Sheet (placeholder)

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

    var body: some View {
        NavigationStack {
            Form {
                Section("Name") {
                    TextField("First Name", text: $firstName)
                    TextField("Last Name", text: $lastName)
                }
                Section("Contact") {
                    TextField("Phone", text: $phone)
                        .keyboardType(.phonePad)
                    TextField("Email", text: $email)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                }
                Section("Details") {
                    TextField("Role / Company", text: $role)
                }
                if let error = errorMessage {
                    Section {
                        Text(error)
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("Edit Contact")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { saveContact() }
                        .disabled(firstName.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .task { loadContact() }
        }
    }

    private func loadContact() {
        guard let service = appCore.peopleService else { return }
        do {
            if let c = try service.getContact(id: contactId) {
                firstName = c.firstName
                lastName = c.lastName
                phone = c.phone ?? ""
                email = c.email ?? ""
                role = c.company ?? ""
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
                firstName: firstName.trimmingCharacters(in: .whitespaces),
                lastName: lastName.trimmingCharacters(in: .whitespaces),
                phone: phone.trimmingCharacters(in: .whitespaces),
                email: email.trimmingCharacters(in: .whitespaces).isEmpty ? nil : email.trimmingCharacters(in: .whitespaces),
                role: role.trimmingCharacters(in: .whitespaces).isEmpty ? nil : role.trimmingCharacters(in: .whitespaces)
            )
            dismiss()
            onSave()
        } catch {
            errorMessage = userFriendlyError(error, context: "save contact")
        }
    }
}
