import Testing
@testable import Weird_Parts

@Suite("FilterStack helpers")
struct FilterStackTests {
    private struct FixtureItem {
        let status: String
        let urgent: Bool
    }

    @Test func filterCountsReturnsZeroesForEmptyBase() {
        let counts = filterCounts(
            base: [FixtureItem](),
            keys: ["all", "draft", "submitted"],
            matches: { item, key in item.status == key }
        )

        #expect(counts["all"] == 0)
        #expect(counts["draft"] == 0)
        #expect(counts["submitted"] == 0)
    }

    @Test func filterCountsCountsSingleKey() {
        let base = [
            FixtureItem(status: "draft", urgent: false),
            FixtureItem(status: "submitted", urgent: false),
            FixtureItem(status: "draft", urgent: true)
        ]

        let counts = filterCounts(base: base, keys: ["draft"]) { item, key in
            item.status == key
        }

        #expect(counts["draft"] == 2)
    }

    @Test func filterCountsCountsMultipleKeys() {
        let base = [
            FixtureItem(status: "draft", urgent: false),
            FixtureItem(status: "submitted", urgent: false),
            FixtureItem(status: "approved", urgent: false),
            FixtureItem(status: "submitted", urgent: true)
        ]

        let counts = filterCounts(base: base, keys: ["draft", "submitted", "approved"]) { item, key in
            item.status == key
        }

        #expect(counts["draft"] == 1)
        #expect(counts["submitted"] == 2)
        #expect(counts["approved"] == 1)
    }

    @Test func filterCountsAllReturnsBaseCountWithoutCallingPredicate() {
        let base = [
            FixtureItem(status: "draft", urgent: false),
            FixtureItem(status: "submitted", urgent: true)
        ]
        var predicateCalls = 0

        let counts = filterCounts(base: base, keys: ["all"]) { _, _ in
            predicateCalls += 1
            return false
        }

        #expect(counts["all"] == 2)
        #expect(predicateCalls == 0)
    }

    @Test func filterCountsUsesPredicateAgainstAlreadyFilteredBase() {
        let searchedAndDatedBase = [
            FixtureItem(status: "draft", urgent: true),
            FixtureItem(status: "submitted", urgent: true),
            FixtureItem(status: "draft", urgent: true)
        ]

        let counts = filterCounts(base: searchedAndDatedBase, keys: ["all", "draft"]) { item, key in
            item.urgent && item.status == key
        }

        #expect(counts["all"] == 3)
        #expect(counts["draft"] == 2)
    }
}
