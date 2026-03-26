import SwiftUI
import WiredPartCore

/// Contacts list page with smart card type filters, sort options,
/// active/inactive sections, and color-coded type badges.
struct IOSContactsPage: View {
    @EnvironmentObject private var appCore: AppCore

    // MARK: - State

    @State private var activeContacts: [PeopleService.ContactListItem] = []
    @State private var inactiveContacts: [PeopleService.ContactListItem] = []
    @State private var typeCounts: [String: Int] = [:]
    @State private var isLoading = true
    @State private var searchText = ""
    @State private var typeFilter = "all"
    @State private var sortOption: ContactSort = .recentlyUpdated
    @State private var showInactive = false
    @State private var loadError: String?

    private enum ActiveSheet: String, Identifiable {
        case addContact
        case help
        var id: String { rawValue }
    }
    @State private var activeSheet: ActiveSheet?

    private enum ContactSort: String, CaseIterable {
        case recentlyUpdated = "Recently Updated"
        case name = "Name"
        case type = "Type"
    }

    private let typeFilters = ["all", "gc", "supplier", "contractor", "owner", "vendor", "active", "inactive"]

    var body: some View {
        VStack(spacing: 0) {
            smartCardsRow
            contactList
        }
        .navigationTitle("Contacts")
        .searchable(text: $searchText, prompt: "Search contacts...")
        .onChange(of: searchText) { loadData() }
        .onChange(of: typeFilter) { loadData() }
        .onChange(of: sortOption) { loadData() }
        .refreshable { loadData() }
        .task { loadData() }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                HStack(spacing: 12) {
                    Menu {
                        Picker("Sort", selection: $sortOption) {
                            ForEach(ContactSort.allCases, id: \.self) { sort in
                                Text(sort.rawValue).tag(sort)
                            }
                        }
                    } label: {
                        Label("Sort", systemImage: "arrow.up.arrow.down")
                    }
                    Button { activeSheet = .addContact } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            ToolbarItem(placement: .primaryAction) {
                Button { activeSheet = .help } label: {
                    Image(systemName: "questionmark.circle")
                }
            }
        }
        .sheet(item: $activeSheet) { sheet in
            switch sheet {
            case .addContact:
                AddContactSheet { loadData() }
                    .environmentObject(appCore)
            case .help:
                PageHelpSheet(
                    title: "Contacts Help",
                    sections: [
                        ("What This Page Does", "View and manage all contacts across your organization. Contacts include GCs (general contractors), suppliers, contractors, owners, vendors, and other external people you work with."),
                        ("Smart Card Filters", "Tap the type cards at the top to filter by contact type: All, GC, Supplier, Contractor, Owner, Vendor, Active, or Inactive. The count on each card shows how many contacts match that type."),
                        ("Sorting & Search", "Use the sort button to order contacts by Recently Updated, Name, or Type. The search bar filters by first name, last name, company, or email."),
                        ("Active vs Inactive", "Active contacts appear in the main list. Inactive contacts are collapsed by default — tap the disclosure arrow to expand them. Inactive rows appear slightly dimmed."),
                        ("Tips", "Pull down to refresh. Contact type badges are color-coded: blue for GC, purple for supplier, orange for contractor, green for owner, and teal for vendor. Tap the + button to add a new contact with a first name and phone number (both required).")
                    ]
                )
            }
        }
    }

    // MARK: - Smart Cards

