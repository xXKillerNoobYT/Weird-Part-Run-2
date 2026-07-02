import SwiftUI
import WiredPartCore

/// Suppliers management page showing all suppliers with contact info and scores.
///
/// Searchable list with supplier cards showing contact details, delivery info,
/// and quality scores. Supports create, edit, delete via sheets and swipe actions.
struct PartsSuppliersPage: View {
    @EnvironmentObject private var appCore: AppCore
    @State private var suppliers: [SupplierListRow] = []
    @State private var isLoading = true
    @State private var loadError: String?
    @State private var searchText = ""
    // Single active-sheet enum to avoid multiple .sheet conflicts
    enum ActiveSheet: Identifiable {
        case addSupplier
        case addSupplierBrands(Int64)
        case supplierDetail(SupplierListRow)
        case editSupplier(SupplierListRow)
        case help

        var id: String {
            switch self {
            case .addSupplier: return "addSupplier"
            case .addSupplierBrands(let supplierId): return "addSupplierBrands-\(supplierId)"
            case .supplierDetail(let s): return "detail-\(s.id)"
            case .editSupplier(let s): return "edit-\(s.id)"
            case .help: return "help"
            }
        }
    }

    @State private var activeSheet: ActiveSheet?
    @State private var pendingAddBrandsSupplierId: Int64?
    @State private var filterActive: Bool? = true
    @State private var supplierToDelete: SupplierListRow?
    @State private var showDeleteConfirm = false
    @State private var deleteError: String?
    @State private var sortOption: SupplierSortOption = .nameAsc

    enum SupplierSortOption: String, CaseIterable {
        case nameAsc = "Name A→Z"
        case nameDesc = "Name Z→A"
        case qualityDesc = "Quality ↓"
        case onTimeDesc = "On-Time ↓"
        case reliabilityDesc = "Reliability ↓"
        case partCountDesc = "Most Parts"
        case recentlyAdded = "Recently Added"
    }

    var body: some View {
        VStack(spacing: 0) {
            OnboardingBanner(pageId: "parts-suppliers")

            // Active/All toggle + sort
            HStack {
                Picker("Filter", selection: Binding(
                    get: { filterActive ?? false ? 0 : 1 },
                    set: { filterActive = $0 == 0 ? true : nil }
                )) {
                    Text("Active").tag(0)
                    Text("All").tag(1)
                }
                .pickerStyle(.segmented)

                Menu {
                    ForEach(SupplierSortOption.allCases, id: \.self) { option in
                        Button {
                            sortOption = option
                        } label: {
                            if sortOption == option {
                                Label(option.rawValue, systemImage: "checkmark")
                            } else {
                                Text(option.rawValue)
                            }
                        }
                    }
                } label: {
                    Image(systemName: "arrow.up.arrow.down")
                        .frame(width: 44, height: 44)
                        .accessibilityLabel("Sort suppliers")
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)

            if isLoading {
                ProgressView("Loading suppliers...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error = loadError {
                ErrorStateView(message: error) { Task { await loadData() } }
            } else if filteredSuppliers.isEmpty {
                emptyState
            } else {
                suppliersList
            }
        }
        .searchable(text: $searchText, prompt: "Search suppliers...")
        .onChange(of: searchText) { _, _ in postSuppliersContext() }
        .refreshable { await loadData() }
        .toolbar {
            ToolbarItem(placement: .automatic) {
                Button { activeSheet = .addSupplier } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("Add supplier")
            }
            ToolbarItem(placement: .primaryAction) {
                Button { activeSheet = .help } label: {
                    Image(systemName: "questionmark.circle")
                }
                .accessibilityLabel("Help")
            }
        }
        .sheet(item: $activeSheet) { sheet in
            switch sheet {
            case .addSupplier:
                SupplierFormSheet(
                    supplier: nil,
                    onSave: { await loadData() },
                    onAddBrands: { supplierId in
                        presentAddBrandsPicker(for: supplierId)
                    }
                )
                .environmentObject(appCore)
            case .addSupplierBrands(let supplierId):
                SupplierBrandPickerSheet(supplierId: supplierId) {
                    await loadData()
                }
                .environmentObject(appCore)
            case .supplierDetail(let supplier):
                SupplierDetailSheet(supplier: supplier, onEdit: {
                    activeSheet = .editSupplier(supplier)
                }, onUpdate: { await loadData() })
            case .editSupplier(let supplier):
                SupplierFormSheet(
                    supplier: supplier,
                    onSave: { await loadData() },
                    onAddBrands: nil
                )
                .environmentObject(appCore)
            case .help:
                PageHelpSheet(
                    title: "Suppliers Help",
                    sections: [
                        ("Overview", "Manage your supplier directory. View quality ratings, on-time delivery scores, and the number of parts each supplier provides."),
                        ("Adding Suppliers", "Tap + to add a new supplier with contact info, terms, and delivery preferences."),
                        ("Sorting & Filtering", "Sort by name, quality, on-time rate, or reliability. Use search to find specific suppliers quickly.")
                    ]
                )
            }
        }
        .onChange(of: activeSheet?.id) { _, sheetId in
            guard sheetId == nil, let supplierId = pendingAddBrandsSupplierId else { return }
            pendingAddBrandsSupplierId = nil
            activeSheet = .addSupplierBrands(supplierId)
        }
        .background(DS.Background.page)
        .task {
            await loadData()
            appCore.onboardingManager?.markCompleted("suppliers-view")
        }
        .onAppear { postSuppliersContext() }
        .onDisappear {
            NotificationCenter.default.post(name: .suppliersPageInactive, object: nil)
        }
        .alert("Delete Supplier?", isPresented: $showDeleteConfirm) {
            Button("Cancel", role: .cancel) { supplierToDelete = nil }
            Button("Delete", role: .destructive) {
                if let supplier = supplierToDelete {
                    Task { await deleteSupplier(supplier) }
                }
            }
        } message: {
            if let supplier = supplierToDelete {
                Text("Delete \"\(supplier.name)\"? This cannot be undone.")
            }
        }
    }

    // MARK: - Filtered

    private func presentAddBrandsPicker(for supplierId: Int64) {
        if activeSheet == nil {
            activeSheet = .addSupplierBrands(supplierId)
        } else {
            pendingAddBrandsSupplierId = supplierId
        }
    }

    private var filteredSuppliers: [SupplierListRow] {
        var result = suppliers
        if let active = filterActive, active {
            result = result.filter { $0.isActive == 1 }
        }
        if !searchText.isEmpty {
            let query = searchText.lowercased()
            result = result.filter {
                $0.name.lowercased().contains(query) ||
                ($0.contactName?.lowercased().contains(query) ?? false) ||
                ($0.email?.lowercased().contains(query) ?? false) ||
                ($0.phone?.lowercased().contains(query) ?? false) ||
                ($0.accountNumber?.lowercased().contains(query) ?? false)
            }
        }
        switch sortOption {
        case .nameAsc: result.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        case .nameDesc: result.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedDescending }
        case .qualityDesc: result.sort { ($0.qualityScore ?? 0) > ($1.qualityScore ?? 0) }
        case .onTimeDesc: result.sort { ($0.onTimeRate ?? 0) > ($1.onTimeRate ?? 0) }
        case .reliabilityDesc: result.sort { ($0.reliabilityScore ?? 0) > ($1.reliabilityScore ?? 0) }
        case .partCountDesc: result.sort { $0.partCount > $1.partCount }
        case .recentlyAdded: result.sort { $0.id > $1.id }
        }
        return result
    }

    // MARK: - Suppliers List

    @ViewBuilder
    private var suppliersList: some View {
        List {
            if let error = deleteError {
                Section {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                        .font(.caption)
                }
            }

            Section {
                Text("\(filteredSuppliers.count) supplier\(filteredSuppliers.count == 1 ? "" : "s")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            ForEach(filteredSuppliers) { supplier in
                Button {
                    activeSheet = .supplierDetail(supplier)
                } label: {
                    supplierRow(supplier)
                }
                .buttonStyle(.plain)
                .swipeActions(edge: .trailing) {
                    Button(role: .destructive) {
                        supplierToDelete = supplier
                        showDeleteConfirm = true
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                    Button {
                        activeSheet = .editSupplier(supplier)
                    } label: {
                        Label("Edit", systemImage: "pencil")
                    }
                    .tint(.blue)
                }
            }
        }
        .listStyle(.insetGrouped)
    }

    @ViewBuilder
    private func supplierRow(_ supplier: SupplierListRow) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "building.2.fill")
                .foregroundStyle(supplier.isActive == 1 ? Color.accentColor : .secondary)
                .font(.title3)
                .frame(width: 40, height: 40)
                .background(Color(.tertiarySystemGroupedBackground))
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(supplier.name)
                        .font(.body)
                        .fontWeight(.medium)
                    if supplier.isActive != 1 {
                        Text("Inactive")
                            .font(.caption2)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.red.opacity(0.1))
                            .foregroundStyle(.red)
                            .clipShape(Capsule())
                    }
                }

