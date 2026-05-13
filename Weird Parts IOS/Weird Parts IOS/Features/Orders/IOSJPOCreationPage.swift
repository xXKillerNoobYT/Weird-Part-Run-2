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
    @State private var jobLookup: [Int64: JobsService.JobListItem] = [:]

    // MARK: - Cart

    @State private var cartItems: [CartItem] = []

    // MARK: - Search

    @State private var searchText = ""
    @State private var searchResults: [Part] = []
    @State private var isSearching = false
    @State private var recentSearches: [String] = []
    @State private var bestMatchName: String?
    @State private var internetHelpEnabled = false

    // MARK: - Suggestions

    @State private var highlightedCartPartId: Int64?
    @State private var lastAddedPartId: Int64?
    @State private var companionSuggestions: [PartsService.CompanionSuggestion] = []
    @State private var aiSuggestions: [AISuggestion] = []

    struct AISuggestion: Identifiable {
        let id = UUID()
        let partName: String
        let reason: String
        let suggestedQty: Int
        let partId: Int64?
    }

    private var suggestionContextPartId: Int64? {
        highlightedCartPartId ?? lastAddedPartId ?? cartItems.first?.partId
    }

    // MARK: - Confirm Dialog

    @State private var confirmingPart: Part?
    @State private var confirmQty: Int = 1
    @State private var confirmOriginalQty: Int = 1
    @State private var confirmSource = ""  // "companion" or "ai"
    @State private var showConfirmDialog = false

    // MARK: - State

    @State private var activeSheet: ActiveSheet?
    @State private var isSubmitting = false
    @State private var submitError: String?
    @State private var showSuggestionsOnPhone = false
    @State private var showJobVerification = false
    @State private var showSuccessToast = false
    @State private var successMessage = ""
    @State private var pendingRemoveIndex: Int?
    @State private var fastAddInitialName = ""

    private let aiService = FoundationModelsService()

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
        var brandSelectionMode: BrandSelectionMode = .specific

        enum StockStatus: String {
            case inStock
            case lowStock
            case outOfStock
        }

        enum BrandSelectionMode: String, CaseIterable, Identifiable {
            case specific
            case general

            var id: String { rawValue }

            var title: String {
                switch self {
                case .specific: "Specific brand"
                case .general: "General"
                }
            }
        }
    }

    private enum ActiveSheet: Identifiable {
        case qrScanner
        case help
        case fastAdd

        var id: String {
            switch self {
            case .qrScanner: "qrScanner"
            case .help: "help"
            case .fastAdd: "fastAdd"
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            FirstVisitHint(pageId: "jpoCreation", message: "Search for parts on the left, add them to your cart. The AI suggests related parts on the right.")

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
                // Fix #149: dismiss keyboard when scrolling order creation
                .scrollDismissesKeyboard(.interactively)
            }
        }
        .navigationTitle("New Parts Order")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button { submitOrder() } label: {
                    if isSubmitting {
                        ProgressView()
                    } else {
                        Text("Submit")
                            .fontWeight(.semibold)
                    }
                }
                .disabled(cartItems.isEmpty || selectedJobId == nil || isSubmitting)
            }
            ToolbarItem(placement: .primaryAction) {
                Button { activeSheet = .help } label: {
                    Image(systemName: "questionmark.circle")
                }
                .accessibilityLabel("Help")
            }
        }
        .sheet(item: $activeSheet) { sheet in
            Group {
                switch sheet {
                case .qrScanner:
                    QRScanSheet(expectedType: .part) { result in
                        if let partId = result.entityId, result.isFound {
                            addPartById(partId)
                        }
                        activeSheet = nil
                    }
                    .environmentObject(appCore)
                case .help:
                    PageHelpSheet(
                        title: "New Parts Order Help",
                        sections: [
                            ("What This Page Does", "Create a Job Purchase Order (JPO) to request parts for your job. Search for parts, add them to your cart, set quantities, and submit for office approval."),
                            ("How to Use It", "1. Your clocked-in job auto-fills at the top. Change it if needed.\n2. Set priority (Normal/High/Urgent) and delivery preference.\n3. Search for parts by name or scan a QR code.\n4. Tap the + button to add parts to the cart. Adjust quantities with +/- buttons.\n5. Check the suggestions panel for companion parts you might need.\n6. Add notes for the office, then tap Submit."),
                            ("Stock Colors", "Green dot = in stock at the shop. Orange dot = low stock. Red dot = out of stock. In-stock parts get transferred from the shop; out-of-stock parts get ordered from suppliers."),
                            ("Tips", "Enable the Internet toggle on search to get AI-assisted part matching. Tap a cart item to see companion suggestions for that specific part. The cart shows an estimated cost total based on last-known pricing.")
                        ]
                    )
                case .fastAdd:
                    FastAddCustomPartSheet(initialName: fastAddInitialName) { part, quantity in
                        addToCart(part: part, quantity: quantity)
                        searchText = part.name
                        searchResults = []
                    }
                    .environmentObject(appCore)
                }
            }
            .presentationDetents([.large])
        }
        .alert("Error", isPresented: Binding(
            get: { submitError != nil },
            set: { if !$0 { submitError = nil } }
        )) {
            Button("OK") { submitError = nil }
        } message: {
            Text(submitError ?? "")
        }
        .alert(
            "Add \(confirmingPart?.name ?? "Part")?",
            isPresented: $showConfirmDialog
        ) {
            TextField("Quantity", value: $confirmQty, format: .number)
                .keyboardType(.numberPad)
            Button("Cancel", role: .cancel) { }
            Button("Add to Cart") {
                if let part = confirmingPart {
                    addToCart(part: part, quantity: confirmQty)
                    recordSuggestionFeedback(
                        partId: part.id ?? 0,
                        suggestedQty: confirmOriginalQty,
                        acceptedQty: confirmQty,
                        source: confirmSource
                    )
                }
            }
        } message: {
            let stock = getShopStock(partId: confirmingPart?.id ?? 0)
            Text("Suggested: \(confirmOriginalQty). Shop stock: \(stock). Adjust if needed.")
        }
        .alert("Different Job", isPresented: $showJobVerification) {
            // "Yes" intentionally has no body — selectedJobId is already set to the
            // new job; dismissing the alert is sufficient to confirm the selection.
            Button("Yes, for \(selectedJobName)") { }
            Button("No, use clocked-in job", role: .cancel) {
                if let cId = clockedInJobId,
                   let job = jobLookup[cId] {
                    selectedJobId = cId
                    selectedJobName = job.jobName
                }
            }
        } message: {
            Text("You're clocked in at a different job. Create this order for \(selectedJobName)?")
        }
        .overlay {
            if showSuccessToast {
                VStack {
                    Spacer()
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                            .accessibilityHidden(true)
                        Text(successMessage)
                            .font(.subheadline)
                            .fontWeight(.medium)
                    }
                    .padding()
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                    .padding(.bottom, 32)
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .allowsHitTesting(false)
            }
        }
        .task { await loadJobContext() }
        .onChange(of: cartItems.count) { loadSuggestions() }
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
                        // Warn if user is clocked in at a different job
                        if let cId = clockedInJobId, cId != id {
                            showJobVerification = true
                        }
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

                Toggle(isOn: $internetHelpEnabled) {
                    Label("Internet", systemImage: "globe")
                        .font(.caption2)
                }
                .toggleStyle(.switch)
                .controlSize(.mini)
                .fixedSize()

                Button { activeSheet = .qrScanner } label: {
                    Label("Scan", systemImage: "qrcode.viewfinder")
                        .font(.caption)
                }
                .accessibilityLabel("Scan QR code")
            }

            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
                TextField("Search parts...", text: $searchText)
                    .textFieldStyle(.plain)
                    .onChange(of: searchText) { searchParts() }
                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                        searchResults = []
                        bestMatchName = nil
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Clear search")
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
                VStack(alignment: .leading, spacing: 8) {
                    Text("No parts found for \"\(searchText)\"")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Button {
                        fastAddInitialName = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
                        activeSheet = .fastAdd
                    } label: {
                        Label("Fast Add Custom Part", systemImage: "plus.circle")
                            .font(.caption)
                    }
                    .buttonStyle(.bordered)
                    .accessibilityLabel("Fast add custom part")
                }
                .padding(.vertical, 8)
            } else {
                ForEach(searchResults, id: \.id) { part in
                    searchResultRow(part)
                }
            }

            // Recent searches
            if searchText.isEmpty && !recentSearches.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Recent")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                    ForEach(recentSearches, id: \.self) { query in
                        Button {
                            searchText = query
                            searchParts()
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "clock")
                                    .font(.caption2)
                                    .accessibilityHidden(true)
                                Text(query)
                                    .font(.caption)
                            }
                            .foregroundStyle(.secondary)
                        }
                    }
                }
            }

            if searchText.isEmpty && recentSearches.isEmpty {
                Text("Type at least 2 characters to search")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(sizeClass == .regular ? 12 : 0)
    }

    private func searchResultRow(_ part: Part) -> some View {
        let isBestMatch = bestMatchName.map { part.name.lowercased().contains($0.lowercased()) } ?? false

        return HStack(spacing: 8) {
            // AI best match indicator
            if isBestMatch {
                Image(systemName: "bolt.fill")
                    .foregroundStyle(.yellow)
                    .font(.caption)
                    .accessibilityLabel("Best match")
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(part.name)
                    .font(.subheadline)
                    .fontWeight(isBestMatch ? .semibold : .regular)
                    .lineLimit(1)
                HStack(spacing: 4) {
                    if let code = part.code, !code.isEmpty {
                        Text(code)
                            .font(.caption2)
                            .monospaced()
                            .foregroundStyle(.secondary)
                    }
                    stockIndicator(for: part)
                }
            }

            Spacer()

            if part.companyCostPrice > 0 {
                Text(String(format: "$%.2f", part.companyCostPrice))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Button {
                addToCart(part: part)
            } label: {
                Image(systemName: alreadyInCart(partId: part.id) ? "checkmark.circle.fill" : "plus.circle.fill")
                    .font(.title3)
                    .foregroundStyle(alreadyInCart(partId: part.id) ? .green : Color.accentColor)
                    .accessibilityHidden(true)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(alreadyInCart(partId: part.id) ? "Already in cart" : "Add to cart")
            .accessibilityAddTraits(alreadyInCart(partId: part.id) ? .isSelected : [])
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
                .accessibilityHidden(true)
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
                        .accessibilityHidden(true)
                    Text("Add parts from search or suggestions")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, minHeight: 100)
            } else {
                ForEach(Array(cartItems.enumerated()), id: \.element.id) { index, item in
                    cartRow(index: index)
                        .onTapGesture {
                            highlightedCartPartId = item.partId
                            loadSuggestions()
                        }
                        .background(
                            highlightedCartPartId == item.partId
                                ? Color.accentColor.opacity(0.08)
                                : Color.clear
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 6))
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
                    if item.brandSelectionMode == .general {
                        generalModeBadge
                    }
                }
                Picker("Brand mode", selection: $cartItems[index].brandSelectionMode) {
                    ForEach(CartItem.BrandSelectionMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .controlSize(.mini)
                .frame(maxWidth: 220)
                .accessibilityLabel("Brand selection mode for \(item.partName)")
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
                .accessibilityLabel("Decrease quantity")

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
                .accessibilityLabel("Increase quantity")
            }

            // Remove button
            Button(role: .destructive) {
                pendingRemoveIndex = index
            } label: {
                Image(systemName: "trash")
                    .font(.caption)
                    .foregroundStyle(.red)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Remove from cart")
            .confirmationDialog("Remove from cart?", isPresented: Binding(
                get: { pendingRemoveIndex == index },
                set: { if !$0 { pendingRemoveIndex = nil } }
            ), titleVisibility: .visible) {
                Button("Remove", role: .destructive) {
                    if let idx = pendingRemoveIndex, idx < cartItems.count {
                        cartItems.remove(at: idx)
                    }
                    pendingRemoveIndex = nil
                }
                Button("Cancel", role: .cancel) { pendingRemoveIndex = nil }
            }
        }
        .padding(.vertical, 4)
    }

    private var generalModeBadge: some View {
        Label("General", systemImage: "circle.dashed")
            .font(.caption2)
            .foregroundStyle(.teal)
            .labelStyle(.titleAndIcon)
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
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Suggestions")
                    .font(.headline)
                Spacer()
                if let contextId = suggestionContextPartId,
                   let name = cartItems.first(where: { $0.partId == contextId })?.partName {
                    Text("for: \(name)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            if cartItems.isEmpty {
                Label("Add a part to see suggestions", systemImage: "lightbulb")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .padding(.vertical, 16)
            } else {
                // Top 5: Companion Rules
                if !companionSuggestions.isEmpty {
                    Label("Companion Rules", systemImage: "link")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    ForEach(companionSuggestions, id: \.partId) { suggestion in
                        suggestionRow(
                            icon: "link",
                            partName: suggestion.partName,
                            detail: suggestion.pattern,
                            subDetail: "\(suggestion.points) pts · \(Int(suggestion.confidence))% conf",
                            suggestedQty: suggestion.suggestedQty,
                            partId: suggestion.partId
                        )
                    }
                }

                // Bottom 3: AI Picks
                if !aiSuggestions.isEmpty {
                    Label("AI Picks", systemImage: "sparkles")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    ForEach(aiSuggestions) { suggestion in
                        suggestionRow(
                            icon: "sparkles",
                            partName: suggestion.partName,
                            detail: suggestion.reason,
                            subDetail: nil,
                            suggestedQty: suggestion.suggestedQty,
                            partId: suggestion.partId
                        )
                    }
                }

                if companionSuggestions.isEmpty && aiSuggestions.isEmpty {
                    Text("No suggestions available for this part")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .padding(sizeClass == .regular ? 12 : 0)
    }

    @ViewBuilder
    private func suggestionRow(icon: String, partName: String, detail: String,
                               subDetail: String?, suggestedQty: Int, partId: Int64?) -> some View {
        let isInCart = partId != nil && cartItems.contains(where: { $0.partId == partId })

        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 16)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 1) {
                Text(partName)
                    .font(.caption)
                    .fontWeight(.medium)
                    .lineLimit(1)
                Text(detail)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                if let sub = subDetail {
                    Text(sub)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }

            Spacer()

            if isInCart {
                Label("In cart", systemImage: "checkmark.circle.fill")
                    .font(.caption2)
                    .foregroundStyle(.green)
            } else if let pid = partId {
                Button {
                    prepareSuggestionConfirm(
                        partId: pid,
                        suggestedQty: suggestedQty,
                        source: icon == "link" ? "companion" : "ai"
                    )
                } label: {
                    Text("+ Add \(suggestedQty)")
                        .font(.caption2)
                        .fontWeight(.medium)
                }
                .buttonStyle(.bordered)
                .controlSize(.mini)
            } else {
                Text("Not in catalog")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 2)
    }

    /// iPhone: collapsible DisclosureGroup
    private var suggestionsSection: some View {
        DisclosureGroup(isExpanded: $showSuggestionsOnPhone) {
            suggestionsPanel
        } label: {
            HStack {
                Image(systemName: "lightbulb")
                    .accessibilityHidden(true)
                Text("Suggestions")
                    .font(.headline)
                if !companionSuggestions.isEmpty || !aiSuggestions.isEmpty {
                    Text("(\(companionSuggestions.count + aiSuggestions.count))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    // MARK: - Cart Logic

    private func addToCart(part: Part, quantity: Int = 1) {
        guard let partId = part.id else { return }

        // Already in cart — increment
        if let idx = cartItems.firstIndex(where: { $0.partId == partId }) {
            cartItems[idx].quantity += quantity
            lastAddedPartId = partId
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
        lastAddedPartId = partId
    }

    private func addPartById(_ partId: Int64, quantity: Int = 1) {
        guard let service = appCore.partsService else {
            submitError = "Parts service not available"
            return
        }
        do {
            let details = try service.getPart(id: partId)
            addToCart(part: details.part, quantity: quantity)
        } catch {
            submitError = userFriendlyError(error, context: "submit data")
        }
    }

    private func alreadyInCart(partId: Int64?) -> Bool {
        guard let id = partId else { return false }
        return cartItems.contains { $0.partId == id }
    }

    // MARK: - Suggestion Confirm + Feedback

    private func prepareSuggestionConfirm(partId: Int64, suggestedQty: Int, source: String) {
        guard let service = appCore.partsService,
              let details = try? service.getPart(id: partId) else {
            submitError = "Parts service not available"
            return
        }
        confirmingPart = details.part
        confirmQty = suggestedQty
        confirmOriginalQty = suggestedQty
        confirmSource = source
        showConfirmDialog = true
    }

    private func recordSuggestionFeedback(partId: Int64, suggestedQty: Int, acceptedQty: Int, source: String) {
        guard let contextPartId = suggestionContextPartId,
              let service = appCore.partsService else { return }
        do {
            try service.recordCompanionFeedback(
                sourcePartId: contextPartId,
                targetPartId: partId,
                suggestedQty: suggestedQty,
                acceptedQty: acceptedQty,
                source: source,
                userId: appCore.currentUser?.id
            )
        } catch {
            // Non-critical — silently ignore feedback recording failures
        }
    }

    // MARK: - Stock

    private func getShopStock(partId: Int64) -> Int {
        guard let service = appCore.partsService else {
            submitError = "Parts service not available"
            return 0
        }
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
            submitError = "Parts service not available"
            searchResults = []
            bestMatchName = nil
            return
        }
        isSearching = true
        bestMatchName = nil

        // Standard search
        do {
            searchResults = try service.searchParts(query: searchText, limit: 20)
        } catch {
            searchResults = []
        }
        isSearching = false

        // Track recent search
        let trimmed = searchText.trimmingCharacters(in: .whitespaces)
        if !trimmed.isEmpty && !recentSearches.contains(trimmed) {
            recentSearches.insert(trimmed, at: 0)
            if recentSearches.count > 5 { recentSearches.removeLast() }
        }

        // AI re-ranking (if available and results exist)
        if !searchResults.isEmpty && aiService.checkAvailability() == .available {
            let currentQuery = searchText
            let partNames = searchResults.prefix(10).map(\.name).joined(separator: ", ")
            let context = buildSearchContext()
            Task {
                let result = await aiService.generatePreFill(
                    fieldType: "best_match_part_name",
                    contextData: [
                        "search_query": currentQuery,
                        "context": context,
                        "available_parts": partNames,
                        "instructions": "Return ONLY the exact part name of the most likely match. No explanation."
                    ]
                )
                if result.success, let text = result.text {
                    await MainActor.run {
                        bestMatchName = text.trimmingCharacters(in: .whitespacesAndNewlines)
                    }
                }
            }
        }
    }

    private func buildSearchContext() -> String {
        var context = "User is building a parts order."
        if !cartItems.isEmpty {
            let cartNames = cartItems.map(\.partName).joined(separator: ", ")
            context += " Cart contains: \(cartNames)."
        }
        if !recentSearches.isEmpty {
            context += " Recent searches: \(recentSearches.joined(separator: ", "))."
        }
        if !selectedJobName.isEmpty {
            context += " Job: \(selectedJobName)."
        }
        if internetHelpEnabled {
            context += " Internet help is enabled for part identification."
        }
        return context
    }

    // MARK: - Job Loading

    private func loadJobContext() async {
        guard let jobsService = appCore.jobsService else {
            submitError = "Jobs service not available"
            return
        }

        // Load active jobs
        do {
            jobs = try jobsService.listJobs(status: "active", limit: 100)
            jobLookup = Dictionary(uniqueKeysWithValues: jobs.map { ($0.id, $0) })
        } catch {
            submitError = userFriendlyError(error, context: "submit data")
        }

        // Check if user is clocked in
        guard let userId = appCore.currentUser?.id else {
            // User not logged in
            return
        }
        do {
            if let activeEntry = try jobsService.getActiveClockEntry(userId: userId) {
                clockedInJobId = activeEntry.jobId
                selectedJobId = activeEntry.jobId
                selectedJobName = activeEntry.jobName
            }
        } catch {
            submitError = userFriendlyError(error, context: "submit data")
        }
    }

    // MARK: - Suggestions Loading

    private func loadSuggestions() {
        guard let contextPartId = suggestionContextPartId,
              let service = appCore.partsService else {
            companionSuggestions = []
            aiSuggestions = []
            return
        }

        // Top 5: Companion Rules
        do {
            companionSuggestions = try service.getCompanionSuggestionsForPart(partId: contextPartId, limit: 5)
        } catch {
            companionSuggestions = []
        }

        // Bottom 3: AI Picks
        guard aiService.checkAvailability() == .available else { return }

        let cartNames = cartItems.map(\.partName).joined(separator: ", ")
        let contextPart = cartItems.first(where: { $0.partId == contextPartId })?.partName ?? ""

        Task {
            let result = await aiService.generatePreFill(
                fieldType: "parts_suggestions",
                contextData: [
                    "cart_contents": cartNames,
                    "context_part": contextPart,
                    "job": selectedJobName,
                    "instructions": """
                        Suggest 3 additional construction/electrical parts that are NOT in the cart.
                        For each, return: partName|reason|qty (one per line, no numbering).
                        """
                ]
            )
            if result.success, let text = result.text {
                let lines = text.components(separatedBy: "\n").filter { !$0.isEmpty }
                let suggestions: [AISuggestion] = lines.prefix(3).compactMap { line in
                    let parts = line.components(separatedBy: "|")
                    guard parts.count >= 3 else { return nil }
                    let name = parts[0].trimmingCharacters(in: .whitespaces)
                    let reason = parts[1].trimmingCharacters(in: .whitespaces)
                    let qty = Int(parts[2].trimmingCharacters(in: .whitespaces)) ?? 1
                    // Try to match to a real part in catalog
                    let matchedPart = try? service.searchParts(query: name, limit: 1).first
                    return AISuggestion(
                        partName: matchedPart?.name ?? name,
                        reason: reason,
                        suggestedQty: qty,
                        partId: matchedPart?.id
                    )
                }
                await MainActor.run {
                    aiSuggestions = suggestions
                }
            }
        }
    }

    // MARK: - Submit

    private func submitOrder() {
        guard let service = appCore.ordersService,
              let jobId = selectedJobId ?? clockedInJobId,
              let userId = appCore.currentUser?.id else {
            submitError = "Missing job or user info"
            return
        }
        isSubmitting = true
        submitError = nil

        do {
            let lines = cartItems.map { (partId: $0.partId, quantity: $0.quantity) }
            let brandSelectionModes = cartItems.map(\.brandSelectionMode.rawValue)
            let jpoId = try service.createJPOWithLines(
                jobId: jobId,
                requestedBy: userId,
                priority: priority,
                deliveryOption: deliveryOption,
                notes: notes.isEmpty ? nil : notes,
                lines: lines,
                brandSelectionModes: brandSelectionModes
            )

            appCore.onboardingManager?.markCompleted("jpo-create")

            // Show success toast with routing summary
            let transfers = cartItems.filter { $0.stockStatus == .inStock }.count
            let pending = cartItems.count - transfers
            successMessage = "JPO #\(jpoId): \(transfers) auto-transfer, \(pending) pending approval"
            isSubmitting = false

            withAnimation {
                showSuccessToast = true
            }
            Task {
                try? await Task.sleep(nanoseconds: 1_500_000_000)
                await MainActor.run { dismiss() }
            }
        } catch {
            submitError = userFriendlyError(error, context: "submit data")
            isSubmitting = false
        }
    }
}

private struct FastAddCustomPartSheet: View {
    @EnvironmentObject private var appCore: AppCore
    @Environment(\.dismiss) private var dismiss

    let initialName: String
    let onAdd: (Part, Int) -> Void

    @State private var name: String
    @State private var quantity = 1
    @State private var code = ""
    @State private var manufacturerDetail = ""
    @State private var notes = ""
    @State private var errorMessage: String?

    init(initialName: String, onAdd: @escaping (Part, Int) -> Void) {
        self.initialName = initialName
        self.onAdd = onAdd
        _name = State(initialValue: initialName)
    }

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var isDirty: Bool {
        trimmedName != initialName ||
        quantity != 1 ||
        !code.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
        !manufacturerDetail.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
        !notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Part") {
                    TextField("Part name", text: $name)
                    Stepper("Quantity: \(quantity)", value: $quantity, in: 1...9999)
                }

                Section("Known Details") {
                    TextField("Code (optional)", text: $code)
                        .textInputAutocapitalization(.characters)
                    TextField("Manufacturer detail (optional)", text: $manufacturerDetail)
                    TextField("Notes (optional)", text: $notes, axis: .vertical)
                        .lineLimit(2...4)
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("Fast Add Part")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") { save() }
                        .disabled(trimmedName.isEmpty)
                }
            }
            .interactiveDismissDisabled(isDirty)
        }
    }

    private func save() {
        guard let service = appCore.partsService else {
            errorMessage = "Parts service not available"
            return
        }

        do {
            let partId = try service.createFastAddCustomPartForJPO(
                PartsService.FastAddCustomPartDraft(
                    name: trimmedName,
                    code: code,
                    manufacturerPartNumber: manufacturerDetail,
                    notes: notes
                )
            )
            let part = try service.getPart(id: partId).part
            onAdd(part, quantity)
            dismiss()
        } catch {
            errorMessage = userFriendlyError(error, context: "fast add custom part")
        }
    }
}
