import SwiftUI

// MARK: - System Integration

/// Centralized checks for system accessibility and appearance settings.
/// Use these instead of querying environment values directly in every view.

enum DSSystem {

    // MARK: Reduce Motion

    /// Whether the user has enabled Reduce Motion in system settings.
    static var prefersReducedMotion: Bool {
        UIAccessibility.isReduceMotionEnabled
    }

    // MARK: Reduce Transparency

    /// Whether the user has enabled Reduce Transparency in system settings.
    static var prefersReducedTransparency: Bool {
        UIAccessibility.isReduceTransparencyEnabled
    }

    // MARK: Bold Text

    /// Whether the user has enabled Bold Text in system settings.
    static var prefersBoldText: Bool {
        UIAccessibility.isBoldTextEnabled
    }

    // MARK: Dynamic Type Category

    /// Current content size category from the trait collection.
    static var contentSizeCategory: UIContentSizeCategory {
        UIApplication.shared.preferredContentSizeCategory
    }

    /// Whether the user is using an accessibility-level text size (AX1-AX5).
    static var isAccessibilityTextSize: Bool {
        contentSizeCategory >= .accessibilityMedium
    }
}

// MARK: - Environment-Based Accessibility Modifier

/// A view modifier that adapts layout for accessibility text sizes.
/// When Dynamic Type is at an accessibility level, stacks switch from
/// horizontal to vertical to prevent clipping.
struct DSAdaptiveStack: ViewModifier {
    @Environment(\.dynamicTypeSize) private var typeSize

    let horizontalSpacing: CGFloat
    let verticalSpacing: CGFloat
    let horizontalAlignment: HorizontalAlignment
    let verticalAlignment: VerticalAlignment

    init(
        hSpacing: CGFloat = DS.Space.sm,
        vSpacing: CGFloat = DS.Space.xs,
        hAlign: HorizontalAlignment = .leading,
        vAlign: VerticalAlignment = .center
    ) {
        self.horizontalSpacing = hSpacing
        self.verticalSpacing = vSpacing
        self.horizontalAlignment = hAlign
        self.verticalAlignment = vAlign
    }

    func body(content: Content) -> some View {
        if typeSize.isAccessibilitySize {
            VStack(alignment: horizontalAlignment, spacing: verticalSpacing) {
                content
            }
        } else {
            HStack(alignment: verticalAlignment, spacing: horizontalSpacing) {
                content
            }
        }
    }
}

// MARK: - Reduce Transparency Aware Glass

/// A modifier that applies glass effect only when the system allows transparency.
/// Falls back to a standard card when Reduce Transparency is enabled.
struct DSTransparencyAwareGlass: ViewModifier {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    func body(content: Content) -> some View {
        if reduceTransparency {
            content.dsCard()
        } else {
            content.dsGlassCard()
        }
    }
}

// MARK: - Minimum Tap Target

/// Ensures the rendered accessibility hit area stays at least 44x44pt per Apple HIG.
/// On Catalyst this uses a larger logical frame so the scaled accessibility frame
/// still measures above the same floor.
struct DSMinimumTapTarget: ViewModifier {
    #if targetEnvironment(macCatalyst)
    /// Catalyst exposes SwiftUI frames in scaled AppKit accessibility points.
    /// Sixty logical points preserve a measured accessibility frame above 44pt.
    @ScaledMetric private var minSize: CGFloat = 60
    #else
    @ScaledMetric private var minSize: CGFloat = 44
    #endif

    func body(content: Content) -> some View {
        content
            .frame(minWidth: minSize, minHeight: minSize)
            .contentShape(Rectangle())
    }
}

// MARK: - View Extensions

extension View {
    /// Wraps content in an adaptive stack that switches from horizontal
    /// to vertical at accessibility text sizes.
    func dsAdaptiveStack(
        hSpacing: CGFloat = DS.Space.sm,
        vSpacing: CGFloat = DS.Space.xs,
        hAlign: HorizontalAlignment = .leading,
        vAlign: VerticalAlignment = .center
    ) -> some View {
        modifier(DSAdaptiveStack(
            hSpacing: hSpacing,
            vSpacing: vSpacing,
            hAlign: hAlign,
            vAlign: vAlign
        ))
    }

    /// Applies glass when transparency is allowed, falls back to solid card otherwise.
    func dsSmartGlass() -> some View {
        modifier(DSTransparencyAwareGlass())
    }

    /// Ensures the view meets the 44x44pt minimum tap target.
    func dsMinTapTarget() -> some View {
        modifier(DSMinimumTapTarget())
    }
}
