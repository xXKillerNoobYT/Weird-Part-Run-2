import SwiftUI
import WiredPartCore

/// Tool checkouts list page.
///
/// Displays a searchable, sortable table of all tool checkouts with tool name,
/// user, checked out at, due date, and status columns. Status distinguishes
/// between active (checked out) and returned checkouts.
struct ToolCheckoutsPage: View {
    @EnvironmentObject private var appCore: AppCore

    // MARK: - Data State

    @State private var checkouts: [ToolsService.CheckoutRow] = []
    @State private var isLoading = true
    @State private var searchText = ""

    // MARK: - Sorting

    @State private var sortOrder = [KeyPathComparator(\ToolsService.CheckoutRow.id)]

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
                Text("Tool Checkouts")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                Text("\(checkouts.count) checkout\(checkouts.count == 1 ? "" : "s")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            TextField("Search checkouts...", text: $searchText)
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
            ProgressView("Loading checkouts...")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if checkouts.isEmpty {
            VStack(spacing: 12) {
                Image(systemName: "arrow.up.right.square")
                    .font(.system(size: 40))
                    .foregroundStyle(.tertiary)
                Text("No checkouts found")
                    .font(.headline)
                Text("Tool checkouts will appear here when tools are checked out.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            Table(sortedCheckouts, sortOrder: $sortOrder) {
                TableColumn("Tool", value: \.toolName) { checkout in
                    Text(checkout.toolName)
                        .fontWeight(.medium)
                }
                .width(min: 140, ideal: 200)

                TableColumn("User", value: \.checkedOutByName) { checkout in
                    Text(checkout.checkedOutByName)
                        .font(.callout)
                }
                .width(min: 120, ideal: 160)

                TableColumn("Checked Out At", value: \.checkedOutAt) { checkout in
                    Text(checkout.checkedOutAt)
                        .font(.caption)
                }
                .width(min: 120, ideal: 160)

                TableColumn("Due Date") { (checkout: ToolsService.CheckoutRow) in
                    Text(checkout.expectedReturn ?? "-")
                        .font(.caption)
                        .foregroundStyle(checkout.expectedReturn != nil ? .primary : .secondary)
                }
                .width(min: 100, ideal: 140)

                TableColumn("Status") { (checkout: ToolsService.CheckoutRow) in
                    checkoutStatusBadge(checkout)
                }
                .width(min: 80, ideal: 110)
            }
            .tableStyle(.inset(alternatesRowBackgrounds: true))
        }
    }

    private var sortedCheckouts: [ToolsService.CheckoutRow] {
        checkouts.sorted(using: sortOrder)
    }

    // MARK: - Badges

    private func checkoutStatusBadge(_ checkout: ToolsService.CheckoutRow) -> some View {
        let isReturned = checkout.returnedAt != nil
        let label = isReturned ? "Returned" : "Checked Out"
        let color: Color = isReturned ? .green : .blue
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
            let allCheckouts = try service.listCheckouts()
            // Client-side search filter
            if searchText.isEmpty {
                checkouts = allCheckouts
            } else {
                let query = searchText.lowercased()
                checkouts = allCheckouts.filter {
                    $0.toolName.lowercased().contains(query) ||
                    $0.checkedOutByName.lowercased().contains(query)
                }
            }
        } catch {
            print("[ToolCheckoutsPage] Load error: \(error)")
        }
        isLoading = false
    }
}
