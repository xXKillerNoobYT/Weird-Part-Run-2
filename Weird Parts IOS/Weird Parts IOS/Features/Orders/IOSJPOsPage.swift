import SwiftUI
import WiredPartCore

/// Job Purchase Orders list page for iOS.
///
/// Displays a searchable list of JPOs with job name, requester,
/// status badge, priority badge, and line count. Supports pull-to-refresh,
/// status-based filtering with count badges, QR scanning, and Create JPO
/// with auto-fill from the user's current clock-in.
struct IOSJPOsPage: View {
    @EnvironmentObject private var appCore: AppCore

    // MARK: - State

    @State private var allJPOs: [OrdersService.JPOListItem] = []
    @State private var isLoading = true
    @State private var searchText = ""
    @State private var dateRange: ReportDateRange = .thisWeek
    @State private var customStart = Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date()
    @State private var customEnd = Date()
    @State private var statusFilter = "all"
    @State private var loadError: String?
    @State private var activeSheet: ActiveSheet?

    private let statusOptions = ["all", "draft", "pending", "submitted", "approved", "rejected"]

    private enum ActiveSheet: Identifiable {
        case qrScanner
        case scannedJPODetail(Int64)
        case help

        var id: String {
            switch self {
            case .qrScanner: "qrScanner"
            case .scannedJPODetail(let id): "scannedJPO-\(id)"
            case .help: "help"
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            OnboardingBanner(pageId: "orders-jpos")
            StandardFilterBar(selectedRange: $dateRange, customStart: $customStart, customEnd: $customEnd)
            statusPicker

            // Pending KPI line
            if pendingCount > 0 {
                HStack {
                    Label("\(pendingCount) pending approval", systemImage: "clock.badge.exclamationmark")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .padding(.horizontal)
                .padding(.vertical, 4)
            }

            jpoList
        }
        .navigationTitle("Job Purchase Orders")
        .searchable(text: $searchText, prompt: "Search JPOs...")
        .onChange(of: searchText) { loadData() }
        .refreshable { loadData() }
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button { activeSheet = .qrScanner } label: {
                    Image(systemName: "qrcode.viewfinder")
                }
                .accessibilityLabel("Scan QR code")
                NavigationLink {
                    IOSJPOCreationPage()
                        .environmentObject(appCore)
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("Create job purchase order")
            }
            ToolbarItem(placement: .primaryAction) {
                Button { activeSheet = .help } label: {
                    Image(systemName: "questionmark.circle")
                }
                .accessibilityLabel("Help")
            }
        }
        .sheet(item: $activeSheet) { sheet in
            sheetContent(for: sheet)
        }
        .task {
            loadData()
            appCore.onboardingManager?.markCompleted("jpo-view-list")
        }
        .onAppear {
            NotificationCenter.default.post(
                name: .jposPageActive,
                object: nil,
                userInfo: [
                    "context": "JPOs Page: \(allJPOs.count) total JPOs, filter: \(statusFilter), \(pendingCount) pending approval."
                ]
            )
            // Register AI filter (prompt 62S)
            appCore.aiFilterRegistry.register(
                pageId: "jpos",
                filterName: "JPO Status",
                options: statusOptions,
                activate: { value in
                    statusFilter = value
                }
            )
            appCore.aiFilterRegistry.applyPendingFilter(pageId: "jpos")
        }
        .onDisappear {
            NotificationCenter.default.post(name: .jposPageInactive, object: nil)
            appCore.aiFilterRegistry.deregister(pageId: "jpos")
        }
    }

    // MARK: - Sheet Content

    @ViewBuilder
    private func sheetContent(for sheet: ActiveSheet) -> some View {
        switch sheet {
        case .qrScanner:
            QRScanSheet(expectedType: .po) { result in
                if result.entityId != nil, result.isFound {
                    // PO scanned — show JPO detail for the linked JPO
                    // For now, dismiss and reload; a future prompt can wire PO→JPO navigation
                    activeSheet = nil
                }
            }
            .environmentObject(appCore)
        case .scannedJPODetail(let jpoId):
            NavigationStack {
                IOSJPODetailPage(jpoId: jpoId)
                    .environmentObject(appCore)
            }
        case .help:
            PageHelpSheet(
                title: "Job Purchase Orders Help",
                sections: [
                    ("What This Page Does", "Lists all Job Purchase Orders (JPOs) -- requests from field workers for parts they need on the job. Each JPO is tied to a specific job and goes through an approval workflow."),
                    ("How to Use It", "Filter by status using the chips at the top (Draft, Pending, Submitted, Approved, Rejected). Search by job name or requester. Tap a JPO to see its line items and take action. Tap + to create a new JPO or scan a QR code to find one."),
                    ("Status Flow", "Draft -> Submitted -> Pending (awaiting approval) -> Approved (goes to procurement) or Rejected (sent back with a reason). The pending count badge shows how many need manager attention."),
                    ("Tips", "Pull down to refresh. If a JPO shows a question badge, it means a line item is on hold with a pending question from the approver. Tap into the JPO to view and respond to the chat thread.")
                ]
            )
        }
    }

    // MARK: - Counts

    private var pendingCount: Int {
        allJPOs.filter { $0.status == "pending" }.count
    }

