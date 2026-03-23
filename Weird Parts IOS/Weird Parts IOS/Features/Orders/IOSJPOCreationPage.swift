import SwiftUI
import WiredPartCore

/// Full cart-builder for creating a new JPO with line items.
///
/// 3-panel layout: search (left) | cart (center) | suggestions (right).
/// iPad/Mac: side-by-side via HStack. iPhone: stacked vertically.
/// Auto-fills job from active clock-in. Cart tracks stock levels.
struct IOSJPOCreationPage: View {
    @EnvironmentObject private var appCore: AppCore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.horizontalSizeClass) private var sizeClass

    // MARK: - Job Context

    @State private var selectedJobId: Int64?
    @State private var selectedJobName = ""
    @State private var clockedInJobId: Int64?
    @State private var priority = "normal"
    @State private var deliveryOption = "partial"
    @State private var notes = ""
    @State private var jobs: [JobsService.JobListItem] = []

    // MARK: - Cart

    @State private var cartItems: [CartItem] = []

    // MARK: - Search

    @State private var searchText = ""
    @State private var searchResults: [Part] = []
    @State private var isSearching = false

    // MARK: - State

    @State private var activeSheet: ActiveSheet?
    @State private var isSubmitting = false
    @State private var submitError: String?
    @State private var showSuggestionsOnPhone = false

    // MARK: - Model

    struct CartItem: Identifiable {
        let id = UUID()
        let partId: Int64
        let partName: String
        let partCode: String?
        var quantity: Int
        let unitPrice: Double?
        let shopStock: Int
        let stockStatus: StockStatus

        enum StockStatus: String {
            case inStock
            case lowStock
            case outOfStock
        }
    }

    private enum ActiveSheet: Identifiable {
        case qrScanner

        var id: String {
            switch self {
            case .qrScanner: "qrScanner"
            }
        }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                jobHeader

                Divider()

                if sizeClass == .regular {
                    // iPad / Mac: side-by-side
                    HStack(spacing: 0) {
                        searchPanel
                            .frame(maxWidth: .infinity)
                        Divider()
                        cartPanel
                            .frame(maxWidth: .infinity)
                        Divider()
                        suggestionsPanel
                            .frame(maxWidth: .infinity)
                    }
                } else {
                    // iPhone: stacked
                    ScrollView {
                        VStack(spacing: 16) {
                            searchPanel
                            cartPanel
                            suggestionsSection
                        }
                        .padding()
                    }
                }
            }
            .navigationTitle("New Parts Order")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .disabled(isSubmitting)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Submit") { submitOrder() }
                        .disabled(cartItems.isEmpty || selectedJobId == nil || isSubmitting)
                        .fontWeight(.semibold)
                }
            }
            .sheet(item: $activeSheet) { sheet in
                switch sheet {
                case .qrScanner:
                    QRScanSheet(expectedType: .part) { result in
                        if let partId = result.entityId, result.isFound {
                            addPartById(partId)
                        }
                        activeSheet = nil
                    }
                    .environmentObject(appCore)
                }
            }
            .alert("Error", isPresented: .constant(submitError != nil)) {
                Button("OK") { submitError = nil }
            } message: {
                Text(submitError ?? "")
            }
            .task { await loadJobContext() }
        }
    }

    // MARK: - Job Header

    private var jobHeader: some View {
        VStack(spacing: 8) {
            if selectedJobId != nil, clockedInJobId == selectedJobId {
                // Showing clocked-in job
                HStack {
                    VStack(alignment: .leading) {
                        Text(selectedJobName)
                            .fontWeight(.medium)
                        Text("Clocked in")
                            .font(.caption)
                            .foregroundStyle(.green)
                    }
                    Spacer()
                    Button("Change") {
                        clockedInJobId = nil
                        selectedJobId = nil
                        selectedJobName = ""
                    }
                    .font(.caption)
                }
            } else {
                // Job picker
                Picker("Job", selection: $selectedJobId) {
                    Text("Select a job...").tag(nil as Int64?)
                    ForEach(jobs, id: \.id) { job in
                        Text("\(job.jobNumber) — \(job.jobName)").tag(job.id as Int64?)
                    }
                }
                .onChange(of: selectedJobId) {
                    if let id = selectedJobId,
                       let job = jobs.first(where: { $0.id == id }) {
                        selectedJobName = job.jobName
                    }
                }
            }

            HStack(spacing: 12) {
                Picker("Priority", selection: $priority) {
                    Text("Normal").tag("normal")
                    Text("High").tag("high")
                    Text("Urgent").tag("urgent")
                }
                .pickerStyle(.segmented)

                Picker("Delivery", selection: $deliveryOption) {
                    Label("As available", systemImage: "shippingbox").tag("partial")
                    Label("Wait for full", systemImage: "shippingbox.and.arrow.backward").tag("full")
                }
                .pickerStyle(.menu)
            }
        }
        .padding()
    }

    // MARK: - Search Panel

    private var searchPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Search")
                    .font(.headline)
                Spacer()
                Button { activeSheet = .qrScanner } label: {
                    Label("Scan", systemImage: "qrcode.viewfinder")
                        .font(.caption)
                }
            }

            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Search parts...", text: $searchText)
                    .textFieldStyle(.plain)
                    .onChange(of: searchText) { searchParts() }
                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                        searchResults = []
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(8)
            .background(Color.secondary.opacity(0.1))
            .clipShape(RoundedRectangle(cornerRadius: 8))

            if isSearching {
                ProgressView()
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 8)
            } else if searchResults.isEmpty && !searchText.isEmpty && searchText.count >= 2 {
                Text("No parts found for \"\(searchText)\"")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 8)
            } else {
                ForEach(searchResults, id: \.id) { part in
                    searchResultRow(part)
                }
            }

            if searchText.isEmpty {
                Text("Type at least 2 characters to search")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(sizeClass == .regular ? 12 : 0)
    }

    private func searchResultRow(_ part: Part) -> some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(part.name)
                    .font(.subheadline)
                    .lineLimit(1)
                HStack(spacing: 4) {
                    if let code = part.code, !code.isEmpty {
                        Text(code)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    stockIndicator(for: part)
                }
            }

            Spacer()

            if let price = part.companyCostPrice as Double?, price > 0 {
                Text(String(format: "$%.2f", price))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Button {
                addToCart(part: part)
            } label: {
                Image(systemName: alreadyInCart(partId: part.id) ? "checkmark.circle.fill" : "plus.circle.fill")
                    .font(.title3)
                    .foregroundStyle(alreadyInCart(partId: part.id) ? .green : Color.accentColor)
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 4)
    }

    private func stockIndicator(for part: Part) -> some View {
        let stock = getShopStock(partId: part.id ?? 0)
        let color: Color = stock > (part.minStockLevel ?? 0) ? .green :
                           stock > 0 ? .orange : .red
        let label = stock > 0 ? "\(stock) in stock" : "Out of stock"
        return HStack(spacing: 2) {
            Circle().fill(color).frame(width: 6, height: 6)
            Text(label)
                .font(.caption2)
                .foregroundStyle(color)
        }
    }

    // MARK: - Cart Panel

    private var cartPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Cart (\(cartItems.count))")
                .font(.headline)

            if cartItems.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "cart")
                        .font(.largeTitle)
                        .foregroundStyle(.tertiary)
                    Text("Add parts from search or suggestions")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, minHeight: 100)
            } else {
                ForEach(Array(cartItems.enumerated()), id: \.element.id) { index, item in
                    cartRow(index: index)
                }

                Divider()

                // Summary
                HStack {
                    Text("\(cartItems.count) part\(cartItems.count == 1 ? "" : "s")")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    let total = cartItems.reduce(0.0) { $0 + (($1.unitPrice ?? 0) * Double($1.quantity)) }
                    if total > 0 {
                        Text(String(format: "Est: $%.2f", total))
                            .font(.caption)
                            .fontWeight(.medium)
                    }
                }

                let transfers = cartItems.filter { $0.stockStatus == .inStock }.count
                let ordering = cartItems.count - transfers
                HStack(spacing: 4) {
                    if transfers > 0 {
                        Label("\(transfers) transfer", systemImage: "arrow.left.arrow.right")
                            .font(.caption2)
                            .foregroundStyle(.green)
                    }
                    if ordering > 0 {
                        Label("\(ordering) to order", systemImage: "cart.badge.plus")
                            .font(.caption2)
                            .foregroundStyle(.orange)
                    }
                }

                // Notes
                TextField("Notes for the office...", text: $notes, axis: .vertical)
                    .lineLimit(2...4)
                    .font(.caption)
                    .padding(8)
                    .background(Color.secondary.opacity(0.05))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            }
        }
        .padding(sizeClass == .regular ? 12 : 0)
    }

    private func cartRow(index: Int) -> some View {
        HStack(spacing: 8) {
            let item = cartItems[index]
            VStack(alignment: .leading, spacing: 2) {
                Text(item.partName)
                    .font(.subheadline)
                    .lineLimit(1)
                HStack(spacing: 4) {
                    stockStatusBadge(item.stockStatus)
                    Text("\(item.shopStock) in stock")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            // Quantity stepper
            HStack(spacing: 4) {
                Button {
                    if cartItems[index].quantity > 1 {
                        cartItems[index].quantity -= 1
                    }
                } label: {
                    Image(systemName: "minus.circle")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)

                Text("\(cartItems[index].quantity)")
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .frame(minWidth: 24)
                    .multilineTextAlignment(.center)

                Button {
                    cartItems[index].quantity += 1
                } label: {
                    Image(systemName: "plus.circle")
                        .foregroundStyle(Color.accentColor)
                }
                .buttonStyle(.plain)
            }

            // Remove button
            Button {
                cartItems.remove(at: index)
            } label: {
                Image(systemName: "trash")
                    .font(.caption)
                    .foregroundStyle(.red)
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 4)
    }

    private func stockStatusBadge(_ status: CartItem.StockStatus) -> some View {
        let (color, icon): (Color, String) = switch status {
        case .inStock: (.green, "checkmark.circle.fill")
        case .lowStock: (.orange, "exclamationmark.triangle.fill")
        case .outOfStock: (.red, "xmark.circle.fill")
        }
        return Image(systemName: icon)
            .font(.caption2)
            .foregroundStyle(color)
    }

    // MARK: - Suggestions Panel

    /// iPad: full panel. iPhone: collapsible section.
    private var suggestionsPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Suggestions")
                .font(.headline)

            Text("Companion rules and AI suggestions will appear here.")
                .font(.caption)
                .foregroundStyle(.secondary)

            // Placeholder — 30C fills this in
            if cartItems.isEmpty {
                Label("Add a part to see suggestions", systemImage: "lightbulb")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .padding(.vertical, 16)
            }
        }
        .padding(sizeClass == .regular ? 12 : 0)
    }

    /// iPhone: collapsible DisclosureGroup
    private var suggestionsSection: some View {
        DisclosureGroup(isExpanded: $showSuggestionsOnPhone) {
            suggestionsPanel
        } label: {
            HStack {
                Image(systemName: "lightbulb")
                Text("Suggestions")
                    .font(.headline)
            }
        }
    }

    // MARK: - Cart Logic

    private func addToCart(part: Part, quantity: Int = 1) {
        guard let partId = part.id else { return }

        // Already in cart — increment
        if let idx = cartItems.firstIndex(where: { $0.partId == partId }) {
            cartItems[idx].quantity += quantity
            return
        }

        let stock = getShopStock(partId: partId)
        let status: CartItem.StockStatus
        if stock >= quantity { status = .inStock }
        else if stock > 0 { status = .lowStock }
        else { status = .outOfStock }

        cartItems.append(CartItem(
            partId: partId,
            partName: part.name,
            partCode: part.code,
            quantity: quantity,
            unitPrice: part.companyCostPrice,
            shopStock: stock,
            stockStatus: status
        ))
    }

    private func addPartById(_ partId: Int64) {
        guard let service = appCore.partsService else { return }
        do {
            if let part = try service.getPartById(partId) {
                addToCart(part: part)
            }
        } catch { }
    }

    private func alreadyInCart(partId: Int64?) -> Bool {
        guard let id = partId else { return false }
        return cartItems.contains { $0.partId == id }
    }

    // MARK: - Stock

    private func getShopStock(partId: Int64) -> Int {
        guard let service = appCore.partsService else { return 0 }
        do {
            let summary = try service.getPartStockSummary(partId: partId)
            return summary.total
        } catch {
            return 0
        }
    }

    // MARK: - Search

    private func searchParts() {
        guard let service = appCore.partsService, searchText.count >= 2 else {
            searchResults = []
            return
        }
        isSearching = true
        do {
            searchResults = try service.searchParts(query: searchText, limit: 20)
        } catch {
            searchResults = []
        }
        isSearching = false
    }

    // MARK: - Job Loading

    private func loadJobContext() async {
        guard let jobsService = appCore.jobsService else { return }

        // Load active jobs
        do {
            jobs = try jobsService.listJobs(status: "active", limit: 100)
        } catch { }

        // Check if user is clocked in
        guard let userId = appCore.currentUser?.id else { return }
        do {
            if let activeEntry = try jobsService.getActiveClockEntry(userId: userId) {
                clockedInJobId = activeEntry.jobId
                selectedJobId = activeEntry.jobId
                selectedJobName = activeEntry.jobName
            }
        } catch { }
    }

    // MARK: - Submit

    private func submitOrder() {
        guard let service = appCore.ordersService,
              let jobId = selectedJobId,
              let userId = appCore.currentUser?.id else {
            submitError = "Cannot create order — missing job or user"
            return
        }
        isSubmitting = true
        submitError = nil

        do {
            // Create the JPO
            let jpoId = try service.createJPO(
                jobId: jobId,
                requestedBy: userId,
                priority: priority,
                notes: notes.isEmpty ? nil : notes
            )

            // Add each cart item as a line
            for item in cartItems {
                try service.addJPOLine(
                    jpoId: jpoId,
                    partId: item.partId,
                    quantity: item.quantity,
                    notes: nil
                )
            }

            dismiss()
        } catch {
            submitError = error.localizedDescription
        }
        isSubmitting = false
    }
}
