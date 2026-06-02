import SwiftUI
import MessageUI

// MARK: - POSendToSupplierSheet

/// The full "Prep & Send to Supplier" flow for a Purchase Order.
///
/// Flow:
///   1. Sheet opens showing PO summary and supplier contact info.
///   2. User taps "Prep PDF & Open Mail" → generates PDF, pre-fills Mail with
///      the supplier's primary email, subject, and a body template.
///   3. User reviews/edits and sends from Mail.
///   4. Mail dismisses back to this sheet; a confirmation prompt appears.
///   5. User optionally enters a supplier confirmation number, then taps
///      "Confirm Sent" → calls OrdersService.markPOSentToSupplier → closes sheet.
///
/// If Mail is unavailable (simulator / no account configured) a Share Sheet
/// is offered instead so the PDF can be AirDropped, saved, or sent another way.
struct POSendToSupplierSheet: View {

    let po: OrdersService.PODetail
    let supplierContacts: [PartsService.SupplierContact]
    var onConfirmedSent: () -> Void     // called after DB is updated

    @EnvironmentObject var appCore: AppCore
    @Environment(\.dismiss) var dismiss

    // MARK: - State
    @State private var pdfData: Data?
    @State private var isGeneratingPDF = false
    @State private var pdfError: String?

    @State private var showMailComposer = false
    @State private var showShareSheet   = false
    @State private var shareURL: URL?

    /// After mail is sent (or skipped), show the "Confirm Sent" prompt
    @State private var showConfirmSent   = false
    @State private var confirmationNum   = ""
    @State private var isSaving          = false
    @State private var saveError: String?

    // MARK: - Computed

    private var primaryEmail: String? {
        supplierContacts.first(where: { $0.isPrimary == 1 })?.email
            ?? supplierContacts.first?.email
    }

    private var pdfFileName: String {
        "PO-\(po.poNumber.replacingOccurrences(of: "/", with: "-")).pdf"
    }

    private var emailSubject: String {
        "Purchase Order \(po.poNumber) — \(po.supplierName)"
    }

