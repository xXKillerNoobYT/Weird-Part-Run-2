import Foundation

// MARK: - Validation Errors (Fix #213)

/// Errors thrown when user-supplied input to service create/update methods
/// fails length, type, or range checks. These replace silent acceptance of
/// oversized strings and negative values that the audit found across services.
public enum ValidationError: Error, Sendable, LocalizedError {
    /// A text field exceeded its maximum character length.
    case stringTooLong(field: String, limit: Int, actual: Int)
    /// A numeric field received a negative value where non-negative is required.
    case negativeValue(field: String, value: Double)
    /// A required field was empty or whitespace-only.
    case emptyRequired(field: String)

    public var errorDescription: String? {
        switch self {
        case .stringTooLong(let field, let limit, let actual):
            return "\(field) is too long (\(actual) chars; limit \(limit))."
        case .negativeValue(let field, let value):
            return "\(field) cannot be negative (got \(value))."
        case .emptyRequired(let field):
            return "\(field) is required."
        }
    }
}

// MARK: - Validator helpers

/// Lightweight validators for service create/update parameters.
/// Kept as free functions (not a type) so call sites stay readable:
/// `try Validators.requireName(name, field: "Part name")`
public enum Validators {

    /// Default length caps used across services.
    public enum Limits {
        public static let name: Int = 200
        public static let code: Int = 100
        public static let description: Int = 2000
        public static let notes: Int = 5000
        public static let url: Int = 2048
    }

    /// Require a non-empty name, cap at `limit` characters (default 200).
    public static func requireName(_ s: String, field: String, limit: Int = Limits.name) throws {
        let trimmed = s.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw ValidationError.emptyRequired(field: field)
        }
        guard s.count <= limit else {
            throw ValidationError.stringTooLong(field: field, limit: limit, actual: s.count)
        }
    }

    /// Optional text: allow nil/empty, cap at `limit` characters when present.
    public static func requireText(_ s: String?, field: String, limit: Int) throws {
        guard let s else { return }
        guard s.count <= limit else {
            throw ValidationError.stringTooLong(field: field, limit: limit, actual: s.count)
        }
    }

    /// Numeric value must be >= 0. For prices, quantities, rates, etc.
    public static func requireNonNegative(_ v: Double, field: String) throws {
        guard v >= 0 else {
            throw ValidationError.negativeValue(field: field, value: v)
        }
    }

    /// Integer variant of requireNonNegative.
    public static func requireNonNegative(_ v: Int, field: String) throws {
        guard v >= 0 else {
            throw ValidationError.negativeValue(field: field, value: Double(v))
        }
    }
}
