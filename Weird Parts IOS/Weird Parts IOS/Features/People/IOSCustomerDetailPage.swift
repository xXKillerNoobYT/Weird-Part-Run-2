import SwiftUI
import WiredPartCore

/// Customer detail page with full sections: contact, additional contacts, business,
/// billing (hat-gated), job history, communication history, documents, and lifetime stats.
struct IOSCustomerDetailPage: View {
    @EnvironmentObject private var appCore: AppCore
    let customer: PeopleService.CustomerListItem

    // MARK: - State

    @State private var detail: PeopleService.CustomerDetail?
    @State private var paymentStatus: PeopleService.PaymentStatus?
    @State private var paymentRecords: [PeopleService.PaymentRecord] = []
    @State private var paymentTrackingEnabled = false
    @State private var loadError: String?
    @State private var activeSheet: ActiveSheet?

    private enum ActiveSheet: Identifiable {
        case addContact
        case addNote
        case addPayment
        case help

        var id: String {
            switch self {
            case .addContact: return "addContact"
            case .addNote: return "addNote"
            case .addPayment: return "addPayment"
            case .help: return "help"
            }
        }
    }

    private var hasFinancials: Bool {
        appCore.hasPermission("view_job_financials")
    }

    var body: some View {
        Group {
            if let error = loadError {
                ErrorStateView(message: error) { loadData() }
            } else if let detail = detail {
                detailList(detail)
            } else {
                ProgressView("Loading customer...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .navigationTitle(customer.companyName ?? customer.contactName ?? "Customer")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { activeSheet = .help } label: {
                    Image(systemName: "questionmark.circle")
                }
                .accessibilityLabel("Help")
            }
        }
        .refreshable { loadData() }
        .task { loadData() }
        .sheet(item: $activeSheet) { sheet in
            switch sheet {
            case .addContact:
                AddCustomerContactSheet(customerId: customer.id) { loadData() }
                    .environmentObject(appCore)
            case .addNote:
                AddCommunicationSheet(customerId: customer.id) { loadData() }
                    .environmentObject(appCore)
            case .addPayment:
                AddPaymentSheet(customerId: customer.id) { loadData() }
                    .environmentObject(appCore)
            case .help:
                PageHelpSheet(
                    title: "Customer Detail Help",
                    sections: [
                        ("What This Page Does", "View all details for a single customer: contact info, additional contacts, business info, billing and payment status, job history, communication log, documents, and lifetime stats."),
                        ("Contacts", "The primary contact info shows phone (tappable to call), email (tappable to send), and address. The Additional Contacts section lets you add site contacts, billing contacts, or other people associated with this customer."),
                        ("Billing & Payment", "If you have financial permissions, the Billing section shows total revenue, average job size, and a payment status bar. When payment tracking is enabled, you can see individual invoices and record new payments."),
                        ("Communication Log", "Track calls, emails, meetings, and notes with timestamps and who recorded them. Use the Add Note button to log a new interaction."),
                        ("Tips", "Pull down to refresh. Phone numbers and emails are tappable links. The job history section shows all jobs for this customer with color-coded status badges. Lifetime stats at the bottom give you a quick snapshot of the relationship.")
                    ]
                )
            }
        }
    }

    // MARK: - Detail List

