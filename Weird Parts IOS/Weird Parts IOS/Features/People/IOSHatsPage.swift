import SwiftUI
import WiredPartCore

/// Employee hats (roles) management page for iOS.
///
/// Displays a searchable list of hats with name, description, and the count
/// of employees currently assigned to each hat. Supports pull-to-refresh.
struct IOSHatsPage: View {
    @EnvironmentObject private var appCore: AppCore

    // MARK: - State

    @State private var hats: [PeopleService.HatListItem] = []
    @State private var isLoading = true
    @State private var searchText = ""

    var body: some View {
        hatList
            .navigationTitle("Hats & Roles")
            .searchable(text: $searchText, prompt: "Search hats...")
            .onChange(of: searchText) { /* local filter only */ }
            .refreshable { loadData() }
            .task { loadData() }
    }

    // MARK: - Hat List

    @ViewBuilder
    private var hatList: some View {
        if isLoading {
            ProgressView("Loading hats...")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if filteredHats.isEmpty {
            ContentUnavailableView {
                Label("No Hats", systemImage: "graduationcap")
            } description: {
                Text("No roles have been created yet.")
            }
        } else {
            List(filteredHats, id: \.id) { hat in
                hatRow(hat)
            }
            #if os(iOS)
            .listStyle(.insetGrouped)
            #endif
        }
    }

    private var filteredHats: [PeopleService.HatListItem] {
        guard !searchText.isEmpty else { return hats }
        let query = searchText.lowercased()
        return hats.filter {
            $0.name.lowercased().contains(query) ||
            ($0.description?.lowercased().contains(query) ?? false)
        }
    }

    private func hatRow(_ hat: PeopleService.HatListItem) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "graduationcap.fill")
                .font(.title3)
                .foregroundStyle(Color.purple)
                .frame(width: 32)

            VStack(alignment: .leading, spacing: 4) {
                Text(hat.name)
                    .fontWeight(.medium)
                if let desc = hat.description, !desc.isEmpty {
                    Text(desc)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 4) {
                assignedBadge(hat.userCount)
            }
        }
        .padding(.vertical, 4)
    }

    // MARK: - Badges

    private func assignedBadge(_ count: Int) -> some View {
        let color: Color = count > 0 ? .blue : .secondary
        return HStack(spacing: 4) {
            Image(systemName: "person.2.fill")
                .font(.caption2)
            Text("\(count)")
                .font(.system(.caption2, weight: .semibold))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(Capsule().fill(color.opacity(0.15)))
        .foregroundStyle(color)
    }

    // MARK: - Data Loading

    private func loadData() {
        guard let service = appCore.peopleService else { return }
        isLoading = hats.isEmpty
        do {
            hats = try service.listHats()
        } catch {
            print("[IOSHatsPage] Load error: \(error)")
        }
        isLoading = false
    }
}