    private var smartCardsRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(typeFilters, id: \.self) { filter in
                    smartCard(
                        title: displayName(filter),
                        count: typeCounts[filter] ?? 0,
                        isActive: typeFilter == filter
                    ) {
                        typeFilter = filter
                    }
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
        }
    }

    private func smartCard(title: String, count: Int, isActive: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 2) {
                Text("\(count)")
                    .font(.title3).bold()
                    .foregroundStyle(isActive ? .white : .primary)
                Text(title)
                    .font(.caption2)
                    .foregroundStyle(isActive ? .white.opacity(0.8) : .secondary)
            }
            .frame(minWidth: 64)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(isActive ? Color.accentColor : Color(.systemGray6))
            )
        }
        .buttonStyle(.plain)
    }

    private func displayName(_ filter: String) -> String {
        switch filter {
        case "all": return "All"
        case "gc": return "GC"
        case "active": return "Active"
        case "inactive": return "Inactive"
        default: return filter.capitalized
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
        } else if filteredActive.isEmpty && filteredInactive.isEmpty {
            ContentUnavailableView {
                Label("No Contacts", systemImage: "person.crop.rectangle.stack")
            } description: {
                Text("No contacts match your criteria.")
            }
        } else {
            List {
                // Active contacts
                Section {
                    ForEach(filteredActive) { contact in
                        NavigationLink(value: contact.id) {
                            contactRow(contact)
                        }
                    }
                } header: {
                    Text("Active (\(filteredActive.count))")
                }

                // Inactive (collapsed by default)
                if !filteredInactive.isEmpty {
                    Section {
                        DisclosureGroup("Inactive (\(filteredInactive.count))", isExpanded: $showInactive) {
                            ForEach(filteredInactive) { contact in
                                NavigationLink(value: contact.id) {
                                    contactRow(contact)
                                        .opacity(0.6)
                                }
                            }
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
        }
    }

    private var filteredActive: [PeopleService.ContactListItem] {
        guard !searchText.isEmpty else { return activeContacts }
        let query = searchText.lowercased()
        return activeContacts.filter { matchesSearch($0, query: query) }
    }

    private var filteredInactive: [PeopleService.ContactListItem] {
        guard !searchText.isEmpty else { return inactiveContacts }
        let query = searchText.lowercased()
        return inactiveContacts.filter { matchesSearch($0, query: query) }
    }

    private func matchesSearch(_ contact: PeopleService.ContactListItem, query: String) -> Bool {
        contact.firstName.lowercased().contains(query) ||
        contact.lastName.lowercased().contains(query) ||
        (contact.company?.lowercased().contains(query) ?? false) ||
        (contact.email?.lowercased().contains(query) ?? false)
    }

    private func contactRow(_ contact: PeopleService.ContactListItem) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("\(contact.firstName) \(contact.lastName)").font(.headline)
                HStack(spacing: 4) {
                    if let type = contact.contactType, !type.isEmpty {
                        Text(type.capitalized)
                            .font(.caption)
                            .foregroundStyle(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 1)
                            .background(typeColor(type))
                            .clipShape(Capsule())
                    }
                    if let company = contact.company, !company.isEmpty {
                        Text(company).font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            Spacer()
            if let phone = contact.phone, !phone.isEmpty {
                Label(phone, systemImage: "phone")
                    .font(.caption2).foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 2)
    }

    private func typeColor(_ type: String?) -> Color {
        switch type {
        case "gc": return .blue
        case "supplier": return .purple
        case "contractor": return .orange
        case "owner": return .green
        case "vendor": return .teal
        default: return .gray
        }
    }

    // MARK: - Data Loading

    private func loadData() {
        guard let service = appCore.peopleService else {
            isLoading = false
            loadError = "People service unavailable"
            return
        }
        isLoading = activeContacts.isEmpty && inactiveContacts.isEmpty
        loadError = nil
        do {
            let sortKey: String
            switch sortOption {
            case .name: sortKey = "name"
            case .type: sortKey = "type"
            case .recentlyUpdated: sortKey = "recently_updated"
            }

            let filter = typeFilter == "all" ? nil : typeFilter
            let result = try service.getContactsSorted(sortBy: sortKey, typeFilter: filter)
            activeContacts = result.active
            inactiveContacts = result.inactive
            typeCounts = try service.getContactTypeCounts()
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

    private let typeOptions = ["gc", "contractor", "supplier", "vendor", "owner", "other"]

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