    private func detailList(_ detail: PeopleService.CustomerDetail) -> some View {
        List {
            // Contact Info
            Section {
                if let phone = detail.phone, !phone.isEmpty {
                    let digits = phone.filter(\.isNumber)
                    HStack {
                        Text("Phone").foregroundStyle(.secondary)
                        Spacer()
                        if let url = URL(string: "tel:\(digits)") {
                            Link(phone, destination: url)
                        } else {
                            Text(phone)
                        }
                    }
                }
                if let email = detail.email, !email.isEmpty,
                   let encoded = email.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
                   let url = URL(string: "mailto:\(encoded)") {
                    HStack {
                        Text("Email").foregroundStyle(.secondary)
                        Spacer()
                        Link(email, destination: url)
                    }
                }
                if let address = detail.address, !address.isEmpty {
                    LabeledContent("Address", value: address)
                }
            } header: {
                Text("Contact Info")
            }

            // Additional Contacts
            Section {
                if detail.contacts.isEmpty {
                    Text("No additional contacts")
                        .foregroundStyle(.secondary)
                        .font(.caption)
                } else {
                    ForEach(detail.contacts) { contact in
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 6) {
                                Text(contact.name).font(.headline)
                                if let role = contact.role, !role.isEmpty {
                                    Text(role)
                                        .font(.caption)
                                        .foregroundStyle(.white)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 1)
                                        .background(Capsule().fill(Color.accentColor))
                                }
                            }
                            if let phone = contact.phone, !phone.isEmpty {
                                Label(phone, systemImage: "phone")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            if let email = contact.email, !email.isEmpty {
                                Label(email, systemImage: "envelope")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                Button { activeSheet = .addContact } label: {
                    Label("Add Contact", systemImage: "person.badge.plus")
                }
            } header: {
                Text("Additional Contacts (\(detail.contacts.count))")
            }

            // Business Info
            Section {
                if let company = detail.companyName, !company.isEmpty {
                    LabeledContent("Company", value: company)
                }
                if let type = detail.customerType, !type.isEmpty {
                    LabeledContent("Type", value: type.capitalized)
                }
            } header: {
                Text("Business Info")
            }

            // Billing & Payment (hat-gated)
            if hasFinancials {
                Section {
                    if let revenue = detail.stats.totalRevenue {
                        LabeledContent("Total Revenue", value: formatCurrency(revenue))
                    }
                    if let avg = detail.stats.averageJobSize {
                        LabeledContent("Avg Job Size", value: formatCurrency(avg))
                    }

                    if paymentTrackingEnabled, let status = paymentStatus {
                        PaymentStatusBar(status: status)
                    }

                    if paymentTrackingEnabled {
                        ForEach(paymentRecords) { record in
                            HStack {
                                VStack(alignment: .leading) {
                                    Text(record.invoiceNumber ?? "Invoice")
                                    Text(record.dueDate)
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                VStack(alignment: .trailing) {
                                    Text(formatCurrency(record.amount))
                                    Text(record.status.capitalized)
                                        .font(.caption)
                                        .foregroundStyle(record.status == "overdue" ? .red : record.status == "paid" ? .green : .orange)
                                }
                            }
                        }
                        Button { activeSheet = .addPayment } label: {
                            Label("Record Payment", systemImage: "dollarsign.circle")
                        }
                    }
                } header: {
                    Text("Billing & Payment")
                }
            }

            // Job History
            Section {
                if detail.jobHistory.isEmpty {
                    Text("No jobs yet")
                        .foregroundStyle(.secondary)
                        .font(.caption)
                } else {
                    ForEach(detail.jobHistory) { job in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(job.name).font(.headline)
                                Text(job.jobNumber)
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            StatusBadge(
                                text: job.status.replacingOccurrences(of: "_", with: " ").capitalized,
                                color: statusColor(job.status)
                            )
                        }
                    }
                }
            } header: {
                HStack {
                    Text("Job History")
                    Spacer()
                    Text("\(detail.stats.totalJobs) total")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }

            // Communication History
            Section {
                if detail.communicationLog.isEmpty {
                    Text("No notes yet")
                        .foregroundStyle(.secondary)
                        .font(.caption)
                } else {
                    ForEach(detail.communicationLog) { entry in
                        VStack(alignment: .leading, spacing: 2) {
                            HStack {
                                Image(systemName: commIcon(entry.commType))
                                    .foregroundStyle(.blue)
                                    .accessibilityHidden(true)
                                Text(entry.commType.capitalized)
                                    .font(.caption).bold()
                                Spacer()
                                Text(entry.createdAt)
                                    .font(.caption2).foregroundStyle(.secondary)
                            }
                            Text(entry.content)
                                .font(.caption)
                            Text("by \(entry.createdBy)")
                                .font(.caption2).foregroundStyle(.tertiary)
                        }
                    }
                }
                Button { activeSheet = .addNote } label: {
                    Label("Add Note", systemImage: "square.and.pencil")
                }
            } header: {
                Text("Communication History")
            }

            // Documents
            Section {
                Text("Contracts, proposals, and documents")
                    .foregroundStyle(.secondary)
                    .font(.caption)
            } header: {
                Text("Documents")
            }

            // Lifetime Stats
            Section {
                LabeledContent("Total Jobs", value: "\(detail.stats.totalJobs)")
                LabeledContent("Active", value: "\(detail.stats.activeJobs)")
                LabeledContent("Completed", value: "\(detail.stats.completedJobs)")
                if let first = detail.stats.firstJobDate, !first.isEmpty {
                    LabeledContent("Customer Since", value: first)
                }
            } header: {
                Text("Lifetime Stats")
            }
        }
        // Fix #149: dismiss keyboard when scrolling customer detail
        .scrollDismissesKeyboard(.interactively)
        .listStyle(.insetGrouped)
    }

    // MARK: - Helpers

    private func commIcon(_ type: String) -> String {
        switch type {
        case "call": return "phone.fill"
        case "email": return "envelope.fill"
        case "meeting": return "person.2.fill"
        default: return "note.text"
        }
    }

    private func statusColor(_ status: String) -> Color {
        switch status {
        case "active": return .green
        case "completed": return .blue
        case "on_hold": return .orange
        default: return .secondary
        }
    }

    private func formatCurrency(_ value: Double) -> String {
        Formatters.formatCurrency(value)
    }

    private func loadData() {
        guard let service = appCore.peopleService else {
            loadError = "Service unavailable"
            return
        }
        loadError = nil
        do {
            detail = try service.getCustomerDetail(customerId: customer.id, includeFinancials: hasFinancials)
            paymentTrackingEnabled = (try? service.isPaymentTrackingEnabled()) ?? false
            if paymentTrackingEnabled && hasFinancials {
                paymentStatus = try? service.getCustomerPaymentStatus(customerId: customer.id)
                paymentRecords = (try? service.getPaymentRecords(customerId: customer.id)) ?? []
            }
        } catch {
            loadError = userFriendlyError(error, context: "load customer details")
        }
    }
}

// MARK: - Payment Status Bar

struct PaymentStatusBar: View {
    let status: PeopleService.PaymentStatus

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Payment Status")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                Text("\(Int(status.paymentPercent * 100))% paid")
                    .font(.caption).bold()
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(barColor.opacity(0.2))
                    RoundedRectangle(cornerRadius: 4)
                        .fill(barColor)
                        .frame(width: geo.size.width * min(status.paymentPercent, 1.0))
                }
            }
            .frame(height: 8)

            if status.isOverdue {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                        .accessibilityHidden(true)
                    Text("Overdue: \(formatCurrency(status.totalOverdue))")
                        .font(.caption).foregroundStyle(.red)
                    if let days = status.oldestOverdueDays {
                        Text("(\(days) days)")
                            .font(.caption2).foregroundStyle(.red)
                    }
                }
            }
        }
    }

    private var barColor: Color {
        if status.paymentPercent >= 0.9 { return .green }
        if status.paymentPercent >= 0.5 { return .yellow }
        return .red
    }

    private func formatCurrency(_ value: Double) -> String {
        Formatters.formatCurrency(value)
    }
}

