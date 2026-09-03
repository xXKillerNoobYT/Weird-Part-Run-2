import Foundation

/// Shared, non-secret validation for every UI that asks a person to choose a PIN.
///
/// Error copy is intentionally fixed and never includes a submitted PIN. PIN
/// hashing and current-PIN authentication remain the responsibility of
/// `AuthService`; this helper only prevents incomplete or mismatched forms from
/// reaching that service.
enum PINConfirmationValidator {
    static func newPINError(pin: String, confirmation: String) -> String? {
        let normalizedPIN = normalize(pin)
        let normalizedConfirmation = normalize(confirmation)

        guard !normalizedPIN.isEmpty else {
            return "Enter a new PIN."
        }
        guard normalizedPIN.count >= 4,
              normalizedPIN.count <= 8,
              normalizedPIN.allSatisfy(\.isNumber) else {
            return "PIN must be 4–8 digits."
        }
        guard !normalizedConfirmation.isEmpty else {
            return "Confirm the new PIN."
        }
        guard normalizedPIN == normalizedConfirmation else {
            return "PIN entries do not match."
        }
        return nil
    }

    static func changePINError(currentPIN: String, newPIN: String, confirmation: String) -> String? {
        guard !normalize(currentPIN).isEmpty else {
            return "Enter your current PIN."
        }
        return newPINError(pin: newPIN, confirmation: confirmation)
    }

    static func normalize(_ pin: String) -> String {
        pin.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
