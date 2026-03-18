import SwiftUI

/// Design System semantic color palette.
///
/// Builds on SwiftUI's adaptive system colors. Never use raw hex values
/// (except the user's custom accent from settings). All colors adapt
/// automatically to light/dark mode and high contrast.
///
/// Usage:
///   .foregroundStyle(DS.SemanticColor.success)
///   .background(DS.SemanticColor.tint(.orange))
///   .foregroundStyle(DS.SemanticColor.jobStatus("active"))
extension DS {
    enum SemanticColor {
        // MARK: - Status Colors

        /// Positive outcomes: active, complete, received, in-stock
        static let success: Color = .green

        /// Attention needed: pending, expiring, approaching limit
        static let warning: Color = .orange

        /// Critical: overdue, failed, over-budget, deleted
        static let error: Color = .red

        /// Informational: new, info, default accent
        static let info: Color = .blue

        // MARK: - Tint Helpers

        /// 15% opacity background for status badges and chips.
        static func tint(_ color: Color) -> Color {
            color.opacity(0.15)
        }

        /// 6% opacity background for subtle stat cards.
        static func muted(_ color: Color) -> Color {
            color.opacity(0.06)
        }

        // MARK: - Entity Status Mapping

        /// Map a job status string to a semantic color.
        static func jobStatus(_ status: String) -> Color {
            switch status.lowercased() {
            case "active", "in_progress": return success
            case "pending", "submitted": return warning
            case "completed", "closed": return .secondary
            case "cancelled": return error
            default: return .secondary
            }
        }

        /// Map an order/PO status string to a semantic color.
        static func orderStatus(_ status: String) -> Color {
            switch status.lowercased() {
            case "draft": return .secondary
            case "submitted", "pending": return warning
            case "approved", "ordered": return info
            case "received": return success
            case "cancelled", "rejected": return error
            default: return .secondary
            }
        }

        /// Map a priority level to a semantic color.
        static func priority(_ level: String) -> Color {
            switch level.lowercased() {
            case "critical", "urgent": return error
            case "high": return warning
            case "medium", "normal": return info
            case "low": return .secondary
            default: return .secondary
            }
        }
    }

    // MARK: - Background Aliases

    enum Background {
        /// Page-level background (grouped tables, scroll views).
        static let page = Color(.systemGroupedBackground)

        /// Card / secondary container background.
        static let card = Color(.secondarySystemGroupedBackground)

        /// Nested / tertiary container background.
        static let nested = Color(.tertiarySystemGroupedBackground)
    }
}

// MARK: - Color Hex Initializer

extension Color {
    /// Create a Color from a hex string like "#2563eb" or "2563eb".
    init?(hex: String) {
        var cleaned = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleaned.hasPrefix("#") { cleaned.removeFirst() }
        guard cleaned.count == 6, let rgb = UInt64(cleaned, radix: 16) else { return nil }
        let r = Double((rgb >> 16) & 0xFF) / 255.0
        let g = Double((rgb >> 8) & 0xFF) / 255.0
        let b = Double(rgb & 0xFF) / 255.0
        self.init(red: r, green: g, blue: b)
    }
}
