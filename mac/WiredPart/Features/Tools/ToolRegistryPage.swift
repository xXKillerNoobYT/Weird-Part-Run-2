import SwiftUI
import WiredPartCore

/// Tool registry list page.
///
/// Displays a searchable, sortable table of all tools with name, category,
/// serial number, status, and location columns. Status badges use color
/// coding: available = green, checked_out = blue, maintenance = orange,
/// lost = red.
struct ToolRegistryPage: View {
    @EnvironmentObject private var appCore: AppCore

    // MARK: - Data State

    @State private var tools: [ToolsService.ToolListItem] = []
    @State private var isLoading = true
    @State private var searchText = ""

    // MARK: - Sorting

    @State private var sortOrder = [KeyPathComparator(\ToolsService.ToolListItem.name)]

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
                Text("Tool Registry")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                Text("\(tools.count) tool\(tools.count == 1 ? "" : "s")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            TextField("Search tools...", text: $searchText)
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
            ProgressView("Loading tools...")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if tools.isEmpty {
            VStack(spacing: 12) {
                Image(systemName: "wrench.and.screwdriver")
                    .font(.system(size: 40))
                    .foregroundStyle(.tertiary)
                Text("No tools found")
                    .font(.headline)
                Text("Tools will appear here once added to the registry.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            Table(sortedTools, sortOrder: $sortOrder) {
                TableColumn("Name", value: \.name) { tool in
                    Text(tool.name)
                        .fontWeight(.medium)
                }
                .width(min: 140, ideal: 200)

                TableColumn("Category", value: \.toolType) { tool in
                    Text(tool.toolType.isEmpty ? "-" : tool.toolType.capitalized)
                        .font(.callout)
                }
                .width(min: 100, ideal: 140)

                TableColumn("Serial Number") { (tool: ToolsService.ToolListItem) in
                    Text(tool.serialNumber ?? "-")
                        .font(.system(.callout, design: .monospaced))
                        .foregroundStyle(tool.serialNumber != nil ? .primary : .secondary)
                }
                .width(min: 100, ideal: 160)

                TableColumn("Status", value: \.status) { tool in
                    statusBadge(tool.status)
                }
                .width(min: 90, ideal: 120)

                TableColumn("Assigned To") { (tool: ToolsService.ToolListItem) in
                    Text(tool.assignedToName ?? "-")
                        .font(.callout)
                        .foregroundStyle(tool.assignedToName != nil ? .primary : .secondary)
                }
                .width(min: 100, ideal: 160)
            }
            .tableStyle(.inset(alternatesRowBackgrounds: true))
        }
    }

    private var sortedTools: [ToolsService.ToolListItem] {
        tools.sorted(using: sortOrder)
    }

    // MARK: - Badges

    private func statusBadge(_ status: String) -> some View {
        let color: Color = switch status {
        case "available": .green
        case "checked_out": .blue
        case "maintenance": .orange
        case "lost": .red
        default: .secondary
        }
        return Text(status.replacingOccurrences(of: "_", with: " ").capitalized)
            .font(.system(.caption, weight: .semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Capsule().fill(color.opacity(0.15)))
            .foregroundStyle(color)
    }

    // MARK: - Data Loading

    private func load() {
        guard let db = appCore.db else { return }
        let service = ToolsService(db: db)
        isLoading = true
        do {
            let allTools = try service.listTools()
            // Client-side search filter
            if searchText.isEmpty {
                tools = allTools
            } else {
                let query = searchText.lowercased()
                tools = allTools.filter {
                    $0.name.lowercased().contains(query) ||
                    $0.toolNumber.lowercased().contains(query) ||
                    ($0.serialNumber?.lowercased().contains(query) ?? false) ||
                    $0.toolType.lowercased().contains(query)
                }
            }
        } catch {
            print("[ToolRegistryPage] Load error: \(error)")
        }
        isLoading = false
    }
}
