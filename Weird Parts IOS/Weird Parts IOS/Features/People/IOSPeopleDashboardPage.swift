import SwiftUI
import WiredPartCore

/// People module dashboard showing live workforce status, time-off,
/// expiring certifications, and team assignments.
struct IOSPeopleDashboardPage: View {
    @EnvironmentObject private var appCore: AppCore

    @State private var workingNow: [PeopleService.WorkerStatus] = []
    @State private var offToday: [PeopleService.EmployeeSummary] = []
    @State private var expiringCerts: [PeopleService.CertificationAlert] = []
    @State private var teamAssignments: [PeopleService.TeamAssignment] = []
    @State private var overdueCustomers: [PeopleService.CustomerPaymentAlert] = []
    @State private var paymentTrackingEnabled = false
    @State private var isLoading = true
    @State private var loadError: String?
    @State private var activeSheet: ActiveSheet?

    private enum ActiveSheet: Identifiable {
        case help
        var id: String { "help" }
    }

    var body: some View {
        VStack(spacing: 0) {
            OnboardingBanner(pageId: "people-dashboard")

            Group {
                if isLoading {
                    ProgressView("Loading...")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let error = loadError {
                    ErrorStateView(message: error) { loadData() }
                } else {
                    dashboardContent
                }
            }
        }
        .navigationTitle("People")
        .task {
            loadData()
            appCore.onboardingManager?.markCompleted("people-dashboard-view")
        }
        .refreshable { loadData() }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { activeSheet = .help } label: {
                    Image(systemName: "questionmark.circle")
                }
            }
        }
        .sheet(item: $activeSheet) { _ in
            PageHelpSheet(
                title: "People Dashboard Help",
                sections: [
                    ("What This Page Does", "The People Dashboard gives you a real-time overview of your workforce. See who is clocked in, who is off today, which certifications are expiring, and which teams are assigned to jobs."),
                    ("How to Use It", "The smart cards at the top summarize key numbers at a glance. Scroll down to see details for each section: Working Now shows live clock-in status, Off Today lists scheduled absences, and Certifications Expiring Soon flags upcoming renewals. Team Assignments Today shows which teams are dispatched."),
                    ("Payment Alerts", "When payment tracking is enabled, overdue customer invoices appear at the bottom with the amount and number of days overdue."),
                    ("Tips", "Pull down to refresh the dashboard with the latest data. Tap into other People pages from the navigation menu to manage employees, customers, contractors, teams, and contacts.")
                ]
            )
        }
    }

    // MARK: - Dashboard Content

    private var dashboardContent: some View {
        List {
            // Smart cards row
            Section {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        smartCard(title: "Working Now", count: workingNow.count, color: .green)
                        smartCard(title: "Off Today", count: offToday.count, color: .orange)
                        smartCard(title: "Cert. Expiring", count: expiringCerts.count,
                                  color: expiringCerts.isEmpty ? .gray : .red)
                        smartCard(title: "Teams Active", count: teamAssignments.count, color: .blue)
                    }
                    .padding(.horizontal)
                }
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
            }

            // Working Now (live)
            Section {
                if workingNow.isEmpty {
                    Text("No one clocked in")
                        .foregroundStyle(.secondary)
                        .font(.subheadline)
                } else {
                    ForEach(workingNow) { worker in
                        HStack {
                            Circle()
                                .fill(.green)
                                .frame(width: 8, height: 8)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(worker.name).font(.headline)
                                Text(worker.jobName ?? "No job")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            VStack(alignment: .trailing, spacing: 2) {
                                Text(worker.elapsedTime)
                                    .font(.caption).monospacedDigit()
                                if let todo = worker.currentTodo {
                                    Text(todo)
                                        .font(.caption2).foregroundStyle(.blue)
                                        .lineLimit(1)
                                }
                            }
                        }
                    }
                }
            } header: {
                HStack {
                    Text("Working Now")
                    Spacer()
                    Text("\(workingNow.count) people")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }

            // Off Today
            Section {
                if offToday.isEmpty {
                    Text("Everyone available")
                        .foregroundStyle(.secondary)
                        .font(.subheadline)
                } else {
                    ForEach(offToday) { employee in
                        HStack {
                            Text(employee.name)
                            Spacer()
                            Text(employee.offReason ?? "Time Off")
                                .font(.caption)
                                .foregroundStyle(.orange)
                        }
                    }
                }
            } header: {
                Text("Off Today")
            }

            // Expiring Certifications
            if !expiringCerts.isEmpty {
                Section {
                    ForEach(expiringCerts) { cert in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(cert.employeeName).font(.headline)
                                Text(cert.certName).font(.caption)
                            }
                            Spacer()
                            VStack(alignment: .trailing, spacing: 2) {
                                Text("Expires")
                                    .font(.caption2).foregroundStyle(.secondary)
                                Text(cert.expiryDate, style: .date)
                                    .font(.caption)
                                    .foregroundStyle(cert.daysUntilExpiry < 14 ? .red : .orange)
                            }
                        }
                    }
                } header: {
                    HStack {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                        Text("Certifications Expiring Soon")
                    }
                }
            }

            // Team Assignments Today
            Section {
                if teamAssignments.isEmpty {
                    Text("No team assignments today")
                        .foregroundStyle(.secondary)
                        .font(.subheadline)
                } else {
                    ForEach(teamAssignments) { assignment in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(assignment.teamName).font(.headline)
                            Text(assignment.jobName).font(.caption).foregroundStyle(.blue)
                            Text("\(assignment.memberCount) members assigned")
                                .font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                }
            } header: {
                Text("Team Assignments Today")
            }

            // Payment Alerts (when tracking enabled)
            if paymentTrackingEnabled && !overdueCustomers.isEmpty {
                Section {
                    ForEach(overdueCustomers) { alert in
                        HStack {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(.red)
                            VStack(alignment: .leading) {
                                Text(alert.customerName).font(.headline)
                                Text("\(alert.overdueDays) days overdue")
                                    .font(.caption).foregroundStyle(.red)
                            }
                            Spacer()
                            Text(formatCurrency(alert.overdueAmount))
                                .font(.headline).foregroundStyle(.red)
                        }
                    }
                } header: {
                    Text("Payment Alerts")
                }
            }
        }
        .listStyle(.insetGrouped)
    }

    // MARK: - Helpers

    private func formatCurrency(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "USD"
        return formatter.string(from: NSNumber(value: value)) ?? "$\(value)"
    }

    // MARK: - Smart Card

    private func smartCard(title: String, count: Int, color: Color) -> some View {
        VStack(spacing: 4) {
            Text("\(count)")
                .font(.title)
                .fontWeight(.bold)
                .foregroundStyle(color)
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(width: 90, height: 70)
        .background(color.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    // MARK: - Data Loading

    private func loadData() {
        guard let service = appCore.peopleService else {
            loadError = "People service unavailable"
            isLoading = false
            return
        }

        do {
            workingNow = try service.getWorkersCurrentlyClocked()
            offToday = try service.getEmployeesOffToday()
            expiringCerts = try service.getExpiringCertifications(withinDays: 30)
            teamAssignments = try service.getTodaysTeamAssignments()

            // Payment alerts
            paymentTrackingEnabled = (try? service.isPaymentTrackingEnabled()) ?? false
            if paymentTrackingEnabled {
                overdueCustomers = (try? service.getOverdueCustomers()) ?? []
            }

            loadError = nil
        } catch {
            loadError = userFriendlyError(error, context: "load people dashboard")
        }
        isLoading = false
    }
}
