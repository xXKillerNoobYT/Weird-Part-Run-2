import SwiftUI
import WiredPartCore

/// Customer detail page showing company info, contacts, and job history.
struct IOSCustomerDetailPage: View {
    @EnvironmentObject private var appCore: AppCore
    let customer: PeopleService.CustomerListItem

    var body: some View {
        List {
            Section("Company Info") {
                if let company = customer.companyName, !company.isEmpty {
                    detailRow("Company", company)
                }
                if let contact = customer.contactName, !contact.isEmpty {
                    detailRow("Contact", contact)
                }
            }

            Section("Contact Details") {
                if let email = customer.email, !email.isEmpty,
                   let encoded = email.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
                   let url = URL(string: "mailto:\(encoded)") {
                    HStack {
                        Text("Email")
                            .foregroundStyle(.secondary)
                        Spacer()
                        Link(email, destination: url)
                    }
                }
                if let phone = customer.phone, !phone.isEmpty {
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

            // Job history placeholder
            Section("Job History") {
                Text("Job history will be populated from JobsService")
                    .foregroundStyle(.secondary)
                    .font(.caption)
            }
        }
        #if os(iOS)
        .listStyle(.insetGrouped)
        #endif
        .navigationTitle(customer.companyName ?? customer.contactName ?? "Customer")
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
