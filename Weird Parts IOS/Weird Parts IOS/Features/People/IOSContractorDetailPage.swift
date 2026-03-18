import SwiftUI
import WiredPartCore

/// Contractor detail page showing contact info and W-9 status.
struct IOSContractorDetailPage: View {
    @EnvironmentObject private var appCore: AppCore
    let contractor: PeopleService.ContractorListItem

    var body: some View {
        List {
            Section("Contractor Info") {
                detailRow("Name", "\(contractor.firstName) \(contractor.lastName)")
                if let company = contractor.company, !company.isEmpty {
                    detailRow("Company", company)
                }
            }

            Section("Contact Details") {
                if let email = contractor.email, !email.isEmpty,
                   let encoded = email.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
                   let url = URL(string: "mailto:\(encoded)") {
                    HStack {
                        Text("Email")
                            .foregroundStyle(.secondary)
                        Spacer()
                        Link(email, destination: url)
                    }
                }
                if let phone = contractor.phone, !phone.isEmpty {
                    let digits = phone.filter(\.isNumber)
                    HStack {
                        Text("Phone")
                            .foregroundStyle(.secondary)
                        Spacer()
                        if let url = URL(string: "tel:\(digits)") {
                            Link(phone, destination: url)
                        } else {
                            Text(phone)
                        }
                    }
                }
            }

            // W-9 section
            Section {
                HStack {
                    Image(systemName: "doc.text.fill")
                        .foregroundStyle(Color.accentColor)
                    Text("W-9 Form")
                    Spacer()
                    Text("Not on file")
                        .foregroundStyle(.orange)
                        .font(.caption)
                }
            } header: {
                Text("Tax Documents")
            } footer: {
                Text("W-9 document management will be available in a future update.")
            }
        }
        #if os(iOS)
        .listStyle(.insetGrouped)
        #endif
        .navigationTitle("\(contractor.firstName) \(contractor.lastName)")
    }

    private func detailRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .fontWeight(.medium)
        }
    }
}
