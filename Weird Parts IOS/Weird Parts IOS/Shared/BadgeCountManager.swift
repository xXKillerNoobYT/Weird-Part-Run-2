import SwiftUI
import WiredPartCore
import os.log

/// Observable badge count manager that provides live pending-item counts
/// for tab bar badges across the entire app.
///
/// Refreshes on:
/// - Tab appearance (via `refresh()`)
/// - Scene phase changes (foreground resume)
/// - Manual pull-to-refresh on any page
///
/// Published as an `@EnvironmentObject` alongside `AppCore` so every
/// navigation view can read badge counts without prop-drilling.
@MainActor
final class BadgeCountManager: ObservableObject {

    @Published private(set) var counts = BadgeCountService.BadgeCounts()

    private var service: BadgeCountService?
    private var userId: Int64?
    private let logger = Logger(subsystem: "com.wiredpart.ios", category: "BadgeCountManager")

    // MARK: - Configuration

    /// Configure with the badge count service after AppCore finishes bootstrap.
    func configure(service: BadgeCountService, userId: Int64?) {
        self.service = service
        self.userId = userId
        refresh()
    }

    /// Update the current user ID (e.g. after login).
    func setUserId(_ userId: Int64?) {
        self.userId = userId
        refresh()
    }

    // MARK: - Refresh

    /// Refresh all badge counts from the database. Safe to call frequently.
    func refresh() {
        guard let service else { return }
        Task.detached(priority: .utility) { [userId] in
            do {
                let newCounts = try service.getAllBadgeCounts(userId: userId)
                await MainActor.run { [weak self] in
                    self?.counts = newCounts
                }
            } catch {
                // Badge count errors are non-fatal — log and continue
                await MainActor.run { [weak self] in
                    self?.logger.warning("[BadgeCountManager] Refresh failed: \(error.localizedDescription)")
                }
            }
        }
    }

    // MARK: - Convenience

    /// Badge count for a specific module by ID.
    func badge(for moduleId: String) -> Int {
        counts.badge(for: moduleId)
    }

    /// Whether badge tint should be red (items pending > 7 days).
    var shouldUseRedTint: Bool {
        counts.hasOldItems
    }
}
