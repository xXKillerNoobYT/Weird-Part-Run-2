import SwiftUI
import WiredPartCore

/// Pulled items staging area page for iOS.
///
/// Displays parts that have been pulled from warehouse stock and tagged
/// for specific jobs or destinations. Shows part name, quantity, destination,
/// and the person who tagged them. Supports pull-to-refresh.
struct IOSStagingPage: View {
    @EnvironmentObject private var appCore: AppCore

    // MARK: - State

    @State private var stagedItems: [WarehouseService.StagedItem] = []
    @State private var isLoading = true
    @State private var searchText = ""
    @State private var loadError: String?

    var body: some View {
        stagingList
            .navigationTitle("Staging Area")
            .searchable(text: $searchText, prompt: "Search staged parts...")
            .onChange(of: searchText) { /* local filter only */ }
            .refreshable { loadData() }
            .task { loadData() }
    }

    // MARK: - Staging List

    @ViewBuilder
    private var stagingList: some View {
        if isLoading {
            ProgressView("Loading staged items...")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let error = loadError {
            ErrorStateView(message: error) { loadData() }
        } else if filteredItems.isEmpty {
            ContentUnavailableView {
                Label("No Staged Items", systemImage: "tray")
            } description: {
                Text("No parts are currently staged for pickup.")
            }
        } else {
            List {
                Section {
                    Text("\(filteredItems.count) item\(filteredItems.count == 1 ? "" : "s") staged")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                ForEach(filteredItems, id: \.id) { item in
                    stagedRow(item)
                }
            }
            #if os(iOS)
            .listStyle(.insetGrouped)
            #endif
        }
    }

    private var filteredItems: [WarehouseService.StagedItem] {
        guard !searchText.isEmpty else { return stagedItems }
        let query = searchText.lowercased()
        return stagedItems.filter {
            $0.partName.lowercased().contains(query) ||
            ($0.partCode?.lowercased().contains(query) ?? false) ||
            ($0.destinationLabel?.lowercased().contains(query) ?? false)
        }
    }

    private func stagedRow(_ item: WarehouseService.StagedItem) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "tray.and.arrow.down.fill")
                .font(.title3)
                .foregroundStyle(Color.orange)
                .frame(width: 32)

            VStack(alignment: .leading, spacing: 4) {
                Text(item.partName)
                    .fontWeight(.medium)
                    .lineLimit(1)
                if let code = item.partCode, !code.isEmpty {
                    Text(code)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
                if let dest = item.destinationLabel, !dest.isEmpty {
                    Label(dest, systemImage: "arrow.right.circle")
                        .font(.caption)
                        .foregroundStyle(.blue)
                } else if let destType = item.destinationType {
                    Label(destType.capitalized, systemImage: "arrow.right.circle")
                        .font(.caption)
                        .foregroundStyle(.blue)
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 4) {
                Text("x\(item.qty)")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                if let taggedBy = item.taggedByName {
                    Text(taggedBy)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                if let taggedAt = item.taggedAt {
                    Text(formatDate(taggedAt))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .padding(.vertical, 4)
    }

    // MARK: - Helpers

    private func formatDate(_ dateStr: String) -> String {
        if dateStr.count >= 10 { return String(dateStr.prefix(10)) }
        return dateStr
    }

    // MARK: - Data Loading

    private func loadData() {
        guard let service = appCore.warehouseService else { return }
        isLoading = stagedItems.isEmpty
        loadError = nil
        do {
            stagedItems = try service.getStagedItems()
        } catch {
            loadError = error.localizedDescription
        }
        isLoading = false
    }
}
