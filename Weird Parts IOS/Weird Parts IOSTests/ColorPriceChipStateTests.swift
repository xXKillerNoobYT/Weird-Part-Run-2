import Testing
@testable import Weird_Parts

struct ColorPriceChipStateTests {
    @MainActor
    @Test func colorPriceChipStatesPreserveResolutionFailures() async throws {
        let cache: [Int64: ColorPriceCacheEntry] = [
            1: .resolved(4.25),
            2: .resolved(nil),
            3: .unavailable
        ]

        #expect(CategoriesTreeView.priceChipState(for: 1, cache: cache) == .priced(4.25))
        #expect(CategoriesTreeView.priceChipState(for: 2, cache: cache) == .unpriced)
        #expect(CategoriesTreeView.priceChipState(for: 3, cache: cache) == .unavailable)
        #expect(CategoriesTreeView.priceChipState(for: 4, cache: cache) == .loading)
    }
}
