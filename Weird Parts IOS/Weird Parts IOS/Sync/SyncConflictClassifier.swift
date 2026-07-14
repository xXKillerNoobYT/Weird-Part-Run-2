import Foundation
import WiredPartCore

/// Severity levels for sync conflicts, from auto-resolvable to human-required.
enum ConflictSeverity {
    /// Timestamps, sort orders — LWW is fine, no review needed.
    case trivial
    /// One field changed — pick newer value, flag for optional review.
    case simple
    /// Multiple fields, both meaningful — auto-resolve but show in review.
    case moderate
    /// Text content merged — AI merge needed, user confirms.
    case hard
    /// Financial/stock data — human MUST decide, never auto-resolve.
    case critical
}

/// Classification of which conflicts need what level of attention.
enum SyncConflictClassifier {

    /// Persisted/synced financial and stock fields that always require an
    /// explicit local/remote decision. Keep schema names here; legacy aliases
    /// remain below for conflict rows created by older app versions.
    private static let criticalFields: Set<String> = [
        "qty", "stock", "cost", "price", "total", "budget",
        "forecast_adu_30", "min_stock", "target_stock", "max_stock",
        "min_stock_level", "target_stock_level", "max_stock_level",
        "current_stock", "committed_qty", "on_order_qty",
        "unit_cost", "company_cost_price", "sell_price", "markup_percent",
        "company_markup_percent",
        "regular_hours", "overtime_hours", "total_hours",
        "amount", "balance", "rate", "hourly_rate",
    ]

    /// Classify a conflict based on its field name and values.
    static func classify(_ conflict: ConflictLogEntry) -> ConflictSeverity {
        let field = conflict.fieldName.lowercased()

        // Trivial: metadata fields where LWW is always acceptable
        let trivialFields: Set<String> = [
            "updated_at", "sort_order", "last_seen_at", "sync_batch_id",
            "synced", "last_sync_at", "sequence",
        ]
        if trivialFields.contains(field) { return .trivial }

        // Critical: financial, stock, pricing — human must decide
        if criticalFields.contains(field) { return .critical }

        // Hard: text content where both edits could have value
        let localHasContent = !(conflict.localValue ?? "").isEmpty
        let remoteHasContent = !(conflict.remoteValue ?? "").isEmpty
        if ConflictResolver.isTextResolutionField(field) && localHasContent && remoteHasContent {
            return .hard
        }

        // Simple: single field, non-critical
        return .simple
    }

    /// Whether a conflict severity should be auto-resolved without user action.
    static func isAutoResolvable(_ severity: ConflictSeverity) -> Bool {
        switch severity {
        case .trivial, .simple: return true
        case .moderate: return true  // auto-resolve but flag for review
        case .hard, .critical: return false
        }
    }

    /// Whether a conflict should be shown in the review banner.
    static func needsReview(_ severity: ConflictSeverity) -> Bool {
        switch severity {
        case .trivial: return false
        case .simple, .moderate, .hard, .critical: return true
        }
    }
}
