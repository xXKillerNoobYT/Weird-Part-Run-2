import Foundation

/// Shared normalization rules for durable user-entered text.
///
/// Service boundaries use these helpers so SwiftUI forms, tests, sync/import paths,
/// and future non-UI callers all reject visually blank required values the same way.
public extension String {
    /// Returns this value trimmed with `.whitespacesAndNewlines`.
    var trimmedRequiredText: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// True when a required durable value is empty after whitespace/newline trimming.
    var isBlankRequiredText: Bool {
        trimmedRequiredText.isEmpty
    }

    /// Trims a required durable value, returning `nil` when the input is visually blank.
    var normalizedRequiredText: String? {
        let trimmed = trimmedRequiredText
        return trimmed.isEmpty ? nil : trimmed
    }
}

public extension Optional where Wrapped == String {
    /// Trims optional durable text and normalizes whitespace/newline-only input to `nil`.
    var normalizedOptionalText: String? {
        guard let value = self else { return nil }
        return value.normalizedRequiredText
    }
}
