import SwiftUI
import WiredPartCore

/// Shared wrapping "flow" layout for chip rows.
///
/// Wraps children onto new rows when they would cross the proposed width.
/// All geometry goes through `FlowLayoutMath` (unit-tested in core), which
/// guarantees a finite measured size even for unconstrained proposals —
/// SwiftUI probes with `proposal.width == nil` / `.infinity`, and echoing
/// that back as the measured width breaks sheets and scroll views (#1203).
struct FlowChipLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        FlowLayoutMath.layout(
            itemSizes: subviews.map { $0.sizeThatFits(.unspecified) },
            spacing: spacing,
            proposedWidth: proposal.width
        ).size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let sizes = subviews.map { $0.sizeThatFits(.unspecified) }
        let result = FlowLayoutMath.layout(
            itemSizes: sizes,
            spacing: spacing,
            proposedWidth: bounds.width
        )
        for (index, origin) in result.origins.enumerated() {
            subviews[index].place(
                at: CGPoint(x: bounds.minX + origin.x, y: bounds.minY + origin.y),
                proposal: ProposedViewSize(sizes[index])
            )
        }
    }
}
