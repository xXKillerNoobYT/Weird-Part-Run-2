import SwiftUI
import GRDB
import WiredPartCore

/// Job detail page showing full job info, team members, parts, and labor summary.
///
/// Provides a comprehensive view of a single job with sections for job info,
/// address, budget/billing, team members, assigned parts, and labor history.
/// The user picks a job from a dropdown to view details.
struct JobDetailPage: View {
    @EnvironmentObject private var appCore: AppCore

    // MARK: - State

    @State private var jobs: [JobsService.JobListItem] = []
    @State private var selectedJobId: Int64?
    @State private var detail: JobsService.JobDetail?
    @State private var detailError: String?
    @State private var teamMembers: [JobsService.TeamMemberRow] = []
    @State private var jobParts: [JobsService.JobPartRow] = []
    @State private var laborSummary: JobsService.LaborSummary?
    @State private var isLoading = true

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            detailContent
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task { loadJobList() }
    }

    // MARK: - Toolbar

    private var toolbar: some View {
        HStack(spacing: 12) {
            Text("Job Detail")
                .font(.largeTitle)
                .fontWeight(.bold)

            Spacer()

            Picker("Select Job", selection: $selectedJobId) {
                Text("Select a job...").tag(nil as Int64?)
                ForEach(jobs, id: \.id) { job in
                    Text("\(job.jobNumber) — \(job.jobName)").tag(job.id as Int64?)
                }
            }
            .pickerStyle(.menu)
            .frame(width: 300)
            .onChange(of: selectedJobId) { loadDetail() }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 16)
    }

    // MARK: - Detail Content

    @ViewBuilder
    private var detailContent: some View {
        if selectedJobId == nil {
            VStack(spacing: 12) {
                Image(systemName: "doc.text.magnifyingglass")
                    .font(.system(size: 40))
                    .foregroundStyle(.tertiary)
                Text("Select a job above to view details")
                    .font(.headline)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if isLoading {
            ProgressView("Loading job detail...")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let detailError {
            VStack(spacing: 12) {
                Image(systemName: "exclamationmark.triangle")
                    .font(.system(size: 40))
                    .foregroundStyle(.orange)
                Text(detailError)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let detail {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    jobInfoSection(detail)
                    addressSection(detail)
                    budgetSection(detail)
                    teamSection
                    partsSection
                    laborSection
                }
                .padding(24)
            }
        } else {
            Text("Job not found")
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    // MARK: - Sections

    private func jobInfoSection(_ job: JobsService.JobDetail) -> some View {
        GroupBox("Job Information") {
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], alignment: .leading, spacing: 12) {
                infoRow("Job Number", job.jobNumber)
                infoRow("Job Name", job.jobName)
                infoRow("Customer", job.customerName ?? "—")
                infoRow("Status", job.status.capitalized)
                infoRow("Priority", job.priority.capitalized)
                infoRow("Type", job.jobType)
                infoRow("Start Date", job.startDate ?? "—")
                infoRow("Due Date", job.dueDate ?? "—")
                if let lead = job.leadUserName {
                    infoRow("Lead", lead)
                }
            }
            .padding(8)
        }
    }

    private func addressSection(_ job: JobsService.JobDetail) -> some View {
        GroupBox("Location") {
            VStack(alignment: .leading, spacing: 8) {
                if let addr = job.addressLine1, !addr.isEmpty {
                    Text(addr)
                }
                if let addr2 = job.addressLine2, !addr2.isEmpty {
                    Text(addr2)
                }
                let cityLine = [job.city, job.state, job.zip].compactMap { $0 }.joined(separator: ", ")
                if !cityLine.isEmpty {
                    Text(cityLine)
                        .foregroundStyle(.secondary)
                }
                if let lat = job.gpsLat, let lng = job.gpsLng {
                    Text("GPS: \(String(format: "%.6f", lat)), \(String(format: "%.6f", lng))")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(8)
        }
    }

    private func budgetSection(_ job: JobsService.JobDetail) -> some View {
        GroupBox("Budget & Billing") {
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                if let budget = job.budgetLimit {
                    infoRow("Budget Limit", String(format: "$%.2f", budget))
                }
                if let rate = job.billingRate {
                    infoRow("Billing Rate", String(format: "$%.2f/hr", rate))
                }
                if let hours = job.estimatedHours {
                    infoRow("Est. Hours", String(format: "%.1f", hours))
                }
                infoRow("Parts Cost", String(format: "$%.2f", job.partsCost))
                infoRow("Labor Hours", String(format: "%.1f", job.laborHours))
            }
            .padding(8)
        }
    }

    private var teamSection: some View {
        GroupBox("Team Members (\(teamMembers.count))") {
            if teamMembers.isEmpty {
                Text("No team members assigned")
                    .foregroundStyle(.secondary)
                    .padding(8)
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(teamMembers, id: \.id) { member in
                        HStack {
                            Image(systemName: "person.circle")
                                .foregroundStyle(.blue)
                            Text(member.userName)
                                .fontWeight(.medium)
                            Text("(\(member.role))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Spacer()
                        }
                    }
                }
                .padding(8)
            }
        }
    }

    private var partsSection: some View {
        GroupBox("Job Parts (\(jobParts.count))") {
            if jobParts.isEmpty {
                Text("No parts assigned to this job")
                    .foregroundStyle(.secondary)
                    .padding(8)
            } else {
                VStack(spacing: 4) {
                    ForEach(jobParts, id: \.id) { part in
                        HStack {
                            VStack(alignment: .leading) {
                                Text(part.partName)
                                    .fontWeight(.medium)
                                if let code = part.partCode, !code.isEmpty {
                                    Text(code)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            Spacer()
                            Text("Used: \(part.qtyConsumed)")
                                .font(.caption)
                            Text("Returned: \(part.qtyReturned)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Divider()
                    }
                }
                .padding(8)
            }
        }
    }

    private var laborSection: some View {
        GroupBox("Labor Summary") {
            if let summary = laborSummary {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                    infoRow("Regular Hours", String(format: "%.1f", summary.totalRegularHours))
                    infoRow("Overtime Hours", String(format: "%.1f", summary.totalOvertimeHours))
                    infoRow("Entries", "\(summary.totalEntries)")
                    infoRow("Workers", "\(summary.uniqueWorkers)")
                }
                .padding(8)
            } else {
                Text("No labor data")
                    .foregroundStyle(.secondary)
                    .padding(8)
            }
        }
    }

    // MARK: - Helpers

    private func infoRow(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .fontWeight(.medium)
        }
    }

    // MARK: - Data Loading

    private func loadJobList() {
        guard let service = appCore.jobsService else { return }
        do {
            jobs = try service.listJobs()
        } catch {
            print("[JobDetailPage] Load list error: \(error)")
        }
    }

    private func loadDetail() {
        guard let service = appCore.jobsService, let jobId = selectedJobId else { return }
        isLoading = true
        detailError = nil
        do {
            detail = try service.getJob(id: jobId)
            teamMembers = try service.getTeamMembers(jobId: jobId)
            jobParts = try service.getJobParts(jobId: jobId)
            laborSummary = try service.getLaborSummary(jobId: jobId)
        } catch {
            print("[JobDetailPage] Load detail error: \(error)")
            detailError = "Failed to load job: \(error.localizedDescription)"
            detail = nil
        }
        isLoading = false
    }
}
