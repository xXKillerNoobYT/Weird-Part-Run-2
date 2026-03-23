import SwiftUI
import WiredPartCore

/// Customer detail page showing company info, contacts, and job history.
struct IOSCustomerDetailPage: View {
    @EnvironmentObject private var appCore: AppCore
    let customer: PeopleService.CustomerListItem

    @State private var customerJobs: [JobsService.JobListItem] = []
    @State private var jobsError: String?

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

            // Job history
            Section("Job History") {
                if let error = jobsError {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                } else if customerJobs.isEmpty {
                    EmptyStateView(
                        icon: "clock",
                        title: "No Job History",
                        message: "Jobs linked to this customer will appear here."
                    )
                } else {
                    ForEach(customerJobs) { job in
                        NavigationLink(value: job.id) {
                            HStack(spacing: 12) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(job.jobName)
                                        .font(.subheadline)
                                        .fontWeight(.medium)
                                    Text(job.jobNumber)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                StatusBadge(
                                    text: job.status.replacingOccurrences(of: "_", with: " ").capitalized,
                                    color: job.status == "active" ? .green : job.status == "completed" ? .blue : .secondary
                                )
                            }
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(customer.companyName ?? customer.contactName ?? "Customer")
        .refreshable { loadJobHistory() }
        .task { loadJobHistory() }
    }

    private func loadJobHistory() {
        guard let service = appCore.jobsService else {
            jobsError = "Service unavailable"
            return
        }
        do {
            customerJobs = try service.getJobsForCustomer(customerId: customer.id)
        } catch {
            jobsError = error.localizedDescription
        }
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
