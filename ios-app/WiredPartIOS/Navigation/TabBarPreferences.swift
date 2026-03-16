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
@MainActor
final class TabBarPreferences: ObservableObject {
    @Published var tabOrder: [String] = []

    private var userId: Int64?

    // MARK: - Keys

    private var userDefaultsKey: String {
        guard let id = userId else { return "tabOrder_default" }
        return "tabOrder_\(id)"
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
    }

    /// Save the current order to UserDefaults.
    func save() {
        UserDefaults.standard.set(tabOrder, forKey: userDefaultsKey)
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
