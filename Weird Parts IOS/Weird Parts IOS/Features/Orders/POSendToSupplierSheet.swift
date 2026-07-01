import SwiftUI
import MessageUI
import WiredPartCore

// MARK: - POSendToSupplierSheet
//
// Full "Send to Supplier" flow for one or more Purchase Orders.
//
// ## What's here
//
//  ┌─ Request Type picker ─────────────────────────────────────────┐
//  │  [Order Request]  [Pricing / Quote Request]                    │
//  │  Sets email_request_type on all sent POs.                      │
//  └───────────────────────────────────────────────────────────────┘
//  ┌─ Grouping toggle ─────────────────────────────────────────────┐
//  │  OFF → single PO email (original behaviour)                   │
//  │  ON  → select sibling POs for same supplier → one combined     │
//  │        email with all PDFs attached, consolidated line list.   │
//  └───────────────────────────────────────────────────────────────┘
//
// ## Send flow
//  1. Pick request type + grouping.
//  2. Tap "Prep PDF & Open Mail" — generates PDF(s), opens Mail.
//  3. User reviews/sends. Falls back to share sheet if Mail unavailable.
//  4. Back in this sheet → "Confirm Sent" section appears.
//  5. Optional: supplier confirmation number.
//  6. Tap "Confirm Sent" → marks all included POs in DB → dismiss.

struct POSendToSupplierSheet: View {

    // The "primary" PO this sheet was opened from
    let po: OrdersService.PODetail
    let supplierContacts: [PartsService.SupplierContact]
    var onConfirmedSent: () -> Void

    @EnvironmentObject var appCore: AppCore
    @Environment(\.dismiss) var dismiss

    // MARK: - Request type

    enum EmailRequestType: String, CaseIterable, Identifiable {
        case order   = "order"
        case pricing = "pricing"
        var id: String { rawValue }
        var label: String {
            switch self {
            case .order:   return "Order Request"
            case .pricing: return "Pricing / Quote Request"
            }
        }
        var icon: String {
            switch self {
            case .order:   return "cart.fill"
            case .pricing: return "tag.fill"
            }
        }
        var color: Color {
            switch self {
            case .order:   return .blue
            case .pricing: return .orange
            }
        }
    }

    @State private var selectedRequestType: EmailRequestType = .order

    // MARK: - Grouping

    @State private var groupEnabled = false
    /// Other sendable POs for the same supplier, fetched lazily
    @State private var siblingPOs: [OrdersService.POListItem] = []
    @State private var siblingPOsLoading = false
    @State private var siblingPOsError: String?
    /// IDs of sibling POs the user has toggled ON to include
    @State private var includedSiblingIds: Set<Int64> = []

    // MARK: - Mail / PDF

    @State private var pdfData: Data?                    // primary PO pdf
    @State private var siblingPDFs: [Int64: Data] = [:]  // sibling id → pdf
    @State private var isGeneratingPDF = false
    @State private var pdfError: String?
    @State private var mailError: String?
    @State private var showMailComposer = false
    @State private var showShareSheet   = false
    @State private var shareItems: [Any] = []

    // MARK: - Confirmation

    @State private var showConfirmSent = false
    @State private var confirmationNum  = ""
    @State private var isSaving         = false
    @State private var saveError: String?

    // MARK: - Computed

    private var primaryEmail: String? {
        supplierContacts.first(where: { $0.isPrimary == 1 })?.email
            ?? supplierContacts.first?.email
    }

    private var includedPOs: [Int64] {
        // primary always included
        guard groupEnabled else { return [po.id] }
        return [po.id] + Array(includedSiblingIds)
    }

    private var includedSiblingPOs: [OrdersService.POListItem] {
        guard groupEnabled else { return [] }
        return siblingPOs.filter { includedSiblingIds.contains($0.id) }
    }

    private var relatedJobSummary: String? {
        var seen = Set<String>()
        let jobNames = po.lines.compactMap { line -> String? in
            guard let name = line.jobName?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !name.isEmpty,
                  !seen.contains(name)
            else { return nil }
            seen.insert(name)
            return name
        }

        guard !jobNames.isEmpty else { return nil }
        return jobNames.joined(separator: ", ")
    }

    private var emailSubject: String {
        let type = selectedRequestType == .pricing ? "Pricing Request" : "Purchase Order"
        let jobSuffix = relatedJobSummary.map { " — Job: \($0)" } ?? ""
        if groupEnabled && !includedSiblingIds.isEmpty {
            return "\(type) — \(po.supplierName) (\(includedPOs.count) orders)\(jobSuffix)"
        }
        return "\(type) \(po.poNumber) — \(po.supplierName)\(jobSuffix)"
    }

