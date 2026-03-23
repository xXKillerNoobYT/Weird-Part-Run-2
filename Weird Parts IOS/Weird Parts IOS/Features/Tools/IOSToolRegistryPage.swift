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
    @State private var loadError: String?
    @State private var activeSheet: ActiveSheet?

    private enum ActiveSheet: Identifiable {
        case toolScanner
        case printLabels

        var id: String {
            switch self {
            case .toolScanner: "toolScanner"
            case .printLabels: "printLabels"
            }
        }
    }

    private let statusOptions = ["all", "available", "checked_out", "maintenance", "lost"]

    var body: some View {
        VStack(spacing: 0) {
            statusPicker
            toolList
        }
        .navigationTitle("Tool Registry")
        .searchable(text: $searchText, prompt: "Search tools...")
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button { activeSheet = .printLabels } label: {
                    Image(systemName: "printer")
                }
                Button { activeSheet = .toolScanner } label: {
                    Image(systemName: "qrcode.viewfinder")
                }
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
            }
        }
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
                        Text(status == "all" ? "All" : status.replacingOccurrences(of: "_", with: " ").capitalized)
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
                toolRow(tool)
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
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.maximumFractionDigits = 0
        return formatter.string(from: NSNumber(value: value)) ?? "$\(Int(value))"
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
        } catch {
            loadError = error.localizedDescription
        }
        isLoading = false
    }
}
