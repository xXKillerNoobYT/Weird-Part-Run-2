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
            #if os(iOS)
            .listStyle(.insetGrouped)
            #endif
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
        guard let service = appCore.peopleService else { return }
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
