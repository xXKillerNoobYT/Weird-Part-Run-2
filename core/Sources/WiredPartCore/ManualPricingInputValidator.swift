import Foundation

/// Validates human-entered catalog pricing fields before they reach persistence.
///
/// Manual SwiftUI `TextField` values must not use `Double(text) ?? 0` because
/// malformed drafts such as `abc`, `$12`, or a blank field become zero and can
/// silently overwrite real catalog prices.
public enum ManualPricingInputValidator {
    public enum ValidationError: LocalizedError, Equatable {
        case required(fieldName: String)
        case invalidNumber(fieldName: String)
        case negative(fieldName: String)
        case percentTooHigh(fieldName: String, maxExclusive: Double)

        public var errorDescription: String? {
            switch self {
            case .required(let fieldName):
                return "\(fieldName) is required. Keep your entered value and fix it before saving."
            case .invalidNumber(let fieldName):
                return "\(fieldName) must be a valid number. Keep your entered value and fix it before saving."
            case .negative(let fieldName):
                return "\(fieldName) must be zero or greater. Keep your entered value and fix it before saving."
            case .percentTooHigh(let fieldName, let maxExclusive):
                return "\(fieldName) must be less than \(String(format: "%.0f", maxExclusive))%. Keep your entered value and fix it before saving."
            }
        }
    }

    public static func parseMoney(_ rawValue: String, fieldName: String) throws -> Double {
        try parseNonNegativeDecimal(rawValue, fieldName: fieldName)
    }

    public static func parsePercent(_ rawValue: String, fieldName: String) throws -> Double {
        try parseNonNegativeDecimal(rawValue, fieldName: fieldName)
    }

    public static func parseMarginPercent(_ rawValue: String, fieldName: String) throws -> Double {
        let value = try parsePercent(rawValue, fieldName: fieldName)
        guard value < 100 else {
            throw ValidationError.percentTooHigh(fieldName: fieldName, maxExclusive: 100)
        }
        return value
    }

    private static func parseNonNegativeDecimal(_ rawValue: String, fieldName: String) throws -> Double {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw ValidationError.required(fieldName: fieldName)
        }
        guard let value = Double(trimmed), value.isFinite else {
            throw ValidationError.invalidNumber(fieldName: fieldName)
        }
        guard value >= 0 else {
            throw ValidationError.negative(fieldName: fieldName)
        }
        return value
    }
}
