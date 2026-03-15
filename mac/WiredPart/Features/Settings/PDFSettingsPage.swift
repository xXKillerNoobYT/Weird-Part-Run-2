import SwiftUI
import WiredPartCore

/// PDF document settings page.
///
/// Fully functional — reads/writes PDF settings via SettingsService.
/// Controls: accent color, show unit prices, show extended, payment terms,
/// delivery notes, footer text.
struct PDFSettingsPage: View {
    @EnvironmentObject private var appCore: AppCore
    @State private var accentColor: String = "#2563eb"
    @State private var showUnitPrices: Bool = true
    @State private var showExtended: Bool = true
    @State private var paymentTerms: String = "Net 30"
    @State private var deliveryNotes: String = ""
    @State private var footerText: String = ""
    @State private var showSaved: Bool = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Text("PDF Settings")
                    .font(.largeTitle)
                    .fontWeight(.bold)

                Text("Configure how PDFs (purchase orders, invoices) are generated.")
                    .foregroundStyle(.secondary)

                GroupBox("Display Options") {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text("Accent Color")
                                .frame(width: 120, alignment: .leading)
                            TextField("#hex", text: $accentColor)
                                .textFieldStyle(.roundedBorder)
                                .frame(maxWidth: 120)
                            Circle()
                                .fill(ThemeManager.color(fromHex: accentColor))
                                .frame(width: 20, height: 20)
                        }
                        Toggle("Show Unit Prices", isOn: $showUnitPrices)
                        Toggle("Show Extended Prices", isOn: $showExtended)
                    }
                    .padding(.vertical, 4)
                }

                GroupBox("Document Content") {
                    VStack(alignment: .leading, spacing: 12) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Payment Terms")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            TextField("e.g. Net 30", text: $paymentTerms)
                                .textFieldStyle(.roundedBorder)
                        }
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Delivery Notes")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            TextEditor(text: $deliveryNotes)
                                .frame(height: 60)
                                .border(Color(.separatorColor))
                        }
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Footer Text")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            TextEditor(text: $footerText)
                                .frame(height: 60)
                                .border(Color(.separatorColor))
                        }
                    }
                    .padding(.vertical, 4)
                }

                HStack {
                    Button("Save") { save() }
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
        .task { loadSettings() }
    }

    private func loadSettings() {
        guard let settings = appCore.settingsService else { return }
        if let pdf = try? settings.getPDFSettings() {
            accentColor = pdf.accentColor
            showUnitPrices = pdf.showUnitPrices
            showExtended = pdf.showExtended
            paymentTerms = pdf.paymentTerms
            deliveryNotes = pdf.deliveryNotes
            footerText = pdf.footerText
        }
    }

    private func save() {
        guard let settings = appCore.settingsService else { return }
        let pdf = SettingsService.PDFSettings(
            accentColor: accentColor,
            showUnitPrices: showUnitPrices,
            showExtended: showExtended,
            footerText: footerText,
            paymentTerms: paymentTerms,
            deliveryNotes: deliveryNotes
        )
        _ = try? settings.updatePDFSettings(pdf)

        withAnimation { showSaved = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            withAnimation { showSaved = false }
        }
    }
}
