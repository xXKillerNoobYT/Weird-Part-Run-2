import SwiftUI
import WiredPartCore

/// Parts Categories page — filing system with 5-level drill-down hierarchy:
/// Category > Style > Type > Brand > Color.
///
/// **Layout:**
/// - iPad/Mac (large screen): split view — tree browser LEFT, editor panel RIGHT
/// - iPhone (compact): single column with NavigationStack push/pop
struct PartsCategoriesPage: View {
    @EnvironmentObject private var appCore: AppCore
    @State private var hierarchy = PartsService.HierarchyTree(categories: [])
    @State private var selection: TreeSelection?
    @State private var isLoading = true
    @State private var loadError: String?

    var body: some View {
        Group {
            if isLoading {
                ProgressView("Loading hierarchy...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error = loadError {
                ErrorStateView(message: error) {
                    Task { await loadHierarchy() }
                }
            } else if DeviceContext.isLargeScreen {
                splitLayout
            } else {
                compactLayout
            }
        }
        .background(DS.Background.page)
        .task { await loadHierarchy() }
        .refreshable { await loadHierarchy() }
    }

    // MARK: - Split Layout (iPad / Mac)

    @ViewBuilder
    private var splitLayout: some View {
        HStack(spacing: 0) {
            // LEFT: Tree browser
            CategoriesTreeView(
                hierarchy: hierarchy,
                selection: $selection,
                onRefresh: { await loadHierarchy() }
            )
            .frame(minWidth: 280, idealWidth: 320)

            Divider()

            // RIGHT: Editor panel
            CategoriesEditorPanel(
                selection: selection,
                hierarchy: hierarchy,
                onRefresh: { await loadHierarchy() }
            )
            .frame(minWidth: 300, idealWidth: 400, maxWidth: .infinity)
        }
    }

    // MARK: - Compact Layout (iPhone)

    @ViewBuilder
    private var compactLayout: some View {
        NavigationStack {
            CategoriesTreeView(
                hierarchy: hierarchy,
                selection: $selection,
                onRefresh: { await loadHierarchy() }
            )
            .navigationDestination(item: $selection) { sel in
                CategoriesEditorPanel(
                    selection: sel,
                    hierarchy: hierarchy,
                    onRefresh: { await loadHierarchy() }
                )
                .navigationTitle("Details")
                .navigationBarTitleDisplayMode(.inline)
            }
        }
    }

    // MARK: - Data Loading

    @Sendable
    private func loadHierarchy() async {
        guard let service = appCore.partsService else {
            isLoading = false
            loadError = "Parts service not available."
            return
        }
        do {
            let tree = try service.getHierarchy()
            await MainActor.run {
                hierarchy = tree
                isLoading = false
                loadError = nil
            }
        } catch {
            await MainActor.run {
                loadError = error.localizedDescription
                isLoading = false
            }
        }
    }
}

// MARK: - NavigationDestination support for TreeSelection

extension TreeSelection: Hashable {
    func hash(into hasher: inout Hasher) {
        switch self {
        case .category(let id):
            hasher.combine(0)
            hasher.combine(id)
        case .style(let id):
            hasher.combine(1)
            hasher.combine(id)
        case .type(let id):
            hasher.combine(2)
            hasher.combine(id)
        case .brand(let brandId, let typeId):
            hasher.combine(3)
            hasher.combine(brandId)
            hasher.combine(typeId)
        case .color(let colorId, let typeId, let brandId):
            hasher.combine(4)
            hasher.combine(colorId)
            hasher.combine(typeId)
            hasher.combine(brandId)
        }
    }
}

#Preview {
    PartsCategoriesPage()
}

