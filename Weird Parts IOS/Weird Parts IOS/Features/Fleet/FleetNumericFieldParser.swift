import Foundation

/// Shared validation for optional Fleet integer text fields.
///
/// Blank input is treated as omitted, but malformed non-empty input is rejected so pasted
/// text or hardware-keyboard input cannot be silently dropped by `Int(...)` returning nil.
enum FleetNumericFieldParser {
    struct ValidationError: LocalizedError, Equatable {
        let fieldName: String

        nonisolated var errorDescription: String? {
            "\(fieldName) must be a whole number."
        }
    }

    nonisolated static func optionalWholeNumber(_ rawValue: String, fieldName: String) throws -> Int? {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        guard trimmed.allSatisfy(\.isWholeNumber), let value = Int(trimmed) else {
            throw ValidationError(fieldName: fieldName)
        }

        return value
    }
}
