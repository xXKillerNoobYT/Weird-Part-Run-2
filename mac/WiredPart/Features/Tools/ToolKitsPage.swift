import SwiftUI
import WiredPartCore

/// Tool kits list page.
///
/// Displays a searchable, sortable table of all tool kits with kit name,
/// tool count, status, and description columns.
struct ToolKitsPage: View {
    @EnvironmentObject private var appCore: AppCore

    // MARK: - Data State

    @State private var kits: [ToolsService.KitListItem] = []
    @State private var isLoading = true
    @State private var searchText = ""

    // MARK: - Sorting

    @State private var sortOrder = [KeyPathComparator(\ToolsService.KitListItem.name)]

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
                Text("Tool Kits")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                Text("\(kits.count) kit\(kits.count == 1 ? "" : "s")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            TextField("Search kits...", text: $searchText)
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
            ProgressView("Loading kits...")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if kits.isEmpty {
            VStack(spacing: 12) {
                Image(systemName: "bag")
                    .font(.system(size: 40))
                    .foregroundStyle(.tertiary)
                Text("No kits found")
                    .font(.headline)
                Text("Tool kits will appear here once created.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            Table(sortedKits, sortOrder: $sortOrder) {
                TableColumn("Kit Name", value: \.name) { kit in
                    Text(kit.name)
                        .fontWeight(.medium)
                }
                .width(min: 140, ideal: 220)

                TableColumn("Tool Count", value: \.itemCount) { kit in
                    HStack(spacing: 4) {
                        Image(systemName: "wrench.and.screwdriver")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text("\(kit.itemCount)")
                            .font(.callout)
                    }
                }
                .width(min: 80, ideal: 110)

                TableColumn("Status") { (kit: ToolsService.KitListItem) in
                    kitStatusBadge(kit.isActive)
                }
                .width(min: 80, ideal: 100)

                TableColumn("Description") { (kit: ToolsService.KitListItem) in
                    Text(kit.description ?? "-")
                        .font(.callout)
                        .lineLimit(2)
                        .foregroundStyle(kit.description != nil ? .primary : .secondary)
                }
                .width(min: 160, ideal: 280)
            }
            .tableStyle(.inset(alternatesRowBackgrounds: true))
        }
    }

    private var sortedKits: [ToolsService.KitListItem] {
        kits.sorted(using: sortOrder)
    }

    // MARK: - Badges

    private func kitStatusBadge(_ isActive: Bool) -> some View {
        let label = isActive ? "Active" : "Inactive"
        let color: Color = isActive ? .green : .secondary
        return Text(label)
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
            let allKits = try service.listKits()
            // Client-side search filter
            if searchText.isEmpty {
                kits = allKits
            } else {
                let query = searchText.lowercased()
                kits = allKits.filter {
                    $0.name.lowercased().contains(query) ||
                    ($0.description?.lowercased().contains(query) ?? false)
                }
            }
        } catch {
            print("[ToolKitsPage] Load error: \(error)")
        }
        isLoading = false
    }
}
