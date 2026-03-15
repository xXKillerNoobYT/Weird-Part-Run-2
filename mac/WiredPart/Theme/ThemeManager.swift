import SwiftUI

/// Utility enum for theme-related conversions.
///
/// Converts between the string-based theme settings stored in GRDB
/// and the SwiftUI types used by the view layer.
enum ThemeManager {

    /// Map a theme mode string ("light", "dark", "system") to a SwiftUI ColorScheme.
    /// Returns nil for "system" so the OS preference is used.
    static func colorScheme(for mode: String) -> ColorScheme? {
        switch mode.lowercased() {
        case "light": return .light
        case "dark":  return .dark
        default:      return nil  // system
        }
    }

    /// Parse a hex color string (e.g. "#2563eb" or "2563eb") into a SwiftUI Color.
    /// Falls back to `.accentColor` on parse failure.
    static func color(fromHex hex: String) -> Color {
        var str = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if str.hasPrefix("#") { str.removeFirst() }
        guard str.count == 6, let rgb = UInt64(str, radix: 16) else {
            return .accentColor
        }
        return Color(
            red:   Double((rgb >> 16) & 0xFF) / 255.0,
            green: Double((rgb >> 8) & 0xFF)  / 255.0,
            blue:  Double(rgb & 0xFF)         / 255.0
        )
    }
}
