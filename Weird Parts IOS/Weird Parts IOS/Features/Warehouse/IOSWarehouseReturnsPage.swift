import SwiftUI
import WiredPartCore

/// Warehouse return processing page for iOS.
///
/// Displays pending returns with type, reason, status, supplier name,
/// and credit amount. Supports smart card filters by status, action buttons
/// per return (approve/reject/ship/complete), and pull-to-refresh.
struct IOSWarehouseReturnsPage: View {
    @EnvironmentObject private var appCore: AppCore

    // MARK: - State

    @State private var allReturns: [OrdersService.ReturnListItem] = []
    @State private var isLoading = true
    @State private var searchText = ""
    @State private var loadError: String?
    @State private var actionError: String?
    @State private var selectedFilter: StatusFilter?
    @State private var activeSheet: ActiveSheet?

    private enum ActiveSheet: Identifiable {
        case createReturn
        case help
        var id: String {
            switch self {
            case .createReturn: "createReturn"
            case .help: "help"
            }
        }
    }

    private enum StatusFilter: String, CaseIterable {
        case pending = "Pending"
        case approved = "Approved"
        case shipped = "Shipped"
        case completed = "Completed"

        var matchStatuses: [String] {
            switch self {
            case .pending: ["pending", "requested"]
            case .approved: ["approved"]
            case .shipped: ["shipped"]
            case .completed: ["completed"]
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Smart card filters
            if !allReturns.isEmpty {
                smartCardFilters
            }

            returnsList
        }
        .navigationTitle("Returns")
        .searchable(text: $searchText, prompt: "Search returns...")
        .refreshable { loadData() }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { activeSheet = .createReturn } label: {
                    Image(systemName: "plus")
                }
            }
            ToolbarItem(placement: .secondaryAction) {
                Button { activeSheet = .help } label: {
                    Image(systemName: "questionmark.circle")
                }
            }
        }
        .sheet(item: $activeSheet) { sheet in
            switch sheet {
            case .createReturn:
                CreateReturnSheet(onSave: { loadData() })
                    .environmentObject(appCore)
            case .help:
                PageHelpSheet(
                    title: "Returns Help",
                    sections: [
                        ("Overview", "Manage return requests to suppliers. Track items through the full return lifecycle: pending, approved, shipped, and completed."),
                        ("Creating Returns", "Tap + to create a new return. Select the supplier, parts, and reason for return."),
                        ("Status Tracking", "Use the smart card filters to view returns by status. Tap any return for full details and actions.")
                    ]
                )
            }
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
                ForEach(StatusFilter.allCases, id: \.self) { filter in
                    let count = allReturns.filter { ret in filter.matchStatuses.contains(ret.status) }.count
                    smartCard(filter: filter, count: count)
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
        }
    }

    private func smartCard(filter: StatusFilter, count: Int) -> some View {
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

    private func filterIcon(_ filter: StatusFilter) -> String {
        switch filter {
        case .pending: "clock.fill"
        case .approved: "checkmark.circle.fill"
        case .shipped: "shippingbox.fill"
        case .completed: "checkmark.seal.fill"
        }
    }

    private func filterColor(_ filter: StatusFilter) -> Color {
        switch filter {
        case .pending: .orange
        case .approved: .blue
        case .shipped: .purple
        case .completed: .green
        }
    }

    // MARK: - Returns List

    @ViewBuilder
    private var returnsList: some View {
        if isLoading {
            ProgressView("Loading returns...")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let error = loadError {
            ErrorStateView(message: error) { loadData() }
        } else if filteredReturns.isEmpty {
            EmptyStateView(
                icon: "arrow.uturn.left.circle",
                title: "No Returns",
                message: searchText.isEmpty && selectedFilter == nil
                    ? "No returns found. Tap + to create a new return."
                    : "No returns match your criteria."
            )
        } else {
            List(filteredReturns, id: \.id) { ret in
                returnRow(ret)
                    .swipeActions(edge: .trailing) {
                        swipeActions(for: ret)
                    }
            }
            .listStyle(.insetGrouped)
        }
    }

    private var filteredReturns: [OrdersService.ReturnListItem] {
        var result = allReturns

        if let filter = selectedFilter {
            result = result.filter { filter.matchStatuses.contains($0.status) }
        }

        if !searchText.isEmpty {
            let query = searchText.lowercased()
            result = result.filter {
                $0.returnType.lowercased().contains(query) ||
                ($0.supplierName?.lowercased().contains(query) ?? false) ||
                ($0.reason?.lowercased().contains(query) ?? false)
            }
        }

        return result
    }

    @ViewBuilder
    private func swipeActions(for ret: OrdersService.ReturnListItem) -> some View {
        switch ret.status {
        case "pending", "requested":
            Button { updateStatus(returnId: ret.id, status: "approved") } label: {
                Label("Approve", systemImage: "checkmark.circle")
            }
            .tint(.green)
            Button(role: .destructive) { updateStatus(returnId: ret.id, status: "cancelled") } label: {
                Label("Reject", systemImage: "xmark.circle")
            }
        case "approved":
            Button { updateStatus(returnId: ret.id, status: "shipped") } label: {
                Label("Mark Shipped", systemImage: "shippingbox")
            }
            .tint(.purple)
        case "shipped":
            Button { updateStatus(returnId: ret.id, status: "completed") } label: {
                Label("Complete", systemImage: "checkmark.seal")
            }
            .tint(.green)
        default:
            EmptyView()
        }
    }

    private func returnRow(_ ret: OrdersService.ReturnListItem) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "arrow.uturn.left.circle.fill")
                .font(.title3)
                .foregroundStyle(statusColor(ret.status))
                .frame(width: 32)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text("RET #\(ret.id)")
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                    typeBadge(ret.returnType)
                }
                if let supplier = ret.supplierName {
                    Text(supplier)
                        .fontWeight(.medium)
                        .lineLimit(1)
                }
                if let reason = ret.reason, !reason.isEmpty {
                    Text(reason)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 4) {
                statusBadge(ret.status)
                if let credit = ret.creditAmount {
                    Text(String(format: "$%.2f", credit))
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundStyle(.green)
                }
                Label("\(ret.lineCount) items", systemImage: "shippingbox")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }

    // MARK: - Badges

    private func statusBadge(_ status: String) -> some View {
        let color = statusColor(status)
        return Text(status.capitalized)
            .font(.system(.caption2, weight: .semibold))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Capsule().fill(color.opacity(0.15)))
            .foregroundStyle(color)
    }

    private func statusColor(_ status: String) -> Color {
        switch status {
        case "pending", "requested": .orange
        case "approved": .blue
        case "shipped": .purple
        case "completed": .green
        case "cancelled": .red
        default: .secondary
        }
    }

    private func typeBadge(_ type: String) -> some View {
        Text(type.replacingOccurrences(of: "_", with: " ").capitalized)
            .font(.caption2)
            .foregroundStyle(.purple)
    }

    // MARK: - Actions

    private func updateStatus(returnId: Int64, status: String) {
        guard let service = appCore.ordersService else {
            actionError = "Service not available"
            return
        }
        do {
            try service.updateReturnStatus(returnId: returnId, status: status)
            loadData()
        } catch {
            actionError = error.localizedDescription
        }
    }

    // MARK: - Data Loading

    private func loadData() {
        guard let service = appCore.ordersService else {
            loadError = "Service not available"
            isLoading = false
            return
        }
        isLoading = allReturns.isEmpty
        loadError = nil
        do {
            allReturns = try service.listReturns(status: nil)
        } catch {
            loadError = error.localizedDescription
        }
        isLoading = false
    }
}


