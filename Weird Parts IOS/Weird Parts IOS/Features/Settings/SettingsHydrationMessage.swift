import Foundation

nonisolated func settingsHydrationMessage(_ error: Error) -> String {
    if let hydrationError = error as? SettingsHydrationError {
        return hydrationError.localizedDescription
    }
    return userFriendlyError(error, context: "load")
}