// MARK: - Add Customer Contact Sheet

private struct AddCustomerContactSheet: View {
    @EnvironmentObject private var appCore: AppCore
    @Environment(\.dismiss) private var dismiss

    let customerId: Int64
    let onSave: () -> Void

    @State private var firstName = ""
    @State private var lastName = ""
    @State private var role = ""
    @State private var phone = ""
    @State private var email = ""
    @State private var errorMessage: String?
    @State private var isSaving = false
    @State private var isDirty = false
    @State private var showDiscardAlert = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Contact") {
                    TextField("First Name", text: $firstName)
                        .textContentType(.givenName)
                        .onChange(of: firstName) { _, _ in isDirty = true }
                    TextField("Last Name", text: $lastName)
                        .textContentType(.familyName)
                        .onChange(of: lastName) { _, _ in isDirty = true }
                    TextField("Role (e.g. Site Contact, Billing)", text: $role)
                        .onChange(of: role) { _, _ in isDirty = true }
                }
                Section("Details") {
                    TextField("Phone", text: $phone)
                        .textContentType(.telephoneNumber)
                        .keyboardType(.phonePad)
                        .onChange(of: phone) { _, _ in isDirty = true }
                    TextField("Email", text: $email)
                        .textContentType(.emailAddress)
                        .keyboardType(.emailAddress)
                        .autocapitalization(.none)
                        .onChange(of: email) { _, _ in isDirty = true }
                }
                if let error = errorMessage {
                    Section {
                        Text(error).foregroundStyle(.red).font(.caption)
                    }
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle("Add Contact")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        if isDirty { showDiscardAlert = true } else { dismiss() }
                    }
                        .disabled(isSaving)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(firstName.trimmingCharacters(in: .whitespaces).isEmpty || isSaving)
                }
            }
            .alert("Discard changes?", isPresented: $showDiscardAlert) {
                Button("Discard", role: .destructive) { dismiss() }
                Button("Keep Editing", role: .cancel) {}
            } message: {
                Text("Your unsaved changes will be lost.")
            }
        }
        .interactiveDismissDisabled(isDirty || isSaving)
    }

    private func save() {
        isSaving = true
        defer { isSaving = false }
        guard let service = appCore.peopleService else {
            errorMessage = "Service unavailable"
            return
        }
        do {
            try service.createContact(
                entityType: "customer",
                entityId: customerId,
                firstName: firstName.trimmingCharacters(in: .whitespaces),
                lastName: lastName.trimmingCharacters(in: .whitespaces),
                role: role.isEmpty ? "contact" : role,
                phone: phone,
                email: email.isEmpty ? nil : email
            )
            isDirty = false
            dismiss()
            onSave()
        } catch {
            errorMessage = userFriendlyError(error, context: "load customer")
        }
    }
}

// MARK: - Add Communication Sheet

