import SwiftUI
import WiredPartCore

/// Tool maintenance tracking page — shows service history and upcoming maintenance.
struct IOSToolMaintenancePage: View {
    @EnvironmentObject private var appCore: AppCore

    @State private var tools: [ToolsService.ToolListItem] = []
    @State private var isLoading = true
    @State private var loadError: String?

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
        .refreshable { loadData() }
        .task { loadData() }
    }

    private var maintenanceTools: [ToolsService.ToolListItem] {
        tools.filter { $0.status == "maintenance" }
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
        #if os(iOS)
        .listStyle(.insetGrouped)
        #endif
    }

    private func loadData() {
        guard let service = appCore.toolsService else { return }
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
