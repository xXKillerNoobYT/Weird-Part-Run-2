import SwiftUI
import WiredPartCore

/// Pulled items staging area page for iOS.
///
/// Displays parts that have been pulled from warehouse stock and tagged
/// for specific jobs or destinations. Shows part name, quantity, destination,
/// and the person who tagged them.
///
/// Features swipe-to-load with confirmation, batch selection mode,
/// smart card filters by destination type, and pull-to-refresh.
struct IOSStagingPage: View {
    @EnvironmentObject private var appCore: AppCore

    // MARK: - State

    @State private var stagedItems: [WarehouseService.StagedItem] = []
    @State private var isLoading = true
    @State private var searchText = ""
    @State private var loadError: String?
    @State private var actionError: String?

    // Confirmation
    @State private var itemToLoad: WarehouseService.StagedItem?
    @State private var showLoadConfirm = false

    // Batch selection
    @State private var selectedItems: Set<Int64> = []
    @State private var isSelecting = false
    @State private var showBatchConfirm = false

    // Smart card filter
    @State private var selectedFilter: DestinationFilter?

    private enum DestinationFilter: String, CaseIterable {
        case job = "Jobs"
        case truck = "Trucks"
        case trailer = "Trailers"
        case other = "Other"

        var matchTypes: [String] {
            switch self {
            case .job: ["job"]
            case .truck: ["truck"]
            case .trailer: ["trailer"]
            case .other: ["warehouse", "staging", "pulled", ""]
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Smart card filters
            if !stagedItems.isEmpty {
                smartCardFilters
            }

            stagingList
        }
        .navigationTitle("Staging Area")
        .searchable(text: $searchText, prompt: "Search staged parts...")
        .refreshable { loadData() }
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                if isSelecting {
                    Button("Clear \(selectedItems.count)") {
                        showBatchConfirm = true
                    }
                    .disabled(selectedItems.isEmpty)

                    Button("Cancel") {
                        isSelecting = false
                        selectedItems.removeAll()
                    }
                } else if !stagedItems.isEmpty {
                    Button {
                        isSelecting = true
                    } label: {
                        Image(systemName: "checklist")
                    }
                }
            }
        }
        .alert("Mark as Loaded?", isPresented: $showLoadConfirm) {
            Button("Cancel", role: .cancel) { }
            Button("Confirm Loaded") {
                if let item = itemToLoad {
                    clearItem(id: item.id)
                }
            }
        } message: {
            Text("This will clear \(itemToLoad?.partName ?? "this item") from staging. It will be marked as loaded onto the truck/vehicle.")
        }
        .alert("Clear \(selectedItems.count) Items?", isPresented: $showBatchConfirm) {
            Button("Cancel", role: .cancel) { }
            Button("Clear All Selected", role: .destructive) {
                clearSelectedItems()
            }
        } message: {
            Text("This will mark \(selectedItems.count) item\(selectedItems.count == 1 ? "" : "s") as loaded and remove them from staging.")
        }
        .alert("Error", isPresented: .constant(actionError != nil)) {
            Button("OK") { actionError = nil }
        } message: {
            Text(actionError ?? "")
        }
        .task { loadData() }
    }

    // MARK: - Smart Card Filters

    private var smartCardFilters: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(DestinationFilter.allCases, id: \.self) { filter in
                    let count = countForFilter(filter)
                    smartCard(filter: filter, count: count)
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
        }
    }

    private func countForFilter(_ filter: DestinationFilter) -> Int {
        stagedItems.filter { item in
            let destType = item.destinationType ?? ""
            return filter.matchTypes.contains(destType)
        }.count
    }

    private func smartCard(filter: DestinationFilter, count: Int) -> some View {
        let isSelected = selectedFilter == filter
        let color = filterColor(filter)

        return Button {
            selectedFilter = isSelected ? nil : filter
        } label: {
            VStack(spacing: 4) {
                HStack(spacing: 4) {
                    Image(systemName: filterIcon(filter))
                        .font(.caption)
                    Text("\(count)")
                        .font(.title3)
                        .fontWeight(.bold)
                }
                Text(filter.rawValue)
                    .font(.caption2)
                    .lineLimit(1)
            }
            .frame(minWidth: 80)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(isSelected ? color.opacity(0.15) : Color.secondary.opacity(0.08))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(isSelected ? color : Color.clear, lineWidth: 1.5)
            )
            .foregroundStyle(isSelected ? color : .primary)
        }
        .buttonStyle(.plain)
    }

    private func filterIcon(_ filter: DestinationFilter) -> String {
        switch filter {
        case .job: "hammer.fill"
        case .truck: "truck.box.fill"
        case .trailer: "truck.box.badge.clock.fill"
        case .other: "tray.full.fill"
        }
    }

    private func filterColor(_ filter: DestinationFilter) -> Color {
        switch filter {
        case .job: .purple
        case .truck: .green
        case .trailer: .orange
        case .other: .blue
        }
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
            if searchText.isEmpty && selectedFilter == nil {
                EmptyStateView(
                    icon: "tray",
                    title: "No Staged Items",
                    message: "No parts are currently staged for pickup. Use the Movement Wizard to pull parts from warehouse stock."
                )
            } else {
                EmptyStateView(
                    icon: "magnifyingglass",
                    title: "No Results",
                    message: "No staged items match your current filters."
                )
            }
        } else {
            List {
                Section {
                    Text("\(filteredItems.count) item\(filteredItems.count == 1 ? "" : "s") staged")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                ForEach(filteredItems, id: \.id) { item in
                    HStack(spacing: 0) {
                        if isSelecting {
                            Image(systemName: selectedItems.contains(item.id) ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(selectedItems.contains(item.id) ? .green : .secondary)
                                .font(.title3)
                                .padding(.trailing, 10)
                                .onTapGesture {
                                    toggleSelection(item.id)
                                }
                        }

                        stagedRow(item)
                    }
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        Button {
                            itemToLoad = item
                            showLoadConfirm = true
                        } label: {
                            Label("Loaded", systemImage: "checkmark.circle")
                        }
                        .tint(.green)
                    }
                }
            }
            .listStyle(.insetGrouped)
        }
    }

    private var filteredItems: [WarehouseService.StagedItem] {
        var result = stagedItems

        // Destination filter
        if let filter = selectedFilter {
            result = result.filter { item in
                let destType = item.destinationType ?? ""
                return filter.matchTypes.contains(destType)
            }
        }

        // Search filter
        if !searchText.isEmpty {
            let query = searchText.lowercased()
            result = result.filter {
                $0.partName.lowercased().contains(query) ||
                ($0.partCode?.lowercased().contains(query) ?? false) ||
                ($0.destinationLabel?.lowercased().contains(query) ?? false)
            }
        }

        return result
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

    private func toggleSelection(_ id: Int64) {
        if selectedItems.contains(id) {
            selectedItems.remove(id)
        } else {
            selectedItems.insert(id)
        }
    }

    // MARK: - Actions

    private func clearItem(id: Int64) {
        guard let service = appCore.warehouseService else { return }
        do {
            try service.clearStagingTag(id: id)
            loadData()
        } catch {
            actionError = error.localizedDescription
        }
    }

    private func clearSelectedItems() {
        guard let service = appCore.warehouseService else { return }
        var failCount = 0
        for itemId in selectedItems {
            do {
                try service.clearStagingTag(id: itemId)
            } catch {
                failCount += 1
            }
        }
        selectedItems.removeAll()
        isSelecting = false
        loadData()
        if failCount > 0 {
            actionError = "\(failCount) item\(failCount == 1 ? "" : "s") failed to clear."
        }
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
