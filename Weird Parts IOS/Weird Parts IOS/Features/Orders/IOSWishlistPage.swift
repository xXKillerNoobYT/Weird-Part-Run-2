import SwiftUI
import WiredPartCore

/// Wishlist page for iOS.
///
/// Displays wishlist items in a 3-section layout: User Added, Forecast Demand,
/// and System Auto-Added. Each section has different approval rules.
/// User-added items auto-approve after 14 days if no action is taken.
struct IOSWishlistPage: View {
    @EnvironmentObject private var appCore: AppCore

    // MARK: - State

    @State private var sections = WishlistService.WishlistSections()
    @State private var statusCounts = WishlistService.StatusCounts()
    @State private var selectedStatus: StatusFilter = .all
    @State private var isLoading = true
    @State private var searchText = ""
    @State private var loadError: String?
    /// Degraded-state banner when the auto-approval write pass fails — eligible
    /// items would otherwise stay pending forever with no indication (#1335).
    @State private var autoApprovalError: String?
    @State private var activeSheet: ActiveSheet?
    @State private var itemToDelete: WishlistItem?

    private enum ActiveSheet: Identifiable {
        case addItem
        case help
        case dismiss(WishlistItem)
        var id: String {
            switch self {
            case .addItem: "addItem"
            case .help: "help"
            case .dismiss(let item): "dismiss-\(item.id ?? 0)"
            }
        }
    }

    /// Status filter for the smart-card strip.
    /// `.all` shows every item across all sections.
    /// Other cases narrow rows to a single `wishlist_items.status` value while
    /// preserving the 3-section grouping (User Added / Forecast / System).
    private enum StatusFilter: String, CaseIterable, Identifiable {
        case all
        case pending
        case approved
        case dismissed
        case sentToProcurement

        var id: String { rawValue }

        /// User-facing label. Kept short to fit a 96pt-wide card at 375pt viewport.
        var title: String {
            switch self {
            case .all: "All"
            case .pending: "Pending"
            case .approved: "Approved"
            case .dismissed: "Dismissed"
            case .sentToProcurement: "Procured"
            }
        }

        /// Accessibility label — spells out abbreviations for VoiceOver.
        var accessibilityTitle: String {
            switch self {
            case .all: "All items"
            case .pending: "Pending"
            case .approved: "Approved"
            case .dismissed: "Dismissed"
            case .sentToProcurement: "Sent to procurement"
            }
        }

        /// SF Symbol — mirrors the icon vocabulary used in `statusBadge`.
        var icon: String {
            switch self {
            case .all: "tray.full"
            case .pending: "clock"
            case .approved: "checkmark.circle"
            case .dismissed: "xmark.circle"
            case .sentToProcurement: "shippingbox"
            }
        }

