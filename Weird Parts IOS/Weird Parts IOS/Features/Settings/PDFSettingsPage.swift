import SwiftUI
import WiredPartCore

/// Fully functional PDF document settings page.
///
/// Reads and writes PDF template settings (accent color, show prices,
/// footer text, payment terms, delivery notes) via SettingsService.
struct PDFSettingsPage: View {
    @EnvironmentObject private var appCore: AppCore
    @Environment(\.dismiss) private var dismiss
    @State private var activeSheet: ActiveSheet?
    @State private var accentColor = "#2563eb"
    @State private var showUnitPrices = true
    @State private var showExtended = true
    @State private var footerText = ""
    @State private var paymentTerms = "Net 30"
    @State private var deliveryNotes = ""
    @State private var saved = false
    @State private var errorMessage: String?
    @State private var isDirty = false
    @State private var hasLoadedSettings = false
    @State private var showDiscardConfirmation = false

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
        // Fix #149: dismiss keyboard on scroll
        .scrollDismissesKeyboard(.interactively)
        .navigationTitle("PDF Settings")
        .navigationBarBackButtonHidden(isDirty)
        .toolbar {
            if isDirty {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        showDiscardConfirmation = true
                    } label: {
                        Label("Back", systemImage: "chevron.left")
                    }
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button { activeSheet = .help } label: {
                    Image(systemName: "questionmark.circle")
                }
                .accessibilityLabel("Help")
            }
        }
        .sheet(item: $activeSheet) { _ in
            Group {
                PageHelpSheet(title: "PDF Settings Help", sections: [
                    ("What This Page Does", "Customizes the appearance and content of generated PDF documents such as purchase orders and invoices. Controls accent color, price display, payment terms, and footer text."),
                    ("How to Use It", "Adjust display options, pick an accent color, set payment terms, and enter footer or delivery notes. Tap Save to apply changes to all future PDF exports."),
                ])
            }
            .presentationDetents([.medium, .large])
        }
        .task { loadPDFSettings() }
        .alert("Error", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("OK") { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
        .interactiveDismissDisabled(isDirty)
        .alert("Discard changes?", isPresented: $showDiscardConfirmation) {
            Button("Discard", role: .destructive) { dismiss() }
            Button("Keep Editing", role: .cancel) {}
        } message: {
            Text("You have unsaved changes that will be lost.")
        }
        .onChange(of: accentColor) { _, _ in markDirty() }
        .onChange(of: showUnitPrices) { _, _ in markDirty() }
        .onChange(of: showExtended) { _, _ in markDirty() }
        .onChange(of: footerText) { _, _ in markDirty() }
        .onChange(of: paymentTerms) { _, _ in markDirty() }
        .onChange(of: deliveryNotes) { _, _ in markDirty() }
    }

    private enum ActiveSheet: Identifiable {
        case help
        var id: String { "help" }
    }

    private func loadPDFSettings() {
        guard let service = appCore.settingsService else {
            errorMessage = "Settings service unavailable"
            return
        }
        hasLoadedSettings = false
        do {
            let pdf = try service.getPDFSettings()
            accentColor = pdf.accentColor
            showUnitPrices = pdf.showUnitPrices
            showExtended = pdf.showExtended
            footerText = pdf.footerText
            paymentTerms = pdf.paymentTerms
            deliveryNotes = pdf.deliveryNotes
            isDirty = false
            Task { @MainActor in
                hasLoadedSettings = true
            }
        } catch {
            errorMessage = userFriendlyError(error, context: "load")
        }
    }

    private func markDirty() {
        guard hasLoadedSettings else { return }
        isDirty = true
        saved = false
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
            isDirty = false
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(2))
                saved = false
            }
        } catch {
            errorMessage = userFriendlyError(error, context: "save")
        }
    }
}
