import Foundation
import CoreGraphics

/// Pure geometry for wrapping "flow" layouts (chip rows).
///
/// Shared by the app-side SwiftUI `Layout` adapters so every flow layout wraps
/// with the same rules and — critically — never reports a non-finite measured
/// size. SwiftUI probes custom layouts with unconstrained proposals
/// (`proposal.width == nil` or `.infinity`); naive implementations that echo
/// `proposal.width ?? .infinity` back as their measured width can overflow
/// sheets, break wrapping, or trip layout assertions (#1203).
public enum FlowLayoutMath {

    /// Result of a flow layout pass. All values are finite.
    public struct Result: Sendable, Equatable {
        /// Measured size: `width` is the resolved wrap bound when one exists,
        /// otherwise the single-row content width. Never infinite or NaN.
        public let size: CGSize
        /// Top-left origin for each item, in the same order as `itemSizes`.
        public let origins: [CGPoint]

        public init(size: CGSize, origins: [CGPoint]) {
            self.size = size
            self.origins = origins
        }
    }

    /// Resolve a proposed width into a usable wrap bound.
    ///
    /// Returns `nil` for unconstrained proposals — `nil`, non-finite (`.infinity`,
    /// NaN), or non-positive widths — meaning "lay out on a single row".
    public static func resolveWrapWidth(_ proposedWidth: CGFloat?) -> CGFloat? {
        guard let width = proposedWidth, width.isFinite, width > 0 else { return nil }
        return width
    }

    /// Compute wrapped positions for `itemSizes` against `proposedWidth`.
    ///
    /// Items flow left-to-right separated by `spacing`, wrapping to a new row
    /// when the next item would cross the wrap bound (an item wider than the
    /// bound still gets its own row rather than being dropped). Unconstrained
    /// proposals produce a single row whose finite content width is reported.
    public static func layout(
        itemSizes: [CGSize],
        spacing: CGFloat,
        proposedWidth: CGFloat?
    ) -> Result {
        let wrapWidth = resolveWrapWidth(proposedWidth)
        var origins: [CGPoint] = []
        origins.reserveCapacity(itemSizes.count)
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var contentWidth: CGFloat = 0

        for itemSize in itemSizes {
            if let wrapWidth, x + itemSize.width > wrapWidth, x > 0 {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            origins.append(CGPoint(x: x, y: y))
            rowHeight = max(rowHeight, itemSize.height)
            x += itemSize.width + spacing
            contentWidth = max(contentWidth, x - spacing)
        }

        let measuredWidth = wrapWidth ?? contentWidth
        let measuredHeight = itemSizes.isEmpty ? 0 : y + rowHeight
        return Result(
            size: CGSize(width: measuredWidth, height: measuredHeight),
            origins: origins
        )
    }
}
