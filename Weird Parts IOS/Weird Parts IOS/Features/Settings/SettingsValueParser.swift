import Foundation

/// Parses persisted SettingsService values without silently treating malformed saved values as missing.
/// Missing keys use the supplied UI default. Present-but-invalid keys are collected so settings pages
/// can stop loading and warn the owner before a later save overwrites the corrupt stored value.
struct SettingsValueParser {
    private(set) var invalidEntries: [SettingsHydrationError.InvalidEntry] = []

    mutating func int(_ settings: [String: String], key: String, default defaultValue: Int) -> Int {
        guard let rawValue = settings[key] else { return defaultValue }
        let value = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let parsed = Int(value) else {
            recordInvalid(key: key, value: rawValue, expectedType: "whole number")
            return defaultValue
        }
        return parsed
    }

    mutating func double(_ settings: [String: String], key: String, default defaultValue: Double) -> Double {
        guard let rawValue = settings[key] else { return defaultValue }
        let value = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let parsed = Double(value), parsed.isFinite else {
            recordInvalid(key: key, value: rawValue, expectedType: "number")
            return defaultValue
        }
        return parsed
    }

    mutating func bool(_ settings: [String: String], key: String, default defaultValue: Bool) -> Bool {
        guard let rawValue = settings[key] else { return defaultValue }
        let value = rawValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        switch value {
        case "true": return true
        case "false": return false
        default:
            recordInvalid(key: key, value: rawValue, expectedType: "true or false")
            return defaultValue
        }
    }

    mutating func rawEnum<T: RawRepresentable & CaseIterable>(
        _ settings: [String: String], key: String, default defaultValue: T
    ) -> T where T.RawValue == String {
        guard let rawValue = settings[key] else { return defaultValue }
        guard let parsed = T(rawValue: rawValue) else {
            let validValues = T.allCases.map { "\($0.rawValue)" }.joined(separator: ", ")
            recordInvalid(key: key, value: rawValue, expectedType: "one of: \(validValues)")
            return defaultValue
        }
        return parsed
    }

    func throwIfInvalid() throws {
        guard !invalidEntries.isEmpty else { return }
        throw SettingsHydrationError(invalidEntries: invalidEntries)
    }

    private mutating func recordInvalid(key: String, value: String, expectedType: String) {
        invalidEntries.append(.init(key: key, value: value, expectedType: expectedType))
    }
}

nonisolated struct SettingsHydrationError: LocalizedError, Equatable, Sendable {
    struct InvalidEntry: Equatable, Sendable {
        let key: String
        let value: String
        let expectedType: String
    }

    let invalidEntries: [InvalidEntry]

    var errorDescription: String? {
        let listedEntries = invalidEntries
            .prefix(5)
            .map { "\($0.key)=\"\(Self.displayValue($0.value))\" (expected \($0.expectedType))" }
            .joined(separator: ", ")
        let extraCount = max(0, invalidEntries.count - 5)
        let suffix = extraCount > 0 ? ", and \(extraCount) more" : ""
        return "Saved settings contain invalid values and were not overwritten. Fix these stored values before saving: \(listedEntries)\(suffix)."
    }

    private static func displayValue(_ value: String) -> String {
        let sanitized = value
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\r", with: " ")
        let maxLength = 80
        guard sanitized.count > maxLength else { return sanitized }
        return "\(sanitized.prefix(maxLength))…"
    }
}
