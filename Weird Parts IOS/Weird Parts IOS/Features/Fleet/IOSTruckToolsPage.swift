import SwiftUI
import WiredPartCore

/// Page showing tools assigned to fleet vehicles.
///
/// Lists tools that are checked out to vehicles (truck stock).
struct IOSTruckToolsPage: View {
    @EnvironmentObject private var appCore: AppCore

    @State private var checkouts: [ToolsService.CheckoutRow] = []
    @State private var isInitialLoading = true
    @State private var isRefreshing = false
    @State private var hasLoadedOnce = false
    @State private var searchText = ""
    @State private var loadError: String?
    @State private var activeSheet: ActiveSheet?

    private enum ActiveSheet: Identifiable {
        case help
        var id: String { "help" }
    }

    var body: some View {
        VStack(spacing: 0) {
            Group {
                if isInitialLoading {
                    ProgressView("Loading truck tools...")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let error = loadError {
                    ErrorStateView(message: error) { loadData() }
                } else if filteredCheckouts.isEmpty {
                    EmptyStateView(
                        icon: "wrench.and.screwdriver",
                        title: "No Tools on Trucks",
                        message: searchText.isEmpty ? "No tools are currently checked out to vehicles." : "No tools match your search."
                    )
                } else {
                    toolsList
                }
            }
            .overlay(alignment: .top) {
                refreshingOverlay
            }
        }
        .navigationTitle("Truck Tools")
        .searchable(text: $searchText, prompt: "Search tools...")
        .refreshable { loadData() }
        .task { loadData() }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { activeSheet = .help } label: {
                    Image(systemName: "questionmark.circle")
                }
                .accessibilityLabel("Help")
            }
        }
        .sheet(item: $activeSheet) { _ in
            PageHelpSheet(
                title: "Truck Tools Help",
                sections: [
                    ("Overview", "This page shows all tools currently checked out to fleet vehicles. It gives a quick view of which tools are on which trucks and who checked them out."),
                    ("Reading Entries", "Each row shows the tool name, who checked it out, the checkout date, and the expected return date if one was set. Overdue returns are highlighted in orange."),
                    ("Searching", "Use the search bar to find tools by name or by the person who checked them out. This is useful when you need to locate a specific tool across the fleet."),
                    ("Tips", "Tools are checked out and returned through the Tools section. If a tool is missing, check this page first to see which truck it was last assigned to. Keep expected return dates updated to avoid overdue notices.")
                ]
            )
        }
    }

    @ViewBuilder
    private var refreshingOverlay: some View {
        if isRefreshing {
            ProgressView()
                .progressViewStyle(.linear)
                .padding(.horizontal)
                .padding(.top, 8)
                .transition(.opacity)
                .accessibilityLabel("Refreshing truck tools")
        }
    }

    private var toolsList: some View {
        List(filteredCheckouts, id: \.id) { checkout in
            HStack(spacing: 12) {
                Image(systemName: "wrench.fill")
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 28)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 2) {
                    Text(checkout.toolName)
                        .fontWeight(.medium)
                    Text("Checked out by \(checkout.checkedOutByName)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(String(checkout.checkedOutAt.prefix(10)))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }

                Spacer()

                if let expected = checkout.expectedReturn, !expected.isEmpty {
                    Text("Due: \(String(expected.prefix(10)))")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                }
            }
            .padding(.vertical, 2)
        }
        .listStyle(.insetGrouped)
    }

    private var filteredCheckouts: [ToolsService.CheckoutRow] {
        guard !searchText.isEmpty else { return checkouts }
        let query = searchText.lowercased()
        return checkouts.filter {
            $0.toolName.lowercased().contains(query) ||
            $0.checkedOutByName.lowercased().contains(query)
        }
    }

    private func loadData() {
        guard let service = appCore.toolsService else {
            loadError = "Tools service not available"
            hasLoadedOnce = true
            isInitialLoading = false
            isRefreshing = false
            return
        }

        if hasLoadedOnce {
            isRefreshing = true
        } else {
            isInitialLoading = true
        }

        DispatchQueue.main.async {
            defer {
                self.hasLoadedOnce = true
                self.isInitialLoading = false
                self.isRefreshing = false
            }

            self.loadError = nil
            do {
                // Get active checkouts (tools currently out on trucks)
                self.checkouts = try service.listCheckouts(active: true)
            } catch {
                self.loadError = userFriendlyError(error, context: "load truck tools")
            }
        }
    }
}
