import SwiftUI
import WiredPartCore

/// Approvals page for reviewing and approving/denying JPOs and POs.
///
/// Shows pending JPOs that need approval. The current user can approve or deny
/// each request. Uses OrdersService for data loading and status updates.
struct ApprovalsPage: View {
    @EnvironmentObject private var appCore: AppCore

    @State private var pendingJPOs: [OrdersService.JPOListItem] = []
    @State private var isLoading = true
    @State private var selectedJPO: OrdersService.JPODetail?
    @State private var showDetail = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()

            if isLoading {
                ProgressView("Loading approvals…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if pendingJPOs.isEmpty {
                emptyState
            } else {
                approvalsList
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .task { loadData() }
        .sheet(isPresented: $showDetail) {
            if let detail = selectedJPO {
                JPOApprovalDetailSheet(
                    detail: detail,
                    onApprove: { approveJPO(id: detail.id) },
                    onDeny: { denyJPO(id: detail.id) }
                )
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Approvals")
                    .font(.title2)
                    .fontWeight(.bold)
                Text("\(pendingJPOs.count) pending approval\(pendingJPOs.count == 1 ? "" : "s")")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                loadData()
            } label: {
                Image(systemName: "arrow.clockwise")
            }
        }
        .padding()
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 48))
                .foregroundStyle(.green)
            Text("All Caught Up")
                .font(.title3)
                .fontWeight(.semibold)
            Text("No pending approvals at this time.")
                .font(.body)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Approvals List

    private var approvalsList: some View {
        Table(pendingJPOs) {
            TableColumn("Job") { jpo in
                Text(jpo.jobName)
                    .lineLimit(1)
            }
            .width(min: 120, ideal: 180)

            TableColumn("Requested By") { jpo in
                Text(jpo.requestedByName)
                    .lineLimit(1)
            }
            .width(min: 100, ideal: 140)

            TableColumn("Priority") { jpo in
                priorityBadge(jpo.priority)
            }
            .width(80)

            TableColumn("Lines") { jpo in
                Text("\(jpo.lineCount)")
                    .monospacedDigit()
            }
            .width(60)

            TableColumn("Date") { jpo in
                Text(formattedDate(jpo.createdAt))
                    .foregroundStyle(.secondary)
            }
            .width(min: 80, ideal: 120)

            TableColumn("Actions") { jpo in
                HStack(spacing: 8) {
                    Button("Review") {
                        reviewJPO(id: jpo.id)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)

                    Button("Approve") {
                        approveJPO(id: jpo.id)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .tint(.green)
                }
            }
            .width(min: 160, ideal: 180)
        }
    }

    // MARK: - Helpers

    private func priorityBadge(_ priority: String) -> some View {
        let color: Color = switch priority {
        case "urgent": .red
        case "high": .orange
        case "normal": .blue
        default: .gray
        }
        return Text(priority.capitalized)
            .font(.caption)
            .fontWeight(.medium)
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .background(Capsule().fill(color.opacity(0.15)))
            .foregroundStyle(color)
    }

    private func formattedDate(_ dateString: String?) -> String {
        guard let dateString else { return "—" }
        // Show just the date portion
        return String(dateString.prefix(10))
    }

    // MARK: - Data Loading

    private func loadData() {
        guard let service = appCore.ordersService else { return }
        isLoading = true
        do {
            pendingJPOs = try service.listJPOs(status: "pending")
        } catch {
            print("[ApprovalsPage] Error loading approvals: \(error)")
            pendingJPOs = []
        }
        isLoading = false
    }

    private func reviewJPO(id: Int64) {
        guard let service = appCore.ordersService else { return }
        do {
            selectedJPO = try service.getJPODetail(id: id)
            showDetail = true
        } catch {
            print("[ApprovalsPage] Error loading JPO detail: \(error)")
        }
    }

    private func approveJPO(id: Int64) {
        guard let service = appCore.ordersService else { return }
        do {
            try service.updateJPOStatus(id: id, status: "approved")
            loadData()
            showDetail = false
        } catch {
            print("[ApprovalsPage] Error approving JPO: \(error)")
        }
    }

    private func denyJPO(id: Int64) {
        guard let service = appCore.ordersService else { return }
        do {
            try service.updateJPOStatus(id: id, status: "denied")
            loadData()
            showDetail = false
        } catch {
            print("[ApprovalsPage] Error denying JPO: \(error)")
        }
    }
}

// MARK: - JPO Approval Detail Sheet

private struct JPOApprovalDetailSheet: View {
    let detail: OrdersService.JPODetail
    let onApprove: () -> Void
    let onDeny: () -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header
            HStack {
                Text("JPO #\(detail.id)")
                    .font(.title2)
                    .fontWeight(.bold)
                Spacer()
                Button("Close") { dismiss() }
            }

            // Info grid
            Grid(alignment: .leading, horizontalSpacing: 24, verticalSpacing: 8) {
                GridRow {
                    Text("Job:").foregroundStyle(.secondary)
                    Text(detail.jobName)
                }
                GridRow {
                    Text("Requested By:").foregroundStyle(.secondary)
                    Text(detail.requestedByName)
                }
                GridRow {
                    Text("Priority:").foregroundStyle(.secondary)
                    Text(detail.priority.capitalized)
                }
                if let notes = detail.notes, !notes.isEmpty {
                    GridRow {
                        Text("Notes:").foregroundStyle(.secondary)
                        Text(notes)
                    }
                }
            }

            Divider()

            // Lines
            Text("Order Lines (\(detail.lines.count))")
                .font(.headline)

            if detail.lines.isEmpty {
                Text("No line items.")
                    .foregroundStyle(.secondary)
            } else {
                Table(detail.lines) {
                    TableColumn("Part") { line in
                        Text(line.partName ?? line.description ?? "—")
                    }
                    TableColumn("Qty") { line in
                        Text("\(line.quantity)")
                            .monospacedDigit()
                    }
                    .width(60)
                    TableColumn("Priority") { line in
                        Text(line.priority.capitalized)
                    }
                    .width(80)
                }
                .frame(minHeight: 120)
            }

            Spacer()

            // Action buttons
            HStack {
                Spacer()
                Button("Deny", role: .destructive) { onDeny() }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                Button("Approve") { onApprove() }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .tint(.green)
            }
        }
        .padding(24)
        .frame(minWidth: 600, minHeight: 500)
    }
}