        /// The DB `status` string this filter maps to, or `nil` for `.all`
        /// which means "no filter".
        var dbStatus: String? {
            switch self {
            case .all: nil
            case .pending: "pending"
            case .approved: "approved"
            case .dismissed: "dismissed"
            case .sentToProcurement: "sent_to_procurement"
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            OnboardingBanner(pageId: "orders-wishlist")
            smartCardFilters
            if let error = autoApprovalError {
                // Auto-approval pass failed (#1335) — items stay pending until retry.
                HStack(spacing: 8) {
                    Label(error, systemImage: "exclamationmark.triangle")
                        .font(.callout)
                        .foregroundStyle(.red)
                    Spacer()
                    Button("Retry") { loadData() }
                        .font(.callout)
                }
                .padding(.horizontal)
                .padding(.vertical, 6)
            }
            contentView
        }
        .task { appCore.onboardingManager?.markCompleted("wishlist-view") }
        .navigationTitle("Wishlist")
        .searchable(text: $searchText, prompt: "Search wishlist...")
        .onChange(of: searchText) { _, _ in postAIContext() }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { activeSheet = .addItem } label: { Image(systemName: "plus") }
                    .accessibilityLabel("Add wishlist item")
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
            case .addItem:
                AddWishlistItemSheet(onSave: { loadData() })
                    .environmentObject(appCore)
            case .help:
                PageHelpSheet(
                    title: "Wishlist Help",
                    sections: [
                        ("What This Page Does", "Tracks parts that should be procured. Items can be added manually or generated automatically by forecasting when stock levels need attention."),
                        ("Status Filters", "The cards at the top filter by status: All, Pending, Approved, Dismissed, and Procured. Each shows a live count. Tap a card to focus on one status — sections collapse automatically when empty."),
                        ("3 Sections", "User Added — items you or your team added manually (auto-approve after 14 days). Forecast Demand — system suggestions based on usage patterns. System Auto-Added — below MIN with no stock at shop."),
                        ("Item Flow", "Pending (needs review) → Approved (ready for procurement) → Sent to Procurement. Dismissed items can be reopened if needed."),
                        ("Dismissing Items", "Swipe left to dismiss. A reason is required so the team knows why an item was passed over."),
                        ("Tips", "Forecast items show a confidence score. High confidence (≥80%) items are strong recommendations. Lower scores should be verified manually.")
                    ]
                )
            case .dismiss(let item):
                DismissWishlistItemSheet(item: item) { reason in
                    dismissItem(item, reason: reason)
                }
            }
        }
        .confirmationDialog(
            "Delete Wishlist Item?",
            isPresented: Binding(get: { itemToDelete != nil }, set: { if !$0 { itemToDelete = nil } }),
            titleVisibility: .visible
        ) {
            if let item = itemToDelete {
                Button("Delete \"\(item.partName)\"", role: .destructive) {
                    Haptics.warning()
                    deleteItem(item)
                    itemToDelete = nil
                }
            }
            Button("Cancel", role: .cancel) { itemToDelete = nil }
        } message: {
            Text("This item will be permanently removed from the wishlist.")
        }
        .refreshable { loadData() }
        .task { loadData() }
        .onDisappear {
            NotificationCenter.default.post(name: .ordersWishlistPageInactive, object: nil)
        }
    }

    // MARK: - Smart Card Filters

    /// Horizontal scroll of status filter cards: All / Pending / Approved / Dismissed / Procured.
    /// Always rendered (no totalCount gate) so users can see status counts even when the
    /// currently-filtered view is empty — this is the cue that drives them to switch filters.
    private var smartCardFilters: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(StatusFilter.allCases) { filter in
                    smartCard(for: filter)
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
        }
        .background(Color(.systemBackground))
    }

    private func smartCard(for filter: StatusFilter) -> some View {
        let isSelected = selectedStatus == filter
        let color = filterColor(filter)
        let count = filterCount(filter)
        let isZero = count == 0 && filter != .all

        return Button {
            Haptics.impact(.light)
            selectedStatus = filter
        } label: {
            VStack(spacing: 4) {
                HStack(spacing: 4) {
                    Image(systemName: filter.icon)
                        .font(.caption)
                        .accessibilityHidden(true)
                    Text("\(count)")
                        .font(.title3)
                        .fontWeight(.bold)
                        .monospacedDigit()
                }
                Text(filter.title)
                    .font(.caption2)
                    .lineLimit(1)
            }
            .frame(minWidth: 80, minHeight: 44)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(isSelected ? color.opacity(0.18) : Color.secondary.opacity(0.08))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(isSelected ? color : Color.clear, lineWidth: 1.5)
            )
            .foregroundStyle(isSelected ? color : (isZero ? Color.secondary : .primary))
            .opacity(isZero ? 0.55 : 1.0)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(filter.accessibilityTitle), \(count) items")
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }

    private func filterColor(_ filter: StatusFilter) -> Color {
        switch filter {
        case .all: .accentColor
        case .pending: .orange
        case .approved: .green
        case .dismissed: .secondary
        case .sentToProcurement: .purple
        }
    }

    private func filterCount(_ filter: StatusFilter) -> Int {
        switch filter {
        case .all: statusCounts.total
        case .pending: statusCounts.pending
        case .approved: statusCounts.approved
        case .dismissed: statusCounts.dismissed
        case .sentToProcurement: statusCounts.sentToProcurement
        }
    }

    // MARK: - Content View

    @ViewBuilder
    private var contentView: some View {
        if isLoading {
            ProgressView("Loading wishlist...")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let error = loadError {
            ErrorStateView(message: error) { loadData() }
        } else if totalCount == 0 && searchText.isEmpty {
            EmptyStateView(
                icon: "heart.text.clipboard",
                title: "No Wishlist Items",
                message: "Add parts to your wishlist to track procurement needs."
            )
        } else if filteredIsEmpty {
            filteredEmptyState
        } else {
            sectionsView
        }
    }

    /// Empty state when DB has items but the current filter+search combo matches nothing.
    /// Offers a one-tap "Show All" escape so the user never gets stuck on an empty filter.
    @ViewBuilder
    private var filteredEmptyState: some View {
        let hasSearch = !searchText.isEmpty
        let isAll = selectedStatus == .all

        VStack(spacing: 12) {
            Image(systemName: selectedStatus == .all ? "heart.text.clipboard" : selectedStatus.icon)
                .font(.system(size: 44))
                .foregroundStyle(.secondary)
            Text(filteredEmptyTitle(hasSearch: hasSearch, isAll: isAll))
                .font(.headline)
                .multilineTextAlignment(.center)
            Text(filteredEmptyMessage(hasSearch: hasSearch, isAll: isAll))
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            if !isAll {
                Button {
                    selectedStatus = .all
                } label: {
                    Text("Show All")
                        .fontWeight(.semibold)
                        .frame(minWidth: 120, minHeight: 44)
                }
                .buttonStyle(.borderedProminent)
                .padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }

    private func filteredEmptyTitle(hasSearch: Bool, isAll: Bool) -> String {
        if hasSearch { return "No Matches" }
        switch selectedStatus {
        case .all: return "No Wishlist Items"
        case .pending: return "Nothing Pending"
        case .approved: return "Nothing Approved"
        case .dismissed: return "Nothing Dismissed"
        case .sentToProcurement: return "Nothing Sent to Procurement"
        }
    }

    private func filteredEmptyMessage(hasSearch: Bool, isAll: Bool) -> String {
        if hasSearch {
            return isAll
                ? "No items match your search."
                : "No \(selectedStatus.title.lowercased()) items match your search."
        }
        switch selectedStatus {
        case .all:
            return "Add parts to your wishlist to track procurement needs."
        case .pending:
            return "Everything has been reviewed. New items will appear here when added."
        case .approved:
            return "No approved items waiting. Approve a pending item to see it here."
        case .dismissed:
            return "Nothing has been dismissed yet."
        case .sentToProcurement:
            return "No items have been sent to procurement yet."
        }
    }

    private var totalCount: Int {
        sections.userAdded.count + sections.forecastDemand.count + sections.autoAdded.count
    }

    // MARK: - 3-Section List

    private var sectionsView: some View {
        List {
            // Section 1: User Added
            if !filteredUserAdded.isEmpty {
                Section {
                    ForEach(filteredUserAdded) { item in
                        wishlistRow(item)
                            .swipeActions(edge: .leading, allowsFullSwipe: true) {
                                leadingSwipeActions(item)
                            }
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                trailingSwipeActions(item)
                            }
                    }
                } header: {
                    sectionHeader("User Added", count: sections.userAdded.count,
                                  subtitle: "Auto-approves after 14 days if no action")
                }
            }

            // Section 2: Forecast Demand
            if !filteredForecast.isEmpty {
                Section {
                    ForEach(filteredForecast) { item in
                        wishlistRow(item)
                            .swipeActions(edge: .leading, allowsFullSwipe: true) {
                                leadingSwipeActions(item)
                            }
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                trailingSwipeActions(item)
                            }
                    }
                } header: {
                    sectionHeader("Forecast Demand", count: sections.forecastDemand.count,
                                  subtitle: "System suggestions based on usage patterns")
                }
            }

            // Section 3: System Auto-Added
            if !filteredAutoAdded.isEmpty {
                Section {
                    ForEach(filteredAutoAdded) { item in
                        wishlistRow(item)
                            .swipeActions(edge: .leading, allowsFullSwipe: true) {
                                leadingSwipeActions(item)
                            }
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                trailingSwipeActions(item)
                            }
                    }
                } header: {
                    sectionHeader("System Auto-Added", count: sections.autoAdded.count,
                                  subtitle: "Below MIN with no stock at shop")
                }
            }

        }
        .listStyle(.insetGrouped)
    }

    // MARK: - Section Header

    private func sectionHeader(_ title: String, count: Int, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(title)
                    .font(.headline)
                Spacer()
                Text("\(count)")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundStyle(.secondary)
            }
            Text(subtitle)
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .textCase(nil)
    }

    // MARK: - Filtering

    private func applyFilters(_ items: [WishlistItem]) -> [WishlistItem] {
        var result = items
        if let status = selectedStatus.dbStatus {
            result = result.filter { $0.status == status }
        }
        if !searchText.isEmpty {
            let query = searchText.lowercased()
            result = result.filter {
                $0.partName.lowercased().contains(query) ||
                ($0.reason?.lowercased().contains(query) ?? false) ||
                ($0.notes?.lowercased().contains(query) ?? false) ||
                ($0.requestedBy?.lowercased().contains(query) ?? false)
            }
        }
        return result
    }

    private var filteredUserAdded: [WishlistItem] { applyFilters(sections.userAdded) }
    private var filteredForecast: [WishlistItem] { applyFilters(sections.forecastDemand) }
    private var filteredAutoAdded: [WishlistItem] { applyFilters(sections.autoAdded) }

    /// True when the active filter+search combination has nothing to show.
    private var filteredIsEmpty: Bool {
        filteredUserAdded.isEmpty && filteredForecast.isEmpty && filteredAutoAdded.isEmpty
    }

    // MARK: - Swipe Actions

    @ViewBuilder
    private func leadingSwipeActions(_ item: WishlistItem) -> some View {
        if item.status == "pending" {
            Button {
                Haptics.impact(.medium)
                approveItem(item)
            } label: {
                Label("Approve", systemImage: "checkmark.circle")
            }
            .tint(.green)
        }
        if item.status == "approved" {
            Button {
                Haptics.impact(.medium)
                sendToProcurement(item)
            } label: {
                Label("Send to PO", systemImage: "shippingbox")
            }
            .tint(.purple)
        }
    }

    @ViewBuilder
    private func trailingSwipeActions(_ item: WishlistItem) -> some View {
        if item.status == "pending" || item.status == "approved" {
            Button(role: .destructive) {
                Haptics.impact(.medium)
                activeSheet = .dismiss(item)
            } label: {
                Label("Dismiss", systemImage: "xmark.circle")
            }
        }
        if item.status == "dismissed" {
            Button {
                Haptics.impact(.medium)
                reopenItem(item)
            } label: {
                Label("Reopen", systemImage: "arrow.uturn.left")
            }
            .tint(.blue)
        }
        Button(role: .destructive) {
            itemToDelete = item
        } label: {
            Label("Delete", systemImage: "trash")
        }
    }

    // MARK: - Row View

    private func wishlistRow(_ item: WishlistItem) -> some View {
        HStack(spacing: 12) {
            // Priority indicator bar
            RoundedRectangle(cornerRadius: 2)
                .fill(priorityColor(item.priority))
                .frame(width: 4, height: 44)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(item.partName)
                        .fontWeight(.medium)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    priorityBadge(item.priority)
                }

                HStack(spacing: 8) {
                    Label("\(item.qtySuggested)", systemImage: "number")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .accessibilityLabel("Suggested quantity: \(item.qtySuggested)")

                    sourceTypeBadge(item.sourceType)

                    if let reason = item.reason, !reason.isEmpty {
                        Text(reason)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }

                // Auto-approve countdown for pending user-added items
                if item.sourceType == "manual" && item.status == "pending",
                   let autoApproveStr = item.autoApproveAt {
                    let daysLeft = daysUntilAutoApprove(autoApproveStr)
                    if daysLeft > 0 {
                        Label("Auto-approves in \(daysLeft) day\(daysLeft == 1 ? "" : "s")", systemImage: "clock.arrow.circlepath")
                            .font(.caption2)
                            .foregroundStyle(.orange)
                    } else {
                        Label("Auto-approving soon", systemImage: "clock.arrow.circlepath")
                            .font(.caption2)
                            .foregroundStyle(.green)
                    }
                }

                // Certainty score for forecast items
                if item.sourceType == "forecast", let score = item.certaintyScore {
                    certaintyBadge(score)
                }

                if let requestedBy = item.requestedBy, !requestedBy.isEmpty {
                    Text("by \(requestedBy)")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 4) {
                statusBadge(item.status)

                if let date = item.createdAt {
                    Text(formatDate(date))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .padding(.vertical, 4)
    }

    // MARK: - Badges

    private func priorityColor(_ priority: String) -> Color {
        return TimelinePriorityColor.fallbackColor(priority: priority)
    }

    private func priorityBadge(_ priority: String) -> some View {
        let color = priorityColor(priority)
        return Text(priority.capitalized)
            .font(.system(.caption2, weight: .semibold))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Capsule().fill(color.opacity(0.15)))
            .foregroundStyle(color)
    }

    private func statusBadge(_ status: String) -> some View {
        let (label, color): (String, Color) = switch status {
        case "pending": ("Pending", .orange)
        case "approved": ("Approved", .green)
        case "dismissed": ("Dismissed", .secondary)
        case "sent_to_procurement": ("Procured", .purple)
        default: (status.capitalized, .secondary)
        }
        return Text(label)
            .font(.system(.caption2, weight: .semibold))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Capsule().fill(color.opacity(0.15)))
            .foregroundStyle(color)
    }

    private func sourceTypeBadge(_ sourceType: String) -> some View {
        let (icon, label): (String, String) = switch sourceType {
        case "manual": ("hand.raised", "Manual")
        case "forecast": ("chart.line.uptrend.xyaxis", "Forecast")
        case "system": ("gearshape", "System")
        case "reorder": ("arrow.triangle.2.circlepath", "Reorder")
        default: ("questionmark", sourceType.capitalized)
        }
        return Label(label, systemImage: icon)
            .font(.caption2)
            .foregroundStyle(.blue)
    }

    private func certaintyBadge(_ score: Double) -> some View {
        let isHigh = score >= 0.80
        let label = isHigh ? "High confidence" : "Review needed"
        let color: Color = isHigh ? .green : .orange
        return HStack(spacing: 4) {
            Image(systemName: isHigh ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                .font(.caption2)
                .accessibilityHidden(true)
            Text(label)
                .font(.caption2)
                .fontWeight(.medium)
        }
        .foregroundStyle(color)
    }

    // MARK: - Actions

    private func approveItem(_ item: WishlistItem) {
        guard let service = appCore.wishlistService else { loadError = "Service not available"; return }
        guard let id = item.id else { loadError = "Invalid item — missing ID"; return }
        guard let userId = appCore.currentUser?.id else { loadError = "Not authenticated"; return }
        do {
            let updated = try service.approveItem(id: id, byUserId: userId)
            Haptics.success()
            applyPartialUpdate(updated)
        } catch {
            loadError = userFriendlyError(error, context: "approve wishlist item")
        }
    }

    private func dismissItem(_ item: WishlistItem, reason: String) {
        guard let service = appCore.wishlistService else { loadError = "Service not available"; return }
        guard let id = item.id else { loadError = "Invalid item — missing ID"; return }
        guard let userId = appCore.currentUser?.id else { loadError = "Not authenticated"; return }
        do {
            let updated = try service.dismissItem(id: id, byUserId: userId, reason: reason)
            Haptics.success()
            applyPartialUpdate(updated)
        } catch {
            loadError = userFriendlyError(error, context: "dismiss wishlist item")
        }
    }

    private func sendToProcurement(_ item: WishlistItem) {
        guard let service = appCore.wishlistService else { loadError = "Service not available"; return }
        guard let id = item.id else { loadError = "Invalid item — missing ID"; return }
        guard let userId = appCore.currentUser?.id else { loadError = "Not authenticated"; return }
        do {
            let updated = try service.sendToProcurement(id: id, byUserId: userId)
            Haptics.success()
            applyPartialUpdate(updated)
        } catch {
            loadError = userFriendlyError(error, context: "send to procurement")
        }
    }

    private func reopenItem(_ item: WishlistItem) {
        guard let service = appCore.wishlistService else { loadError = "Service not available"; return }
        guard let id = item.id else { loadError = "Invalid item — missing ID"; return }
        guard let userId = appCore.currentUser?.id else { loadError = "Not authenticated"; return }
        do {
            let updated = try service.reopenItem(id: id, byUserId: userId)
            Haptics.success()
            applyPartialUpdate(updated)
        } catch {
            loadError = userFriendlyError(error, context: "reopen wishlist item")
        }
    }

    private func deleteItem(_ item: WishlistItem) {
        guard let service = appCore.wishlistService else { loadError = "Service not available"; return }
        guard let id = item.id else { loadError = "Invalid item — missing ID"; return }
        do {
            try service.deleteItem(id: id)
            removeFromSections(item)
        } catch {
            loadError = userFriendlyError(error, context: "delete wishlist item")
        }
    }

    // MARK: - Partial Update Helpers

    /// Apply a single-item diff: remove the old version from whichever section holds it,
    /// then insert the updated item at the front of the section that matches its sourceType.
    /// Only `loadData()` (initial load + pull-to-refresh) performs a full DB fetch.
    private func applyPartialUpdate(_ updatedItem: WishlistItem) {
        guard let id = updatedItem.id else { return }
        let newUserAdded = sections.userAdded.filter { $0.id != id }
        let newForecast = sections.forecastDemand.filter { $0.id != id }
        let newAutoAdded = sections.autoAdded.filter { $0.id != id }
        switch updatedItem.sourceType {
        case "manual":
            sections = WishlistService.WishlistSections(
                userAdded: [updatedItem] + newUserAdded,
                forecastDemand: newForecast,
                autoAdded: newAutoAdded
            )
        case "forecast":
            sections = WishlistService.WishlistSections(
                userAdded: newUserAdded,
                forecastDemand: [updatedItem] + newForecast,
                autoAdded: newAutoAdded
            )
        default:
            sections = WishlistService.WishlistSections(
                userAdded: newUserAdded,
                forecastDemand: newForecast,
                autoAdded: [updatedItem] + newAutoAdded
            )
        }
        recomputeStatusCounts()
    }

    /// Remove a deleted item from whichever section holds it, with no DB fetch.
    private func removeFromSections(_ item: WishlistItem) {
        guard let id = item.id else { return }
        sections = WishlistService.WishlistSections(
            userAdded: sections.userAdded.filter { $0.id != id },
            forecastDemand: sections.forecastDemand.filter { $0.id != id },
            autoAdded: sections.autoAdded.filter { $0.id != id }
        )
        recomputeStatusCounts()
    }

    /// Recompute status counts from current in-memory sections so smart cards
    /// stay accurate after partial updates without hitting the DB.
    private func recomputeStatusCounts() {
        var pending = 0, approved = 0, dismissed = 0, sent = 0
        let all = sections.userAdded + sections.forecastDemand + sections.autoAdded
        for item in all {
            switch item.status {
            case "pending": pending += 1
            case "approved": approved += 1
            case "dismissed": dismissed += 1
            case "sent_to_procurement": sent += 1
            default: break
            }
        }
        statusCounts = WishlistService.StatusCounts(
            pending: pending,
            approved: approved,
            dismissed: dismissed,
            sentToProcurement: sent
        )
    }

    // MARK: - Data Loading

    private func loadData() {
        guard let service = appCore.wishlistService else {
            loadError = "Wishlist service not available"
            isLoading = false
            return
        }
        isLoading = totalCount == 0
        loadError = nil
        let currentUserId = appCore.currentUser?.id
        // Run auto-approvals in a background task before reading sections (DIS-006).
        // processAutoApprovals was removed from getSectionedItems() to avoid main-thread
        // DB writes inside a read; we fire it here as a detached utility task instead.
        Task.detached(priority: .utility) {
            // Auto-approval is a WRITE: if it throws, items that policy says should
            // auto-approve silently stay pending. Surface it as a banner (#1335)
            // while still loading the sections below so the page stays usable.
            // Capture the raw error here and map it to user-facing copy inside
            // MainActor.run — userFriendlyError is main-actor-isolated and must
            // not be called from the detached task itself.
            var autoApprovalFailure: (any Error)?
            do {
                _ = try service.processAutoApprovals(byUserId: currentUserId)
            } catch {
                autoApprovalFailure = error
            }
            do {
                let result = try service.getSectionedItems()
                // Counts are computed independently so card totals reflect ALL items,
                // not just the currently-filtered subset. A counts failure now routes
                // to loadError instead of rendering all-zero status cards (#1335).
                let counts = try service.getStatusCounts()
                await MainActor.run {
                    sections = result
                    statusCounts = counts
                    autoApprovalError = autoApprovalFailure.map { userFriendlyError($0, context: "run wishlist auto-approvals") }
                    isLoading = false
                    postAIContext()
                }
            } catch {
                await MainActor.run {
                    autoApprovalError = autoApprovalFailure.map { userFriendlyError($0, context: "run wishlist auto-approvals") }
                    loadError = userFriendlyError(error, context: "load wishlist")
                    isLoading = false
                }
            }
        }
    }

    private func postAIContext() {
        let context = [
            "Orders wishlist page is open.",
            "User-added items: \(sections.userAdded.count), forecast demand: \(sections.forecastDemand.count), system auto-added: \(sections.autoAdded.count).",
            "Status counts — pending: \(statusCounts.pending), approved: \(statusCounts.approved), dismissed: \(statusCounts.dismissed), sent to procurement: \(statusCounts.sentToProcurement).",
            "Active status filter: \(selectedStatus.title).",
            "Filtered visible items: \(filteredUserAdded.count + filteredForecast.count + filteredAutoAdded.count).",
            "Search text is \(searchText.isEmpty ? "empty" : "active").",
            "This context is read-only; explain wishlist sections, approval state, confidence scores, dismissal requirements, and procurement handoff without changing items."
        ].joined(separator: " ")
        NotificationCenter.default.post(
            name: .ordersWishlistPageActive,
            object: nil,
            userInfo: ["context": context]
        )
    }

    // MARK: - Helpers

    private func daysUntilAutoApprove(_ dateString: String) -> Int {
        guard let date = Formatters.iso8601Basic.date(from: dateString) else { return 0 }
        let interval = date.timeIntervalSinceNow
        return max(0, Int(ceil(interval / 86400)))
    }

    private func formatDate(_ dateString: String) -> String {
        let date = Formatters.iso8601Basic.date(from: dateString)
            ?? Formatters.sqlDateTimeFormatter.date(from: dateString)
        guard let date else { return dateString }
        return Formatters.shortDateDisplayFormatter.string(from: date)
    }
}

// MARK: - Dismiss Wishlist Item Sheet

/// Sheet requiring a reason when dismissing a wishlist item.
private struct DismissWishlistItemSheet: View {
    @Environment(\.dismiss) private var dismiss

    let item: WishlistItem
    let onDismiss: (String) -> Void

    @State private var reason = ""
    @State private var showError = false

    private var trimmedReason: String {
        reason.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack {
                        Text("Item")
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text(item.partName)
                            .fontWeight(.medium)
                    }
                    HStack {
                        Text("Qty")
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text("\(item.qtySuggested)")
                    }
                }

                Section("Dismiss Reason") {
                    TextEditor(text: $reason)
                        .frame(minHeight: 80)
                        .overlay(alignment: .topLeading) {
                            if reason.isEmpty {
                                Text("Why is this item being dismissed?")
                                    .foregroundStyle(.tertiary)
                                    .padding(.top, 8)
                                    .padding(.leading, 4)
                                    .allowsHitTesting(false)
                            }
                        }

                    HStack {
                        if showError && trimmedReason.count < 10 {
                            Text("Reason must be at least 10 characters")
                                .font(.caption)
                                .foregroundStyle(.red)
                        }
                        Spacer()
                        Text("\(trimmedReason.count) characters")
                            .font(.caption)
                            .foregroundStyle(trimmedReason.count >= 10 ? Color.secondary : Color.orange)
                    }
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle("Dismiss Item")
            .navigationBarTitleDisplayMode(.inline)
            .interactiveDismissDisabled(!trimmedReason.isEmpty)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Dismiss") {
                        if trimmedReason.count >= 10 {
                            onDismiss(trimmedReason)
                            dismiss()
                        } else {
                            showError = true
                        }
                    }
                    .fontWeight(.semibold)
                    .foregroundStyle(.red)
                }
            }
        }
    }
}

