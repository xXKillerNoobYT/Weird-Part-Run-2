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
        case help
        var id: String { rawValue }
    }
    @State private var activeSheet: ActiveSheet?

    var body: some View {
        VStack(spacing: 0) {
            OnboardingBanner(pageId: "people-customers")
            customerList
        }
            .task { appCore.onboardingManager?.markCompleted("customers-view") }
            .navigationTitle("Customers")
            .searchable(text: $searchText, prompt: "Search customers...")
            .onChange(of: searchText) { loadData() }
            .refreshable { loadData() }
            .task { loadData() }
            .onAppear { postPageContext() }
            .onDisappear {
                NotificationCenter.default.post(name: .customersPageInactive, object: nil)
            }
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button { activeSheet = .addCustomer } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("Add customer")
                }
                ToolbarItem(placement: .primaryAction) {
                    Button { activeSheet = .help } label: {
                        Image(systemName: "questionmark.circle")
                    }
                    .accessibilityLabel("Help")
                }
            }
            .sheet(item: $activeSheet) { sheet in
                switch sheet {
                case .addCustomer:
                    AddCustomerSheet { loadData() }
                        .environmentObject(appCore)
                case .help:
                    PageHelpSheet(
                        title: "Customers Help",
                        sections: [
                            ("What This Page Does", "View and manage all customers. Each row shows the company name, primary contact, email, and phone number."),
                            ("How to Use It", "Type in the search bar to filter customers by company name, contact name, or email. Tap a customer to see their full detail page with contacts, job history, billing, and communication logs. Tap the + button to add a new customer."),
                            ("Adding a Customer", "The contact name is required. You can also add a company name, email, phone, and address. Customers appear in the list immediately after saving."),
                            ("Tips", "Pull down to refresh the customer list. Tap into a customer to add additional contacts, record payments, or log communications like calls and meetings.")
                        ]
                    )
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
                .accessibilityHidden(true)

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
            loadError = userFriendlyError(error, context: "load customers")
        }
        isLoading = false
        postPageContext()
    }

    private func postPageContext() {
        NotificationCenter.default.post(
            name: .customersPageActive,
            object: nil,
            userInfo: [
                "context": "Customers Page: \(customers.count) customers, \(filteredCustomers.count) visible, search active: \(!searchText.isEmpty)."
            ]
        )
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
    @State private var isDirty = false
    @State private var showDiscardAlert = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Required") {
                    TextField("Contact Name", text: $name)
                        .textContentType(.name)
                        .onChange(of: name) { _, _ in isDirty = true }
                }
                Section("Details") {
                    TextField("Company Name", text: $companyName)
                        .textContentType(.organizationName)
                        .onChange(of: companyName) { _, _ in isDirty = true }
                    TextField("Email", text: $email)
                        .textContentType(.emailAddress)
                        .keyboardType(.emailAddress)
                        .autocapitalization(.none)
                        .onChange(of: email) { _, _ in isDirty = true }
                    TextField("Phone", text: $phone)
                        .textContentType(.telephoneNumber)
                        .keyboardType(.phonePad)
                        .onChange(of: phone) { _, _ in isDirty = true }
                    TextField("Address", text: $address)
                        .textContentType(.fullStreetAddress)
                        .onChange(of: address) { _, _ in isDirty = true }
                }
                if let error = errorMessage {
                    Section {
                        Text(error).foregroundStyle(.red).font(.caption)
                    }
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle("Add Customer")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        if isDirty { showDiscardAlert = true } else { dismiss() }
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .alert("Discard customer changes?", isPresented: $showDiscardAlert) {
                Button("Discard", role: .destructive) { dismiss() }
                Button("Keep Editing", role: .cancel) {}
            } message: {
                Text("Your unsaved changes will be lost.")
            }
        }
        .interactiveDismissDisabled(isDirty)
    }

    private func save() {
        guard let service = appCore.peopleService else {
            errorMessage = "People service unavailable"
            return
        }
        do {
            try service.createCustomer(
                name: name.trimmingCharacters(in: .whitespacesAndNewlines),
                companyName: companyName.isEmpty ? nil : companyName,
                email: email.isEmpty ? nil : email,
                phone: phone.isEmpty ? nil : phone,
                address: address.isEmpty ? nil : address
            )
            dismiss()
            onSave()
        } catch {
            errorMessage = userFriendlyError(error, context: "save customer")
        }
    }
}
