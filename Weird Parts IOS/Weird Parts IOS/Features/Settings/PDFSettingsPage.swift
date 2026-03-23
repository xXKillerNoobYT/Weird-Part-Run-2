import SwiftUI
import WiredPartCore

/// Fully functional PDF document settings page.
///
/// Reads and writes PDF template settings (accent color, show prices,
/// footer text, payment terms, delivery notes) via SettingsService.
struct PDFSettingsPage: View {
    @EnvironmentObject private var appCore: AppCore
    @State private var accentColor = "#2563eb"
    @State private var showUnitPrices = true
    @State private var showExtended = true
    @State private var footerText = ""
    @State private var paymentTerms = "Net 30"
    @State private var deliveryNotes = ""
    @State private var saved = false
    @State private var errorMessage: String?

    private let paymentOptions = ["Net 15", "Net 30", "Net 45", "Net 60", "Due on Receipt", "COD"]

    var body: some View {
        Form {
            Section("Display Options") {
                Toggle("Show Unit Prices", isOn: $showUnitPrices)
                Toggle("Show Extended Totals", isOn: $showExtended)
            }

            Section("Accent Color") {
                TextField("Hex Color (e.g. #2563eb)", text: $accentColor)
                    .monospaced()
                if let color = Color(hex: accentColor) {
                    HStack {
                        Text("Preview:")
                        RoundedRectangle(cornerRadius: 4)
                            .fill(color)
                            .frame(width: 40, height: 20)
                    }
                }
            }

            Section("Payment") {
                Picker("Payment Terms", selection: $paymentTerms) {
                    ForEach(paymentOptions, id: \.self) { option in
                        Text(option).tag(option)
                    }
                }
            }

            Section("Footer & Notes") {
                TextField("Footer Text", text: $footerText, axis: .vertical)
                    .lineLimit(3...6)
                TextField("Delivery Notes", text: $deliveryNotes, axis: .vertical)
                    .lineLimit(3...6)
            }

            Section {
                Button {
                    savePDFSettings()
                } label: {
                    HStack {
                        Spacer()
                        Text(saved ? "Saved!" : "Save PDF Settings")
                            .fontWeight(.semibold)
                        Spacer()
                    }
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .onAppear { loadPDFSettings() }
        .alert("Error", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("OK") { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private func loadPDFSettings() {
        guard let service = appCore.settingsService else {
            errorMessage = "Settings service unavailable"
            return
        }
        do {
            let pdf = try service.getPDFSettings()
            accentColor = pdf.accentColor
            showUnitPrices = pdf.showUnitPrices
            showExtended = pdf.showExtended
            footerText = pdf.footerText
            paymentTerms = pdf.paymentTerms
            deliveryNotes = pdf.deliveryNotes
        } catch {
            errorMessage = "Failed to load: \(error.localizedDescription)"
        }
    }

    private func savePDFSettings() {
        guard let service = appCore.settingsService else {
            errorMessage = "Settings service unavailable"
            return
        }
        let settings = SettingsService.PDFSettings(
            accentColor: accentColor,
            showUnitPrices: showUnitPrices,
            showExtended: showExtended,
            footerText: footerText,
            paymentTerms: paymentTerms,
            deliveryNotes: deliveryNotes
        )
        do {
            _ = try service.updatePDFSettings(settings)
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