    private var emailBody: String {
        var lines: [String] = []
        lines.append("Dear \(po.supplierName),")
        lines.append("")

        if let relatedJobSummary {
            lines.append("Re: \(relatedJobSummary)")
            lines.append("")
        }

        if selectedRequestType == .pricing {
            lines.append("Please find attached our pricing request\(groupEnabled && !includedSiblingIds.isEmpty ? "s" : "") for the following items.")
            lines.append("We would appreciate your best pricing and availability at your earliest convenience.")
        } else {
            lines.append("Please find attached our purchase order\(groupEnabled && !includedSiblingIds.isEmpty ? "s" : "") for your review and processing.")
        }

        lines.append("")

        // Summary list of included POs
        let allPoNums = [po.poNumber] + includedSiblingPOs.map { $0.poNumber }
        if allPoNums.count > 1 {
            lines.append("Included orders:")
            allPoNums.forEach { lines.append("  • \($0)") }
            lines.append("")
        }

        if let delivery = po.expectedDelivery {
            lines.append("Requested delivery date: \(delivery)")
        }
        if let notes = po.notes, !notes.isEmpty {
            lines.append("Notes: \(notes)")
        }

        lines.append("")
        if selectedRequestType == .pricing {
            lines.append("Please reply with your quote at your earliest convenience.")
        } else {
            lines.append("Please confirm receipt and advise if any items require lead time beyond the requested date.")
        }
        lines.append("")
        lines.append("Thank you,")
        lines.append(appCore.currentUser?.displayName ?? "WiredPart Team")
        return lines.joined(separator: "\n")
    }

