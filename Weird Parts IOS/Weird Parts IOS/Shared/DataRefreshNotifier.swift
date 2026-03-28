import SwiftUI
import Combine

// MARK: - Data Refresh Notification System
//
// Lightweight notification-based data invalidation. Any view can post a
// "data changed" notification for a specific domain (e.g. "parts-hierarchy",
// "brands", "warehouse"), and any view observing that domain will auto-refresh.
//
// This supplements the existing callback-based refresh pattern by acting as a
// safety net — if the onSave callback chain fails for any reason, the
// notification still fires and triggers a reload.

/// Domains for data change notifications. Add new domains as needed.
enum DataDomain: String {
    case partsHierarchy = "parts-hierarchy"
    case partsCatalog = "parts-catalog"
    case brands = "brands"
    case suppliers = "suppliers"
    case warehouse = "warehouse"
    case jobs = "jobs"
    case orders = "orders"
    case fleet = "fleet"
    case people = "people"
    case scheduling = "scheduling"
    case tools = "tools"
    case notebooks = "notebooks"
}

/// Post a data-change notification for a specific domain.
/// Call this after any successful GRDB write operation.
func notifyDataChanged(_ domain: DataDomain) {
    NotificationCenter.default.post(
        name: .dataDidChange,
        object: nil,
        userInfo: ["domain": domain.rawValue]
    )
}

/// Post a data-change notification for multiple domains at once.
func notifyDataChanged(_ domains: [DataDomain]) {
    for domain in domains {
        notifyDataChanged(domain)
    }
}

extension Notification.Name {
    static let dataDidChange = Notification.Name("com.wiredpart.dataDidChange")
}

// MARK: - SwiftUI View Modifier for Auto-Refresh

/// A view modifier that listens for data-change notifications and triggers a refresh.
///
/// Usage:
/// ```swift
/// .onDataChange(.partsHierarchy) {
///     await loadHierarchy()
/// }
/// ```
struct DataChangeRefreshModifier: ViewModifier {
    let domain: DataDomain
    let action: () async -> Void

    func body(content: Content) -> some View {
        content
            .onReceive(
                NotificationCenter.default.publisher(for: .dataDidChange)
                    .filter { notification in
                        guard let d = notification.userInfo?["domain"] as? String else { return false }
                        return d == domain.rawValue
                    }
                    // Debounce rapid-fire notifications (e.g. bulk import)
                    .debounce(for: .milliseconds(250), scheduler: RunLoop.main)
            ) { _ in
                Task { @MainActor in
                    await action()
                }
            }
    }
}

extension View {
    /// Observe data changes for a specific domain and trigger a refresh.
    func onDataChange(_ domain: DataDomain, perform action: @escaping () async -> Void) -> some View {
        modifier(DataChangeRefreshModifier(domain: domain, action: action))
    }
}
