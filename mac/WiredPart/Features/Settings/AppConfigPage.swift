import SwiftUI
import WiredPartCore

/// App configuration page.
///
/// Fully functional — reads/writes warranty settings via SettingsService.
/// - Warranty days input with preset buttons (90, 182, 365, 730)
struct AppConfigPage: View {
    @EnvironmentObject private var appCore: AppCore
    @State private var warrantyDays: Int = 365
    @State private var warrantyText: String = "365"
    @State private var showSaved: Bool = false

    private let presets: [(label: String, days: Int)] = [
        ("90 days",  90),
        ("6 months", 182),
        ("1 year",   365),
        ("2 years",  730),
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Text("App Configuration")
                    .font(.largeTitle)
                    .fontWeight(.bold)

                GroupBox("Default Warranty Period") {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Set the default warranty length applied to new parts and orders.")
                            .font(.callout)
                            .foregroundStyle(.secondary)

                        HStack(spacing: 8) {
                            ForEach(presets, id: \.days) { preset in
                                Button(preset.label) {
                                    warrantyDays = preset.days
                                    warrantyText = String(preset.days)
                                }
                                .buttonStyle(.bordered)
                                .tint(warrantyDays == preset.days ? .accentColor : nil)
                            }
                        }

                        HStack {
                            TextField("Days", text: $warrantyText)
                                .textFieldStyle(.roundedBorder)
                                .frame(maxWidth: 100)
                                .onChange(of: warrantyText) { _, newValue in
                                    if let days = Int(newValue), days > 0 {
                                        warrantyDays = days
                                    }
                                }
                            Text("days")
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 4)
                }

                HStack {
                    Button("Save") {
                        save()
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
        .task { loadConfig() }
    }

    private func loadConfig() {
        guard let settings = appCore.settingsService else { return }
        if let days = try? settings.getWarrantyLengthDays() {
            warrantyDays = days
            warrantyText = String(days)
        }
    }

    private func save() {
        guard let settings = appCore.settingsService else { return }
        try? settings.updateWarrantyLengthDays(warrantyDays)

        withAnimation { showSaved = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            withAnimation { showSaved = false }
        }
    }
}
