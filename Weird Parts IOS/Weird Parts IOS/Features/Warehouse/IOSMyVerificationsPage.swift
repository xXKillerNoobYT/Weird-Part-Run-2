import SwiftUI
import WiredPartCore

/// Operator inbox for pending multi-user verification assignments.
struct IOSMyVerificationsPage: View {
    @EnvironmentObject private var appCore: AppCore

    @State private var assignments: [MultiUserAuditAssignment] = []
    @State private var isLoading = true
    @State private var loadError: String?
    @State private var selectedAssignment: MultiUserAuditAssignment?

    var body: some View {
        Group {
            if isLoading {
                ProgressView("Loading assignments...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let loadError {
                ErrorStateView(message: loadError) { loadData() }
            } else if assignments.isEmpty {
                ContentUnavailableView(
                    "No Pending Verifications",
                    systemImage: "checkmark.seal",
                    description: Text("You have no multi-user verification assignments right now.")
                )
            } else {
                List(assignments, id: \.id) { assignment in
                    Button {
                        selectedAssignment = assignment
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "person.2.badge.gearshape")
                                .foregroundStyle(.blue)
                                .frame(width: 24)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(assignment.partName)
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
                        }
                    }
                    .buttonStyle(.plain)
                }
                .listStyle(.insetGrouped)
                .refreshable { loadData() }
            }
        }
        .navigationTitle("My Verifications")
        .sheet(item: $selectedAssignment) { assignment in
            IOSVerificationSubmitSheet(assignment: assignment) {
                selectedAssignment = nil
                loadData()
            }
            .environmentObject(appCore)
        }
        .task { loadData() }
    }

    private func loadData() {
        guard let service = appCore.warehouseService,
              let userId = appCore.currentUser?.id else {
            isLoading = false
            loadError = "Service or user unavailable"
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