    private func pdfFileName(for poNumber: String) -> String {
        "\(selectedRequestType == .pricing ? "PricingRequest" : "PO")-\(poNumber.replacingOccurrences(of: "/", with: "-")).pdf"
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    requestTypeCard
                    groupingCard
                    if groupEnabled && !siblingPOs.isEmpty {
                        siblingSelectionCard
                    }
                    supplierCard
                    instructionsCard
                    actionArea
                    if showConfirmSent { confirmSentCard }
                }
                .padding()
                .animation(.easeInOut(duration: 0.2), value: groupEnabled)
                .animation(.easeInOut(duration: 0.2), value: showConfirmSent)
            }
            .navigationTitle("Send to Supplier")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .sheet(isPresented: $showMailComposer) { mailComposerView }
            .sheet(isPresented: $showShareSheet)   {
                ReportShareSheet(items: shareItems)
            }
            .alert("PDF Error", isPresented: Binding(
                get: { pdfError != nil }, set: { if !$0 { pdfError = nil } }
            )) { Button("OK") {} } message: { Text(pdfError ?? "") }
            .alert("Mail Error", isPresented: Binding(
                get: { mailError != nil }, set: { if !$0 { mailError = nil } }
            )) { Button("OK") {} } message: { Text(mailError ?? "") }
            .alert("Save Error", isPresented: Binding(
                get: { saveError != nil }, set: { if !$0 { saveError = nil } }
            )) { Button("OK") {} } message: { Text(saveError ?? "") }
            .task { loadInitialState() }
        }
    }

    // MARK: - Cards

    /// Request type selector — order vs pricing
    private var requestTypeCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Request Type", systemImage: "questionmark.circle.fill")
                .font(.headline)
            Text("What kind of email is this?")
                .font(.caption).foregroundStyle(.secondary)
            Divider()
            HStack(spacing: 10) {
                ForEach(EmailRequestType.allCases) { type in
                    requestTypeButton(type)
                }
            }
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func requestTypeButton(_ type: EmailRequestType) -> some View {
        let selected = selectedRequestType == type
        return Button {
            withAnimation(.easeInOut(duration: 0.15)) { selectedRequestType = type }
        } label: {
            VStack(spacing: 6) {
                Image(systemName: type.icon)
                    .font(.title2)
                    .foregroundStyle(selected ? .white : type.color)
                Text(type.label)
                    .font(.caption).fontWeight(.medium)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(selected ? .white : .primary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(selected ? type.color : type.color.opacity(0.10))
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(selected ? type.color : Color.clear, lineWidth: 2)
            )
        }
        .buttonStyle(.plain)
    }

    /// Grouping toggle
    private var groupingCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Email Grouping", systemImage: "tray.2.fill")
                .font(.headline)
            Divider()
            Toggle(isOn: $groupEnabled.animation()) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(groupEnabled ? "Grouped — one email for all selected POs" : "Individual — separate email per PO")
                        .font(.subheadline).fontWeight(.medium)
                    Text(groupEnabled
                         ? "All selected POs attach as separate PDFs in one email."
                         : "This PO sends as its own email with its own PDF.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .onChange(of: groupEnabled) { _, on in
                clearSiblingPOState()
                if on {
                    fetchSiblingPOs()
                }
            }

            if groupEnabled && siblingPOsLoading {
                HStack { ProgressView(); Text("Checking for other POs…").font(.caption).foregroundStyle(.secondary) }
            } else if groupEnabled, let siblingPOsError {
                Label(siblingPOsError, systemImage: "exclamationmark.triangle")
                    .font(.caption).foregroundStyle(.orange)
            } else if groupEnabled && siblingPOs.isEmpty {
                Label("No other draft or submitted POs for this supplier.", systemImage: "info.circle")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    /// Sibling PO checklist
    private var siblingSelectionCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Other POs to Include", systemImage: "checkmark.rectangle.stack")
                    .font(.headline)
                Spacer()
                Button(includedSiblingIds.count == siblingPOs.count ? "Deselect All" : "Select All") {
                    withAnimation {
                        if includedSiblingIds.count == siblingPOs.count {
                            includedSiblingIds = []
                        } else {
                            includedSiblingIds = Set(siblingPOs.map(\.id))
                        }
                    }
                }
                .font(.caption)
            }
            Text("Choose which POs to bundle into this email. Each gets its own PDF attachment.")
                .font(.caption).foregroundStyle(.secondary)
            Divider()

            // Primary PO (always included, non-toggleable)
            siblingRow(poNumber: po.poNumber, status: po.status,
                       lineCount: po.lines.count, total: po.totalCost,
                       isIncluded: true, isPrimary: true, id: po.id)

            ForEach(siblingPOs, id: \.id) { sibling in
                siblingRow(
                    poNumber: sibling.poNumber,
                    status: sibling.status,
                    lineCount: sibling.lineCount,
                    total: sibling.totalCost,
                    isIncluded: includedSiblingIds.contains(sibling.id),
                    isPrimary: false,
                    id: sibling.id
                )
            }
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func siblingRow(
        poNumber: String, status: String, lineCount: Int,
        total: Double?, isIncluded: Bool, isPrimary: Bool, id: Int64
    ) -> some View {
        HStack(spacing: 12) {
            if isPrimary {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.blue)
                    .font(.title3)
            } else {
                Button {
                    withAnimation {
                        if includedSiblingIds.contains(id) {
                            includedSiblingIds.remove(id)
                        } else {
                            includedSiblingIds.insert(id)
                        }
                    }
                } label: {
                    Image(systemName: isIncluded ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(isIncluded ? .blue : .secondary)
                        .font(.title3)
                }
                .buttonStyle(.plain)
            }

            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(poNumber).font(.subheadline).fontWeight(.medium)
                    if isPrimary {
                        Text("(this PO)").font(.caption2).foregroundStyle(.blue)
                    }
                    Spacer()
                    if let total {
                        Text(String(format: "$%.2f", total))
                            .font(.caption).fontWeight(.medium).foregroundStyle(.primary)
                    }
                }
                Text("\(lineCount) item\(lineCount == 1 ? "" : "s")  •  \(status.replacingOccurrences(of: "_", with: " ").capitalized)")
                    .font(.caption2).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }

    /// Supplier contacts summary
    private var supplierCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Supplier Contact", systemImage: "person.crop.circle")
                .font(.headline)
            Divider()
            if supplierContacts.isEmpty {
                Text("No contacts on file — you can still generate the PDF and send manually.")
                    .font(.caption).foregroundStyle(.orange)
            } else {
                ForEach(supplierContacts, id: \.contactId) { c in
                    HStack {
                        VStack(alignment: .leading, spacing: 1) {
                            Text("\(c.firstName) \(c.lastName)\(c.isPrimary == 1 ? " ★" : "")")
                                .font(.subheadline).fontWeight(c.isPrimary == 1 ? .bold : .regular)
                            if let e = c.email { Text(e).font(.caption).foregroundStyle(.blue) }
                        }
                        Spacer()
                    }
                }
            }
            if primaryEmail == nil {
                Label("No email on file — PDF will open via share sheet.", systemImage: "exclamationmark.triangle")
                    .font(.caption).foregroundStyle(.orange)
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
            // Dynamic instructions based on request type + grouping
            let typeStr = selectedRequestType == .pricing ? "pricing request" : "purchase order"
            let groupStr = (groupEnabled && !includedSiblingIds.isEmpty)
                ? "with \(includedSiblingIds.count + 1) PDFs attached (one per PO)"
                : "with the PO PDF attached"
            Text("1. Tap **Prep & Open Mail** to generate the PDF\(groupEnabled && !includedSiblingIds.isEmpty ? "s" : "") and open Mail with your \(typeStr) pre-filled \(groupStr).\n\n2. Review and send from Mail.\n\n3. Tap **Confirm Sent** here. The PO\(includedSiblingIds.isEmpty ? "" : "s") will advance to Ordered (or stay as-is for pricing requests).")
                .font(.caption).foregroundStyle(.secondary)
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var actionArea: some View {
        VStack(spacing: 12) {
            Button { prepAndSend() } label: {
                if isGeneratingPDF {
                    HStack { ProgressView(); Text("Generating PDF…") }
                        .frame(maxWidth: .infinity)
                } else {
                    Label("Prep\(groupEnabled && !includedSiblingIds.isEmpty ? " \(includedPOs.count) PDFs" : " PDF") & Open Mail",
                          systemImage: "envelope.badge.fill")
                        .frame(maxWidth: .infinity)
                }
            }
            .buttonStyle(.borderedProminent)
            .tint(selectedRequestType.color)
            .controlSize(.large)
            .disabled(isGeneratingPDF || siblingPOsLoading || (groupEnabled && siblingPOsError != nil))

            if !showConfirmSent {
                Button { withAnimation { showConfirmSent = true } } label: {
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
                .font(.headline).foregroundStyle(.green)
            Divider()

            // Summary of what will be marked
            let poCount = includedPOs.count
            Group {
                if selectedRequestType == .pricing {
                    Text("Confirm you sent the **pricing request** to **\(po.supplierName)**. The PO\(poCount > 1 ? "s" : "") will be recorded as sent but status stays as-is (pricing requests don't advance to Ordered).")
                } else {
                    Text("Confirm you sent **\(poCount) PO\(poCount > 1 ? "s" : "")** to **\(po.supplierName)**. Status will advance to **Ordered**.")
                }
            }
            .font(.caption).foregroundStyle(.secondary)

            TextField("Supplier confirmation # (optional)", text: $confirmationNum)
                .textFieldStyle(.roundedBorder)
                .autocorrectionDisabled()

            Button { confirmSent() } label: {
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
        if let primaryPDF = pdfData {
            let attachments: [(data: Data, mimeType: String, fileName: String)] = buildAttachments(primaryPDF: primaryPDF)
            MailComposerSheet(
                to: [primaryEmail].compactMap { $0 },
                subject: emailSubject,
                body: emailBody,
                attachments: attachments
            ) { result in
                handleMailComposerFinished(result)
            }
        }
    }

    private func handleMailComposerFinished(_ result: MFMailComposeResult) {
        showMailComposer = false

        switch result {
        case .sent:
            withAnimation { showConfirmSent = true }
        case .cancelled, .saved:
            break
        case .failed:
            mailError = "Mail did not send, so supplier confirmation was not opened automatically. Try sending again, use the share sheet fallback, or confirm manually only after verifying the supplier message was sent."
        @unknown default:
            mailError = "Mail finished with an unknown result, so supplier confirmation was not opened automatically. Verify the message was sent before confirming manually."
        }
    }

    private func buildAttachments(primaryPDF: Data) -> [(data: Data, mimeType: String, fileName: String)] {
        var result: [(data: Data, mimeType: String, fileName: String)] = [
            (primaryPDF, "application/pdf", pdfFileName(for: po.poNumber))
        ]
        for sibling in includedSiblingPOs {
            if let pdf = siblingPDFs[sibling.id] {
                result.append((pdf, "application/pdf", pdfFileName(for: sibling.poNumber)))
            }
        }
        return result
    }

    // MARK: - Data loading

    private func loadInitialState() {
        // Default request type from stored PO value if already set
        if po.emailRequestType == "pricing" {
            selectedRequestType = .pricing
        }
    }

    private func clearSiblingPOState() {
        siblingPOs = []
        includedSiblingIds = []
        siblingPDFs = [:]
        siblingPOsError = nil
        siblingPOsLoading = false
    }

    private func fetchSiblingPOs() {
        let supplierId = po.supplierId
        guard let svc = appCore.ordersService else {
            let message = "Orders service unavailable. Other POs for this supplier could not be checked."
            siblingPOsError = message
            pdfError = message
            return
        }
        siblingPOsError = nil
        siblingPOsLoading = true
        Task {
            do {
                let results = try svc.listSendablePOs(supplierId: supplierId, excludingId: po.id)
                await MainActor.run {
                    guard groupEnabled else { return }
                    siblingPOs = results
                    // Default: select all siblings
                    includedSiblingIds = Set(results.map(\.id))
                    siblingPOsError = nil
                    siblingPOsLoading = false
                }
            } catch {
                await MainActor.run {
                    guard groupEnabled else { return }
                    let message = "Could not check for other POs for this supplier. Grouped sending is blocked until the sibling lookup succeeds. Error: \(error.localizedDescription)"
                    siblingPOs = []
                    includedSiblingIds = []
                    siblingPOsLoading = false
                    siblingPOsError = message
                    pdfError = message
                }
            }
        }
    }

    // MARK: - PDF generation + send

    private func prepAndSend() {
        if groupEnabled, let siblingPOsError {
            pdfError = siblingPOsError
            return
        }

        isGeneratingPDF = true
        pdfError = nil
        Task {
            // Generate primary PO pdf
            let primaryGen = POPDFGenerator(po: po, supplierEmail: primaryEmail, companyName: "WiredPart")
            let primaryPDF = primaryGen.generatePDF()

            // Generate sibling PDFs if grouped
            var sibPDFs: [Int64: Data] = [:]
            if groupEnabled {
                guard let ordersService = appCore.ordersService else {
                    await MainActor.run {
                        isGeneratingPDF = false
                        pdfError = "Orders service unavailable. The selected sibling purchase orders could not be prepared."
                    }
                    return
                }

                var failedSiblings: [String] = []
                for sibling in includedSiblingPOs {
                    do {
                        let detail = try ordersService.getPODetail(id: sibling.id)
                        let gen = POPDFGenerator(po: detail, supplierEmail: primaryEmail, companyName: "WiredPart")
                        sibPDFs[sibling.id] = gen.generatePDF()
                    } catch {
                        failedSiblings.append("\(sibling.poNumber) (\(error.localizedDescription))")
                    }
                }

                if !failedSiblings.isEmpty {
                    await MainActor.run {
                        isGeneratingPDF = false
                        siblingPDFs = sibPDFs
                        pdfError = "One or more selected sibling purchase orders could not be prepared, so no partial supplier send was opened. Deselect the failed PO(s) or try again: \(failedSiblings.joined(separator: "; "))"
                    }
                    return
                }
            }

            await MainActor.run {
                pdfData = primaryPDF
                siblingPDFs = sibPDFs
                isGeneratingPDF = false

                if MFMailComposeViewController.isAvailableOnDevice {
                    showMailComposer = true
                } else {
                    // Share sheet fallback — share all PDFs
                    var urls: [URL] = []
                    let tmp = FileManager.default.temporaryDirectory
                    let allPDFs = [(primaryPDF, po.poNumber)] + includedSiblingPOs.compactMap { sibling in
                        sibPDFs[sibling.id].map { ($0, sibling.poNumber) }
                    }
                    do {
                        for (data, num) in allPDFs {
                            let url = tmp.appendingPathComponent(pdfFileName(for: num))
                            try data.write(to: url)
                            urls.append(url)
                        }
                        shareItems = urls
                        showShareSheet = true
                    } catch {
                        shareItems = []
                        pdfError = "Share sheet could not prepare every selected PO attachment, so no partial supplier share was opened. Error: \(error.localizedDescription)"
                    }
                }
            }
        }
    }

    // MARK: - Confirm send

    private func confirmSent() {
        guard let userId = appCore.currentUser?.id else { saveError = "No logged-in user."; return }
        guard let svc = appCore.ordersService else { saveError = "Orders service unavailable."; return }
        isSaving = true

        let groupId = (groupEnabled && includedPOs.count > 1) ? UUID().uuidString : nil
        let reqType = selectedRequestType.rawValue
        let confNum = confirmationNum.isEmpty ? nil : confirmationNum

        Task {
            do {
                try svc.markPOsSentToSupplier(
                    ids: includedPOs,
                    sentByUserId: userId,
                    confirmationNumber: confNum,
                    emailRequestType: reqType,
                    sendGroupId: groupId
                )
                await MainActor.run {
                    isSaving = false
                    dismiss()
                    onConfirmedSent()
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
