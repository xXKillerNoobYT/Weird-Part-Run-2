import SwiftUI
import WiredPartCore

/// Lists contractors (sub-contractors) from the contacts table
/// where contact_type = 'contractor'.
///
/// Shows name, company, phone, and email. Supports search filtering.
struct IOSContractorsPage: View {
    @EnvironmentObject private var appCore: AppCore

    @State private var contractors: [PeopleService.ContractorListItem] = []
    @State private var searchText = ""
    @State private var isLoading = true
    @State private var loadError: String?

    private enum ActiveSheet: Identifiable {
        case create
        case edit(PeopleService.ContractorListItem)
        case help

        var id: String {
            switch self {
            case .create: return "create"
            case .edit(let c): return "edit-\(c.id)"
            case .help: return "help"
            }
        }
    }
    @State private var activeSheet: ActiveSheet?

    var body: some View {
        Group {
            if isLoading {
                ProgressView("Loading contractors…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error = loadError {
                ErrorStateView(message: error) { loadData() }
            } else if contractors.isEmpty {
                EmptyStateView(
                    icon: "person.badge.shield.checkmark.fill",
                    title: "No Contractors",
                    message: "No sub-contractors have been added yet."
                )
            } else {
                contractorList
            }
        }
        .searchable(text: $searchText, prompt: "Search contractors…")
        .onChange(of: searchText) { _, _ in loadData() }
        .task { loadData() }
        .refreshable { loadData() }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { activeSheet = .create } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("Add contractor")
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
            case .create:
                AddContractorSheet { loadData() }
                    .environmentObject(appCore)
            case .edit:
                // Future: edit contractor sheet
                EmptyView()
            case .help:
                PageHelpSheet(
                    title: "Contractors Help",
                    sections: [
                        ("What This Page Does", "View and manage sub-contractors your company works with. Each row shows the contractor's name, company, phone, and email."),
                        ("How to Use It", "Use the search bar to filter by name, company, phone, or email. Tap a contractor to see their full detail page with qualifications, performance ratings, job history, and notes. Tap the + button to add a new contractor."),
                        ("Adding a Contractor", "A company name is required. You can also add a contact name, phone, email, and trade or specialty. The trade is saved as a note for reference."),
                        ("Tips", "Pull down to refresh the list. Contractor detail pages include qualification tracking for licenses, insurance, and W-9 status, plus a performance rating system for quality, reliability, and timeliness.")
                    ]
                )
            }
        }
    }

    private var contractorList: some View {
        List(contractors) { contractor in
            NavigationLink(destination: IOSContractorDetailPage(contractor: contractor)) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("\(contractor.firstName) \(contractor.lastName)")
                            .font(.headline)
                        Spacer()
                        if let company = contractor.company, !company.isEmpty {
                            Text(company)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 2)
                                .background(Capsule().fill(Color(.systemGray5)))
                        }
                    }

                    if let phone = contractor.phone, !phone.isEmpty {
                        Label(phone, systemImage: "phone.fill")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    if let email = contractor.email, !email.isEmpty {
                        Label(email, systemImage: "envelope.fill")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }
                .padding(.vertical, 2)
            }
        }
        .listStyle(.insetGrouped)
    }

    private func loadData() {
        guard let service = appCore.peopleService else {
            isLoading = false
            loadError = "People service unavailable"
            return
        }
        isLoading = contractors.isEmpty
        loadError = nil
        do {
            let query = searchText.isEmpty ? nil : searchText
            contractors = try service.listContractors(search: query)
        } catch {
            loadError = userFriendlyError(error, context: "load contractors")
        }
        isLoading = false
    }
}
// MARK: - Add Contractor Sheet

private struct AddContractorSheet: View {
    @EnvironmentObject private var appCore: AppCore
    @Environment(\.dismiss) private var dismiss

    let onSave: () -> Void

    @State private var companyName = ""
    @State private var contactName = ""
    @State private var email = ""
    @State private var phone = ""
    @State private var trade = ""
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("Required") {
                    TextField("Company Name", text: $companyName)
                        .textContentType(.organizationName)
                }
                Section("Details") {
                    TextField("Contact Name", text: $contactName)
                        .textContentType(.name)
                    TextField("Phone", text: $phone)
                        .textContentType(.telephoneNumber)
                        .keyboardType(.phonePad)
                    TextField("Email", text: $email)
                        .textContentType(.emailAddress)
                        .keyboardType(.emailAddress)
                        .autocapitalization(.none)
                    TextField("Trade / Specialty", text: $trade)
                }
                if let error = errorMessage {
                    Section {
                        Text(error).foregroundStyle(.red).font(.caption)
                    }
                }
            }
            .navigationTitle("Add Contractor")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(companyName.trimmingCharacters(in: .whitespaces).isEmpty)
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
            try service.createContractor(
                companyName: companyName.trimmingCharacters(in: .whitespaces),
                contactName: contactName.isEmpty ? nil : contactName,
                email: email.isEmpty ? nil : email,
                phone: phone.isEmpty ? nil : phone,
                notes: trade.isEmpty ? nil : "Trade: \(trade)"
            )
            onSave()
            dismiss()
        } catch {
            errorMessage = userFriendlyError(error, context: "load contractors")
        }
    }
}
