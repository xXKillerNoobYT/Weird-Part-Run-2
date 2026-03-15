import SwiftUI
import WiredPartCore

/// Customers list page for iOS.
///
/// Displays a searchable list of customers with company name, contact name,
/// email, and phone. Supports pull-to-refresh and search filtering.
struct IOSCustomersPage: View {
    @EnvironmentObject private var appCore: AppCore

    // MARK: - State

    @State private var customers: [PeopleService.CustomerListItem] = []
    @State private var isLoading = true
    @State private var searchText = ""

    var body: some View {
        NavigationStack {
            customerList
                .navigationTitle("Customers")
                .searchable(text: $searchText, prompt: "Search customers...")
                .onChange(of: searchText) { loadData() }
                .refreshable { loadData() }
                .task { loadData() }
        }
    }

    // MARK: - Customer List

    @ViewBuilder
    private var customerList: some View {
        if isLoading {
            ProgressView("Loading customers...")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if filteredCustomers.isEmpty {
            ContentUnavailableView {
                Label("No Customers", systemImage: "building.2")
            } description: {
                Text("No customers match your search.")
            }
        } else {
            List(filteredCustomers, id: \.id) { customer in
                customerRow(customer)
            }
            #if os(iOS)
            .listStyle(.insetGrouped)
            #endif
        }
    }

    private var filteredCustomers: [PeopleService.CustomerListItem] {
        guard !searchText.isEmpty else { return customers }
        let query = searchText.lowercased()
        return customers.filter {
            ($0.companyName?.lowercased().contains(query) ?? false) ||
            ($0.contactName?.lowercased().contains(query) ?? false) ||
            ($0.email?.lowercased().contains(query) ?? false)
        }
    }

    private func customerRow(_ customer: PeopleService.CustomerListItem) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "building.2.fill")
                .font(.title3)
                .foregroundStyle(Color.accentColor)
                .frame(width: 32)

            VStack(alignment: .leading, spacing: 4) {
                Text(customer.companyName ?? "No Company")
                    .fontWeight(.medium)
                if let contact = customer.contactName, !contact.isEmpty {
                    Label(contact, systemImage: "person")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if let email = customer.email, !email.isEmpty {
                    Label(email, systemImage: "envelope")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            if let phone = customer.phone, !phone.isEmpty {
                Label(phone, systemImage: "phone")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 4)
    }

    // MARK: - Data Loading

    private func loadData() {
        guard let service = appCore.peopleService else { return }
        isLoading = customers.isEmpty
        do {
            customers = try service.listCustomers(
                search: searchText.isEmpty ? nil : searchText
            )
        } catch {
            print("[IOSCustomersPage] Load error: \(error)")
        }
        isLoading = false
    }
}
