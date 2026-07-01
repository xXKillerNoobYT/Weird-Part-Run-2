import SwiftUI
import WiredPartCore

/// Flex Pool page — workers browse and self-claim available flex pool jobs.
///
/// Jobs that managers mark as "flex pool" appear here. Workers tap "Claim"
/// to self-assign. If the company requires approval, the claim enters a
/// pending state instead.
struct IOSFlexPoolPage: View {
    @EnvironmentObject private var appCore: AppCore

    // MARK: - Sheet Routing

    private enum ActiveSheet: Identifiable {
        case help
        var id: String { "help" }
    }
    @State private var activeSheet: ActiveSheet?

    // MARK: - State

    @State private var flexJobs: [FlexPoolJob] = []
    @State private var isLoading = true
    @State private var loadError: String?

    // Claim flow
    @State private var jobToClaim: FlexPoolJob?
    @State private var showClaimConfirm = false
    @State private var claimError: String?
    @State private var claimedJobId: Int64?
    @State private var pendingApprovalIds: Set<Int64> = []

    private var currentUserId: Int64? {
        appCore.currentUser?.id
    }

    var body: some View {
        VStack(spacing: 0) {
            OnboardingBanner(pageId: "scheduling-flex-pool")

            if isLoading {
                ProgressView("Loading flex pool...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error = loadError {
                ErrorStateView(message: error) { loadData() }
            } else if flexJobs.isEmpty {
                emptyState
            } else {
                jobList
            }
        }
        .navigationTitle("Flex Pool")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { activeSheet = .help } label: {
                    Image(systemName: "questionmark.circle")
                }
                .accessibilityLabel("Help")
            }
        }
        .sheet(item: $activeSheet) { _ in
            PageHelpSheet(
                title: "Flex Pool Help",
                sections: [
                    ("What Is the Flex Pool?", "The Flex Pool shows jobs that managers have made available for workers to self-claim. These are typically short-duration or overflow jobs that need coverage."),
                    ("Claiming a Job", "Tap Claim on any job to request assignment. If approval is required, your request enters a Pending Approval state until a manager reviews it. Otherwise, the job disappears from the list — you are now assigned."),
                    ("After Claiming", "Once claimed, the job appears on your schedule and in the Clock In list. Pull down to refresh if you don't see your new assignment right away."),
                ]
            )
        }
        .refreshable { loadData() }
        .task { loadData() }
        .confirmationDialog(
            "Claim \(jobToClaim?.jobName ?? "job")?",
            isPresented: $showClaimConfirm,
            titleVisibility: .visible
        ) {
            Button("Confirm") {
                if let job = jobToClaim {
                    claimJob(job)
                }
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("You will be assigned as lead for this job.")
        }
        .alert("Claim Failed", isPresented: .init(
            get: { claimError != nil },
            set: { if !$0 { claimError = nil } }
        )) {
            Button("OK", role: .cancel) { }
        } message: {
            if let error = claimError {
                Text(error)
            }
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        EmptyStateView(
            icon: "person.badge.clock",
            title: "No Flex Pool Jobs",
            message: "No flex pool jobs available right now. Check back later."
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Job List

    private var jobList: some View {
        List {
            ForEach(flexJobs) { job in
                flexJobRow(job)
            }
        }
        .listStyle(.insetGrouped)
    }

    private func flexJobRow(_ job: FlexPoolJob) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(job.jobName)
                    .font(.headline)

                Text(job.jobNumber)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if let address = job.address, !address.isEmpty {
                    HStack(spacing: 4) {
                        Image(systemName: "mappin")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .accessibilityHidden(true)
                        Text(address)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }

                if let hours = job.estimatedHours {
                    HStack(spacing: 4) {
                        Image(systemName: "clock")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .accessibilityHidden(true)
                        Text("\(String(format: "%.1f", hours)) hrs estimated")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Spacer()

            // Pending approval state
            if pendingApprovalIds.contains(job.id) {
                VStack(spacing: 2) {
                    Image(systemName: "clock.badge.questionmark")
                        .font(.title3)
                        .foregroundStyle(.orange)
                        .accessibilityHidden(true)
                    Text("Pending Approval")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                        .fontWeight(.medium)
                }
                .accessibilityLabel("Request sent, pending approval")
            } else {
                Button {
                    jobToClaim = job
                    showClaimConfirm = true
                } label: {
                    Text("Claim")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(Color.accentColor)
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Claim \(job.jobName)")
            }
        }
        .padding(.vertical, 4)
    }

    // MARK: - Claim Logic

    private func claimJob(_ job: FlexPoolJob) {
        guard let service = appCore.schedulingService else {
            claimError = "Scheduling service not available"
            return
        }
        guard let userId = currentUserId else {
            claimError = "User session unavailable. Sign in again."
            return
        }

        do {
            try service.claimFlexJob(jobId: job.id, userId: userId)

            if job.isApprovalRequired {
                // Show "Pending Approval" state instead of removing
                pendingApprovalIds.insert(job.id)
            } else {
                // Remove from list — job is now claimed
                claimedJobId = job.id
                flexJobs.removeAll { $0.id == job.id }
            }
        } catch {
            claimError = userFriendlyError(error, context: "claim flex pool job")
        }
    }

    // MARK: - Data Loading

    private func loadData() {
        guard let service = appCore.schedulingService else {
            isLoading = false
            loadError = "Scheduling service not available."
            return
        }
        guard let userId = currentUserId else {
            flexJobs = []
            pendingApprovalIds = []
            isLoading = false
            loadError = "User session unavailable. Sign in again."
            return
        }
        isLoading = flexJobs.isEmpty
        loadError = nil

        do {
            flexJobs = try service.fetchFlexPool(userId: userId)
        } catch {
            loadError = userFriendlyError(error, context: "load flex pool")
        }
        isLoading = false
    }
}
