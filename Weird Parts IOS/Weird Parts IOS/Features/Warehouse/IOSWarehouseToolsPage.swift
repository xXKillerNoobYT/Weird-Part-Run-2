import SwiftUI
import WiredPartCore

/// Warehouse tools registry page showing tools assigned to the warehouse.
///
/// Lists all tools currently checked into the warehouse with search,
/// filter by status, and navigation to tool details.
struct IOSWarehouseToolsPage: View {
    @EnvironmentObject private var appCore: AppCore

    @State private var tools: [ToolsService.ToolListItem] = []
    @State private var isLoading = true
    @State private var searchText = ""
    @State private var statusFilter: String? = nil
    @State private var loadError: String?

    private let statusOptions = ["All", "Available", "Checked Out", "Maintenance"]

    var body: some View {
        VStack(spacing: 0) {
            if isLoading {
                ProgressView("Loading tools...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error = loadError {
                ErrorStateView(message: error) { loadData() }
            } else if filteredTools.isEmpty {
                EmptyStateView(
                    icon: "wrench.and.screwdriver",
                    title: "No Tools",
                    message: searchText.isEmpty ? "No tools registered in the warehouse." : "No tools match your search."
                )
            } else {
                toolsList
            }
        }
        .navigationTitle("Warehouse Tools")
        .searchable(text: $searchText, prompt: "Search tools...")
        .refreshable { loadData() }
        .task { loadData() }
    }

    @ViewBuilder
    private var toolsList: some View {
        List {
            // Stats header
            Section {
                HStack(spacing: 16) {
                    statCard(count: tools.count, label: "Total", color: .blue)
                    statCard(count: tools.filter { $0.status == "available" }.count, label: "Available", color: .green)
                    statCard(count: tools.filter { $0.status == "checked_out" }.count, label: "Out", color: .orange)
                }
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
                .padding(.vertical, 4)
            }

            // Filter pills
            Section {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(statusOptions, id: \.self) { option in
                            Button {
                                statusFilter = option == "All" ? nil : option.lowercased().replacingOccurrences(of: " ", with: "_")
                            } label: {
                                Text(option)
                                    .font(.caption)
                                    .fontWeight(.medium)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 6)
                                    .background(
                                        Capsule().fill(
                                            isSelectedFilter(option) ? Color.accentColor : Color.secondary.opacity(0.15)
                                        )
                                    )
                                    .foregroundStyle(isSelectedFilter(option) ? .white : .primary)
                            }
                        }
                    }
                }
                .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
                .listRowBackground(Color.clear)
            }

            // Tool rows
            Section("Tools (\(filteredTools.count))") {
                ForEach(filteredTools, id: \.id) { tool in
                    toolRow(tool)
                }
            }
        }
        #if os(iOS)
        .listStyle(.insetGrouped)
        #endif
    }

    private func isSelectedFilter(_ option: String) -> Bool {
        if option == "All" { return statusFilter == nil }
        return statusFilter == option.lowercased().replacingOccurrences(of: " ", with: "_")
    }

    private func statCard(count: Int, label: String, color: Color) -> some View {
        VStack(spacing: 4) {
            Text("\(count)")
                .font(.title3)
                .fontWeight(.bold)
                .foregroundStyle(color)
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .dsCard()
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
            }

            Spacer()

            StatusBadge(text: tool.status.replacingOccurrences(of: "_", with: " ").capitalized, color: toolColor(for: tool.status))
        }
        .padding(.vertical, 2)
    }

    private func toolIcon(for status: String) -> String {
        switch status {
        case "available": return "checkmark.circle.fill"
        case "checked_out": return "arrow.up.right.circle.fill"
        case "maintenance": return "wrench.fill"
        default: return "wrench.and.screwdriver"
        }
    }

    private func toolColor(for status: String) -> Color {
        switch status {
        case "available": return .green
        case "checked_out": return .orange
        case "maintenance": return .red
        default: return .secondary
        }
    }

    private var filteredTools: [ToolsService.ToolListItem] {
        var result = tools
        if let filter = statusFilter {
            result = result.filter { $0.status == filter }
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
