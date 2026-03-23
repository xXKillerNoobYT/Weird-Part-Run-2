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
    @State private var loadError: String?
    private enum ActiveSheet: String, Identifiable {
        case addCustomer
        var id: String { rawValue }
    }
    @State private var activeSheet: ActiveSheet?

    var body: some View {
        customerList
            .navigationTitle("Customers")
            .searchable(text: $searchText, prompt: "Search customers...")
            .onChange(of: searchText) { loadData() }
            .refreshable { loadData() }
            .task { loadData() }
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button { activeSheet = .addCustomer } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(item: $activeSheet) { sheet in
                switch sheet {
                case .addCustomer:
                    AddCustomerSheet { loadData() }
                        .environmentObject(appCore)
                }
            }
    }

    // MARK: - Customer List

    @ViewBuilder
    private var customerList: some View {
        if isLoading {
            ProgressView("Loading customers...")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let error = loadError {
            ErrorStateView(message: error) { loadData() }
        } else if filteredCustomers.isEmpty {
            EmptyStateView(
                icon: "building.2",
                title: "No Customers",
                message: searchText.isEmpty ? "No customers have been added yet." : "No customers match your search."
            )
        } else {
            List(filteredCustomers, id: \.id) { customer in
                NavigationLink(destination: IOSCustomerDetailPage(customer: customer)) {
                    customerRow(customer)
                }
            }
            .listStyle(.insetGrouped)
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
        guard let service = appCore.peopleService else {
            isLoading = false
            loadError = "People service unavailable"
            return
        }
        isLoading = customers.isEmpty
        loadError = nil
        do {
            customers = try service.listCustomers(
                search: searchText.isEmpty ? nil : searchText
            )
        } catch {
            loadError = error.localizedDescription
        }
        isLoading = false
    }
}

// MARK: - Add Customer Sheet

private struct AddCustomerSheet: View {
    @EnvironmentObject private var appCore: AppCore
    @Environment(\.dismiss) private var dismiss

    let onSave: () -> Void

    @State private var name = ""
    @State private var companyName = ""
    @State private var email = ""
    @State private var phone = ""
    @State private var address = ""
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("Required") {
                    TextField("Contact Name", text: $name)
                        .textContentType(.name)
                }
                Section("Details") {
                    TextField("Company Name", text: $companyName)
                        .textContentType(.organizationName)
                    TextField("Email", text: $email)
                        .textContentType(.emailAddress)
                        .keyboardType(.emailAddress)
                        .autocapitalization(.none)
                    TextField("Phone", text: $phone)
                        .textContentType(.telephoneNumber)
                        .keyboardType(.phonePad)
                    TextField("Address", text: $address)
                        .textContentType(.fullStreetAddress)
                }
                if let error = errorMessage {
                    Section {
                        Text(error).foregroundStyle(.red).font(.caption)
                    }
                }
            }
            .navigationTitle("Add Customer")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
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
            try service.createCustomer(
                name: name.trimmingCharacters(in: .whitespaces),
                companyName: companyName.isEmpty ? nil : companyName,
                email: email.isEmpty ? nil : email,
                phone: phone.isEmpty ? nil : phone,
                address: address.isEmpty ? nil : address
            )
            onSave()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
