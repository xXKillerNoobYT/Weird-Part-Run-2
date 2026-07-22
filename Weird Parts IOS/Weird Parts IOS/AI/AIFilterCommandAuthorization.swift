import Foundation

/// A parsed assistant filter command that is eligible for UI activation only after
/// the local user-request boundary and registry allowlist have both been verified.
struct AIFilterActivationCommand: Equatable {
    let pageId: String
    let value: String

    /// Clearing or broadening to every value changes the user's current view more
    /// substantially than a narrow filter, so the panel requires a visible confirm.
    var requiresConfirmation: Bool {
        ["all", "clear", "clear-all"].contains(value.lowercased())
    }
}

/// Keeps model output non-authoritative for navigation filter mutations.
///
/// The model may suggest a structured command, but the command becomes actionable
/// only when the local query explicitly requests filtering, repeats the requested
/// value, and the active registry recognizes the exact page/value pair.
enum AIFilterCommandAuthorization {
    private static let commandPattern = #"\{[^{}]*"activateFilter"\s*:\s*\{[^{}]*"pageId"\s*:\s*"([^"]+)"[^{}]*"value"\s*:\s*"([^"]+)"[^{}]*\}[^{}]*\}"#

    static func authorizedCommands(
        response: String,
        userQuery: String,
        availableFilters: [(pageId: String, filterName: String, options: [String])]
    ) -> [AIFilterActivationCommand] {
        guard explicitlyRequestsFiltering(userQuery) else { return [] }

        let requestedValues = userQuery.lowercased()
        return parsedCommands(from: response).filter { command in
            guard requestedValues.contains(command.value.lowercased()),
                  let filter = availableFilters.first(where: { $0.pageId == command.pageId })
            else {
                return false
            }

            return filter.options.contains {
                $0.compare(command.value, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
            }
        }
    }

    static func parsedCommands(from response: String) -> [AIFilterActivationCommand] {
        guard let regex = try? NSRegularExpression(pattern: commandPattern) else { return [] }
        let nsResponse = response as NSString
        return regex.matches(in: response, range: NSRange(location: 0, length: nsResponse.length)).compactMap { match in
            guard match.numberOfRanges >= 3 else { return nil }
            return AIFilterActivationCommand(
                pageId: nsResponse.substring(with: match.range(at: 1)),
                value: nsResponse.substring(with: match.range(at: 2))
            )
        }
    }

    private static func explicitlyRequestsFiltering(_ query: String) -> Bool {
        let normalized = query.lowercased()
        return normalized.contains("filter")
            || normalized.contains("show only")
            || normalized.contains("only ")
            || normalized.contains("apply ")
    }
}
