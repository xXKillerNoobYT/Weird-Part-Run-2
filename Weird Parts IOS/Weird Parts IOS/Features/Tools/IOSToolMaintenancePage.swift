import SwiftUI
import WiredPartCore

/// Tool maintenance tracking page — shows service history and upcoming maintenance.
struct IOSToolMaintenancePage: View {
    @EnvironmentObject private var appCore: AppCore

    @State private var tools: [ToolsService.ToolListItem] = []
    @State private var isLoading = true
    @State private var loadError: String?
    @State private var searchText = ""
    @State private var activeSheet: ActiveSheet?

    private enum ActiveSheet: Identifiable {
        case help
        var id: String { "help" }
    }

    var body: some View {
        VStack(spacing: 0) {
            if isLoading {
                ProgressView("Loading maintenance data...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error = loadError {
                ErrorStateView(message: error) { loadData() }
            } else if maintenanceTools.isEmpty {
                EmptyStateView(
                    icon: "wrench.fill",
                    title: "No Maintenance",
                    message: "No tools currently need maintenance."
                )
            } else {
                maintenanceList
            }
        }
        .navigationTitle("Tool Maintenance")
        .searchable(text: $searchText, prompt: "Search by tool name or serial...")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { activeSheet = .help } label: {
                    Image(systemName: "questionmark.circle")
                }
            }
        }
        .sheet(item: $activeSheet) { _ in
            PageHelpSheet(
                title: "Tool Maintenance Help",
                sections: [
                    ("What This Page Does", "This page shows all tools that are currently in maintenance status. These are tools that have been pulled from service for repair, calibration, inspection, or any other servicing need."),
                    ("Maintenance List", "Each row shows the tool name, serial number, and an orange 'Maintenance' badge. Use the search bar to find a specific tool by name or serial number."),
                    ("Resolving Maintenance", "To mark a tool as back in service, tap it to open the detail page, then use the Edit action to change its status back to 'Available'. Make sure the tool has actually been repaired or serviced before changing its status."),
                    ("Tips", "Check this page regularly. Tools stuck in maintenance for a long time may need follow-up with the repair shop. If this list is empty, all tools are in working order.")
                ]
            )
        }
        .refreshable { loadData() }
        .task { loadData() }
    }

    private var maintenanceTools: [ToolsService.ToolListItem] {
        let filtered = tools.filter { $0.status == "maintenance" }
        guard !searchText.isEmpty else { return filtered }
        let query = searchText.lowercased()
        return filtered.filter {
            $0.name.lowercased().contains(query) ||
            ($0.serialNumber?.lowercased().contains(query) ?? false)
        }
    }

    private var maintenanceList: some View {
        List(maintenanceTools, id: \.id) { tool in
            HStack(spacing: 12) {
                Image(systemName: "wrench.fill")
                    .foregroundStyle(.orange)
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
                StatusBadge(text: "Maintenance", color: .orange)
            }
        }
        .listStyle(.insetGrouped)
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
        } catch {
            loadError = error.localizedDescription
        }
        isLoading = false
    }
}
