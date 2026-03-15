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

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                filterToggle
                checkoutList
            }
            .navigationTitle("Tool Checkouts")
            .searchable(text: $searchText, prompt: "Search checkouts...")
            .refreshable { loadData() }
            .task { loadData() }
        }
    }

    // MARK: - Filter Toggle

    private var filterToggle: some View {
        HStack(spacing: 8) {
            Button {
                showActiveOnly = true
                loadData()
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

            Button {
                showActiveOnly = false
                loadData()
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
        } else if filteredCheckouts.isEmpty {
            ContentUnavailableView {
                Label("No Checkouts", systemImage: "arrow.up.right.circle")
            } description: {
                Text(showActiveOnly
                    ? "No tools are currently checked out."
                    : "No checkout records found.")
            }
        } else {
            List(filteredCheckouts, id: \.id) { checkout in
                checkoutRow(checkout)
            }
            #if os(iOS)
            .listStyle(.insetGrouped)
            #endif
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
        // Try ISO datetime format first, fall back to showing raw string
        let isoFormatter = DateFormatter()
        isoFormatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        let displayFormatter = DateFormatter()
        displayFormatter.dateStyle = .short

        if let date = isoFormatter.date(from: dateString) {
            return displayFormatter.string(from: date)
        }

        // Try SQLite datetime format
        isoFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        if let date = isoFormatter.date(from: dateString) {
            return displayFormatter.string(from: date)
        }

        // Fall back to first 10 chars (date portion)
        if dateString.count >= 10 {
            return String(dateString.prefix(10))
        }
        return dateString
    }

    private func isOverdue(_ dueDateString: String, returnedAt: String?) -> Bool {
        guard returnedAt == nil else { return false }
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        if let due = f.date(from: String(dueDateString.prefix(10))) {
            return due < Date()
        }
        return false
    }

    // MARK: - Data Loading

    private func loadData() {
        guard let service = appCore.toolsService else { return }
        isLoading = checkouts.isEmpty
        do {
            checkouts = try service.listCheckouts(active: showActiveOnly)
        } catch {
            print("[IOSToolCheckoutsPage] Load error: \(error)")
        }
        isLoading = false
    }
}
