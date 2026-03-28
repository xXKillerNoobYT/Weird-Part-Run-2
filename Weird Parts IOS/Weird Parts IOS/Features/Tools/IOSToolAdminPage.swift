import SwiftUI
import WiredPartCore

/// Tool admin page for bulk management, full tool list, and status overview.
struct IOSToolAdminPage: View {
    @EnvironmentObject private var appCore: AppCore

    @State private var tools: [ToolsService.ToolListItem] = []
    @State private var stats: ToolsService.ToolsStats?
    @State private var isLoading = true
    @State private var searchText = ""
    @State private var loadError: String?
    @State private var activeSheet: ActiveSheet?

    private enum ActiveSheet: Identifiable {
        case help
        var id: String { "help" }
    }

    var body: some View {
        VStack(spacing: 0) {
            if isLoading {
                ProgressView("Loading tools...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error = loadError {
                ErrorStateView(message: error) { loadData() }
            } else {
                toolsContent
            }
        }
        .navigationTitle("Tool Admin")
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
                title: "Tool Admin Help",
                sections: [
                    ("What This Page Does", "Tool Admin is the management view for supervisors and office staff. It provides an overview of tool counts by status along with a complete searchable list of every tool in the system."),
                    ("Overview Section", "The top section shows key counts: total tools, how many are checked out, and how many are in maintenance. These numbers update when you pull to refresh."),
                    ("All Tools List", "Below the overview is the full tool list with status badges. Tap any tool to open its detail page where you can edit information, change status, manage checkouts, and view history."),
                    ("Searching", "Use the search bar to find tools by name or serial number. The count next to 'All Tools' updates to reflect your filtered results."),
                    ("Tips", "Use this page for audits and inventory checks. Sort through tools to verify serial numbers match physical tools. If a tool shows 'Checked Out' but is sitting on the shelf, open its detail page and return it to keep records accurate.")
                ]
            )
        }
        .refreshable { loadData() }
        .task { loadData() }
    }

    private var toolsContent: some View {
        List {
            if let s = stats {
                Section("Overview") {
                    statRow("Total Tools", "\(s.totalTools)", .blue)
                    statRow("Checked Out", "\(s.checkedOut)", .orange)
                    statRow("In Maintenance", "\(s.inMaintenance)", .red)
                }
            }

            Section("All Tools (\(filteredTools.count))") {
                ForEach(filteredTools, id: \.id) { tool in
                    NavigationLink(destination: IOSToolDetailPage(toolId: tool.id).environmentObject(appCore)) {
                        toolRow(tool)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
    }

    private func toolRow(_ tool: ToolsService.ToolListItem) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "wrench.and.screwdriver.fill")
                .foregroundStyle(statusColor(tool.status))
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(tool.name)
                    .fontWeight(.medium)
                if let serial = tool.serialNumber, !serial.isEmpty {
                    Text(serial)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .monospaced()
                }
            }
            Spacer()
            StatusBadge(
                text: tool.status.replacingOccurrences(of: "_", with: " ").capitalized,
                color: statusColor(tool.status)
            )
        }
    }

    private func statRow(_ label: String, _ value: String, _ color: Color) -> some View {
        HStack(spacing: 12) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text(label).foregroundStyle(.secondary)
            Spacer()
            Text(value).fontWeight(.semibold)
        }
    }

    private func statusColor(_ status: String) -> Color {
        switch status {
        case "available": return .green
        case "checked_out": return .orange
        case "maintenance": return .red
        default: return .secondary
        }
    }

    private var filteredTools: [ToolsService.ToolListItem] {
        guard !searchText.isEmpty else { return tools }
        let query = searchText.lowercased()
        return tools.filter {
            $0.name.lowercased().contains(query) ||
            ($0.serialNumber?.lowercased().contains(query) ?? false)
        }
    }

    private func loadData() {
        guard let service = appCore.toolsService else {
            isLoading = false
            loadError = "Tools service unavailable"
            return
        }
        isLoading = tools.isEmpty
        loadError = nil
        do {
            tools = try service.listTools()
            stats = try service.getToolsStats()
        } catch {
            loadError = userFriendlyError(error, context: "load tool admin")
        }
        isLoading = false
    }
}
