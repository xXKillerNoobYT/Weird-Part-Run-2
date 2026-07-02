import Foundation

// MARK: - QR Scan Route (issue #700)
//
// The dashboard QR scanner offers quick actions ("View Part", "Move Stock",
// "Quick Audit", …) that navigate to another module. Navigation itself happens
// through a notification that only selects a module/tab, so the scanned entity
// context must travel out-of-band: the scanner stashes a `QRScanRouteContext`
// keyed by the destination tab, and the destination page consumes it exactly
// once when it appears, landing directly on the scanned entity instead of a
// generic module page.

/// What the user asked to do with the scanned entity.
public enum QRScanAction: String, Sendable, CaseIterable {
    /// Open/inspect the scanned entity (part detail, job detail, tool status…).
    case view
    /// Start a stock movement with the scanned part preselected.
    case moveStock
    /// Audit the scanned warehouse location.
    case audit
    /// Assign/log a part at the scanned warehouse location.
    case assignPart
    /// Show the scanned location on the warehouse floor plan.
    case floorPlan
}

/// Context payload carried from a QR scan quick action to its destination page.
public struct QRScanRouteContext: Sendable, Equatable {
    /// Scanned entity type, when the code resolved to a known entity.
    public let entityType: QREntityType?
    /// Scanned entity id (part id, job id, tool id, vehicle id, or warehouse area id).
    public let entityId: Int64?
    /// Raw scanned code, preserved for external/unknown barcodes.
    public let code: String
    /// Human-searchable identifier (part code, tool serial, vehicle number,
    /// full location code) for destinations that land via a search filter.
    public let searchHint: String?
    /// Storage-unit id containing a scanned warehouse area (floor-plan landing).
    public let locationUnitId: Int64?
    /// What the user asked to do with the entity.
    public let action: QRScanAction
    /// When the context was stashed — used to expire stale, unconsumed routes.
    public let stashedAt: Date

    public init(
        entityType: QREntityType?,
        entityId: Int64?,
        code: String,
        searchHint: String? = nil,
        locationUnitId: Int64? = nil,
        action: QRScanAction,
        stashedAt: Date = Date()
    ) {
        self.entityType = entityType
        self.entityId = entityId
        self.code = code
        self.searchHint = searchHint
        self.locationUnitId = locationUnitId
        self.action = action
        self.stashedAt = stashedAt
    }
}

/// Hand-off store for QR scan quick-action context.
///
/// The scanner stashes a context for a destination tab id *before* posting the
/// navigation notification; the destination page consumes it once when it
/// appears. Consume-once semantics plus a freshness window guarantee a stale
/// stash can never hijack a later, unrelated visit to the same page.
public final class QRScanRouteStore: @unchecked Sendable {
    public static let shared = QRScanRouteStore()

    /// Contexts older than this are dropped on consume (unconsumed routes —
    /// e.g. the user lacked permission for the destination tab — must not
    /// resurface minutes later).
    public static let defaultMaxAge: TimeInterval = 180

    private let lock = NSLock()
    private var pending: [String: QRScanRouteContext] = [:]

    public init() {}

    /// Stash a scan context for a destination tab (e.g. `"parts-catalog"`).
    /// Re-stashing for the same destination replaces the previous context.
    public func stash(_ context: QRScanRouteContext, for destinationTabId: String) {
        lock.lock()
        defer { lock.unlock() }
        pending[destinationTabId] = context
    }

    /// Consume (and clear) the pending context for a destination tab.
    /// Returns `nil` when nothing is stashed or the stash is older than `maxAge`.
    public func consume(
        for destinationTabId: String,
        maxAge: TimeInterval = QRScanRouteStore.defaultMaxAge,
        now: Date = Date()
    ) -> QRScanRouteContext? {
        lock.lock()
        defer { lock.unlock() }
        guard let context = pending.removeValue(forKey: destinationTabId) else { return nil }
        guard now.timeIntervalSince(context.stashedAt) <= maxAge else { return nil }
        return context
    }

    /// Drop every pending context (logout / test isolation).
    public func clearAll() {
        lock.lock()
        defer { lock.unlock() }
        pending.removeAll()
    }
}
