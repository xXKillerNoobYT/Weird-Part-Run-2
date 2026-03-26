import SwiftUI
import WiredPartCore

/// Fully functional theme settings page.
///
/// Reads and writes theme settings (mode, primary color, font family)
/// via the SettingsService.
struct ThemesPage: View {
    @EnvironmentObject private var appCore: AppCore
    @State private var activeSheet: ActiveSheet?
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
        .navigationTitle("Themes")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { activeSheet = .help } label: {
                    Image(systemName: "questionmark.circle")
                }
            }
        }
        .sheet(item: $activeSheet) { _ in
            PageHelpSheet(title: "Themes Help", sections: [
                ("What This Page Does", "Customizes the visual appearance of the app. Choose between light, dark, or system appearance mode, pick an accent color, and select a font family."),
                ("How to Use It", "Select a mode, tap a color preset, choose a font, then tap Save Theme. Changes apply across the entire app on this device."),
            ])
        }
        .onAppear { loadTheme() }
        .alert("Error", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("OK") { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private enum ActiveSheet: Identifiable {
        case help
        var id: String { "help" }
    }

    private func loadTheme() {
        guard let service = appCore.settingsService else {
            errorMessage = "Settings service unavailable"
            return
        }
        do {
            let theme = try service.getTheme()
            themeMode = theme.themeMode
            primaryColor = theme.primaryColor
            fontFamily = theme.fontFamily
        } catch {
            errorMessage = "Failed to load: \(error.localizedDescription)"
        }
    }

    private func saveTheme() {
        guard let service = appCore.settingsService else {
            errorMessage = "Settings service unavailable"
            return
        }
        let settings = SettingsService.ThemeSettings(
            themeMode: themeMode,
            primaryColor: primaryColor,
            fontFamily: fontFamily
        )
        do {
            _ = try service.updateTheme(settings)
            saved = true
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(2))
                saved = false
            }
        } catch {
            errorMessage = "Failed to save: \(error.localizedDescription)"
        }
    }
}
