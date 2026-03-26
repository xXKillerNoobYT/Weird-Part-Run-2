import SwiftUI
import WiredPartCore

/// Warehouse tools registry page showing tools assigned to the warehouse.
///
/// Lists all tools with search, smart card filters by status,
/// swipe actions for checkout/return/maintenance, and pull-to-refresh.
struct IOSWarehouseToolsPage: View {
    @EnvironmentObject private var appCore: AppCore

    @State private var tools: [ToolsService.ToolListItem] = []
    @State private var isLoading = true
    @State private var searchText = ""
    @State private var loadError: String?
    @State private var actionError: String?
    @State private var selectedFilter: ToolFilter?
    @State private var activeSheet: ActiveSheet?

    private enum ActiveSheet: Identifiable {
        case help
        var id: String { "help" }
    }

    private enum ToolFilter: String, CaseIterable {
        case available = "Available"
        case checkedOut = "Checked Out"
        case maintenance = "Maintenance"

        var statusKey: String {
            switch self {
            case .available: "available"
            case .checkedOut: "checked_out"
            case .maintenance: "maintenance"
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Smart card filters
            if !tools.isEmpty {
                smartCardFilters
            }

            toolsContent
        }
        .navigationTitle("Warehouse Tools")
        .searchable(text: $searchText, prompt: "Search tools...")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { activeSheet = .help } label: {
                    Image(systemName: "questionmark.circle")
                }
            }
        }
        .sheet(item: $activeSheet) { _ in
            PageHelpSheet(
                title: "Warehouse Tools Help",
                sections: [
                    ("Overview", "View all tools assigned to the warehouse. Filter by status: available, checked out, or in maintenance."),
                    ("Actions", "Swipe a tool row to check it out, return it, or mark it for maintenance."),
                    ("Search", "Use the search bar to find tools by name or serial number. Pull down to refresh the list.")
                ]
            )
        }
        .refreshable { loadData() }
        .alert("Error", isPresented: .constant(actionError != nil)) {
            Button("OK") { actionError = nil }
        } message: {
            Text(actionError ?? "")
        }
        .task { loadData() }
    }

    // MARK: - Smart Card Filters

    private var smartCardFilters: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(ToolFilter.allCases, id: \.self) { filter in
                    let count = tools.filter { $0.status == filter.statusKey }.count
                    smartCard(filter: filter, count: count)
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
        }
    }

    private func smartCard(filter: ToolFilter, count: Int) -> some View {
        let isSelected = selectedFilter == filter
        let color = toolColor(for: filter.statusKey)

        return Button {
            selectedFilter = isSelected ? nil : filter
        } label: {
            VStack(spacing: 4) {
                HStack(spacing: 4) {
                    Image(systemName: toolIcon(for: filter.statusKey))
                        .font(.caption)
                    Text("\(count)")
                        .font(.title3)
                        .fontWeight(.bold)
                }
                Text(filter.rawValue)
                    .font(.caption2)
                    .lineLimit(1)
            }
            .frame(minWidth: 85)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(isSelected ? color.opacity(0.15) : Color.secondary.opacity(0.08))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(isSelected ? color : Color.clear, lineWidth: 1.5)
            )
            .foregroundStyle(isSelected ? color : .primary)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Content

    @ViewBuilder
    private var toolsContent: some View {
        if isLoading {
            ProgressView("Loading tools...")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let error = loadError {
            ErrorStateView(message: error) { loadData() }
        } else if filteredTools.isEmpty {
            EmptyStateView(
                icon: "wrench.and.screwdriver",
                title: "No Tools",
                message: searchText.isEmpty && selectedFilter == nil
                    ? "No tools registered in the warehouse."
                    : "No tools match your filters."
            )
        } else {
            List {
                Section("Tools (\(filteredTools.count))") {
                    ForEach(filteredTools, id: \.id) { tool in
                        toolRow(tool)
                            .swipeActions(edge: .trailing) {
                                toolSwipeActions(for: tool)
                            }
                    }
                }
            }
            .listStyle(.insetGrouped)
        }
    }

    @ViewBuilder
    private func toolSwipeActions(for tool: ToolsService.ToolListItem) -> some View {
        switch tool.status {
        case "available":
            Button { checkoutTool(tool) } label: {
                Label("Check Out", systemImage: "arrow.up.right.circle")
            }
            .tint(.orange)
        case "checked_out":
            Button { returnTool(tool) } label: {
                Label("Return", systemImage: "arrow.down.left.circle")
            }
            .tint(.green)
        default:
            EmptyView()
        }

        Button { markMaintenance(tool) } label: {
            Label("Maintenance", systemImage: "wrench")
        }
        .tint(.red)
    }

    private func toolRow(_ tool: ToolsService.ToolListItem) -> some View {
        HStack(spacing: 12) {
            Image(systemName: toolIcon(for: tool.status))
                .foregroundStyle(toolColor(for: tool.status))
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 2) {
                Text(tool.name)
                    .fontWeight(.medium)
                if let serial = tool.serialNumber, !serial.isEmpty {
                    Text(serial)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .monospaced()
                }
                if let assignee = tool.assignedToName, !assignee.isEmpty {
                    Text("Assigned to: \(assignee)")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }

            Spacer()

            StatusBadge(text: tool.status.replacingOccurrences(of: "_", with: " ").capitalized, color: toolColor(for: tool.status))
        }
        .padding(.vertical, 2)
    }

    private func toolIcon(for status: String) -> String {
        switch status {
        case "available": "checkmark.circle.fill"
        case "checked_out": "arrow.up.right.circle.fill"
        case "maintenance": "wrench.fill"
        default: "wrench.and.screwdriver"
        }
    }

    private func toolColor(for status: String) -> Color {
        switch status {
        case "available": .green
        case "checked_out": .orange
        case "maintenance": .red
        default: .secondary
        }
    }

    private var filteredTools: [ToolsService.ToolListItem] {
        var result = tools
        if let filter = selectedFilter {
            result = result.filter { $0.status == filter.statusKey }
        }
        if !searchText.isEmpty {
            let query = searchText.lowercased()
            result = result.filter {
                $0.name.lowercased().contains(query) ||
                ($0.serialNumber?.lowercased().contains(query) ?? false)
            }
        }
        return result
    }

    // MARK: - Actions

    private func checkoutTool(_ tool: ToolsService.ToolListItem) {
        guard let service = appCore.toolsService,
              let userId = appCore.currentUser?.id else {
            loadError = "Tools service not available"
            return
        }
        do {
            try service.checkoutTool(toolId: tool.id, userId: userId)
            loadData()
        } catch {
            actionError = error.localizedDescription
        }
    }

    private func returnTool(_ tool: ToolsService.ToolListItem) {
        guard let service = appCore.toolsService,
              let userId = appCore.currentUser?.id else {
            loadError = "Tools service not available"
            return
        }
        do {
            try service.returnTool(toolId: tool.id, userId: userId)
            loadData()
        } catch {
            actionError = error.localizedDescription
        }
    }

    private func markMaintenance(_ tool: ToolsService.ToolListItem) {
        guard let service = appCore.toolsService else {
            actionError = "Service not available"
            return
        }
        do {
            try service.markToolMaintenance(toolId: tool.id)
            loadData()
        } catch {
            actionError = error.localizedDescription
        }
    }

    // MARK: - Data Loading

    private func loadData() {
        guard let service = appCore.toolsService else {
            loadError = "Service not available"
            isLoading = false
            return
        }
        isLoading = tools.isEmpty
        loadError = nil
        do {
            tools = try service.listTools()
        } catch {
            loadError = error.localizedDescription
        }
        isLoading = false
    }
}
