import Testing
@testable import Weird_Parts

@Suite("Destructive confirmation copy")
@MainActor
struct DestructiveConfirmationCopyTests {
    @Test func deleteMessageNamesItemAndWarnsIrreversible() {
        #expect(
            DestructiveConfirmationCopy.deleteMessage(itemName: "PO-1042")
                == "Are you sure you want to delete PO-1042? This cannot be undone."
        )
    }

    @Test func deleteMessageFallsBackForBlankNames() {
        #expect(
            DestructiveConfirmationCopy.deleteMessage(itemName: "   ")
                == "Are you sure you want to delete this item? This cannot be undone."
        )
    }

    @Test func deleteTitleAndButtonKeepActionExplicit() {
        #expect(DestructiveConfirmationCopy.deleteTitle("Template") == "Delete Template?")
        #expect(DestructiveConfirmationCopy.deleteButton("Template") == "Delete Template")
    }
}
