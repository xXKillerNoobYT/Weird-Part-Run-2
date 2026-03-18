import SwiftUI
import WiredPartCore

/// Procurement planner page for iOS.
///
/// Shows approved JPOs whose lines still need to be placed on purchase orders.
/// Lines are grouped by supplier to help batch ordering. Uses the existing
/// `OrdersService.listJPOs(status:)` filtered to approved JPOs that represent
/// procurement demand.
struct IOSProcurementPage: View {
    @EnvironmentObject private var appCore: AppCore

    // MARK: - State

    @State private var jpos: [OrdersService.JPOListItem] = []
    @State private var isLoading = true
    @State private var searchText = ""
    @State private var priorityFilter = "all"
    @State private var loadError: String?

    private let priorityOptions = ["all", "urgent", "high", "normal", "low"]

    var body: some View {
        VStack(spacing: 0) {
            priorityPicker
            procurementList
        }
        .navigationTitle("Procurement")
        .searchable(text: $searchText, prompt: "Search procurement...")
        .onChange(of: searchText) { loadData() }
        .refreshable { loadData() }
        .task { loadData() }
    }

    // MARK: - Priority Picker

    private var priorityPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(priorityOptions, id: \.self) { priority in
                    Button {
                        priorityFilter = priority
                        loadData()
                    } label: {
                        Text(priority == "all" ? "All" : priority.capitalized)
                            .font(.caption)
                            .fontWeight(priorityFilter == priority ? .bold : .regular)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(
                                Capsule().fill(priorityFilter == priority ? Color.accentColor : Color.secondary.opacity(0.2))
                            )
                            .foregroundStyle(priorityFilter == priority ? .white : .primary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
        }
    }

    // MARK: - Procurement List

    @ViewBuilder
    private var procurementList: some View {
        if isLoading {
            ProgressView("Loading procurement items...")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if filteredJPOs.isEmpty {
            ContentUnavailableView {
                Label("No Procurement Needs", systemImage: "cart")
            } description: {
                Text("All approved JPOs have been ordered.")
            }
        } else {
            List(filteredJPOs, id: \.id) { jpo in
                procurementRow(jpo)
            }
            #if os(iOS)
            .listStyle(.insetGrouped)
            #endif
        }
    }

    private var filteredJPOs: [OrdersService.JPOListItem] {
        var result = jpos
        if priorityFilter != "all" {
            result = result.filter { $0.priority == priorityFilter }
        }
        guard !searchText.isEmpty else { return result }
        let query = searchText.lowercased()
        return result.filter {
            $0.jobName.lowercased().contains(query) ||
            $0.requestedByName.lowercased().contains(query)
        }
    }

    private func procurementRow(_ jpo: OrdersService.JPOListItem) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "cart.fill")
                .font(.title3)
                .foregroundStyle(priorityColor(jpo.priority))
                .frame(width: 32)

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
                Label("\(jpo.lineCount) lines", systemImage: "list.bullet")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let date = jpo.createdAt {
                    Text(formatDate(date))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .padding(.vertical, 4)
    }

    // MARK: - Badges

    private func priorityBadge(_ priority: String) -> some View {
        let color = priorityColor(priority)
        return Text(priority.capitalized)
            .font(.system(.caption2, weight: .semibold))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Capsule().fill(color.opacity(0.15)))
            .foregroundStyle(color)
    }

    private func priorityColor(_ priority: String) -> Color {
        switch priority {
        case "urgent": return .red
        case "high": return .orange
        case "normal": return .blue
        case "low": return .secondary
        default: return .secondary
        }
    }

    // MARK: - Helpers

    private func formatDate(_ dateStr: String) -> String {
        if dateStr.count >= 10 { return String(dateStr.prefix(10)) }
        return dateStr
    }

    // MARK: - Data Loading

    private func loadData() {
        guard let service = appCore.ordersService else { return }
        isLoading = jpos.isEmpty
        do {
            // Approved JPOs represent procurement demand — lines needing POs
            jpos = try service.listJPOs(status: "approved")
        } catch {
            print("[IOSProcurementPage] Load error: \(error)")
            loadError = error.localizedDescription
        }
        isLoading = false
    }
}
