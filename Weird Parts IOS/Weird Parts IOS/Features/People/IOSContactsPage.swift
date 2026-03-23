import SwiftUI
import WiredPartCore

/// Contacts list page for iOS.
///
/// Displays a searchable list of contacts with name, company, type badge,
/// email, and phone. Supports pull-to-refresh, search, and type filtering.
struct IOSContactsPage: View {
    @EnvironmentObject private var appCore: AppCore

    // MARK: - State

    @State private var contacts: [PeopleService.ContactListItem] = []
    @State private var isLoading = true
    @State private var searchText = ""
    @State private var typeFilter = "all"
    @State private var loadError: String?
    private enum ActiveSheet: String, Identifiable {
        case addContact
        var id: String { rawValue }
    }
    @State private var activeSheet: ActiveSheet?

    private let typeOptions = ["all", "gc", "contractor", "supplier", "vendor", "other"]

    var body: some View {
        VStack(spacing: 0) {
            typePicker
            contactList
        }
        .navigationTitle("Contacts")
        .searchable(text: $searchText, prompt: "Search contacts...")
        .onChange(of: searchText) { loadData() }
        .refreshable { loadData() }
        .task { loadData() }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { activeSheet = .addContact } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .sheet(item: $activeSheet) { sheet in
            switch sheet {
            case .addContact:
                AddContactSheet { loadData() }
                    .environmentObject(appCore)
            }
        }
    }

    // MARK: - Type Picker

    private var typePicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(typeOptions, id: \.self) { type in
                    Button {
                        typeFilter = type
                        loadData()
                    } label: {
                        Text(type == "all" ? "All" : type.replacingOccurrences(of: "_", with: " ").uppercased())
                            .font(.caption)
                            .fontWeight(typeFilter == type ? .bold : .regular)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(
                                Capsule().fill(typeFilter == type ? Color.accentColor : Color.secondary.opacity(0.2))
                            )
                            .foregroundStyle(typeFilter == type ? .white : .primary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
        }
    }

    // MARK: - Contact List

    @ViewBuilder
    private var contactList: some View {
        if isLoading {
            ProgressView("Loading contacts...")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let error = loadError {
            ErrorStateView(message: error) { loadData() }
        } else if filteredContacts.isEmpty {
            ContentUnavailableView {
                Label("No Contacts", systemImage: "person.crop.rectangle.stack")
            } description: {
                Text("No contacts match your criteria.")
            }
        } else {
            List(filteredContacts, id: \.id) { contact in
                contactRow(contact)
            }
            .listStyle(.insetGrouped)
        }
    }

    private var filteredContacts: [PeopleService.ContactListItem] {
        guard !searchText.isEmpty else { return contacts }
        let query = searchText.lowercased()
        return contacts.filter {
            $0.firstName.lowercased().contains(query) ||
            $0.lastName.lowercased().contains(query) ||
            ($0.company?.lowercased().contains(query) ?? false) ||
            ($0.email?.lowercased().contains(query) ?? false)
        }
    }

    private func contactRow(_ contact: PeopleService.ContactListItem) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "person.text.rectangle")
                .font(.title3)
                .foregroundStyle(Color.accentColor)
                .frame(width: 32)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text("\(contact.firstName) \(contact.lastName)")
                        .fontWeight(.medium)
                    if let type = contact.contactType, !type.isEmpty {
                        typeBadge(type)
                    }
                }
                if let company = contact.company, !company.isEmpty {
                    Label(company, systemImage: "building")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if let email = contact.email, !email.isEmpty {
                    Label(email, systemImage: "envelope")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            if let phone = contact.phone, !phone.isEmpty {
                Label(phone, systemImage: "phone")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 4)
    }

    // MARK: - Badges

    private func typeBadge(_ type: String) -> some View {
        let color: Color = switch type {
        case "gc": .blue
        case "contractor": .orange
        case "supplier", "vendor": .green
        default: .secondary
        }
        return Text(type.uppercased())
            .font(.system(.caption2, weight: .semibold))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Capsule().fill(color.opacity(0.15)))
            .foregroundStyle(color)
    }

    // MARK: - Data Loading

    private func loadData() {
        guard let service = appCore.peopleService else {
            isLoading = false
            loadError = "People service unavailable"
            return
        }
        isLoading = contacts.isEmpty
        loadError = nil
        do {
            contacts = try service.listContacts(
                search: searchText.isEmpty ? nil : searchText,
                contactType: typeFilter == "all" ? nil : typeFilter
            )
        } catch {
            loadError = error.localizedDescription
        }
        isLoading = false
    }
}
// MARK: - Add Contact Sheet

private struct AddContactSheet: View {
    @EnvironmentObject private var appCore: AppCore
    @Environment(\.dismiss) private var dismiss

    let onSave: () -> Void

    @State private var firstName = ""
    @State private var lastName = ""
    @State private var phone = ""
    @State private var email = ""
    @State private var contactType = "other"
    @State private var errorMessage: String?

    private let typeOptions = ["gc", "contractor", "supplier", "vendor", "other"]

    var body: some View {
        NavigationStack {
            Form {
                Section("Required") {
                    TextField("First Name", text: $firstName)
                        .textContentType(.givenName)
                    TextField("Phone", text: $phone)
                        .textContentType(.telephoneNumber)
                        .keyboardType(.phonePad)
                }
                Section("Details") {
                    TextField("Last Name", text: $lastName)
                        .textContentType(.familyName)
                    TextField("Email", text: $email)
                        .textContentType(.emailAddress)
                        .keyboardType(.emailAddress)
                        .autocapitalization(.none)
                    Picker("Type", selection: $contactType) {
                        ForEach(typeOptions, id: \.self) { type in
                            Text(type.uppercased()).tag(type)
                        }
                    }
                }
                if let error = errorMessage {
                    Section {
                        Text(error).foregroundStyle(.red).font(.caption)
                    }
                }
            }
            .navigationTitle("Add Contact")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(firstName.trimmingCharacters(in: .whitespaces).isEmpty || phone.isEmpty)
                }
            }
        }
    }

    private func save() {
        guard let service = appCore.peopleService else {
            errorMessage = "People service unavailable"
            return
        }
        do {
            try service.createContact(
                entityType: contactType,
                entityId: 0,
                firstName: firstName.trimmingCharacters(in: .whitespaces),
                lastName: lastName.trimmingCharacters(in: .whitespaces),
                role: "contact",
                phone: phone,
                email: email.isEmpty ? nil : email
            )
            onSave()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