                HStack(spacing: 8) {
                    if let contact = supplier.contactName, !contact.isEmpty {
                        Label(contact, systemImage: "person.fill")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if let phone = supplier.phone, !phone.isEmpty {
                        Button {
                            let cleaned = phone.replacingOccurrences(of: "[^0-9+]", with: "", options: .regularExpression)
                            if let url = URL(string: "tel:\(cleaned)") {
                                UIApplication.shared.open(url)
                            }
                        } label: {
                            Label(phone, systemImage: "phone.fill")
                                .font(.caption)
                                .foregroundStyle(.blue)
                        }
                        .buttonStyle(.plain)
                    }
                }

                if let acct = supplier.accountNumber, !acct.isEmpty {
                    Label("Acct: \(acct)", systemImage: "number")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if supplier.brandCount == 0 {
                    Label("No brands", systemImage: "exclamationmark.triangle.fill")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                } else {
                    Text("\(supplier.brandCount) brand\(supplier.brandCount == 1 ? "" : "s")")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            // Quality score indicator
            if let score = supplier.qualityScore, score > 0 {
                VStack(alignment: .trailing, spacing: 2) {
                    Text(String(format: "%.0f", score))
                        .font(.subheadline)
                        .fontWeight(.bold)
                        .foregroundStyle(scoreColor(score))
                    Text("quality")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .accessibilityHidden(true)
        }
        .frame(minHeight: 60)
    }

    private func scoreColor(_ score: Double) -> Color {
        if score >= 80 { return .green }
        if score >= 60 { return .orange }
        return .red
    }

    // MARK: - Empty State

    @ViewBuilder
    private var emptyState: some View {
        let isSearching = !searchText.isEmpty
        return VStack(spacing: 16) {
            Image(systemName: isSearching ? "magnifyingglass" : "building.2")
                .decorativeIconFont(48)
                .foregroundStyle(.secondary)
            Text(isSearching ? "No Results" : "No Suppliers Yet")
                .font(.title3)
                .fontWeight(.semibold)
            Text(isSearching
                 ? "Try a different search term."
                 : "Add suppliers to track your parts sources and pricing.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            if !isSearching {
                Button {
                    activeSheet = .addSupplier
                } label: {
                    Label("Add Supplier", systemImage: "plus.circle.fill")
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Data Loading

    @Sendable
    private func loadData() async {
        isLoading = true
        do {
            guard let service = appCore.partsService else {
                isLoading = false
                loadError = "App not ready"
                return
            }
            let results = try service.listSuppliers()
            let rows = results.map { item in
                let s = item.supplier
                return SupplierListRow(
                    id: s.id ?? 0,
                    name: s.name,
                    contactName: s.contactName,
                    email: s.email,
                    phone: s.phone,
                    address: s.address,
                    website: s.website,
                    repName: s.repName,
                    repEmail: s.repEmail,
                    repPhone: s.repPhone,
                    notes: s.notes,
                    deliveryMethod: s.deliveryMethod,
                    deliveryDays: s.deliveryDays,
                    accountNumber: s.accountNumber,
                    onTimeRate: s.onTimeRate,
                    qualityScore: s.qualityScore,
                    reliabilityScore: s.reliabilityScore,
                    isActive: s.isActive ?? 1,
                    brandCount: item.brandCount,
                    partCount: item.partCount
                )
            }
            suppliers = rows
            isLoading = false
        } catch {
            loadError = userFriendlyError(error, context: "load suppliers")
            isLoading = false
        }
    }

    // MARK: - AI Context

    private func postSuppliersContext() {
        guard let service = appCore.partsService else {
            loadError = "Parts service not available"
            return
        }
        let context: String
        do {
            context = try service.buildSupplierAIContext()
        } catch {
            context = "" // AI context non-critical; panel will work without it
        }
        let searchableContext = context + " Supplier page search text is \(searchText.isEmpty ? "empty" : "active"); visible suppliers: \(filteredSuppliers.count) of \(suppliers.count)."
        NotificationCenter.default.post(
            name: .suppliersPageActive,
            object: nil,
            userInfo: ["context": searchableContext]
        )
    }

    // MARK: - Delete

    private func deleteSupplier(_ supplier: SupplierListRow) async {
        do {
            guard let service = appCore.partsService else {
                deleteError = "Service not available"
                return
            }
            try service.deleteSupplier(id: supplier.id)
            supplierToDelete = nil
            deleteError = nil
            await loadData()
        } catch {
            deleteError = userFriendlyError(error, context: "load suppliers")
        }
    }
}

// MARK: - Supplier List Row

struct SupplierListRow: Identifiable, Sendable {
    let id: Int64
    let name: String
    let contactName: String?
    let email: String?
    let phone: String?
    let address: String?
    let website: String?
    let repName: String?
    let repEmail: String?
    let repPhone: String?
    let notes: String?
    let deliveryMethod: String?
    let deliveryDays: String?
    let accountNumber: String?
    let onTimeRate: Double?
    let qualityScore: Double?
    let reliabilityScore: Double?
    let isActive: Int
    let brandCount: Int
    let partCount: Int
}

// MARK: - Supplier Form Sheet

private struct SupplierFormSheet: View {
    let supplier: SupplierListRow?
    let onSave: () async -> Void
    let onAddBrands: ((Int64) -> Void)?
    @EnvironmentObject private var appCore: AppCore
    @Environment(\.dismiss) private var dismiss

    // Basic info
    @State private var name = ""
    @State private var accountNumber = ""
    @State private var isActive = true

    // Main contact
    @State private var contactName = ""
    @State private var email = ""
    @State private var phone = ""
    @State private var address = ""
    @State private var website = ""

    // Sales rep
    @State private var repName = ""
    @State private var repEmail = ""
    @State private var repPhone = ""

    // Delivery
    @State private var deliveryMethod = ""
    @State private var deliveryDays = ""

    // Notes
    @State private var notes = ""

    // Save state
    @State private var saveError: String?
    @State private var isSaving = false
    @State private var showAddBrandsPrompt = false
    @State private var newSupplierId: Int64?

    private let deliveryMethods = ["", "Pickup", "Delivery", "UPS", "FedEx", "USPS", "Freight", "Will Call", "Other"]

    var body: some View {
        NavigationStack {
            Form {
                if let error = saveError {
                    Section {
                        Label(error, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                            .font(.subheadline)
                    }
                }

                Section("Supplier Details") {
                    TextField("Supplier Name *", text: $name)
                        .frame(minHeight: 44)
                    TextField("Account Number", text: $accountNumber)
                        .frame(minHeight: 44)
                    if supplier != nil {
                        Toggle("Active", isOn: $isActive)
                    }
                }

                Section("Main Contact") {
                    TextField("Contact Name", text: $contactName)
                        .frame(minHeight: 44)
                    TextField("Email", text: $email)
                        .frame(minHeight: 44)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                    TextField("Phone", text: $phone)
                        .frame(minHeight: 44)
                        .keyboardType(.phonePad)
                    TextField("Address", text: $address)
                        .frame(minHeight: 44)
                    TextField("Website", text: $website)
                        .frame(minHeight: 44)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                }

                Section("Sales Representative") {
                    TextField("Rep Name", text: $repName)
                        .frame(minHeight: 44)
                    TextField("Rep Email", text: $repEmail)
                        .frame(minHeight: 44)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                    TextField("Rep Phone", text: $repPhone)
                        .frame(minHeight: 44)
                        .keyboardType(.phonePad)
                }

                Section("Delivery Info") {
                    Picker("Delivery Method", selection: $deliveryMethod) {
                        ForEach(deliveryMethods, id: \.self) { method in
                            Text(method.isEmpty ? "Not Set" : method).tag(method)
                        }
                    }
                    TextField("Delivery Days (e.g. Mon-Fri, Next Day)", text: $deliveryDays)
                        .frame(minHeight: 44)
                }

                Section("Notes") {
                    TextField("Notes (optional)", text: $notes, axis: .vertical)
                        .lineLimit(3...6)
                        .frame(minHeight: 80)
                }
            }
            .navigationTitle(supplier == nil ? "New Supplier" : "Edit Supplier")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        Task { await saveAndDismiss() }
                    } label: {
                        if isSaving { ProgressView() } else { Text("Save") }
                    }
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSaving)
                }
            }
            .onAppear {
                if let s = supplier {
                    name = s.name
                    accountNumber = s.accountNumber ?? ""
                    isActive = s.isActive == 1
                    contactName = s.contactName ?? ""
                    email = s.email ?? ""
                    phone = s.phone ?? ""
                    address = s.address ?? ""
                    website = s.website ?? ""
                    repName = s.repName ?? ""
                    repEmail = s.repEmail ?? ""
                    repPhone = s.repPhone ?? ""
                    deliveryMethod = s.deliveryMethod ?? ""
                    deliveryDays = s.deliveryDays ?? ""
                    notes = s.notes ?? ""
                }
            }
            .alert("Add Brands?", isPresented: $showAddBrandsPrompt) {
                Button("Add Brands") {
                    Task {
                        let supplierId = newSupplierId
                        dismiss()
                        await onSave()
                        if let supplierId {
                            await MainActor.run {
                                onAddBrands?(supplierId)
                            }
                        }
                    }
                }
                Button("Skip", role: .cancel) {
                    Task {
                        dismiss()
                        await onSave()
                    }
                }
            } message: {
                Text("Link brands this supplier carries. You can always add them later, but suppliers without brands show an orange warning.")
            }
        }
        .interactiveDismissDisabled(isSaving)
    }

    private func saveAndDismiss() async {
        isSaving = true
        saveError = nil
        do {
            try await save()
            if supplier == nil, newSupplierId != nil {
                isSaving = false
                showAddBrandsPrompt = true
                return
            }
            dismiss()
            await onSave()
        } catch {
            saveError = userFriendlyError(error, context: "save data")
        }
        isSaving = false
    }

    private func save() async throws {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            throw NSError(domain: "WiredPart", code: 0, userInfo: [NSLocalizedDescriptionKey: "Supplier name is required"])
        }
        guard let service = appCore.partsService else {
            saveError = "Parts service not available"
            throw NSError(domain: "WiredPart", code: 0, userInfo: [NSLocalizedDescriptionKey: "Parts service not available"])
        }
        if let s = supplier {
            try service.updateSupplier(
                id: s.id,
                name: trimmedName,
                contactName: contactName.isEmpty ? nil : contactName,
                email: email.isEmpty ? nil : email,
                phone: phone.isEmpty ? nil : phone,
                address: address.isEmpty ? nil : address,
                website: website.isEmpty ? nil : website,
                repName: repName.isEmpty ? nil : repName,
                repEmail: repEmail.isEmpty ? nil : repEmail,
                repPhone: repPhone.isEmpty ? nil : repPhone,
                deliveryMethod: deliveryMethod.isEmpty ? nil : deliveryMethod,
                deliveryDays: deliveryDays.isEmpty ? nil : deliveryDays,
                accountNumber: accountNumber.isEmpty ? nil : accountNumber,
                isActive: isActive ? 1 : 0,
                notes: notes.isEmpty ? nil : notes
            )
        } else {
            newSupplierId = try service.createSupplier(
                name: trimmedName,
                contactName: contactName.isEmpty ? nil : contactName,
                email: email.isEmpty ? nil : email,
                phone: phone.isEmpty ? nil : phone,
                address: address.isEmpty ? nil : address,
                website: website.isEmpty ? nil : website,
                repName: repName.isEmpty ? nil : repName,
                repEmail: repEmail.isEmpty ? nil : repEmail,
                repPhone: repPhone.isEmpty ? nil : repPhone,
                deliveryMethod: deliveryMethod.isEmpty ? nil : deliveryMethod,
                deliveryDays: deliveryDays.isEmpty ? nil : deliveryDays,
                accountNumber: accountNumber.isEmpty ? nil : accountNumber,
                notes: notes.isEmpty ? nil : notes
            )
        }
    }
}

// MARK: - Supplier Brand Picker Sheet

private struct SupplierBrandPickerSheet: View {
    let supplierId: Int64
    let onSave: () async -> Void
    @EnvironmentObject private var appCore: AppCore
    @Environment(\.dismiss) private var dismiss

    @State private var allBrands: [BrandCheckItem] = []
    @State private var isLoading = true
    @State private var loadError: String?
    @State private var isSaving = false
    @State private var searchText = ""

    struct BrandCheckItem: Identifiable {
        let id: Int64
        let name: String
        var isLinked: Bool
    }

    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    ProgressView("Loading brands...")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let error = loadError {
                    VStack(spacing: 12) {
                        Text(error)
                            .foregroundStyle(.red)
                            .font(.subheadline)
                        Button("Retry") { loadBrands() }
                            .buttonStyle(.bordered)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if allBrands.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "tag")
                            .font(.largeTitle)
                            .foregroundStyle(.secondary)
                        Text("No Brands")
                            .font(.headline)
                        Text("Add brands in Parts > Brands first.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    brandList
                }
            }
            .navigationTitle("Manage Brands")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $searchText, prompt: "Search brands...")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        Task { await saveLinks() }
                    } label: {
                        if isSaving {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Text("Save")
                                .fontWeight(.semibold)
                        }
                    }
                    .disabled(isSaving)
                }
            }
            .task { loadBrands() }
            .interactiveDismissDisabled(isSaving)
        }
    }

    private var filteredBrands: [BrandCheckItem] {
        if searchText.isEmpty { return allBrands }
        let query = searchText.lowercased()
        return allBrands.filter { $0.name.lowercased().contains(query) }
    }

    @ViewBuilder
    private var brandList: some View {
        List {
            let linkedCount = allBrands.filter(\.isLinked).count
            Section {
                Text("\(linkedCount) of \(allBrands.count) brands selected")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            ForEach(filteredBrands) { brand in
                Button {
                    toggleBrand(brand.id)
                } label: {
                    HStack(spacing: 14) {
                        Image(systemName: brand.isLinked ? "checkmark.square.fill" : "square")
                            .font(.title3)
                            .foregroundStyle(brand.isLinked ? Color.accentColor : .secondary)
                            .frame(width: 28)

                        Text(brand.name)
                            .font(.body)
                            .fontWeight(.medium)
                            .foregroundStyle(.primary)

                        Spacer()
                    }
                    .frame(minHeight: 50)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .listStyle(.insetGrouped)
    }

    private func toggleBrand(_ brandId: Int64) {
        if let index = allBrands.firstIndex(where: { $0.id == brandId }) {
            allBrands[index].isLinked.toggle()
        }
    }

    private func loadBrands() {
        isLoading = true
        loadError = nil
        do {
            guard let service = appCore.partsService else {
                isLoading = false
                loadError = "Parts service not available"
                return
            }

            let allItems = try service.listBrands()
            let linked = try service.getSupplierBrandRows(supplierId: supplierId)
            let linkedIds = Set(linked.map(\.brandId))

            allBrands = allItems.compactMap { item in
                guard let id = item.brand.id,
                      item.brand.isActive == 1,
                      item.brand.deletedAt == nil else { return nil }
                return BrandCheckItem(
                    id: id,
                    name: item.brand.name,
                    isLinked: linkedIds.contains(id)
                )
            }
            isLoading = false
        } catch {
            loadError = userFriendlyError(error, context: "load brand list")
            isLoading = false
        }
    }

    private func saveLinks() async {
        isSaving = true
        do {
            guard let service = appCore.partsService else {
                loadError = "Parts service not available"
                isSaving = false
                return
            }

            let selectedIds = Set(allBrands.filter(\.isLinked).map(\.id))
            let existingLinks = try service.getSupplierBrandRows(supplierId: supplierId)
            let existingIds = Set(existingLinks.map(\.brandId))

            let toAdd = selectedIds.subtracting(existingIds)
            for brandId in toAdd {
                try service.addBrandSupplier(
                    brandId: brandId,
                    supplierId: supplierId,
                    status: "carry_on_shelf"
                )
            }

            await MainActor.run {
                isSaving = false
                dismiss()
            }
            await onSave()
        } catch {
            await MainActor.run {
                isSaving = false
                loadError = userFriendlyError(error, context: "save supplier-brand links")
            }
        }
    }
}

// MARK: - Supplier Detail Sheet

private struct SupplierDetailSheet: View {
    let supplier: SupplierListRow
    var onEdit: () -> Void
    let onUpdate: () async -> Void
    @EnvironmentObject private var appCore: AppCore
    @Environment(\.dismiss) private var dismiss

    // Single active-sheet enum to avoid multiple .sheet conflicts
    enum ActiveSheet: Identifiable {
        case addContact
        case addBrand

        var id: String {
            switch self {
            case .addContact: return "addContact"
            case .addBrand: return "addBrand"
            }
        }
    }

    @State private var linkedBrands: [PartsService.SupplierBrandRow] = []
    @State private var recentPOs: [(poId: Int64, poNumber: String, status: String, total: Double, date: String)] = []
    @State private var supplierScores: PartsService.SupplierScores?
    @State private var contacts: [PartsService.SupplierContact] = []
    @State private var partCount = 0
    @State private var isLoading = true
    @State private var activeSheet: ActiveSheet?
    @State private var supplierChannelId: Int64?
    @State private var contactToRemove: PartsService.SupplierContact?
    @State private var showRemoveContactConfirm = false
    @State private var loadError: String?

    var body: some View {
        NavigationStack {
            List {
                if let error = loadError {
                    Section {
                        Label(error, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                            .font(.subheadline)
                    }
                }

                // Section 1: Overview
                overviewSection

                // Section 2: Contact Info (tappable)
                contactSection

                // Section 3: Sales Rep
                if supplier.repName != nil || supplier.repEmail != nil || supplier.repPhone != nil {
                    repSection
                }

                // Section 4: Communication
                communicationSection

                // Section 5: Linked Contacts
                contactsListSection

                // Section 6: Performance Scores (auto-calculated)
                scoresSection

                // Section 7: Brands (which brands they carry)
                brandsSection

                // Section 8: Parts Summary (count only — pricing is on the Pricing page)
                partsSummarySection

                // Section 9: Recent Orders
                recentOrdersSection

                // Section 10: Notes
                if let notes = supplier.notes, !notes.isEmpty {
                    Section("Notes") {
                        Text(notes)
                            .font(.subheadline)
                    }
                }
            }
            .navigationTitle(supplier.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        dismiss()
                        onEdit()
                    } label: {
                        Image(systemName: "pencil")
                    }
                }
            }
            .task { await loadAllDetails() }
            .sheet(item: $activeSheet) { sheet in
                switch sheet {
                case .addContact:
                    AddSupplierContactSheet(supplierId: supplier.id) {
                        if let service = appCore.partsService {
                            do {
                                contacts = try service.getSupplierContacts(supplierId: supplier.id)
                            } catch {
                                loadError = userFriendlyError(error, context: "reload contacts")
                            }
                        }
                    }
                    .environmentObject(appCore)
                case .addBrand:
                    LinkSupplierBrandsSheet(supplierId: supplier.id) {
                        await loadAllDetails()
                        await onUpdate()
                    }
                    .environmentObject(appCore)
                }
            }
        }
    }

    // MARK: - Communication

    private var communicationSection: some View {
        Section("Communication") {
            if let channelId = supplierChannelId {
                Button {
                    NotificationCenter.default.post(
                        name: .init("navigateToChannel"),
                        object: nil,
                        userInfo: ["channelId": channelId]
                    )
                    dismiss()
                } label: {
                    Label("Open Supplier Channel", systemImage: "bubble.left.and.bubble.right")
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .frame(minHeight: 44)
                }
            } else {
                Button {
                    createSupplierChannel()
                } label: {
                    Label("Start Conversation", systemImage: "plus.bubble")
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .frame(minHeight: 44)
                }
            }
        }
    }

    private func createSupplierChannel() {
        guard let chatService = appCore.chatService,
              let userId = appCore.currentUser?.id else {
            loadError = "Chat service not available"
            return
        }
        do {
            let displayName = supplier.contactName ?? supplier.name
            let channelId = try chatService.createSupplierChannel(
                name: "Channel: \(supplier.name)",
                supplierId: supplier.id,
                supplierDisplayName: displayName,
                contactId: nil,
                role: nil,
                createdBy: userId
            )
            supplierChannelId = channelId
        } catch {
            loadError = userFriendlyError(error, context: "create supplier channel")
        }
    }

    // MARK: - Overview

    @ViewBuilder
    private var overviewSection: some View {
        Section {
            Button {
                dismiss()
                onEdit()
            } label: {
                Label("Edit Supplier Info", systemImage: "pencil")
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .frame(minHeight: 44)
            }

            if let acct = supplier.accountNumber, !acct.isEmpty {
                LabeledContent("Account #", value: acct)
            }
            if supplier.isActive != 1 {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                    Text("Inactive Supplier")
                        .foregroundStyle(.orange)
                }
            }
            if let method = supplier.deliveryMethod, !method.isEmpty {
                LabeledContent("Delivery", value: method)
            }
            if let days = supplier.deliveryDays, !days.isEmpty {
                LabeledContent("Delivery Schedule", value: days)
            }
        }
    }

    // MARK: - Contact (tappable)

    @ViewBuilder
    private var contactSection: some View {
        Section("Contact") {
            if let contact = supplier.contactName, !contact.isEmpty {
                LabeledContent("Name", value: contact)
            }
            if let phone = supplier.phone, !phone.isEmpty {
                Button {
                    let cleaned = phone.replacingOccurrences(of: "[^0-9+]", with: "", options: .regularExpression)
                    if let url = URL(string: "tel:\(cleaned)") { UIApplication.shared.open(url) }
                } label: {
                    LabeledContent("Phone") {
                        Text(phone).foregroundStyle(.blue)
                    }
                }
                .buttonStyle(.plain)
            }
            if let email = supplier.email, !email.isEmpty {
                Button {
                    if let url = URL(string: "mailto:\(email)") { UIApplication.shared.open(url) }
                } label: {
                    LabeledContent("Email") {
                        Text(email).foregroundStyle(.blue)
                    }
                }
                .buttonStyle(.plain)
            }
            if let address = supplier.address, !address.isEmpty {
                LabeledContent("Address", value: address)
            }
            if let website = supplier.website, !website.isEmpty {
                Button {
                    var urlStr = website
                    if !urlStr.hasPrefix("http") { urlStr = "https://\(urlStr)" }
                    if let url = URL(string: urlStr) { UIApplication.shared.open(url) }
                } label: {
                    LabeledContent("Website") {
                        Text(website).foregroundStyle(.blue)
                    }
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Rep

    @ViewBuilder
    private var repSection: some View {
        Section("Sales Representative") {
            if let rep = supplier.repName, !rep.isEmpty {
                LabeledContent("Name", value: rep)
            }
            if let phone = supplier.repPhone, !phone.isEmpty {
                Button {
                    let cleaned = phone.replacingOccurrences(of: "[^0-9+]", with: "", options: .regularExpression)
                    if let url = URL(string: "tel:\(cleaned)") { UIApplication.shared.open(url) }
                } label: {
                    LabeledContent("Phone") {
                        Text(phone).foregroundStyle(.blue)
                    }
                }
                .buttonStyle(.plain)
            }
            if let email = supplier.repEmail, !email.isEmpty {
                Button {
                    if let url = URL(string: "mailto:\(email)") { UIApplication.shared.open(url) }
                } label: {
                    LabeledContent("Email") {
                        Text(email).foregroundStyle(.blue)
                    }
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Contacts

    @ViewBuilder
    private var contactsListSection: some View {
        Section {
            if contacts.isEmpty {
                Text("No contacts linked yet.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(contacts, id: \.contactId) { contact in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("\(contact.firstName) \(contact.lastName)")
                                .font(.subheadline)
                                .fontWeight(.medium)
                            if contact.isPrimary == 1 {
                                Text("PRIMARY")
                                    .font(.caption2)
                                    .fontWeight(.bold)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Color.blue.opacity(0.15))
                                    .foregroundStyle(.blue)
                                    .clipShape(Capsule())
                            }
                            Spacer()
                            if let role = contact.role, !role.isEmpty {
                                Text(role)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        HStack(spacing: 12) {
                            if let phone = contact.phone, !phone.isEmpty {
                                Button {
                                    let cleaned = phone.replacingOccurrences(of: "[^0-9+]", with: "", options: .regularExpression)
                                    if let url = URL(string: "tel:\(cleaned)") { UIApplication.shared.open(url) }
                                } label: {
                                    Label(phone, systemImage: "phone.fill")
                                        .font(.caption)
                                        .foregroundStyle(.blue)
                                }
                                .buttonStyle(.plain)
                            }
                            if let email = contact.email, !email.isEmpty {
                                Button {
                                    if let url = URL(string: "mailto:\(email)") { UIApplication.shared.open(url) }
                                } label: {
                                    Label(email, systemImage: "envelope.fill")
                                        .font(.caption)
                                        .foregroundStyle(.blue)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    .frame(minHeight: 44)
                    .swipeActions(edge: .trailing) {
                        Button(role: .destructive) {
                            contactToRemove = contact
                            showRemoveContactConfirm = true
                        } label: {
                            Label("Remove", systemImage: "trash")
                        }
                    }
                }
            }
        } header: {
            HStack {
                Text("Contacts (\(contacts.count))")
                Spacer()
                Button {
                    activeSheet = .addContact
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.title3)
                }
                .accessibilityLabel("Add contact")
            }
        }
    }

    // MARK: - Scores

    @ViewBuilder
    private var scoresSection: some View {
        Section("Performance") {
            if let scores = supplierScores, scores.totalOrderCount > 0 {
                LabeledContent("Quality") {
                    Text(String(format: "%.0f%%", scores.qualityScore))
                        .fontWeight(.bold)
                        .foregroundStyle(scoreColor(scores.qualityScore))
                }
                if scores.totalUnitsReceived > 0 {
                    Text("\(scores.totalUnitsReturned) returned of \(scores.totalUnitsReceived) received")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                LabeledContent("On-Time") {
                    Text(String(format: "%.0f%%", scores.onTimeRate))
                        .fontWeight(.bold)
                        .foregroundStyle(scoreColor(scores.onTimeRate))
                }
                if let avg = scores.avgDeliveryDays {
                    Text(String(format: "Avg delivery: %.1f days", avg))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                LabeledContent("Reliability") {
                    Text(String(format: "%.0f%%", scores.reliabilityScore))
                        .fontWeight(.bold)
                        .foregroundStyle(scoreColor(scores.reliabilityScore))
                }
                LabeledContent("Total Orders", value: "\(scores.totalOrderCount)")
            } else {
                Text("No order history yet — scores appear after the first received PO.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Brands

    @ViewBuilder
    private var brandsSection: some View {
        Section {
            if linkedBrands.isEmpty {
                Text("No brands linked yet. Tap + to link existing brands this supplier carries.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(linkedBrands, id: \.brandId) { item in
                    HStack(spacing: 12) {
                        Image(systemName: "tag.fill")
                            .foregroundStyle(Color.accentColor)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.brandName)
                                .font(.subheadline)
                                .fontWeight(.medium)
                            Text("\(item.partCount) parts")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        // Carry status toggle
                        Button {
                            toggleBrandCarryStatus(item)
                        } label: {
                            Text(item.carryStatus == "need_to_order" ? "Need to Order" : "On Shelf")
                                .font(.caption2)
                                .fontWeight(.medium)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(item.carryStatus == "need_to_order" ? Color.orange.opacity(0.15) : Color.green.opacity(0.15))
                                .foregroundStyle(item.carryStatus == "need_to_order" ? .orange : .green)
                                .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                    .frame(minHeight: 44)
                }
            }
        } header: {
            HStack {
                Text("Brands Carried (\(linkedBrands.count))")
                Spacer()
                Button {
                    activeSheet = .addBrand
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.title3)
                }
                .accessibilityLabel("Link brand")
            }
        }
    }

    private func toggleBrandCarryStatus(_ item: PartsService.SupplierBrandRow) {
        guard let service = appCore.partsService else {
            loadError = "Parts service unavailable"
            return
        }
        let newStatus = item.carryStatus == "carry_on_shelf" ? "need_to_order" : "carry_on_shelf"
        do {
            try service.updateBrandSupplierCarryStatus(
                brandId: item.brandId,
                supplierId: supplier.id,
                carryStatus: newStatus
            )
            // Reload brands to reflect the change
            do {
                linkedBrands = try service.getSupplierBrandRows(supplierId: supplier.id)
            } catch {
                loadError = userFriendlyError(error, context: "reload brands")
            }
        } catch {
            loadError = userFriendlyError(error, context: "update carry status")
        }
    }

    // MARK: - Parts Summary (count only)

    @ViewBuilder
    private var partsSummarySection: some View {
        Section("Parts") {
            if partCount > 0 {
                LabeledContent("Linked Parts", value: "\(partCount)")
                Text("View supplier-specific pricing on the Pricing page.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text("No parts linked to this supplier yet.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Recent Orders

    @ViewBuilder
    private var recentOrdersSection: some View {
        Section {
            if recentPOs.isEmpty {
                Text("No purchase orders with this supplier yet.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(recentPOs, id: \.poId) { po in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(po.poNumber.isEmpty ? "PO #\(po.poId)" : po.poNumber)
                                .font(.subheadline)
                                .fontWeight(.medium)
                            Text(String(po.date.prefix(10)))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 2) {
                            Text(String(format: "$%.2f", po.total))
                                .font(.subheadline)
                            statusBadge(po.status)
                        }
                    }
                    .frame(minHeight: 44)
                }
            }
        } header: {
            Text("Recent Orders (\(recentPOs.count))")
        }
    }

    // MARK: - Helpers

    @ViewBuilder
    private func statusBadge(_ status: String) -> some View {
        let color: Color = switch status.lowercased() {
        case "received", "completed", "closed": .green
        case "sent", "submitted": .blue
        case "draft": .secondary
        case "cancelled": .red
        default: .secondary
        }
        Text(status.capitalized)
            .font(.caption2)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color.opacity(0.15))
            .foregroundStyle(color)
            .clipShape(Capsule())
    }

    private func scoreColor(_ score: Double) -> Color {
        if score >= 80 { return .green }
        if score >= 60 { return .orange }
        return .red
    }

    private func loadAllDetails() async {
        guard let service = appCore.partsService else {
            loadError = "Parts service not available"
            isLoading = false
            return
        }
        do {
            linkedBrands = try service.getSupplierBrandRows(supplierId: supplier.id)
            recentPOs = try service.getSupplierRecentPOs(supplierId: supplier.id)
            partCount = try service.getSupplierPartCount(supplierId: supplier.id)
            contacts = try service.getSupplierContacts(supplierId: supplier.id)
            supplierScores = try service.calculateSupplierScores(supplierId: supplier.id)

            // Check for existing supplier channel
            if let chatService = appCore.chatService,
               let userId = appCore.currentUser?.id {
                let channels = try chatService.listSupplierChannels(userId: userId)
                supplierChannelId = channels.first(where: { $0.supplierId == supplier.id })?.channelId
            }

            isLoading = false
        } catch {
            isLoading = false
        }
    }
}

// MARK: - Link Supplier Brands Sheet

private struct LinkSupplierBrandsSheet: View {
    let supplierId: Int64
    let onSave: () async -> Void
    @EnvironmentObject private var appCore: AppCore
    @Environment(\.dismiss) private var dismiss

    @State private var availableBrands: [(id: Int64, name: String)] = []
    @State private var selectedBrandIds: Set<Int64> = []
    @State private var loadError: String?
    @State private var isLoading = true
    @State private var isSaving = false

    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    ProgressView("Loading brands...")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let error = loadError {
                    ErrorStateView(message: error) { Task { await loadAvailableBrands() } }
                } else if availableBrands.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "tag")
                            .decorativeIconFont(40)
                            .foregroundStyle(.secondary)
                        Text("No Unlinked Brands")
                            .font(.headline)
                        Text("All existing brands are already linked to this supplier. Add a new brand from the Brands tab first if needed.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 24)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List(availableBrands, id: \.id) { brand in
                        Button {
                            if selectedBrandIds.contains(brand.id) {
                                selectedBrandIds.remove(brand.id)
                            } else {
                                selectedBrandIds.insert(brand.id)
                            }
                        } label: {
                            let isSelected = selectedBrandIds.contains(brand.id)
                            HStack {
                                Label(brand.name, systemImage: "tag.fill")
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                if isSelected {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(Color.accentColor)
                                }
                            }
                            .frame(minHeight: 44)
                            .accessibilityElement(children: .ignore)
                            .accessibilityLabel(brand.name)
                            .accessibilityValue(isSelected ? "Selected" : "Not selected")
                            .accessibilityHint("Double tap to toggle this brand for linking")
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .navigationTitle("Link Brands")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .disabled(isSaving)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        Task { await save() }
                    } label: {
                        if isSaving { ProgressView() } else { Text("Link") }
                    }
                    .disabled(selectedBrandIds.isEmpty || isSaving)
                }
            }
            .task { await loadAvailableBrands() }
            .interactiveDismissDisabled(isSaving)
        }
    }

    private func loadAvailableBrands() async {
        isLoading = true
        loadError = nil
        do {
            guard let service = appCore.partsService else {
                loadError = "Parts service not available"
                isLoading = false
                return
            }
            availableBrands = try service.listBrandsAvailableForSupplier(supplierId: supplierId)
                .compactMap { brand in
                    guard let id = brand.id else { return nil }
                    return (id: id, name: brand.name)
                }
            isLoading = false
        } catch {
            loadError = userFriendlyError(error, context: "load brands")
            isLoading = false
        }
    }

    private func save() async {
        isSaving = true
        loadError = nil
        do {
            guard let service = appCore.partsService else {
                loadError = "Parts service not available"
                isSaving = false
                return
            }
            let existingBrandIds = try service.getSupplierBrandRows(supplierId: supplierId)
                .map(\.brandId)
            try service.setSupplierBrands(
                supplierId: supplierId,
                brandIds: Set(existingBrandIds).union(selectedBrandIds)
            )
            dismiss()
            await onSave()
        } catch {
            loadError = userFriendlyError(error, context: "link brands")
        }
        isSaving = false
    }
}

// MARK: - Add Supplier Contact Sheet

private struct AddSupplierContactSheet: View {
    let supplierId: Int64
    let onSave: () -> Void
    @EnvironmentObject private var appCore: AppCore
    @Environment(\.dismiss) private var dismiss

    @State private var firstName = ""
    @State private var lastName = ""
    @State private var role = ""
    @State private var phone = ""
    @State private var email = ""
    @State private var isPrimary = false
    @State private var saveError: String?
    @State private var isSaving = false

    private let commonRoles = ["", "Sales Rep", "Accounts Payable", "Accounts Receivable", "Owner", "Manager", "Shipping", "Returns", "Technical Support", "Other"]

    var body: some View {
        NavigationStack {
            Form {
                if let error = saveError {
                    Section {
                        Label(error, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                            .font(.subheadline)
                    }
                }

                Section("Contact Info") {
                    TextField("First Name *", text: $firstName)
                        .frame(minHeight: 44)
                    TextField("Last Name *", text: $lastName)
                        .frame(minHeight: 44)
                    Picker("Role", selection: $role) {
                        ForEach(commonRoles, id: \.self) { r in
                            Text(r.isEmpty ? "Not Set" : r).tag(r)
                        }
                    }
                }

                Section("Contact Methods") {
                    TextField("Phone", text: $phone)
                        .frame(minHeight: 44)
                        .keyboardType(.phonePad)
                    TextField("Email", text: $email)
                        .frame(minHeight: 44)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                }

                Section {
                    Toggle("Primary Contact", isOn: $isPrimary)
                }
            }
            .navigationTitle("Add Contact")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .disabled(isSaving)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        Task { await save() }
                    } label: {
                        if isSaving { ProgressView() } else { Text("Save") }
                    }
                    .disabled(firstName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                              || lastName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                              || isSaving)
                }
            }
            .interactiveDismissDisabled(isSaving)
        }
    }

    private func save() async {
        isSaving = true
        saveError = nil
        do {
            guard let service = appCore.partsService else {
                saveError = "Parts service not available"
                throw NSError(domain: "WiredPart", code: 0, userInfo: [NSLocalizedDescriptionKey: "Parts service not available"])
            }
            try service.addSupplierContact(
                supplierId: supplierId,
                firstName: firstName.trimmingCharacters(in: .whitespacesAndNewlines),
                lastName: lastName.trimmingCharacters(in: .whitespacesAndNewlines),
                role: role.isEmpty ? nil : role,
                phone: phone.isEmpty ? nil : phone,
                email: email.isEmpty ? nil : email,
                isPrimary: isPrimary
            )
            dismiss()
            onSave()
        } catch {
            saveError = userFriendlyError(error, context: "save data")
        }
        isSaving = false
    }
}
