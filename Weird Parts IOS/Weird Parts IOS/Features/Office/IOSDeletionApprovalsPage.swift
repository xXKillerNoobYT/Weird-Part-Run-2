import SwiftUI
import WiredPartCore

/// Office page for reviewing and approving scheduled part/category deletions.
///
/// Shows items in "pending_approval" status (stock reached 0, 30-day timer expired)
/// and "draining" status (still has stock, waiting to reach 0).
struct IOSDeletionApprovalsPage: View {
    @EnvironmentObject private var appCore: AppCore

    @State private var pendingApprovals: [PartsService.ScheduledDeletion] = []
    @State private var drainingItems: [PartsService.ScheduledDeletion] = []
    @State private var isLoading = true
    @State private var loadError: String?
    @State private var processingId: Int64?

    var body: some View {
        Group {
            if isLoading {
                ProgressView("Loading deletion queue...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error = loadError {
                ContentUnavailableView {
                    Label("Error", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(error)
                }
            } else if pendingApprovals.isEmpty && drainingItems.isEmpty {
                ContentUnavailableView {
                    Label("No Pending Deletions", systemImage: "checkmark.seal")
                } description: {
                    Text("All deletion requests have been processed.")
                }
            } else {
                deletionList
            }
        }
        .navigationTitle("Deletion Approvals")
        .refreshable { await loadData() }
        .task { await loadData() }
    }

    // MARK: - List

    @ViewBuilder
    private var deletionList: some View {
        List {
            // Pending Approval section (ready to delete)
            if !pendingApprovals.isEmpty {
                Section {
                    ForEach(pendingApprovals) { item in
                        approvalRow(item)
                    }
                } header: {
                    Label("Ready for Approval (\(pendingApprovals.count))", systemImage: "clock.badge.checkmark")
                } footer: {
                    Text("These items have had zero stock for 30+ days.")
                }
            }

            // Draining section (still has stock)
            if !drainingItems.isEmpty {
                Section {
                    ForEach(drainingItems) { item in
                        drainingRow(item)
                    }
                } header: {
                    Label("Draining — Empty Shelf Mode (\(drainingItems.count))", systemImage: "arrow.down.to.line")
                } footer: {
                    Text("Stock targets set to 0. Once stock reaches 0, a 30-day timer will start.")
                }
            }
        }
        .listStyle(.insetGrouped)
    }

    // MARK: - Approval Row (ready to delete)

    private func approvalRow(_ item: PartsService.ScheduledDeletion) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(item.entityType.capitalized)
                            .font(.system(.caption2, weight: .semibold))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(Color.orange.opacity(0.15)))
                            .foregroundStyle(.orange)
                        Text(item.entityName)
                            .font(.subheadline)
                            .fontWeight(.semibold)
                    }
                    if let reason = item.reason {
                        Text("Reason: \(reason)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if let deleteAfter = item.deleteAfter {
                        Text("Timer expired: \(deleteAfter)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
            }

            // Alternative part recommendation
            if let altName = item.alternativePartName {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.right.circle.fill")
                        .foregroundStyle(.green)
                        .font(.caption)
                    Text("Replacement: **\(altName)**")
                        .font(.caption)
                        .foregroundStyle(.green)
                }
            }

            // Action buttons
            HStack(spacing: 12) {
                Button {
                    Task { await approve(item) }
                } label: {
                    Label("Approve Delete", systemImage: "checkmark.circle.fill")
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
                .disabled(processingId == item.id)

                Button {
                    Task { await cancel(item) }
                } label: {
                    Label("Cancel", systemImage: "xmark.circle.fill")
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                }
                .buttonStyle(.borderedProminent)
                .tint(.secondary)
                .disabled(processingId == item.id)
            }
        }
        .padding(.vertical, 4)
    }

    // MARK: - Draining Row (still has stock)

    private func drainingRow(_ item: PartsService.ScheduledDeletion) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text(item.entityType.capitalized)
                    .font(.system(.caption2, weight: .semibold))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(Color.blue.opacity(0.15)))
                    .foregroundStyle(.blue)
                Text(item.entityName)
                    .font(.subheadline)
                    .fontWeight(.medium)
                Spacer()
                Text("Started with \(item.stockAtSchedule)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if let altName = item.alternativePartName {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.right.circle.fill")
                        .foregroundStyle(.green)
                        .font(.caption)
                    Text("Switch to: \(altName)")
                        .font(.caption)
                }
            }

            // Cancel button only (can't approve while still draining)
            Button {
                Task { await cancel(item) }
            } label: {
                Label("Cancel Empty Shelf Mode", systemImage: "arrow.uturn.backward")
                    .font(.caption)
            }
            .buttonStyle(.bordered)
            .disabled(processingId == item.id)
        }
        .padding(.vertical, 4)
    }

    // MARK: - Actions

    private func approve(_ item: PartsService.ScheduledDeletion) async {
        guard let service = appCore.partsService else { return }
        processingId = item.id
        do {
            try service.approveScheduledDeletion(id: item.id, approvedBy: nil)
            pendingApprovals.removeAll { $0.id == item.id }
        } catch {
            loadError = error.localizedDescription
        }
        processingId = nil
    }

    private func cancel(_ item: PartsService.ScheduledDeletion) async {
        guard let service = appCore.partsService else { return }
        processingId = item.id
        do {
            try service.cancelScheduledDeletion(id: item.id)
            pendingApprovals.removeAll { $0.id == item.id }
            drainingItems.removeAll { $0.id == item.id }
        } catch {
            loadError = error.localizedDescription
        }
        processingId = nil
    }

    // MARK: - Data Loading

    private func loadData() async {
        guard let service = appCore.partsService else {
            loadError = "Parts service not available"
            isLoading = false
            return
        }
        do {
            pendingApprovals = try service.listScheduledDeletions(status: "pending_approval")
            drainingItems = try service.listScheduledDeletions(status: "draining")
        } catch {
            loadError = error.localizedDescription
        }
        isLoading = false
    }
}
