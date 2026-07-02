import Foundation
import WiredPartCore

/// Wraps a raw error into a user-friendly message for display in loadError states.
///
/// Security audit (issue #282, 2026-04-27): this helper never returns raw GRDB error text
/// or DB row contents. Every explicit mapping below returns a fixed, generic string.
/// The final fallback interpolates only the caller-supplied `context` label.
/// **Callers must pass a fixed, non-sensitive label** (e.g. "load vehicles", "save inspection")
/// rather than dynamic identifiers or user data such as VINs, licence plates, or driver names.
///
/// Fleet callsite audit (all confirmed safe fixed labels):
///   "load driver data", "assign driver", "create trailer", "create vehicle",
///   "load fleet dashboard", "load fuel data", "load inspections",
///   "load maintenance data", "load mileage data", "load truck data",
///   "save vehicle data", "report vehicle issue", "load telematics data",
///   "load trailer details", "load trailer locations", "load trailers",
///   "load truck tools", "load vehicle details", "load vehicles",
///   "load inspection data", "save inspection"
func userFriendlyError(_ error: Error, context: String = "load data") -> String {
    if let jobsError = error as? JobsService.JobsError,
       case .invalidClockTimestamp = jobsError {
        return "A saved clock entry has an invalid timestamp. Ask an admin to review the timesheet before using today's hours."
    }

    if let warehouseError = error as? WarehouseService.WarehouseError {
        switch warehouseError {
        case .gridShrinkWouldOrphanItems(let features, let zones):
            // Fixed counts only — no row contents (see security note above).
            var stranded: [String] = []
            if features > 0 { stranded.append("\(features) feature\(features == 1 ? "" : "s")") }
            if zones > 0 { stranded.append("\(zones) zone\(zones == 1 ? "" : "s")") }
            return "Can't shrink the grid: \(stranded.joined(separator: " and ")) would fall outside the new size. Move or remove them first."
        case .invalidDimension:
            // Issue #1165: service-layer dimension/placement validation.
            // Fixed string — no dimension values from the failed input.
            // Width/height must be positive; grid X/Y must be non-negative (0 is valid).
            return "Dimensions must be positive, and grid placement must be zero or greater, and fit inside the floor-plan grid."
        case .noEligibleVerificationCounters(let required, let available):
            // Issue #494: fixed counts only — no user names or part data.
            return "Not enough eligible counters: \(required) needed, \(available) available besides you. Add active users or lower the required count."
        case .partAlreadyFlaggedForVerification:
            // Issue #494: fixed string — no part identifiers (see security note).
            // Only thrown while counts are still coming in or a consensus is
            // waiting to be resolved — dead-end sets are superseded instead.
            return "This part is already out for verification. Wait for the counts to come in, or resolve the submitted counts, before sending it again."
        default:
            break
        }
    }

    let raw = error.localizedDescription
    if raw.contains("no such table") {
        return "This feature isn't set up yet. Contact your admin."
    }
    if raw.contains("UNIQUE constraint") {
        return "This item already exists. Try a different name or code."
    }
    if raw.contains("FOREIGN KEY constraint") {
        return "Can't complete this action — a related item is missing."
    }
    if raw.contains("database is locked") {
        return "The database is busy. Please try again in a moment."
    }
    if raw.contains("disk I/O error") || raw.contains("disk full") {
        return "Storage problem. Check your device has enough space."
    }
    if raw.contains("connection") || raw.contains("timeout") || raw.contains("network") {
        return "Connection issue. Check your network and try again."
    }
    if raw.contains("not found") && !raw.contains("no such table") {
        return "Item not found. It may have been deleted."
    }
    return "Couldn't \(context). Pull down to retry."
}
