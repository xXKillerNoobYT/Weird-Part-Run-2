import SwiftUI
import WiredPartCore

/// Returns list page for iOS.
///
/// Displays a searchable list of part returns with return type, status badge,
/// supplier name, reason, and credit amount. Supports pull-to-refresh,
/// smart card status filters, and create return sheet.
struct IOSReturnsPage: View {
    @EnvironmentObject private var appCore: AppCore

    // MARK: - State

    @State private var allReturns: [OrdersService.ReturnListItem] = []
    @State private var isLoading = true
    @State private var searchText = ""
    @State private var statusFilter: String? = nil  // nil = all
    @State private var loadError: String?
    @State private var activeSheet: ActiveSheet?

    private enum ActiveSheet: Identifiable {
        case createReturn
        case help
        var id: String { String(describing: self) }
    }

    var body: some View {
        VStack(spacing: 0) {
            OnboardingBanner(pageId: "orders-returns")
            smartCardFilters
            returnsList
        }
        .task { appCore.onboardingManager?.markCompleted("returns-view") }
        .navigationTitle("Returns")
        .searchable(text: $searchText, prompt: "Search returns...")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { activeSheet = .createReturn } label: { Image(systemName: "plus") }
                    .accessibilityLabel("Create return")
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
            case .createReturn:
                CreateReturnSheet(onSave: { loadData() })
                    .environmentObject(appCore)
            case .help:
                PageHelpSheet(
                    title: "Returns Help",
                    sections: [
                        ("What This Page Does", "Tracks all part returns to suppliers. Returns can be for wrong parts, damaged items, overstock, or unused materials. Each return has a status, supplier, reason, and credit amount."),
                        ("How to Use It", "Use the filter cards to view by status (Pending, Approved, Shipped, Completed). Search by return type, supplier name, or reason. Tap + to create a new return request."),
                        ("Return Flow", "Pending -> Approved (supplier accepted the return) -> Shipped (parts sent back) -> Completed (credit received). Each stage updates the credit tracking."),
                        ("Tips", "The credit amount shows expected refund value in green. Filter by Pending to see returns that need follow-up with suppliers. Pull down to refresh the list.")
                    ]
                )
            }
        }
        .onChange(of: searchText) { loadData() }
        .onChange(of: statusFilter) { postAIContext() }
        .refreshable { loadData() }
        .task { loadData() }
        .onDisappear {
            NotificationCenter.default.post(name: .returnsPageInactive, object: nil)
        }
    }

    // MARK: - Smart Card Filters

    private func countForStatus(_ status: String) -> Int {
        allReturns.filter { $0.status == status }.count
    }

    private var smartCardFilters: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                smartCard("All", count: allReturns.count, icon: "arrow.uturn.left.circle", filter: nil, color: Color.accentColor)
                smartCard("Pending", count: countForStatus("pending") + countForStatus("requested"), icon: "clock", filter: "pending", color: .orange)
                smartCard("Approved", count: countForStatus("approved"), icon: "checkmark.circle", filter: "approved", color: .blue)
                smartCard("Shipped", count: countForStatus("shipped"), icon: "shippingbox", filter: "shipped", color: .purple)
                smartCard("Completed", count: countForStatus("completed"), icon: "checkmark.seal", filter: "completed", color: .green)
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
        }
    }

    private func smartCard(_ label: String, count: Int, icon: String, filter: String?, color: Color) -> some View {
        Button {
            withAnimation { statusFilter = statusFilter == filter ? nil : filter }
        } label: {
            VStack(spacing: 4) {
                HStack(spacing: 4) {
                    Image(systemName: icon)
                        .font(.caption)
                    Text("\(count)")
                        .font(.title3)
                        .fontWeight(.bold)
                }
                Text(label)
                    .font(.caption2)
            }
            .frame(minWidth: 70)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(statusFilter == filter ? color : Color.secondary.opacity(0.12))
            )
            .foregroundStyle(statusFilter == filter ? .white : .primary)
        }
        .buttonStyle(.plain)
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
                message: searchText.isEmpty ? "No returns match the selected filter." : "No returns match your search."
            )
        } else {
            List(filteredReturns, id: \.id) { ret in
                returnRow(ret)
            }
            .listStyle(.insetGrouped)
        }
    }

    private var filteredReturns: [OrdersService.ReturnListItem] {
        var result = allReturns
        // Status filter
        if let filter = statusFilter {
            if filter == "pending" {
                result = result.filter { $0.status == "pending" || $0.status == "requested" }
            } else {
                result = result.filter { $0.status == filter }
            }
        }
        // Search filter
        guard !searchText.isEmpty else { return result }
        let query = searchText.lowercased()
        return result.filter {
            $0.returnType.lowercased().contains(query) ||
            ($0.supplierName?.lowercased().contains(query) ?? false) ||
            ($0.reason?.lowercased().contains(query) ?? false)
        }
    }

    private func returnRow(_ ret: OrdersService.ReturnListItem) -> some View {
        HStack(spacing: 12) {
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
        let color: Color = switch status {
        case "pending", "requested": .orange
        case "approved": .blue
        case "shipped": .purple
        case "completed": .green
        case "cancelled": .red
        default: .secondary
        }
        return Text(status.capitalized)
            .font(.system(.caption2, weight: .semibold))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Capsule().fill(color.opacity(0.15)))
            .foregroundStyle(color)
    }

    private func typeBadge(_ type: String) -> some View {
        Text(type.replacingOccurrences(of: "_", with: " ").capitalized)
            .font(.caption2)
            .foregroundStyle(.purple)
    }

    // MARK: - Data Loading

    private func loadData() {
        guard let service = appCore.ordersService else {
            loadError = "Orders service not available"
            isLoading = false
            return
        }
        isLoading = allReturns.isEmpty
        loadError = nil
        do {
            // Load all returns for client-side filtering (enables smart card counts)
            allReturns = try service.listReturns(status: nil)
            postAIContext()
        } catch {
            loadError = userFriendlyError(error, context: "load returns")
        }
        isLoading = false
    }

    private func postAIContext() {
        let statusCounts = Dictionary(grouping: allReturns, by: \.status)
            .map { "\($0.key): \($0.value.count)" }
            .sorted()
            .joined(separator: ", ")
        let creditTotal = filteredReturns.compactMap(\.creditAmount).reduce(0, +)
        let visibleExamples = filteredReturns.prefix(5).map { ret in
            "RET #\(ret.id) \(ret.returnType) \(ret.status)"
        }.joined(separator: ", ")
        let context = """
        Returns page. Read-only context.
        Total returns: \(allReturns.count), visible returns: \(filteredReturns.count), active status filter: \(statusFilter ?? "all"), search active: \(!searchText.isEmpty).
        Status counts: \(statusCounts.isEmpty ? "none" : statusCounts), visible credit total: \(Formatters.formatCurrency(creditTotal)).
        Visible examples: \(visibleExamples.isEmpty ? "none" : visibleExamples).
        Available read-only guidance: explain return statuses, current filters, visible credit totals, and where create/help controls are located. Do not create or update returns directly.
        """
        NotificationCenter.default.post(
            name: .returnsPageActive,
            object: nil,
            userInfo: ["context": context]
        )
    }
}
