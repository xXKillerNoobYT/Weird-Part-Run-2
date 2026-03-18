import SwiftUI

/// Generic searchable list wrapper with pull-to-refresh.
///
/// Provides a consistent pattern for filterable data lists throughout the app.
///
/// Usage:
///   SearchableList(
///       items: parts,
///       searchText: $searchText,
///       placeholder: "Search parts...",
///       onRefresh: { await loadParts() }
///   ) { part in
///       PartRow(part: part)
///   }
struct SearchableList<Item: Identifiable, Row: View>: View {
    let items: [Item]
    @Binding var searchText: String
    var placeholder: String = "Search..."
    var onRefresh: (() async -> Void)?
    @ViewBuilder let row: (Item) -> Row

    var body: some View {
        List {
            ForEach(items) { item in
                row(item)
            }
        }
        .listStyle(.plain)
        .searchable(text: $searchText, prompt: placeholder)
        .refreshable {
            await onRefresh?()
        }
        .overlay {
            if items.isEmpty && !searchText.isEmpty {
                ContentUnavailableView.search(text: searchText)
            }
        }
    }
}
