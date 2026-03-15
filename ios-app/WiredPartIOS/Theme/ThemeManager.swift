import SwiftUI
import WiredPartCore

/// Manages the app's visual theme by reading/writing `SettingsService.ThemeSettings`.
///
/// Published as an `@EnvironmentObject` or created on-demand in settings views.
/// Converts the stored hex primary color to a SwiftUI `Color` and maps the
/// stored mode string to the system's `ColorScheme`.
@MainActor
final class ThemeManager: ObservableObject {
    @Published var themeMode: String = "system"
    @Published var primaryColor: String = "#2563eb"
    @Published var fontFamily: String = "Inter"

    private let settingsService: SettingsService

    init(settingsService: SettingsService) {
        self.settingsService = settingsService
        load()
    }

    // MARK: - Load / Save

    func load() {
        do {
            let theme = try settingsService.getTheme()
            themeMode = theme.themeMode
            primaryColor = theme.primaryColor
            fontFamily = theme.fontFamily
        } catch {
            // Fall back to defaults silently
        }
    }

    func save() {
        let settings = SettingsService.ThemeSettings(
            themeMode: themeMode,
            primaryColor: primaryColor,
            fontFamily: fontFamily
        )
        do {
            _ = try settingsService.updateTheme(settings)
        } catch {
            // Silently fail — non-critical
        }
    }

    // MARK: - Computed Properties

    /// Resolved `ColorScheme` for the `.preferredColorScheme()` modifier.
    /// Returns nil for "system" (i.e. follow device setting).
    var resolvedColorScheme: ColorScheme? {
        switch themeMode {
        case "light": return .light
        case "dark": return .dark
        default: return nil
        }
    }

    /// SwiftUI Color derived from the hex string.
    var accentColor: Color {
        Color(hex: primaryColor) ?? .accentColor
    }
}

// MARK: - Hex Color Extension

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
