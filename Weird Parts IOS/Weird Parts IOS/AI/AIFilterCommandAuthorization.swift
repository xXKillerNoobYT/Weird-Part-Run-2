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
/// only when a local request parser identifies an explicit filter mutation for the
/// requested value and the active registry recognizes the exact page/value pair.
enum AIFilterCommandAuthorization {
    private static let commandPattern = #"\{[^{}]*"activateFilter"\s*:\s*\{[^{}]*"pageId"\s*:\s*"([^"]+)"[^{}]*"value"\s*:\s*"([^"]+)"[^{}]*\}[^{}]*\}"#

    static func authorizedCommands(
        response: String,
        userQuery: String,
        availableFilters: [(pageId: String, filterName: String, options: [String])]
    ) -> [AIFilterActivationCommand] {
        return parsedCommands(from: response).filter { command in
            guard let intendedPageId = explicitlyRequestsFiltering(
                userQuery,
                for: command.value,
                availableFilters: availableFilters
            ),
                  intendedPageId == command.pageId,
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

    /// Matches only imperative filter mutations and deliberately excludes questions
    /// about a filter. The query must also name exactly one registered page, so the
    /// model cannot reuse a requested value to mutate a different page. Model output
    /// and navigation/record context are never inputs.
    private static func explicitlyRequestsFiltering(
        _ query: String,
        for value: String,
        availableFilters: [(pageId: String, filterName: String, options: [String])]
    ) -> String? {
        let normalized = query
            .lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let escapedValue = NSRegularExpression.escapedPattern(for: value.lowercased())
        let politePrefix = #"(?:(?:please|can\s+you|could\s+you|would\s+you)\s+)?"#
        let patterns = [
            #"^\#(politePrefix)(?:filter|apply)\b.*\b(?:to|for|as)\s+\#(escapedValue)\b"#,
            #"^\#(politePrefix)show\s+only\s+(?:the\s+)?\#(escapedValue)\b"#,
            #"^\#(politePrefix)show\b.*\bonly\s+\#(escapedValue)\b"#
        ]

        let requestsValue = patterns.contains { pattern in
            guard let regex = try? NSRegularExpression(pattern: pattern) else { return false }
            let range = NSRange(location: 0, length: (normalized as NSString).length)
            return regex.firstMatch(in: normalized, range: range) != nil
        }
        guard requestsValue else { return nil }

        let intendedPageIds = availableFilters.map(\.pageId).filter { pageId in
            queryMentionsPage(normalized, pageId: pageId)
        }
        guard intendedPageIds.count == 1 else { return nil }
        return intendedPageIds[0]
    }

    private static func queryMentionsPage(_ query: String, pageId: String) -> Bool {
        let escapedPageId = NSRegularExpression.escapedPattern(for: pageId.lowercased())
            .replacingOccurrences(of: "-", with: "[-_\\s]+")
        let pattern = #"\b\#(escapedPageId)\b"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return false }
        let range = NSRange(location: 0, length: (query as NSString).length)
        return regex.firstMatch(in: query, range: range) != nil
    }
}
