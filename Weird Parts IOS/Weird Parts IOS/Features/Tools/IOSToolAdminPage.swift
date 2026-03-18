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
                    toolRow(tool)
                }
            }
        }
        #if os(iOS)
        .listStyle(.insetGrouped)
        #endif
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
        guard let service = appCore.toolsService else { return }
        isLoading = tools.isEmpty
        loadError = nil
        do {
            tools = try service.listTools()
            stats = try service.getToolsStats()
        } catch {
            loadError = error.localizedDescription
        }
        isLoading = false
    }
}