    private var emailBody: String {
        var lines: [String] = []
        lines.append("Dear \(po.supplierName),")
        lines.append("")
        lines.append("Please find attached Purchase Order \(po.poNumber).")
        lines.append("")
        if let delivery = po.expectedDelivery {
            lines.append("Requested delivery date: \(delivery)")
        }
        if let notes = po.notes, !notes.isEmpty {
            lines.append("Notes: \(notes)")
        }
        lines.append("")
        lines.append("Please confirm receipt of this order and advise if any items require lead time beyond the requested date.")
        lines.append("")
        lines.append("Thank you,")
        lines.append(appCore.currentUser?.displayName ?? "WiredPart Team")
        return lines.joined(separator: "\n")
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    poSummaryCard
                    supplierCard
                    instructionsCard
                    actionArea
                    if showConfirmSent { confirmSentCard }
                }
                .padding()
            }
            .navigationTitle("Send to Supplier")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .sheet(isPresented: $showMailComposer) { mailComposerView }
            .sheet(isPresented: $showShareSheet)   { shareSheetView }
            .alert("PDF Error", isPresented: Binding(
                get: { pdfError != nil }, set: { if !$0 { pdfError = nil } }
            )) { Button("OK") { pdfError = nil } } message: { Text(pdfError ?? "") }
            .alert("Save Error", isPresented: Binding(
                get: { saveError != nil }, set: { if !$0 { saveError = nil } }
            )) { Button("OK") { saveError = nil } } message: { Text(saveError ?? "") }
        }
    }

    // MARK: - Cards

    private var poSummaryCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Purchase Order", systemImage: "doc.text.fill")
                .font(.headline)
            Divider()
            infoRow("PO Number",  po.poNumber)
            infoRow("Supplier",   po.supplierName)
            infoRow("Status",     po.status.replacingOccurrences(of: "_", with: " ").capitalized)
            if let date = po.orderDate      { infoRow("Order Date", date) }
            if let del  = po.expectedDelivery { infoRow("Expected By", del) }
            if let total = po.totalCost {
                infoRow("Total", String(format: "$%.2f", total))
            }
            infoRow("Line Items", "\(po.lines.count) item(s)")
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var supplierCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Supplier Contact", systemImage: "person.crop.circle")
                .font(.headline)
            Divider()
            if supplierContacts.isEmpty {
                Text("No contacts on file for this supplier.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(supplierContacts, id: \.contactId) { c in
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(c.firstName) \(c.lastName)\(c.isPrimary == 1 ? " (Primary)" : "")")
                            .font(.subheadline).bold()
                        if let email = c.email {
                            Text(email).font(.caption).foregroundStyle(.blue)
                        }
                        if let phone = c.phone {
                            Text(phone).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }
            if primaryEmail == nil {
                Label("No email on file — you can still generate the PDF and send manually.", systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var instructionsCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("How This Works", systemImage: "info.circle")
                .font(.headline)
            Divider()
            Text("1. Tap **Prep PDF & Open Mail** to generate the PO as a PDF and open it in the Mail app with the supplier's email, subject, and a message pre-filled.\n\n2. Review the email, attach any extra files if needed, then tap **Send** in Mail.\n\n3. Return here and tap **Confirm Sent to Supplier** to record the transmission in WiredPart. The PO status will advance to Ordered.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var actionArea: some View {
        VStack(spacing: 12) {
            Button {
                prepAndSend()
            } label: {
                if isGeneratingPDF {
                    ProgressView().tint(.white)
                } else {
                    Label("Prep PDF & Open Mail", systemImage: "envelope.badge.fill")
                        .frame(maxWidth: .infinity)
                }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(isGeneratingPDF)

            if !showConfirmSent {
                Button {
                    withAnimation { showConfirmSent = true }
                } label: {
                    Label("I Already Sent It — Confirm", systemImage: "checkmark.seal")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .tint(.green)
            }
        }
    }

    @ViewBuilder
    private var confirmSentCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Confirm Sent to Supplier", systemImage: "checkmark.circle.fill")
                .font(.headline)
                .foregroundStyle(.green)
            Divider()
            Text("Once you tap **Confirm**, WiredPart records the send time and advances this PO to **Ordered** status.")
                .font(.caption)
                .foregroundStyle(.secondary)

            TextField("Supplier confirmation # (optional)", text: $confirmationNum)
                .textFieldStyle(.roundedBorder)
                .autocorrectionDisabled()

            Button {
                confirmSent()
            } label: {
                if isSaving {
                    ProgressView().tint(.white)
                } else {
                    Label("Confirm Sent to Supplier", systemImage: "checkmark.circle.fill")
                        .frame(maxWidth: .infinity)
                }
            }
            .buttonStyle(.borderedProminent)
            .tint(.green)
            .controlSize(.large)
            .disabled(isSaving)
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    // MARK: - Mail / Share views

    @ViewBuilder
    private var mailComposerView: some View {
        if let pdf = pdfData {
            MailComposerSheet(
                to: [primaryEmail].compactMap { $0 },
                subject: emailSubject,
                body: emailBody,
                attachments: [(data: pdf, mimeType: "application/pdf", fileName: pdfFileName)]
            ) { result in
                showMailComposer = false
                // Any result (sent, saved, cancelled) prompts the confirm step
                withAnimation { showConfirmSent = true }
            }
        }
    }

    @ViewBuilder
    private var shareSheetView: some View {
        if let url = shareURL {
            ReportShareSheet(items: [url])
        }
    }

    // MARK: - Helpers

    private func infoRow(_ label: String, _ value: String) -> some View {
        HStack(alignment: .top) {
            Text(label + ":").font(.caption).foregroundStyle(.secondary).frame(width: 90, alignment: .leading)
            Text(value).font(.caption).foregroundStyle(.primary)
            Spacer()
        }
    }

    private func prepAndSend() {
        isGeneratingPDF = true
        pdfError = nil
        Task {
            let generator = POPDFGenerator(
                po: po,
                supplierEmail: primaryEmail,
                companyName: "WiredPart"
            )
            let data = generator.generatePDF()
            await MainActor.run {
                pdfData = data
                isGeneratingPDF = false
                if MFMailComposeViewController.isAvailableOnDevice {
                    showMailComposer = true
                } else {
                    // Fallback: share sheet (AirDrop, Files, etc.)
                    let url = FileManager.default.temporaryDirectory
                        .appendingPathComponent(pdfFileName)
                    do {
                        try data.write(to: url)
                        shareURL = url
                        showShareSheet = true
                    } catch {
                        pdfError = "Could not write PDF: \(error.localizedDescription)"
                    }
                }
            }
        }
    }

    private func confirmSent() {
        guard let userId = appCore.currentUser?.id else {
            saveError = "No logged-in user found."
            return
        }
        guard let svc = appCore.ordersService else {
            saveError = "Orders service unavailable."
            return
        }
        isSaving = true
        Task {
            do {
                try svc.markPOSentToSupplier(
                    id: po.id,
                    sentByUserId: userId,
                    confirmationNumber: confirmationNum.isEmpty ? nil : confirmationNum
                )
                await MainActor.run {
                    isSaving = false
                    onConfirmedSent()
                    dismiss()
                }
            } catch {
                await MainActor.run {
                    isSaving = false
                    saveError = "Failed to record send: \(error.localizedDescription)"
                }
            }
        }
    }
}
