import SwiftUI
import WiredPartCore

/// Job Purchase Orders list page.
///
/// Displays a searchable, sortable table of all JPOs with job name, requestor,
/// status, priority, line count, and creation date columns. Supports filtering
/// by status and searching by job name.
struct JPOsPage: View {
    @EnvironmentObject private var appCore: AppCore

    // MARK: - Data State

    @State private var jpos: [OrdersService.JPOListItem] = []
    @State private var isLoading = true
    @State private var searchText = ""
    @State private var statusFilter = "all"

    // MARK: - Sorting

    @State private var sortOrder = [KeyPathComparator(\OrdersService.JPOListItem.id)]

    private let statusOptions = ["all", "draft", "pending", "submitted", "approved", "cancelled"]

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            tableContent
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task { load() }
    }

    // MARK: - Toolbar

    private var toolbar: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Job Purchase Orders")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                Text("\(jpos.count) JPO\(jpos.count == 1 ? "" : "s")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Picker("Status", selection: $statusFilter) {
                ForEach(statusOptions, id: \.self) { status in
                    Text(status == "all" ? "All Statuses" : status.capitalized)
                        .tag(status)
                }
            }
            .pickerStyle(.menu)
            .frame(width: 160)
            .onChange(of: statusFilter) { load() }

            TextField("Search JPOs...", text: $searchText)
                .textFieldStyle(.roundedBorder)
                .frame(width: 200)
                .onSubmit { load() }

            Button {
                load()
            } label: {
                Label("Refresh", systemImage: "arrow.clockwise")
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 16)
    }

    // MARK: - Table

    @ViewBuilder
    private var tableContent: some View {
        if isLoading {
            ProgressView("Loading JPOs...")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if jpos.isEmpty {
            VStack(spacing: 12) {
                Image(systemName: "doc.text")
                    .font(.system(size: 40))
                    .foregroundStyle(.tertiary)
                Text("No job purchase orders found")
                    .font(.headline)
                Text("Create a JPO from a job to get started.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            Table(sortedJPOs, sortOrder: $sortOrder) {
                TableColumn("ID", value: \.id) { jpo in
                    Text("#\(jpo.id)")
                        .font(.system(.body, design: .monospaced))
                        .fontWeight(.medium)
                }
                .width(min: 60, ideal: 70)

                TableColumn("Job", value: \.jobName) { jpo in
                    Text(jpo.jobName)
                        .fontWeight(.medium)
                }
                .width(min: 140, ideal: 200)

                TableColumn("Requested By", value: \.requestedByName) { jpo in
                    Text(jpo.requestedByName)
                }
                .width(min: 100, ideal: 140)

                TableColumn("Status", value: \.status) { jpo in
                    statusBadge(jpo.status)
                }
                .width(min: 80, ideal: 100)

                TableColumn("Priority", value: \.priority) { jpo in
                    priorityBadge(jpo.priority)
                }
                .width(min: 70, ideal: 80)

                TableColumn("Lines", value: \.lineCount) { jpo in
                    Text("\(jpo.lineCount)")
                }
                .width(min: 50, ideal: 60)

                TableColumn("Created") { (jpo: OrdersService.JPOListItem) in
                    Text(jpo.createdAt ?? "-")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .width(min: 80, ideal: 120)
            }
            .tableStyle(.inset(alternatesRowBackgrounds: true))
        }
    }

    private var sortedJPOs: [OrdersService.JPOListItem] {
        jpos.sorted(using: sortOrder)
    }

    // MARK: - Badges

    private func statusBadge(_ status: String) -> some View {
        let color: Color = switch status {
        case "draft": .secondary
        case "pending": .orange
        case "submitted": .blue
        case "approved": .green
        case "cancelled": .red
        default: .secondary
        }
        return Text(status.capitalized)
            .font(.system(.caption, weight: .semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Capsule().fill(color.opacity(0.15)))
            .foregroundStyle(color)
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
            .font(.caption)
            .foregroundStyle(color)
    }

    // MARK: - Data Loading

    private func load() {
        guard let db = appCore.db else { return }
        let service = OrdersService(db: db)
        isLoading = true
        do {
            let allJPOs = try service.listJPOs(
                status: statusFilter == "all" ? nil : statusFilter
            )
            // Client-side search filter
            if searchText.isEmpty {
                jpos = allJPOs
            } else {
                let query = searchText.lowercased()
                jpos = allJPOs.filter {
                    $0.jobName.lowercased().contains(query) ||
                    $0.requestedByName.lowercased().contains(query)
                }
            }
        } catch {
            print("[JPOsPage] Load error: \(error)")
        }
        isLoading = false
    }
}
