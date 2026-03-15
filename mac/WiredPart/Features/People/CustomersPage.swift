import SwiftUI
import WiredPartCore

/// Customers list page.
///
/// Displays a searchable, sortable table of all customers with company name,
/// contact name, email, phone, and status columns. Supports searching
/// by company or contact name.
struct CustomersPage: View {
    @EnvironmentObject private var appCore: AppCore

    // MARK: - Data State

    @State private var customers: [PeopleService.CustomerListItem] = []
    @State private var isLoading = true
    @State private var searchText = ""

    // MARK: - Sorting

    @State private var sortOrder = [KeyPathComparator(\PeopleService.CustomerListItem.id)]

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
                Text("Customers")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                Text("\(customers.count) customer\(customers.count == 1 ? "" : "s")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            TextField("Search customers...", text: $searchText)
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
            ProgressView("Loading customers...")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if customers.isEmpty {
            VStack(spacing: 12) {
                Image(systemName: "building.2")
                    .font(.system(size: 40))
                    .foregroundStyle(.tertiary)
                Text("No customers found")
                    .font(.headline)
                Text("Customers will appear here once added.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            Table(sortedCustomers, sortOrder: $sortOrder) {
                TableColumn("Company") { (customer: PeopleService.CustomerListItem) in
                    Text(customer.companyName ?? "-")
                        .fontWeight(.medium)
                }
                .width(min: 140, ideal: 200)

                TableColumn("Contact") { (customer: PeopleService.CustomerListItem) in
                    Text(customer.contactName ?? "-")
                        .font(.callout)
                }
                .width(min: 120, ideal: 180)

                TableColumn("Email") { (customer: PeopleService.CustomerListItem) in
                    Text(customer.email ?? "-")
                        .font(.callout)
                        .foregroundStyle(customer.email != nil ? .primary : .secondary)
                }
                .width(min: 160, ideal: 220)

                TableColumn("Phone") { (customer: PeopleService.CustomerListItem) in
                    Text(customer.phone ?? "-")
                        .font(.callout)
                        .foregroundStyle(customer.phone != nil ? .primary : .secondary)
                }
                .width(min: 100, ideal: 140)
            }
            .tableStyle(.inset(alternatesRowBackgrounds: true))
        }
    }

    private var sortedCustomers: [PeopleService.CustomerListItem] {
        customers.sorted(using: sortOrder)
    }

    // MARK: - Data Loading

    private func load() {
        guard let db = appCore.db else { return }
        let service = PeopleService(db: db)
        isLoading = true
        do {
            let allCustomers = try service.listCustomers()
            // Client-side search filter
            if searchText.isEmpty {
                customers = allCustomers
            } else {
                let query = searchText.lowercased()
                customers = allCustomers.filter {
                    ($0.companyName?.lowercased().contains(query) ?? false) ||
                    ($0.contactName?.lowercased().contains(query) ?? false)
                }
            }
        } catch {
            print("[CustomersPage] Load error: \(error)")
        }
        isLoading = false
    }
}
