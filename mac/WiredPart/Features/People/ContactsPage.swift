import SwiftUI
import WiredPartCore

/// Contacts list page.
///
/// Displays a searchable, sortable table of all contacts with name, company,
/// type, email, and phone columns. Type badges use color coding:
/// gc = blue, contractor = orange, supplier = green.
/// Supports searching by name or company.
struct ContactsPage: View {
    @EnvironmentObject private var appCore: AppCore

    // MARK: - Data State

    @State private var contacts: [PeopleService.ContactListItem] = []
    @State private var isLoading = true
    @State private var searchText = ""

    // MARK: - Sorting

    @State private var sortOrder = [KeyPathComparator(\PeopleService.ContactListItem.lastName)]

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            tableContent
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task { load() }
    }

    // MARK: - Toolbar

    private var toolbar: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Contacts")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                Text("\(contacts.count) contact\(contacts.count == 1 ? "" : "s")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            TextField("Search contacts...", text: $searchText)
                .textFieldStyle(.roundedBorder)
                .frame(width: 200)
                .onSubmit { load() }

            Button {
                load()
            } label: {
                Label("Refresh", systemImage: "arrow.clockwise")
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 16)
    }

    // MARK: - Table

    @ViewBuilder
    private var tableContent: some View {
        if isLoading {
            ProgressView("Loading contacts...")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if contacts.isEmpty {
            VStack(spacing: 12) {
                Image(systemName: "person.crop.rectangle.stack")
                    .font(.system(size: 40))
                    .foregroundStyle(.tertiary)
                Text("No contacts found")
                    .font(.headline)
                Text("Contacts will appear here once added.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            Table(sortedContacts, sortOrder: $sortOrder) {
                TableColumn("Name", value: \.lastName) { contact in
                    Text("\(contact.firstName) \(contact.lastName)")
                        .fontWeight(.medium)
                }
                .width(min: 140, ideal: 200)

                TableColumn("Company") { (contact: PeopleService.ContactListItem) in
                    Text(contact.company ?? "-")
                        .font(.callout)
                        .foregroundStyle(contact.company != nil ? .primary : .secondary)
                }
                .width(min: 120, ideal: 180)

                TableColumn("Type") { (contact: PeopleService.ContactListItem) in
                    typeBadge(contact.contactType)
                }
                .width(min: 80, ideal: 110)

                TableColumn("Email") { (contact: PeopleService.ContactListItem) in
                    Text(contact.email ?? "-")
                        .font(.callout)
                        .foregroundStyle(contact.email != nil ? .primary : .secondary)
                }
                .width(min: 160, ideal: 220)

                TableColumn("Phone") { (contact: PeopleService.ContactListItem) in
                    Text(contact.phone ?? "-")
                        .font(.callout)
                        .foregroundStyle(contact.phone != nil ? .primary : .secondary)
                }
                .width(min: 100, ideal: 140)
            }
            .tableStyle(.inset(alternatesRowBackgrounds: true))
        }
    }

    private var sortedContacts: [PeopleService.ContactListItem] {
        contacts.sorted(using: sortOrder)
    }

    // MARK: - Badges

    private func typeBadge(_ contactType: String?) -> some View {
        let label = contactType?.replacingOccurrences(of: "_", with: " ").capitalized ?? "Other"
        let color: Color = switch contactType {
        case "gc": .blue
        case "contractor": .orange
        case "supplier": .green
        default: .secondary
        }
        return Text(label)
            .font(.system(.caption, weight: .semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Capsule().fill(color.opacity(0.15)))
            .foregroundStyle(color)
    }

    // MARK: - Data Loading

    private func load() {
        guard let db = appCore.db else { return }
        let service = PeopleService(db: db)
        isLoading = true
        do {
            let allContacts = try service.listContacts()
            // Client-side search filter
            if searchText.isEmpty {
                contacts = allContacts
            } else {
                let query = searchText.lowercased()
                contacts = allContacts.filter {
                    $0.firstName.lowercased().contains(query) ||
                    $0.lastName.lowercased().contains(query) ||
                    ($0.company?.lowercased().contains(query) ?? false)
                }
            }
        } catch {
            print("[ContactsPage] Load error: \(error)")
        }
        isLoading = false
    }
}
