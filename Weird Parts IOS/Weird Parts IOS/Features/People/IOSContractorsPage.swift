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
        guard let service = appCore.peopleService else { return }
        isLoading = contractors.isEmpty
        loadError = nil
        do {
            let query = searchText.isEmpty ? nil : searchText
            contractors = try service.listContractors(search: query)
        } catch {
            loadError = error.localizedDescription
        }
        isLoading = false
    }
}
