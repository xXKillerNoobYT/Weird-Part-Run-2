import Foundation

/// Wraps a raw error into a user-friendly message for display in loadError states.
func userFriendlyError(_ error: Error, context: String = "load data") -> String {
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
