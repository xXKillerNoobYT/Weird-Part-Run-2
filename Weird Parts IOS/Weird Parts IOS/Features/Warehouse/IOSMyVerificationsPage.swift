import SwiftUI
import WiredPartCore

/// "My Verification Assignments" page.
///
/// Lists all pending multi-user verification assignments for the current
/// user. Each row opens `IOSVerificationSubmitSheet` to enter a count.
/// Pull-to-refresh reloads the assignment list.
struct IOSMyVerificationsPage: View {
    @EnvironmentObject private var appCore: AppCore

    @State private var assignments: [MultiUserAuditAssignment] = []
    @State private var isLoading = true
    @State private var loadError: String?
    @State private var selectedAssignment: MultiUserAuditAssignment?

    var body: some View {
        VStack(spacing: 0) {
            if isLoading {
                ProgressView("Loading assignments...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error = loadError {
                ErrorStateView(message: error) { loadData() }
            } else if assignments.isEmpty {
                EmptyStateView(
                    icon: "person.2.badge.gearshape",
                    title: "No Pending Assignments",
                    message: "You have no verification assignments waiting for your count."
                )
            } else {
                List {
                    Section("Pending (\(assignments.count))") {
                        ForEach(assignments) { assignment in
                            Button {
                                selectedAssignment = assignment
                            } label: {
                                assignmentRow(assignment)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .listStyle(.insetGrouped)
            }
        }
        .navigationTitle("My Verifications")
        .refreshable { loadData() }
        .sheet(item: $selectedAssignment) { assignment in
            IOSVerificationSubmitSheet(assignment: assignment) {
                selectedAssignment = nil
                loadData()
            }
            .environmentObject(appCore)
        }
        .task { loadData() }
    }

    private func assignmentRow(_ assignment: MultiUserAuditAssignment) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "person.2.badge.gearshape")
                .foregroundStyle(.orange)
                .frame(width: 28)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(assignment.partName)
                    .font(.subheadline)
                    .fontWeight(.medium)
                if let bin = assignment.binLocation, !bin.isEmpty {
                    Text(bin)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .monospaced()
                }
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .accessibilityHidden(true)
        }
        .padding(.vertical, 2)
    }

    private func loadData() {
        guard let service = appCore.warehouseService,
              let userId = appCore.currentUser?.id else {
            loadError = "Service or user unavailable."
            isLoading = false
            return
        }
        isLoading = assignments.isEmpty
        loadError = nil
        do {
            assignments = try service.getMyMultiUserAuditAssignments(userId: userId)
        } catch {
            loadError = userFriendlyError(error, context: "load verification assignments")
        }
        isLoading = false
    }
}
