import SwiftUI
import WiredPartCore

/// Theme customization page.
///
/// Fully functional — reads/writes theme settings via SettingsService.
/// - Theme mode picker (light / dark / system)
/// - Accent color grid (8 presets + custom hex)
/// - Font family picker
struct ThemesPage: View {
    @EnvironmentObject private var appCore: AppCore
    @State private var themeMode: String = "system"
    @State private var primaryColor: String = "#2563eb"
    @State private var fontFamily: String = "Inter"
    @State private var customHex: String = ""
    @State private var showSaved: Bool = false

    private let presetColors: [(name: String, hex: String)] = [
        ("Blue",    "#2563eb"),
        ("Purple",  "#7c3aed"),
        ("Green",   "#059669"),
        ("Red",     "#dc2626"),
        ("Orange",  "#ea580c"),
        ("Pink",    "#db2777"),
        ("Teal",    "#0d9488"),
        ("Slate",   "#475569"),
    ]

    private let fontOptions = ["Inter", "SF Pro", "SF Mono", "Menlo", "Helvetica Neue", "System"]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Text("Themes")
                    .font(.largeTitle)
                    .fontWeight(.bold)

                // Theme Mode
                GroupBox("Appearance") {
                    VStack(alignment: .leading, spacing: 12) {
                        Picker("Theme Mode", selection: $themeMode) {
                            Text("Light").tag("light")
                            Text("Dark").tag("dark")
                            Text("System").tag("system")
                        }
                        .pickerStyle(.segmented)
                        .frame(maxWidth: 300)
                    }
                    .padding(.vertical, 4)
                }

                // Accent Color
                GroupBox("Accent Color") {
                    VStack(alignment: .leading, spacing: 12) {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 44))], spacing: 8) {
                            ForEach(presetColors, id: \.hex) { preset in
                                colorSwatch(hex: preset.hex, label: preset.name)
                            }
                        }

                        HStack {
                            Text("Custom:")
                                .font(.caption)
                            TextField("#hex", text: $customHex)
                                .textFieldStyle(.roundedBorder)
                                .frame(maxWidth: 120)
                            Button("Apply") {
                                let hex = customHex.hasPrefix("#") ? customHex : "#\(customHex)"
                                if hex.count == 7 {
                                    primaryColor = hex
                                }
                            }
                            .disabled(customHex.isEmpty)
                        }
                    }
                    .padding(.vertical, 4)
                }

                // Font Family
                GroupBox("Font") {
                    Picker("Font Family", selection: $fontFamily) {
                        ForEach(fontOptions, id: \.self) { font in
                            Text(font).tag(font)
                        }
                    }
                    .frame(maxWidth: 300)
                    .padding(.vertical, 4)
                }

                // Save
                HStack {
                    Button("Save Theme") {
                        saveTheme()
                    }
                    .buttonStyle(.borderedProminent)

                    if showSaved {
                        Label("Saved", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                            .font(.caption)
                            .transition(.opacity)
                    }
                }
            }
            .padding(24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .task { loadTheme() }
    }

    private func colorSwatch(hex: String, label: String) -> some View {
        let isSelected = primaryColor.lowercased() == hex.lowercased()
        return Button {
            primaryColor = hex
        } label: {
            VStack(spacing: 4) {
                Circle()
                    .fill(ThemeManager.color(fromHex: hex))
                    .frame(width: 32, height: 32)
                    .overlay(
                        Circle()
                            .stroke(isSelected ? Color.primary : Color.clear, lineWidth: 2)
                            .padding(-2)
                    )
                Text(label)
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
            }
        }
        .buttonStyle(.plain)
    }

    private func loadTheme() {
        guard let settings = appCore.settingsService else { return }
        if let theme = try? settings.getTheme() {
            themeMode = theme.themeMode
            primaryColor = theme.primaryColor
            fontFamily = theme.fontFamily
        }
    }

    private func saveTheme() {
        guard let settings = appCore.settingsService else { return }
        let theme = SettingsService.ThemeSettings(
            themeMode: themeMode,
            primaryColor: primaryColor,
            fontFamily: fontFamily
        )
        _ = try? settings.updateTheme(theme)
        appCore.updateTheme()

        withAnimation { showSaved = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            withAnimation { showSaved = false }
        }
    }
}
