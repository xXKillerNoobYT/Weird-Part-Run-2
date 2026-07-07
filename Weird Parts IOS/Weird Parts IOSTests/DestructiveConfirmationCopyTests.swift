import XCTest
@testable import Weird_Parts

/// Behavioral contract for the shared destructive-confirmation copy
/// (panel-quality rubric criterion 8): titles and messages must state the
/// exact affected count with correct pluralization, and single-record
/// confirms must name the record. These call the copy builders directly —
/// no source scans — so they fail only when the user-visible contract breaks.
final class DestructiveConfirmationCopyTests: XCTestCase {

    // MARK: - Count phrase pluralization

    func testCountPhraseSingular() {
        XCTAssertEqual(
            DestructiveConfirmationCopy.countPhrase(count: 1, noun: "wishlist item"),
            "1 wishlist item"
        )
    }

    func testCountPhrasePlural() {
        XCTAssertEqual(
            DestructiveConfirmationCopy.countPhrase(count: 3, noun: "wishlist item"),
            "3 wishlist items"
        )
    }

    func testCountPhraseZeroUsesPlural() {
        XCTAssertEqual(
            DestructiveConfirmationCopy.countPhrase(count: 0, noun: "line"),
            "0 lines"
        )
    }

    func testCountPhraseIrregularPlural() {
        XCTAssertEqual(
            DestructiveConfirmationCopy.countPhrase(count: 2, noun: "category", plural: "categories"),
            "2 categories"
        )
    }

    // MARK: - Titles

    func testTitleInterpolatesActionAndCount() {
        let phrase = DestructiveConfirmationCopy.countPhrase(count: 3, noun: "return")
        XCTAssertEqual(
            DestructiveConfirmationCopy.title(actionLabel: "Delete", countPhrase: phrase),
            "Delete 3 returns?"
        )
    }

    func testRecordTitleNamesTheRecord() {
        XCTAssertEqual(
            DestructiveConfirmationCopy.recordTitle(actionLabel: "Delete", recordName: "Kitchen remodel"),
            "Delete 'Kitchen remodel'?"
        )
    }

    // MARK: - Messages

    func testDefaultMessageStatesCountAndFinality() {
        let message = DestructiveConfirmationCopy.defaultMessage(
            actionVerb: "deletes",
            countPhrase: "3 wishlist items"
        )
        XCTAssertEqual(message, "This deletes 3 wishlist items. This can't be undone from this screen.")
    }

    func testDefaultMessageAppendsSuffix() {
        let message = DestructiveConfirmationCopy.defaultMessage(
            actionVerb: "removes",
            countPhrase: "2 lines",
            suffix: "Items already ordered are unaffected."
        )
        XCTAssertEqual(
            message,
            "This removes 2 lines. This can't be undone from this screen. Items already ordered are unaffected."
        )
    }

    func testDefaultMessageIgnoresEmptySuffix() {
        let message = DestructiveConfirmationCopy.defaultMessage(
            actionVerb: "deletes",
            countPhrase: "1 draft",
            suffix: ""
        )
        XCTAssertEqual(message, "This deletes 1 draft. This can't be undone from this screen.")
    }

    func testDefaultRecordMessageNamesNounAndRecord() {
        let message = DestructiveConfirmationCopy.defaultRecordMessage(
            actionVerb: "deletes",
            noun: "notebook",
            recordName: "Kitchen remodel"
        )
        XCTAssertEqual(message, "This deletes the notebook 'Kitchen remodel'. This can't be undone from this screen.")
    }

    // MARK: - Defensive quoting

    func testQuotedUsesDoubleQuotesWhenNameHasApostrophe() {
        XCTAssertEqual(
            DestructiveConfirmationCopy.recordTitle(actionLabel: "Delete", recordName: "Bob's order"),
            "Delete \"Bob's order\"?"
        )
    }

    func testQuotedDropsWrappingWhenNameHasBothQuoteStyles() {
        XCTAssertEqual(
            DestructiveConfirmationCopy.quoted("Bob's \"special\""),
            "Bob's \"special\""
        )
    }
}

/// Behavioral contract for the shared stable-identifier suffix (CraftKit):
/// record id when present, else a real kebab slug — never a colliding "0".
final class StableAccessibilitySuffixTests: XCTestCase {

    func testUsesIdWhenPresent() {
        XCTAssertEqual(stableAccessibilitySuffix(id: 42, name: "Acme Supply"), "42")
    }

    func testSlugsNameWhenIdIsNil() {
        XCTAssertEqual(stableAccessibilitySuffix(id: nil, name: "Acme Supply Co."), "acme-supply-co")
    }

    func testCollapsesConsecutiveSeparators() {
        XCTAssertEqual(stableAccessibilitySuffix(id: nil, name: "A  &  B (main)"), "a-b-main")
    }

    func testFallsBackWhenNothingSurvivesSlugging() {
        XCTAssertEqual(stableAccessibilitySuffix(id: nil, name: "!!!"), "unnamed")
    }
}
