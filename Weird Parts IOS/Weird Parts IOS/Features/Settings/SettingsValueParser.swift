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
        guard let parsed = Double(value) else {
            recordInvalid(key: key, value: rawValue, expectedType: "number")
            return defaultValue
        }
        return parsed
    }

    mutating func bool(_ settings: [String: String], key: String, default defaultValue: Bool) -> Bool {
        guard let rawValue = settings[key] else { return defaultValue }
        let value = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        switch value {
        case "true": return true
        case "false": return false
        default:
            recordInvalid(key: key, value: rawValue, expectedType: "true or false")
            return defaultValue
        }
    }

    func throwIfInvalid() throws {
        guard !invalidEntries.isEmpty else { return }
        throw SettingsHydrationError(invalidEntries: invalidEntries)
    }

    private mutating func recordInvalid(key: String, value: String, expectedType: String) {
        invalidEntries.append(.init(key: key, value: value, expectedType: expectedType))
    }
}

struct SettingsHydrationError: LocalizedError, Equatable {
    struct InvalidEntry: Equatable {
        let key: String
        let value: String
        let expectedType: String
    }

    let invalidEntries: [InvalidEntry]

    var errorDescription: String? {
        let listedEntries = invalidEntries
            .prefix(5)
            .map { "\($0.key)=\"\($0.value)\" (expected \($0.expectedType))" }
            .joined(separator: ", ")
        let extraCount = invalidEntries.count - 5
        let suffix = extraCount > 0 ? ", and \(extraCount) more" : ""
        return "Saved settings contain invalid values and were not overwritten. Fix these stored values before saving: \(listedEntries)\(suffix)."
    }
}
