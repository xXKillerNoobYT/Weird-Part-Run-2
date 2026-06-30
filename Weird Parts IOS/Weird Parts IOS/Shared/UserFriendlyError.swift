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
