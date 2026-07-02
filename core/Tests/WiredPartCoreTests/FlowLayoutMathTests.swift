import Foundation
import CoreGraphics
import Testing
@testable import WiredPartCore

/// Regression tests for #1203 — custom flow layouts must never report a
/// non-finite measured size, even for unconstrained proposals.
@Suite("FlowLayoutMath Tests")
struct FlowLayoutMathTests {

    private let chip = CGSize(width: 60, height: 20)

    // MARK: - Unconstrained proposals (the #1203 bug)

    @Test("Nil proposal returns finite single-row content width")
    func testNilProposalIsFinite() {
        let result = FlowLayoutMath.layout(
            itemSizes: [chip, chip, chip],
            spacing: 10,
            proposedWidth: nil
        )
        #expect(result.size.width.isFinite)
        #expect(result.size.height.isFinite)
        // Single row: 60 + 10 + 60 + 10 + 60
        #expect(result.size == CGSize(width: 200, height: 20))
        #expect(result.origins == [
            CGPoint(x: 0, y: 0),
            CGPoint(x: 70, y: 0),
            CGPoint(x: 140, y: 0)
        ])
    }

    @Test("Infinite proposal returns finite single-row content width")
    func testInfiniteProposalIsFinite() {
        let result = FlowLayoutMath.layout(
            itemSizes: [chip, chip],
            spacing: 10,
            proposedWidth: .infinity
        )
        #expect(result.size.width.isFinite)
        #expect(result.size == CGSize(width: 130, height: 20))
    }

    @Test("NaN and non-positive proposals are treated as unconstrained")
    func testDegenerateProposals() {
        for proposal in [CGFloat.nan, 0, -100] {
            let result = FlowLayoutMath.layout(
                itemSizes: [chip, chip],
                spacing: 10,
                proposedWidth: proposal
            )
            #expect(result.size.width.isFinite)
            #expect(result.size == CGSize(width: 130, height: 20))
        }
    }

    // MARK: - Constrained wrapping

    @Test("Constrained proposal wraps items onto new rows")
    func testConstrainedWrapping() {
        // Two 60pt chips + spacing = 130 fits in 140; the third wraps.
        let result = FlowLayoutMath.layout(
            itemSizes: [chip, chip, chip],
            spacing: 10,
            proposedWidth: 140
        )
        #expect(result.size == CGSize(width: 140, height: 50))
        #expect(result.origins == [
            CGPoint(x: 0, y: 0),
            CGPoint(x: 70, y: 0),
            CGPoint(x: 0, y: 30)
        ])
    }

    @Test("Row height uses tallest item in the row")
    func testRowHeightUsesTallestItem() {
        let tall = CGSize(width: 60, height: 44)
        let result = FlowLayoutMath.layout(
            itemSizes: [chip, tall, chip],
            spacing: 10,
            proposedWidth: 140
        )
        // Row 1: chip + tall (height 44); row 2: chip (height 20).
        #expect(result.size == CGSize(width: 140, height: 44 + 10 + 20))
        #expect(result.origins[2] == CGPoint(x: 0, y: 54))
    }

    @Test("Item wider than the bound still gets placed on its own row")
    func testOversizedItem() {
        let wide = CGSize(width: 200, height: 20)
        let result = FlowLayoutMath.layout(
            itemSizes: [chip, wide],
            spacing: 10,
            proposedWidth: 100
        )
        #expect(result.origins == [
            CGPoint(x: 0, y: 0),
            CGPoint(x: 0, y: 30)
        ])
        #expect(result.size.width.isFinite)
        #expect(result.size.height == 50)
    }

    // MARK: - Edge cases

    @Test("Empty item list yields zero height and no origins")
    func testEmptyItems() {
        let bounded = FlowLayoutMath.layout(itemSizes: [], spacing: 8, proposedWidth: 320)
        #expect(bounded.size == CGSize(width: 320, height: 0))
        #expect(bounded.origins.isEmpty)

        let unbounded = FlowLayoutMath.layout(itemSizes: [], spacing: 8, proposedWidth: nil)
        #expect(unbounded.size == .zero)
        #expect(unbounded.origins.isEmpty)
    }

    @Test("resolveWrapWidth guards non-finite and non-positive values")
    func testResolveWrapWidth() {
        #expect(FlowLayoutMath.resolveWrapWidth(nil) == nil)
        #expect(FlowLayoutMath.resolveWrapWidth(.infinity) == nil)
        #expect(FlowLayoutMath.resolveWrapWidth(-.infinity) == nil)
        #expect(FlowLayoutMath.resolveWrapWidth(.nan) == nil)
        #expect(FlowLayoutMath.resolveWrapWidth(0) == nil)
        #expect(FlowLayoutMath.resolveWrapWidth(-1) == nil)
        #expect(FlowLayoutMath.resolveWrapWidth(320) == 320)
    }
}
