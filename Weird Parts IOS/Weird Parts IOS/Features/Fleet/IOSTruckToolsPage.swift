import SwiftUI
import WiredPartCore

/// Page showing tools assigned to fleet vehicles.
///
/// Lists tools that are checked out to vehicles (truck stock).
struct IOSTruckToolsPage: View {
    @EnvironmentObject private var appCore: AppCore

    @State private var checkouts: [ToolsService.CheckoutRow] = []
    @State private var isLoading = true
    @State private var searchText = ""
    @State private var loadError: String?

    var body: some View {
        VStack(spacing: 0) {
            if isLoading {
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
        .navigationTitle("Truck Tools")
        .searchable(text: $searchText, prompt: "Search tools...")
        .refreshable { loadData() }
        .task { loadData() }
    }

    private var toolsList: some View {
        List(filteredCheckouts, id: \.id) { checkout in
            HStack(spacing: 12) {
                Image(systemName: "wrench.fill")
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 28)

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
            isLoading = false
            return
        }
        isLoading = checkouts.isEmpty
        loadError = nil
        do {
            // Get active checkouts (tools currently out on trucks)
            checkouts = try service.listCheckouts(active: true)
        } catch {
            loadError = error.localizedDescription
        }
        isLoading = false
    }
}
