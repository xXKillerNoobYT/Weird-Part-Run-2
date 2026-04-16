import SwiftUI
import WiredPartCore

/// Tool registry list page for iOS.
///
/// Displays a searchable list of tools with name, tool number,
/// category, serial number, assigned user, and status badge.
/// Supports pull-to-refresh and status-based filtering.
struct IOSToolRegistryPage: View {
    @EnvironmentObject private var appCore: AppCore

    // MARK: - State

    @State private var tools: [ToolsService.ToolListItem] = []
    @State private var isLoading = true
    @State private var searchText = ""
    @State private var statusFilter = "all"
    @State private var statusCounts: [String: Int] = [:]
    @State private var loadError: String?
    @State private var activeSheet: ActiveSheet?

    private enum ActiveSheet: Identifiable {
        case toolScanner
        case printLabels
        case help

        var id: String {
            switch self {
            case .toolScanner: "toolScanner"
            case .printLabels: "printLabels"
            case .help: "help"
            }
        }
    }

    private let statusOptions = ["all", "available", "checked_out", "maintenance", "lost"]

    var body: some View {
        VStack(spacing: 0) {
            OnboardingBanner(pageId: "tools-registry")
            SkippedModuleHint(moduleId: "tools")
            statusPicker
            toolList
        }
        .task { appCore.onboardingManager?.markCompleted("tools-browse") }
        .navigationTitle("All Tools")
        .searchable(text: $searchText, prompt: "Search tools...")
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button { activeSheet = .printLabels } label: {
                    Image(systemName: "printer")
                }
                .accessibilityLabel("Print labels")
                Button { activeSheet = .toolScanner } label: {
                    Image(systemName: "qrcode.viewfinder")
                }
                .accessibilityLabel("Scan tool QR code")
            }
            ToolbarItem(placement: .primaryAction) {
                Button { activeSheet = .help } label: {
                    Image(systemName: "questionmark.circle")
                }
                .accessibilityLabel("Help")
            }
        }
        .sheet(item: $activeSheet) { sheet in
            switch sheet {
            case .toolScanner:
                QRScanSheet(expectedType: .tool) { result in
                    if result.isFound {
                        if let toolName = result.fields["tool_name"] ?? result.fields["name"] {
                            searchText = toolName
                        } else {
                            searchText = result.code
                        }
                    }
                }
                .environmentObject(appCore)
            case .printLabels:
                QRLabelPrintSheet(items: filteredTools.map { tool in
                    QRLabelContent(
                        entityType: .tool,
                        entityId: tool.id,
                        code: tool.serialNumber ?? tool.toolNumber,
                        title: tool.name,
                        subtitle: tool.toolType.replacingOccurrences(of: "_", with: " ").capitalized,
                        detail: tool.assignedToName
                    )
                })
            case .help:
                PageHelpSheet(
                    title: "All Tools Help",
                    sections: [
                        ("What This Page Does", "The All Tools is the master inventory of every tool the company owns. Each entry shows the tool name, number, category, serial number, who it is assigned to, current status, and value."),
                        ("Searching & Filtering", "Use the search bar to find tools by name, tool number, serial number, or assignee. Tap the status pills at the top (All, Available, Checked Out, Maintenance, Lost) to filter the list by current status."),
                        ("QR Scanner", "Tap the QR code icon in the toolbar to scan a tool's QR label. The scanned tool will appear in your search results automatically."),
                        ("Printing Labels", "Tap the printer icon to generate QR labels for the currently visible tools. You can print labels for the entire filtered list at once."),
                        ("Tool Details", "Tap any tool row to open its full detail page where you can check it out, return it, edit its info, or report an issue."),
                        ("Tips", "Tools with a red 'Lost' badge need investigation. Orange 'Maintenance' tools are out of service. Green 'Available' tools are ready for checkout.")
                    ]
                )
            }
        }
        .onChange(of: searchText) { loadData() }
        .refreshable { loadData() }
        .task { loadData() }
        .onAppear {
            NotificationCenter.default.post(
                name: .toolRegistryPageActive,
                object: nil,
                userInfo: [
                    "context": "All Tools: \(tools.count) tools, filter: \(statusFilter)."
                ]
            )
        }
        .onDisappear {
            NotificationCenter.default.post(name: .toolRegistryPageInactive, object: nil)
        }
    }

    // MARK: - Status Picker

    private var statusPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                let total = statusCounts.values.reduce(0, +)
                SmartFilterCard(
                    title: "All",
                    count: total,
                    isSelected: statusFilter == "all",
                    action: { statusFilter = "all"; loadData() }
                )
                ForEach(statusOptions.dropFirst(), id: \.self) { status in
                    SmartFilterCard(
                        title: status.replacingOccurrences(of: "_", with: " ").capitalized,
                        count: statusCounts[status] ?? 0,
                        isSelected: statusFilter == status,
                        action: { statusFilter = status; loadData() }
                    )
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
        }
    }

    // MARK: - Tool List

    @ViewBuilder
    private var toolList: some View {
        if isLoading {
            ProgressView("Loading tools...")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let error = loadError {
            ErrorStateView(message: error) { loadData() }
        } else if filteredTools.isEmpty {
            EmptyStateView(
                icon: "wrench.and.screwdriver",
                title: "No Tools",
                message: searchText.isEmpty ? "No tools have been registered yet." : "No tools match your criteria."
            )
        } else {
            List(filteredTools, id: \.id) { tool in
                NavigationLink(destination: IOSToolDetailPage(toolId: tool.id).environmentObject(appCore)) {
                    toolRow(tool)
                }
            }
            .listStyle(.insetGrouped)
        }
    }

    private var filteredTools: [ToolsService.ToolListItem] {
        guard !searchText.isEmpty else { return tools }
        let query = searchText.lowercased()
        return tools.filter {
            $0.name.lowercased().contains(query) ||
            $0.toolNumber.lowercased().contains(query) ||
            ($0.serialNumber?.lowercased().contains(query) ?? false) ||
            ($0.assignedToName?.lowercased().contains(query) ?? false)
        }
    }

    private func toolRow(_ tool: ToolsService.ToolListItem) -> some View {
        HStack(spacing: 12) {
            Image(systemName: toolIcon(tool.toolType))
                .font(.title2)
                .foregroundStyle(Color.accentColor)
                .frame(width: 36)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(tool.name)
                        .fontWeight(.medium)
                        .lineLimit(1)
                    categoryBadge(tool.toolType)
                }
                Text(tool.toolNumber)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
                if let serial = tool.serialNumber, !serial.isEmpty {
                    Label(serial, systemImage: "barcode")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                if let assignee = tool.assignedToName {
                    Label(assignee, systemImage: "person")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 4) {
                statusBadge(tool.status)
                if let value = tool.currentValue, value > 0 {
                    Text(formatCurrency(value))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 4)
    }

    // MARK: - Helpers

    private func toolIcon(_ type: String) -> String {
        switch type.lowercased() {
        case "power_tool", "power tool": return "bolt.circle"
        case "hand_tool", "hand tool": return "wrench"
        case "measurement": return "ruler"
        case "safety": return "shield.checkered"
        case "cutting": return "scissors"
        default: return "wrench.and.screwdriver"
        }
    }

    private func categoryBadge(_ type: String) -> some View {
        Text(type.replacingOccurrences(of: "_", with: " ").capitalized)
            .font(.system(.caption2, weight: .medium))
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .background(Capsule().fill(Color.indigo.opacity(0.12)))
            .foregroundStyle(.indigo)
    }

    private func statusBadge(_ status: String) -> some View {
        let color: Color = switch status {
        case "available": .green
        case "checked_out": .blue
        case "maintenance": .orange
        case "lost": .red
        case "retired": .secondary
        default: .secondary
        }
        return Text(status.replacingOccurrences(of: "_", with: " ").capitalized)
            .font(.system(.caption2, weight: .semibold))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Capsule().fill(color.opacity(0.15)))
            .foregroundStyle(color)
    }

    private func formatCurrency(_ value: Double) -> String {
        Formatters.formatCurrencyWhole(value)
    }

    // MARK: - Data Loading

    private func loadData() {
        guard let service = appCore.toolsService else {
            isLoading = false
            loadError = "Tools service unavailable"
            return
        }
        isLoading = tools.isEmpty
        loadError = nil
        do {
            tools = try service.listTools(
                search: searchText.isEmpty ? nil : searchText,
                status: statusFilter == "all" ? nil : statusFilter
            )
            // Load status counts for SmartFilterCard
            if statusCounts.isEmpty {
                let allTools = try service.listTools(search: nil, status: nil)
                var counts: [String: Int] = [:]
                for tool in allTools {
                    counts[tool.status, default: 0] += 1
                }
                statusCounts = counts
            }
        } catch {
            loadError = userFriendlyError(error, context: "load tools")
        }
        isLoading = false
    }
}
