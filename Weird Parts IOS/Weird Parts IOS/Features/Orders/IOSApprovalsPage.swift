import SwiftUI
import WiredPartCore

/// Pending JPO approvals page for iOS.
///
/// Displays job purchase orders awaiting approval. Shows the job name,
/// requester, priority badge, and line count with approve/deny action buttons.
/// Filtered to status = "pending" by default.
struct IOSApprovalsPage: View {
    @EnvironmentObject private var appCore: AppCore

    // MARK: - State

    @State private var pendingJPOs: [OrdersService.JPOListItem] = []
    @State private var isLoading = true
    @State private var searchText = ""
    @State private var processingId: Int64?

    var body: some View {
        approvalList
            .navigationTitle("Approvals")
            .searchable(text: $searchText, prompt: "Search pending approvals...")
            .onChange(of: searchText) { loadData() }
            .refreshable { loadData() }
            .task { loadData() }
    }

    // MARK: - Approval List

    @ViewBuilder
    private var approvalList: some View {
        if isLoading {
            ProgressView("Loading approvals...")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if filteredJPOs.isEmpty {
            ContentUnavailableView {
                Label("No Pending Approvals", systemImage: "checkmark.seal")
            } description: {
                Text("All JPOs have been reviewed.")
            }
        } else {
            List(filteredJPOs, id: \.id) { jpo in
                approvalRow(jpo)
            }
            #if os(iOS)
            .listStyle(.insetGrouped)
            #endif
        }
    }

    private var filteredJPOs: [OrdersService.JPOListItem] {
        guard !searchText.isEmpty else { return pendingJPOs }
        let query = searchText.lowercased()
        return pendingJPOs.filter {
            $0.jobName.lowercased().contains(query) ||
            $0.requestedByName.lowercased().contains(query)
        }
    }

    private func approvalRow(_ jpo: OrdersService.JPOListItem) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text("JPO #\(jpo.id)")
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.secondary)
                        priorityBadge(jpo.priority)
                    }
                    Text(jpo.jobName)
                        .fontWeight(.medium)
                        .lineLimit(1)
                    Text("Requested by \(jpo.requestedByName)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 4) {
                    statusBadge("pending")
                    Label("\(jpo.lineCount) lines", systemImage: "list.bullet")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            // Action buttons
            HStack(spacing: 12) {
                Button {
                    approveJPO(jpo.id)
                } label: {
                    Label("Approve", systemImage: "checkmark.circle.fill")
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                }
                .buttonStyle(.borderedProminent)
                .tint(.green)
                .disabled(processingId == jpo.id)

                Button {
                    denyJPO(jpo.id)
                } label: {
                    Label("Deny", systemImage: "xmark.circle.fill")
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
                .disabled(processingId == jpo.id)
            }
        }
        .padding(.vertical, 4)
    }

    // MARK: - Badges

    private func statusBadge(_ status: String) -> some View {
        Text(status.capitalized)
            .font(.system(.caption2, weight: .semibold))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Capsule().fill(Color.orange.opacity(0.15)))
            .foregroundStyle(.orange)
    }

    private func priorityBadge(_ priority: String) -> some View {
        let color: Color = switch priority {
        case "urgent": .red
        case "high": .orange
        case "normal": .blue
        case "low": .secondary
        default: .secondary
        }
        return Text(priority.capitalized)
            .font(.system(.caption2, weight: .semibold))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Capsule().fill(color.opacity(0.15)))
            .foregroundStyle(color)
    }

    // MARK: - Actions

    private func approveJPO(_ id: Int64) {
        guard let service = appCore.ordersService else { return }
        processingId = id
        do {
            try service.updateJPOStatus(id: id, status: "approved")
            pendingJPOs.removeAll { $0.id == id }
        } catch {
            print("[IOSApprovalsPage] Approve error: \(error)")
        }
        processingId = nil
    }

    private func denyJPO(_ id: Int64) {
        guard let service = appCore.ordersService else { return }
        processingId = id
        do {
            try service.updateJPOStatus(id: id, status: "rejected")
            pendingJPOs.removeAll { $0.id == id }
        } catch {
            print("[IOSApprovalsPage] Deny error: \(error)")
        }
        processingId = nil
    }

    // MARK: - Data Loading

    private func loadData() {
        guard let service = appCore.ordersService else { return }
        isLoading = pendingJPOs.isEmpty
        do {
            pendingJPOs = try service.listJPOs(status: "pending")
        } catch {
            print("[IOSApprovalsPage] Load error: \(error)")
        }
        isLoading = false
    }
}