// MARK: - Add Wishlist Item Sheet

/// Sheet for adding a new wishlist item with part name, quantity, priority, and reason.
private struct AddWishlistItemSheet: View {
    @EnvironmentObject private var appCore: AppCore
    @Environment(\.dismiss) private var dismiss

    let onSave: () -> Void

    @State private var partName = ""
    @State private var qtySuggested = 1
    @State private var priority = "normal"
    @State private var reason = ""
    @State private var notes = ""
    @State private var saveError: String?
    @State private var isSaving = false
    @State private var isDirty = false
    @State private var showCancelConfirmation = false

    private let priorities = ["urgent", "high", "normal", "low"]

    var body: some View {
        NavigationStack {
            Form {
                Section("Part Information") {
                    TextField("Part Name", text: $partName)
                        .textContentType(.none)
                        .onChange(of: partName) { isDirty = true }

                    Stepper("Quantity: \(qtySuggested)", value: $qtySuggested, in: 1...9999)
                        .onChange(of: qtySuggested) { isDirty = true }
                }

                Section("Priority") {
                    Picker("Priority", selection: $priority) {
                        ForEach(priorities, id: \.self) { p in
                            Label(p.capitalized, systemImage: priorityIcon(p))
                                .tag(p)
                        }
                    }
                    .pickerStyle(.segmented)
                    .onChange(of: priority) { isDirty = true }
                }

                Section("Details") {
                    TextField("Reason (optional)", text: $reason, axis: .vertical)
                        .lineLimit(2...4)
                        .onChange(of: reason) { isDirty = true }

                    TextField("Notes (optional)", text: $notes, axis: .vertical)
                        .lineLimit(2...4)
                        .onChange(of: notes) { isDirty = true }
                }

                if let error = saveError {
                    Section {
                        Text(error)
                            .foregroundStyle(.red)
                            .font(.caption)
                    }
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle("Add Wishlist Item")
            .navigationBarTitleDisplayMode(.inline)
            .interactiveDismissDisabled(isDirty || isSaving)
            .confirmationDialog(
                "Discard changes?",
                isPresented: $showCancelConfirmation,
                titleVisibility: .visible
            ) {
                Button("Discard", role: .destructive) { dismiss() }
                Button("Keep editing", role: .cancel) {}
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        if isDirty { showCancelConfirmation = true } else { dismiss() }
                    }
                    .disabled(isSaving)
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isSaving {
                        ProgressView()
                    } else {
                        Button("Add") { saveItem() }
                            .disabled(partName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                            .fontWeight(.semibold)
                    }
                }
            }
        }
    }

    private func priorityIcon(_ priority: String) -> String {
        switch priority {
        case "urgent": "exclamationmark.triangle"
        case "high": "arrow.up"
        case "normal": "minus"
        case "low": "arrow.down"
        default: "minus"
        }
    }

    private func saveItem() {
        guard let service = appCore.wishlistService else {
            saveError = "Wishlist service not available"
            return
        }

        let trimmedName = partName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            saveError = "Part name is required"
            return
        }

        isSaving = true
        saveError = nil

        do {
            try service.addItem(
                partName: trimmedName,
                qtySuggested: qtySuggested,
                reason: reason.isEmpty ? nil : reason,
                priority: priority,
                sourceType: "manual",
                requestedBy: appCore.currentUser?.displayName,
                notes: notes.isEmpty ? nil : notes
            )
            isDirty = false
            dismiss()
            onSave()
        } catch {
            saveError = userFriendlyError(error, context: "save wishlist")
            isSaving = false
        }
    }
}
