import Foundation

/// Standard copy for true delete confirmations.
///
/// GitHub #82 requires the explanatory body to name the item and include the
/// irreversible-action warning. Non-delete actions such as cancel, void,
/// archive, and status transitions should keep their more specific copy.
enum DestructiveConfirmationCopy {
    static func deleteTitle(_ itemType: String) -> String {
        "Delete \(itemType)?"
    }

    static func deleteButton(_ itemType: String) -> String {
        "Delete \(itemType)"
    }

    static func deleteMessage(itemName: String) -> String {
        "Are you sure you want to delete \(normalizedName(itemName))? This cannot be undone."
    }

    static func deleteMessage(itemName: String, consequence: String) -> String {
        "\(deleteMessage(itemName: itemName)) \(consequence)"
    }

    private static func normalizedName(_ itemName: String) -> String {
        let trimmed = itemName.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "this item" : trimmed
    }
}
