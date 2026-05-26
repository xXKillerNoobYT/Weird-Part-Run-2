import SwiftUI
import WiredPartCore

/// Tool checkouts list page for iOS.
///
/// Displays a searchable list of tool checkouts with tool name,
/// checked-out-by user, checkout date, expected return date, and
/// status (active vs returned). Supports pull-to-refresh and
/// active/all filtering.
struct IOSToolCheckoutsPage: View {
    @EnvironmentObject private var appCore: AppCore

    // MARK: - State

    @State private var checkouts: [ToolsService.CheckoutRow] = []
    @State private var isLoading = true
    @State private var searchText = ""
    @State private var showActiveOnly = true
    @State private var loadError: String?
    private enum ActiveSheet: String, Identifiable {
        case toolScanner
        case help
        var id: String { rawValue }
    }
    @State private var activeSheet: ActiveSheet?
    @State private var scannedToolId: Int64?
    @State private var scannedToolName: String?
    @State private var showCheckoutConfirm = false

    var body: some View {
        VStack(spacing: 0) {
            OnboardingBanner(pageId: "tools-checkouts")
            filterToggle
            checkoutList
        }
        .task { appCore.onboardingManager?.markCompleted("tools-checkouts-view") }
        .navigationTitle("Tool Checkouts")
        .searchable(text: $searchText, prompt: "Search checkouts...")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
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
                    if let toolId = result.entityId, result.isFound {
                        scannedToolId = toolId
                        scannedToolName = result.fields["tool_name"] ?? result.fields["name"] ?? result.code
                        showCheckoutConfirm = true
                    }
                }
                .environmentObject(appCore)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
            case .help:
                PageHelpSheet(
                    title: "Tool Checkouts Help",
                    sections: [
                        ("What This Page Does", "This page tracks every tool checkout and return. It shows who has which tools, when they were checked out, when they are due back, and whether they have been returned."),
                        ("Active vs All", "Use the filter pills at the top to switch between 'Active' (tools currently out) and 'All' (complete history including returned tools). Active view is the default so you can quickly see what is still out."),
                        ("Status Badges", "Blue 'Active' means the tool is still checked out. Green 'Returned' means it has been brought back. Red 'Overdue' means the expected return date has passed and the tool has not been returned yet."),
                        ("QR Scanner", "Tap the QR code icon to scan a tool's label. After scanning, you can jump to All Tools to see its full details and check it out or return it."),
                        ("Searching", "Use the search bar to find checkouts by tool name or the person who checked it out."),
                        ("Tips", "Keep an eye on overdue tools. If a tool is overdue, contact the person who has it. Regular checkout tracking prevents lost tools and keeps the team accountable.")
                    ]
                )
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
            }
        }
        .alert("Tool Scanned", isPresented: $showCheckoutConfirm) {
            Button("View in Registry") {
                // Navigate to tools registry with this tool's name as search
                NotificationCenter.default.post(
                    name: .navigateToModule,
                    object: nil,
                    userInfo: ["moduleId": "tools", "tabId": "tools-registry"]
                )
            }
            Button("OK", role: .cancel) {}
        } message: {
            Text(scannedToolName ?? "Unknown tool")
        }
        .refreshable { await loadData() }
        .task { await loadData() }
    }

    // MARK: - Filter Toggle

    private var filterToggle: some View {
        HStack(spacing: 8) {
            Button {
                showActiveOnly = true
                Task { await loadData() }
            } label: {
                Text("Active")
                    .font(.caption)
                    .fontWeight(showActiveOnly ? .bold : .regular)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(
                        Capsule().fill(showActiveOnly ? Color.accentColor : Color.secondary.opacity(0.2))
                    )
                    .foregroundStyle(showActiveOnly ? .white : .primary)
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(showActiveOnly ? .isSelected : [])

            Button {
                showActiveOnly = false
                Task { await loadData() }
            } label: {
                Text("All")
                    .font(.caption)
                    .fontWeight(!showActiveOnly ? .bold : .regular)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(
                        Capsule().fill(!showActiveOnly ? Color.accentColor : Color.secondary.opacity(0.2))
                    )
                    .foregroundStyle(!showActiveOnly ? .white : .primary)
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(!showActiveOnly ? .isSelected : [])

            Spacer()
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
    }

    // MARK: - Checkout List

    @ViewBuilder
    private var checkoutList: some View {
        if isLoading {
            ProgressView("Loading checkouts...")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let error = loadError {
            ErrorStateView(message: error) { Task { await loadData() } }
        } else if filteredCheckouts.isEmpty {
            EmptyStateView(
                icon: "arrow.up.right.circle",
                title: "No Checkouts",
                message: showActiveOnly
                    ? "No tools are currently checked out."
                    : "No checkout records found."
            )
        } else {
            List(filteredCheckouts, id: \.id) { checkout in
                checkoutRow(checkout)
            }
            .listStyle(.insetGrouped)
        }
    }

    private var filteredCheckouts: [ToolsService.CheckoutRow] {
        guard !searchText.isEmpty else { return checkouts }
        let query = searchText.lowercased()
        return checkouts.filter {
            $0.toolName.lowercased().contains(query) ||
            $0.checkedOutByName.lowercased().contains(query)
        }
    }

    private func checkoutRow(_ checkout: ToolsService.CheckoutRow) -> some View {
        HStack(spacing: 12) {
            Image(systemName: checkout.returnedAt == nil ? "arrow.up.right.circle.fill" : "arrow.down.left.circle.fill")
                .font(.title2)
                .foregroundStyle(checkout.returnedAt == nil ? .blue : .green)
                .frame(width: 36)
                .accessibilityLabel(checkout.returnedAt == nil ? "Status: Checked out" : "Status: Returned")

            VStack(alignment: .leading, spacing: 4) {
                Text(checkout.toolName)
                    .fontWeight(.medium)
                    .lineLimit(1)
                Label(checkout.checkedOutByName, systemImage: "person")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Label(formatDate(checkout.checkedOutAt), systemImage: "calendar")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                if let dueDate = checkout.expectedReturn {
                    Label("Due \(formatDate(dueDate))", systemImage: "clock")
                        .font(.caption)
                        .foregroundStyle(isOverdue(dueDate, returnedAt: checkout.returnedAt) ? .red : .secondary)
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 4) {
                statusBadge(checkout)
                if let returnedAt = checkout.returnedAt {
                    Text(formatDate(returnedAt))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .padding(.vertical, 4)
    }

    // MARK: - Badges

    private func statusBadge(_ checkout: ToolsService.CheckoutRow) -> some View {
        let (label, color): (String, Color) = {
            if checkout.returnedAt != nil {
                return ("Returned", .green)
            } else if let due = checkout.expectedReturn, isOverdue(due, returnedAt: nil) {
                return ("Overdue", .red)
            } else {
                return ("Active", .blue)
            }
        }()

        return Text(label)
            .font(.system(.caption2, weight: .semibold))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Capsule().fill(color.opacity(0.15)))
            .foregroundStyle(color)
    }

    // MARK: - Helpers

    private func formatDate(_ dateString: String) -> String {
        Formatters.formatSQLiteDate(dateString)
    }

    private func isOverdue(_ dueDateString: String, returnedAt: String?) -> Bool {
        guard returnedAt == nil else { return false }
        if let due = Formatters.localDateFormatter.date(from: String(dueDateString.prefix(10))) {
            return due < Date()
        }
        return false
    }

    // MARK: - Data Loading

    private func loadData() async {
        guard let service = appCore.toolsService else {
            isLoading = false
            loadError = "Tools service unavailable"
            return
        }
        isLoading = checkouts.isEmpty
        loadError = nil
        do {
            checkouts = try service.listCheckouts(active: showActiveOnly)
        } catch {
            loadError = userFriendlyError(error, context: "load checkouts")
        }
        isLoading = false
    }
}
