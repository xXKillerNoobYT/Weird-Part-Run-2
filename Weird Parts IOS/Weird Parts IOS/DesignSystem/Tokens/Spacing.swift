import SwiftUI

/// Design System spacing scale.
///
/// Every explicit padding, gap, and margin value in the app should reference
/// these tokens instead of raw CGFloat literals. The scale is roughly
/// power-of-2 based, with practical sizes added where the math doesn't
/// produce a useful value.
///
/// Usage:
///   .padding(DS.Space.lg)
///   HStack(spacing: DS.Space.sm) { ... }
enum DS {
    enum Space {
        /// 2pt — tight inline gaps (e.g. between two tiny icons)
        static let xxxs: CGFloat = 2

        /// 4pt — icon-to-text gap, VStack tiny spacing
        static let xxs: CGFloat = 4

        /// 6pt — list row vertical inset, compact padding
        static let xs: CGFloat = 6

        /// 8pt — HStack item gaps, chip horizontal padding
        static let sm: CGFloat = 8

        /// 12pt — card internal spacing, grid gaps
        static let md: CGFloat = 12

        /// 16pt — standard padding, section gaps (SwiftUI default)
        static let lg: CGFloat = 16

        /// 20pt — VStack section spacing, content vertical padding
        static let xl: CGFloat = 20

        /// 24pt — between major sections
        static let xxl: CGFloat = 24

        /// 32pt — EmptyState horizontal inset, wide gutters
        static let xxxl: CGFloat = 32

        /// 40pt — large separators
        static let xxxxl: CGFloat = 40

        /// 48pt — icon sizes in empty/error states
        static let jumbo: CGFloat = 48
    }
}