private struct AddCommunicationSheet: View {
    @EnvironmentObject private var appCore: AppCore
    @Environment(\.dismiss) private var dismiss

    let customerId: Int64
    let onSave: () -> Void

    @State private var commType = "note"
    @State private var content = ""
    @State private var errorMessage: String?
    @State private var isSaving = false
    @State private var isDirty = false
    @State private var showDiscardAlert = false

    private let typeOptions = ["note", "call", "email", "meeting"]

    var body: some View {
        NavigationStack {
            Form {
                Section("Type") {
                    Picker("Type", selection: $commType) {
                        ForEach(typeOptions, id: \.self) { t in
                            Text(t.capitalized).tag(t)
                        }
                    }
                    .pickerStyle(.segmented)
                    .onChange(of: commType) { _, _ in isDirty = true }
                }
                Section("Details") {
                    TextField("Notes", text: $content, axis: .vertical)
                        .lineLimit(3...8)
                        .onChange(of: content) { _, _ in isDirty = true }
                }
                if let error = errorMessage {
                    Section {
                        Text(error).foregroundStyle(.red).font(.caption)
                    }
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle("Add Note")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        if isDirty { showDiscardAlert = true } else { dismiss() }
                    }
                        .disabled(isSaving)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(content.trimmingCharacters(in: .whitespaces).isEmpty || isSaving)
                }
            }
            .alert("Discard changes?", isPresented: $showDiscardAlert) {
                Button("Discard", role: .destructive) { dismiss() }
                Button("Keep Editing", role: .cancel) {}
            } message: {
                Text("Your unsaved changes will be lost.")
            }
        }
        .interactiveDismissDisabled(isDirty || isSaving)
    }

    private func save() {
        isSaving = true
        defer { isSaving = false }
        guard let service = appCore.peopleService else {
            errorMessage = "Service unavailable"
            return
        }
        guard let userId = appCore.currentUser?.id else {
            errorMessage = "Not logged in. Please log in and try again."
            return
        }
        do {
            try service.addCommunicationEntry(
                customerId: customerId,
                commType: commType,
                content: content.trimmingCharacters(in: .whitespaces),
                createdBy: userId
            )
            isDirty = false
            dismiss()
            onSave()
        } catch {
            errorMessage = userFriendlyError(error, context: "load customer")
        }
    }
}

// MARK: - Add Payment Sheet

private struct AddPaymentSheet: View {
    @EnvironmentObject private var appCore: AppCore
    @Environment(\.dismiss) private var dismiss

    let customerId: Int64
    let onSave: () -> Void

    @State private var amountText = ""
    @State private var invoiceNumber = ""
    @State private var dueDate = Date().addingTimeInterval(30 * 86400)
    @State private var errorMessage: String?
    @State private var isSaving = false
    @State private var isDirty = false
    @State private var showDiscardAlert = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Invoice") {
                    TextField("Invoice Number", text: $invoiceNumber)
                        .onChange(of: invoiceNumber) { _, _ in isDirty = true }
                    TextField("Amount", text: $amountText)
                        .keyboardType(.decimalPad)
                        .onChange(of: amountText) { _, _ in isDirty = true }
                    DatePicker("Due Date", selection: $dueDate, displayedComponents: .date)
                        .onChange(of: dueDate) { _, _ in isDirty = true }
                }
                if let error = errorMessage {
                    Section {
                        Text(error).foregroundStyle(.red).font(.caption)
                    }
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle("Add Invoice")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        if isDirty { showDiscardAlert = true } else { dismiss() }
                    }
                        .disabled(isSaving)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(amountText.isEmpty || isSaving)
                }
            }
            .alert("Discard changes?", isPresented: $showDiscardAlert) {
                Button("Discard", role: .destructive) { dismiss() }
                Button("Keep Editing", role: .cancel) {}
            } message: {
                Text("Your unsaved changes will be lost.")
            }
        }
        .interactiveDismissDisabled(isDirty || isSaving)
    }

    private func save() {
        isSaving = true
        defer { isSaving = false }
        guard let service = appCore.peopleService else {
            errorMessage = "Service unavailable"
            return
        }
        guard let amount = Double(amountText), amount > 0 else {
            errorMessage = "Enter a valid amount"
            return
        }
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        let dueDateStr = f.string(from: dueDate)

        guard let userId = appCore.currentUser?.id else {
            errorMessage = "Not logged in. Please log in and try again."
            return
        }
        do {
            try service.createPaymentRecord(
                customerId: customerId,
                jobId: nil,
                amount: amount,
                dueDate: dueDateStr,
                invoiceNumber: invoiceNumber.isEmpty ? nil : invoiceNumber,
                createdBy: userId
            )
            isDirty = false
            dismiss()
            onSave()
        } catch {
            errorMessage = userFriendlyError(error, context: "load customer")
        }
    }
}
