import SwiftUI
import WiredPartCore

/// Fully functional theme settings page.
///
/// Reads and writes theme settings (mode, primary color, font family)
/// via the SettingsService.
struct ThemesPage: View {
    @EnvironmentObject private var appCore: AppCore
    @State private var themeMode = "system"
    @State private var primaryColor = "#2563eb"
    @State private var fontFamily = "Inter"
    @State private var saved = false
    @State private var errorMessage: String?

    private let themeModes = ["system", "light", "dark"]
    private let colorPresets: [(String, String)] = [
        ("Blue", "#2563eb"),
        ("Green", "#16a34a"),
        ("Purple", "#7c3aed"),
        ("Red", "#dc2626"),
        ("Orange", "#ea580c"),
        ("Teal", "#0d9488"),
    ]
    private let fonts = ["Inter", "System", "SF Pro", "Menlo"]

    var body: some View {
        Form {
            Section("Appearance Mode") {
                Picker("Mode", selection: $themeMode) {
                    ForEach(themeModes, id: \.self) { mode in
                        Text(mode.capitalized).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
            }

            Section("Primary Color") {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 60))], spacing: 12) {
                    ForEach(colorPresets, id: \.1) { name, hex in
                        Button {
                            primaryColor = hex
                        } label: {
                            VStack(spacing: 4) {
                                Circle()
                                    .fill(Color(hex: hex) ?? .blue)
                                    .frame(width: 36, height: 36)
                                    .overlay(
                                        Circle()
                                            .strokeBorder(primaryColor == hex ? Color.primary : Color.clear, lineWidth: 2)
                                    )
                                Text(name)
                                    .font(.caption2)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.vertical, 4)
            }

            Section("Font Family") {
                Picker("Font", selection: $fontFamily) {
                    ForEach(fonts, id: \.self) { font in
                        Text(font).tag(font)
                    }
                }
            }

            Section {
                Button {
                    saveTheme()
                } label: {
                    HStack {
                        Spacer()
                        Text(saved ? "Saved!" : "Save Theme")
                            .fontWeight(.semibold)
                        Spacer()
                    }
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .onAppear { loadTheme() }
        .alert("Error", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("OK") { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private func loadTheme() {
        do {
            let theme = try appCore.settingsService.getTheme()
            themeMode = theme.themeMode
            primaryColor = theme.primaryColor
            fontFamily = theme.fontFamily
        } catch {
            print("[ThemesPage] Load error: \(error)")
        }
    }

    private func saveTheme() {
        let settings = SettingsService.ThemeSettings(
            themeMode: themeMode,
            primaryColor: primaryColor,
            fontFamily: fontFamily
        )
        do {
            _ = try appCore.settingsService.updateTheme(settings)
            saved = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { saved = false }
        } catch {
            errorMessage = "Failed to save: \(error.localizedDescription)"
        }
    }
}
