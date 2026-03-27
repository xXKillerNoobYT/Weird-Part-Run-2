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
    return "Couldn't \(context). Pull down to retry."
}
