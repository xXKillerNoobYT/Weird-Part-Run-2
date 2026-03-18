import SwiftUI
import WiredPartCore

/// Job Purchase Orders list page for iOS.
///
/// Displays a searchable list of JPOs with job name, requester,
/// status badge, priority badge, and line count. Supports pull-to-refresh
/// and status-based filtering.
struct IOSJPOsPage: View {
    @EnvironmentObject private var appCore: AppCore

    // MARK: - State

    @State private var jpos: [OrdersService.JPOListItem] = []
    @State private var isLoading = true
    @State private var searchText = ""
    @State private var statusFilter = "all"
    @State private var loadError: String?

    private let statusOptions = ["all", "draft", "pending", "submitted", "approved", "rejected"]

    var body: some View {
        VStack(spacing: 0) {
            statusPicker
            jpoList
        }
        .navigationTitle("Job Purchase Orders")
        .searchable(text: $searchText, prompt: "Search JPOs...")
        .onChange(of: searchText) { loadData() }
        .refreshable { loadData() }
        .task { loadData() }
    }

    // MARK: - Status Picker

    private var statusPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(statusOptions, id: \.self) { status in
                    Button {
                        statusFilter = status
                        loadData()
                    } label: {
                        Text(status == "all" ? "All" : status.capitalized)
                            .font(.caption)
                            .fontWeight(statusFilter == status ? .bold : .regular)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(
                                Capsule().fill(statusFilter == status ? Color.accentColor : Color.secondary.opacity(0.2))
                            )
                            .foregroundStyle(statusFilter == status ? .white : .primary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
        }
    }

    // MARK: - JPO List

    @ViewBuilder
    private var jpoList: some View {
        if isLoading {
            ProgressView("Loading JPOs...")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let error = loadError {
            ErrorStateView(message: error) { loadData() }
        } else if filteredJPOs.isEmpty {
            EmptyStateView(
                icon: "doc.text",
                title: "No JPOs",
                message: searchText.isEmpty ? "No job purchase orders yet." : "No JPOs match your criteria."
            )
        } else {
            List(filteredJPOs, id: \.id) { jpo in
                NavigationLink {
                    IOSJPODetailPage(jpoId: jpo.id)
                        .environmentObject(appCore)
                } label: {
                    jpoRow(jpo)
                }
            }
            #if os(iOS)
            .listStyle(.insetGrouped)
            #endif
        }
    }

    private var filteredJPOs: [OrdersService.JPOListItem] {
        guard !searchText.isEmpty else { return jpos }
        let query = searchText.lowercased()
        return jpos.filter {
            $0.jobName.lowercased().contains(query) ||
            $0.requestedByName.lowercased().contains(query)
        }
    }

    private func jpoRow(_ jpo: OrdersService.JPOListItem) -> some View {
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
                Text("Requested by \(jpo.requestedByName)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 4) {
                statusBadge(jpo.status)
                Label("\(jpo.lineCount) lines", systemImage: "list.bullet")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("JPO number \(jpo.id), \(jpo.jobName), status \(jpo.status), \(jpo.lineCount) line items")
    }

    // MARK: - Badges

    private func statusBadge(_ status: String) -> some View {
        let color: Color = switch status {
        case "draft": .secondary
        case "pending", "submitted": .orange
        case "approved": .green
        case "rejected": .red
        default: .secondary
        }
        return Text(status.capitalized)
            .font(.system(.caption2, weight: .semibold))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
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
            .font(.caption2)
            .foregroundStyle(color)
    }

    // MARK: - Data Loading

    private func loadData() {
        guard let service = appCore.ordersService else { return }
        isLoading = jpos.isEmpty
        loadError = nil
        do {
            jpos = try service.listJPOs(
                status: statusFilter == "all" ? nil : statusFilter
            )
        } catch {
            loadError = error.localizedDescription
        }
        isLoading = false
    }
}