    private func countForStatus(_ status: String) -> Int {
        if status == "all" { return allJPOs.count }
        return allJPOs.filter { $0.status == status }.count
    }

    // MARK: - Status Picker

    private var statusPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(statusOptions, id: \.self) { status in
                    SmartFilterCard(
                        title: status == "all" ? "All" : status.capitalized,
                        count: countForStatus(status),
                        isSelected: statusFilter == status
                    ) {
                        statusFilter = status
                    }
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
        }
    }

    // MARK: - JPO List

    @ViewBuilder
    private var jpoList: some View {
        if isLoading {
            ProgressView("Loading JPOs...")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let error = loadError {
            ErrorStateView(message: error) { loadData() }
        } else if displayedJPOs.isEmpty {
            EmptyStateView(
                icon: "doc.text",
                title: "No JPOs",
                message: searchText.isEmpty ? "No job purchase orders yet." : "No JPOs match your criteria."
            )
        } else {
            List(displayedJPOs, id: \.id) { jpo in
                NavigationLink {
                    IOSJPODetailPage(jpoId: jpo.id)
                        .environmentObject(appCore)
                } label: {
                    jpoRow(jpo)
                }
            }
            .listStyle(.insetGrouped)
        }
    }

    /// JPOs filtered by status and search text.
    private var displayedJPOs: [OrdersService.JPOListItem] {
        var result = allJPOs
        // Status filter
        if statusFilter != "all" {
            result = result.filter { $0.status == statusFilter }
        }
        result = result.filter { dateStringFallsInSelectedRange($0.createdAt ?? $0.dueDate) }
        // Search filter
        if !searchText.isEmpty {
            let query = searchText.lowercased()
            result = result.filter {
                $0.jobName.lowercased().contains(query) ||
                $0.requestedByName.lowercased().contains(query)
            }
        }
        return result
    }

    private var effectiveStart: Date {
        dateRange.dateInterval?.start ?? customStart
    }

    private var effectiveEnd: Date {
        dateRange.dateInterval?.end ?? customEnd
    }

    private func dateStringFallsInSelectedRange(_ rawDate: String?) -> Bool {
        guard let date = parseFilterDate(rawDate) else { return false }
        return date >= Calendar.current.startOfDay(for: effectiveStart) && date <= endOfDay(for: effectiveEnd)
    }

    private func endOfDay(for date: Date) -> Date {
        Calendar.current.dateInterval(of: .day, for: date)?.end.addingTimeInterval(-1) ?? date
    }

    private func parseFilterDate(_ rawDate: String?) -> Date? {
        guard let rawDate, !rawDate.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return Formatters.sqlDateTimeFormatter.date(from: rawDate)
            ?? Formatters.iso8601Fractional.date(from: rawDate)
            ?? Formatters.iso8601Basic.date(from: rawDate)
            ?? Formatters.localDateFormatter.date(from: String(rawDate.prefix(10)))
    }

    private func jpoRow(_ jpo: OrdersService.JPOListItem) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text("JPO #\(jpo.id)")
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                    priorityBadge(jpo.priority, dueDate: jpo.dueDate)
                }
                Text(jpo.jobName)
                    .fontWeight(.medium)
                Text("Requested by \(jpo.requestedByName)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 4) {
                statusBadge(jpo.status)
                Label("\(jpo.lineCount) lines", systemImage: "list.bullet")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if jpo.holdCount > 0 {
                    HStack(spacing: 4) {
                        Image(systemName: "message.badge")
                            .foregroundStyle(.yellow)
                            .accessibilityHidden(true)
                        Text("\(jpo.holdCount) question\(jpo.holdCount == 1 ? "" : "s")")
                            .font(.caption2)
                            .foregroundStyle(.yellow)
                    }
                }
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("JPO number \(jpo.id), \(jpo.jobName), status \(jpo.status), \(jpo.lineCount) line items, \(jpo.holdCount) on hold")
    }

    // MARK: - Badges

    private func statusBadge(_ status: String) -> some View {
        let color: Color = switch status {
        case "draft": .secondary
        case "pending", "submitted": .orange
        case "approved": .green
        case "rejected": .red
        default: .secondary
        }
        return Text(status.capitalized)
            .font(.system(.caption2, weight: .semibold))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Capsule().fill(color.opacity(0.15)))
            .foregroundStyle(color)
    }

    private func priorityBadge(_ priority: String, dueDate: String?) -> some View {
        let color: Color = dueDate != nil
            ? TimelinePriorityColor.color(priority: priority, dueDateString: dueDate)
            : TimelinePriorityColor.fallbackColor(priority: priority)
        return Text(priority.capitalized)
            .font(.caption2)
            .foregroundStyle(color)
    }

    // MARK: - Data Loading

    private func loadData() {
        guard let service = appCore.ordersService else {
            loadError = "Orders service not available"
            isLoading = false
            return
        }
        isLoading = allJPOs.isEmpty
        loadError = nil
        do {
            // Load all JPOs for counts, then filter in-memory
            allJPOs = try service.listJPOs(status: nil, limit: 500)
        } catch {
            loadError = userFriendlyError(error, context: "load job parts orders")
        }
        isLoading = false
    }
}
