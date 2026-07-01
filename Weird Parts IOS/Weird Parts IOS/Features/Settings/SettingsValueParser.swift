import Foundation

/// Parses persisted SettingsService values without hiding corrupt saved configuration.
///
/// Missing keys intentionally use page defaults. Present-but-malformed values throw so
/// settings pages surface a visible load error instead of silently overwriting the
/// existing stored value on the next save.
enum SettingsValueParser {
    enum ParseError: LocalizedError, Equatable {
        case invalidValue(key: String, value: String, expectedType: String)

        var errorDescription: String? {
            switch self {
            case let .invalidValue(key, value, expectedType):
                return "Saved setting \"\(key)\" has invalid \(expectedType) value \"\(value)\". Fix or reset this setting before saving."
            }
        }
    }

    static func int(_ map: [String: String], key: String, default defaultValue: Int) throws -> Int {
        guard let rawValue = map[key] else { return defaultValue }
        let trimmedValue = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let parsedValue = Int(trimmedValue) else {
            throw ParseError.invalidValue(key: key, value: rawValue, expectedType: "whole-number")
        }
        return parsedValue
    }

    static func double(_ map: [String: String], key: String, default defaultValue: Double) throws -> Double {
        guard let rawValue = map[key] else { return defaultValue }
        let trimmedValue = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let parsedValue = Double(trimmedValue) else {
            throw ParseError.invalidValue(key: key, value: rawValue, expectedType: "decimal-number")
        }
        return parsedValue
    }

    static func bool(_ map: [String: String], key: String, default defaultValue: Bool) throws -> Bool {
        guard let rawValue = map[key] else { return defaultValue }
        switch rawValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "true":
            return true
        case "false":
            return false
        default:
            throw ParseError.invalidValue(key: key, value: rawValue, expectedType: "true/false")
        }
    }
}
