import SwiftUI
import Combine

/// Persists the user's custom tab bar order in UserDefaults.
///
/// Each user gets their own key (`tabOrder_<userId>`) so different logins
/// on the same device can have independent tab layouts.
///
/// The `tabOrder` array holds module IDs in the user's preferred order.
/// The first 4 entries become dedicated bottom tabs; the rest go to "More."
/// When empty (or on first launch), the default module order from
/// `NavigationConfig` is used.
/// Navigation layout style for module sub-tabs.
enum NavigationStyle: String, CaseIterable, Sendable {
    case topTabs = "topTabs"
    case sidebar = "sidebar"
    case fullSidebar = "fullSidebar"

    var label: String {
        switch self {
        case .topTabs: return "Top Tabs"
        case .sidebar: return "Sidebar"
        case .fullSidebar: return "Full Sidebar"
        }
    }

    var icon: String {
        switch self {
        case .topTabs: return "rectangle.split.1x2"
        case .sidebar: return "sidebar.left"
        case .fullSidebar: return "sidebar.squares.leading"
        }
    }

    var description: String {
        switch self {
        case .topTabs: return "Scrollable tab bar above content. Best for phones."
        case .sidebar: return "Left sidebar for sub-tabs within each module. Great for iPad."
        case .fullSidebar: return "All modules in a persistent left sidebar. Desktop-style navigation."
        }
    }
}

@MainActor
final class TabBarPreferences: ObservableObject {
    @Published var tabOrder: [String] = []
    @Published var navigationStyle: NavigationStyle = .topTabs

    private var userId: Int64?

    // MARK: - Keys

    private var userDefaultsKey: String {
        guard let id = userId else { return "tabOrder_default" }
        return "tabOrder_\(id)"
    }

    private var navStyleKey: String {
        guard let id = userId else { return "navStyle_default" }
        return "navStyle_\(id)"
    }

    // MARK: - Public API

    /// Load preferences for the given user. Call on login / app launch.
    func load(userId: Int64?) {
        self.userId = userId
        let key = userDefaultsKey
        if let saved = UserDefaults.standard.stringArray(forKey: key), !saved.isEmpty {
            tabOrder = saved
        } else {
            tabOrder = []
        }

        // Load navigation style
        if let rawStyle = UserDefaults.standard.string(forKey: navStyleKey),
           let style = NavigationStyle(rawValue: rawStyle) {
            navigationStyle = style
        } else {
            // Default: full sidebar on iPad/Mac, top tabs on iPhone
            navigationStyle = DeviceContext.isLargeScreen ? .fullSidebar : .topTabs
        }
    }

    /// Save the current order to UserDefaults.
    func save() {
        UserDefaults.standard.set(tabOrder, forKey: userDefaultsKey)
    }

    /// Save the navigation style preference.
    func saveNavigationStyle() {
        UserDefaults.standard.set(navigationStyle.rawValue, forKey: navStyleKey)
    }

    /// Reset to default (clear saved order).
    func reset() {
        tabOrder = []
        UserDefaults.standard.removeObject(forKey: userDefaultsKey)
    }

    /// Returns the user's preferred module order intersected with the
    /// permission-filtered modules. Modules not in the saved order are
    /// appended at the end (so new modules appear automatically).
    func orderedModules(from filtered: [AppModule]) -> [AppModule] {
        guard !tabOrder.isEmpty else { return filtered }

        let idSet = Set(filtered.map(\.id))
        var result: [AppModule] = []
        var seen = Set<String>()

        // 1. Add modules in saved order (if still visible)
        for moduleId in tabOrder {
            if idSet.contains(moduleId), let mod = allModulesById[moduleId] {
                result.append(mod)
                seen.insert(moduleId)
            }
        }

        // 2. Append any new modules not in saved order
        for mod in filtered where !seen.contains(mod.id) {
            result.append(mod)
        }

        return result
    }
}
