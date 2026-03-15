import SwiftUI
import WiredPartCore

/// Hats list page.
///
/// Displays a sortable table of all hats (role tags) with name, description,
/// and user count columns. Supports searching by hat name or description.
struct HatsPage: View {
    @EnvironmentObject private var appCore: AppCore

    // MARK: - Data State

    @State private var hats: [PeopleService.HatListItem] = []
    @State private var isLoading = true
    @State private var searchText = ""

    // MARK: - Sorting

    @State private var sortOrder = [KeyPathComparator(\PeopleService.HatListItem.name)]

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
                Text("Hats")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                Text("\(hats.count) hat\(hats.count == 1 ? "" : "s")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            TextField("Search hats...", text: $searchText)
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
            ProgressView("Loading hats...")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if hats.isEmpty {
            VStack(spacing: 12) {
                Image(systemName: "crown")
                    .font(.system(size: 40))
                    .foregroundStyle(.tertiary)
                Text("No hats found")
                    .font(.headline)
                Text("Create a hat to assign role tags to employees.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 300)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            Table(sortedHats, sortOrder: $sortOrder) {
                TableColumn("Name", value: \.name) { hat in
                    Text(hat.name)
                        .fontWeight(.medium)
                }
                .width(min: 120, ideal: 200)

                TableColumn("Description") { (hat: PeopleService.HatListItem) in
                    Text(hat.description ?? "-")
                        .lineLimit(2)
                        .foregroundStyle(hat.description != nil ? .primary : .secondary)
                }
                .width(min: 200, ideal: 360)

                TableColumn("Users", value: \.userCount) { hat in
                    Text("\(hat.userCount)")
                        .font(.system(.body, design: .monospaced))
                }
                .width(min: 60, ideal: 80)
            }
            .tableStyle(.inset(alternatesRowBackgrounds: true))
        }
    }

    private var sortedHats: [PeopleService.HatListItem] {
        hats.sorted(using: sortOrder)
    }

    // MARK: - Data Loading

    private func load() {
        guard let db = appCore.db else { return }
        let service = PeopleService(db: db)
        isLoading = true
        do {
            let allHats = try service.listHats()
            // Client-side search filter
            if searchText.isEmpty {
                hats = allHats
            } else {
                let query = searchText.lowercased()
                hats = allHats.filter {
                    $0.name.lowercased().contains(query) ||
                    ($0.description?.lowercased().contains(query) ?? false)
                }
            }
        } catch {
            print("[HatsPage] Load error: \(error)")
        }
        isLoading = false
    }
}
