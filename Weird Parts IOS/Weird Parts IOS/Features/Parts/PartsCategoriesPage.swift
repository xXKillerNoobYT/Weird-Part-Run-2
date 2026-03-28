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
    @State private var activeSheet: ActiveSheet?
    /// Incremented after each successful data load to force view identity refresh.
    @State private var dataVersion = 0

    private enum ActiveSheet: Identifiable { case help; var id: String { "help" } }

    var body: some View {
        VStack(spacing: 0) {
            OnboardingBanner(pageId: "parts-categories")

            Group {
                if isLoading {
                    ProgressView("Loading hierarchy...")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .accessibilityIdentifier("categoriesLoadingIndicator")
                } else if let error = loadError {
                    ErrorStateView(message: error) {
                        Task { await loadHierarchy() }
                    }
                    .accessibilityIdentifier("categoriesErrorState")
                } else if DeviceContext.isLargeScreen {
                    splitLayout
                } else {
                    compactLayout
                }
            }
            // Force SwiftUI to rebuild the view tree when data changes.
            // This prevents stale data from persisting after sheet edits.
            .id(dataVersion)
        }
        .accessibilityIdentifier("partsCategoriesPage")
        .background(DS.Background.page)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { activeSheet = .help } label: {
                    Image(systemName: "questionmark.circle")
                }
                .accessibilityIdentifier("categoriesHelpButton")
            }
        }
        .sheet(item: $activeSheet) { _ in
            PageHelpSheet(
                title: "Categories Help",
                sections: [
                    ("Hierarchy", "Parts are organized in a 5-level hierarchy: Category > Style > Type > Brand > Color. Tap any level to drill down."),
                    ("Editing", "Select an item in the tree to view and edit its details in the editor panel. On iPad, the editor appears side-by-side."),
                    ("Managing", "Add new categories, styles, types, brands, and colors from the editor panel. Changes apply immediately to all parts using that classification.")
                ]
            )
        }
        .task {
            await loadHierarchy()
            appCore.onboardingManager?.markCompleted("categories-browse")
        }
        .refreshable { await loadHierarchy() }
        // Auto-refresh when any hierarchy data changes (safety net for notification-based updates)
        .onDataChange(.partsHierarchy) {
            await loadHierarchy()
        }
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
            // Run the (synchronous) GRDB read off the main thread to avoid blocking UI
            let tree = try await Task.detached(priority: .userInitiated) {
                try service.getHierarchy()
            }.value
            await MainActor.run {
                hierarchy = tree
                isLoading = false
                loadError = nil
                dataVersion += 1
            }
        } catch {
            await MainActor.run {
                loadError = userFriendlyError(error, context: "load categories")
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

