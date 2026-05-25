import SwiftUI
import WiredPartCore

/// Procurement planner page for iOS.
///
/// Aggregates ALL demand by PART from multiple sources (JPO lines, overstock),
/// shows stock levels vs TARGET, provides pull-from-shelf vs order options,
/// and per-part supplier selection with tags (cheapest/rated/fastest).
struct IOSProcurementPage: View {
    @EnvironmentObject private var appCore: AppCore

    // MARK: - State

    @State private var items: [OrdersService.ProcurementItem] = []
    @State private var isLoading = true
    @State private var loadError: String?
    @State private var sourceFilter: String? = nil // nil = all
    @State private var selectedSupplier: [Int64: Int64] = [:]  // [partId: supplierId]
    @State private var splitByJPOPartId: Int64? = nil           // expanded part for per-JPO split
    @State private var perJPOSupplier: [String: Int64] = [:]    // [sourceId: supplierId] for split mode
    @State private var checkedParts: Set<Int64> = []            // parts included in generation
    @State private var generateError: String?
    @State private var generateSuccess: String?
    @State private var isGenerating = false
    @State private var searchText = ""

    // Generate POs confirmation
    @State private var showGeneratePOsConfirmation = false

    // Pull action tracking: partId -> (pullQty, orderQty)
    @State private var pullDecisions: [Int64: (pullQty: Int, orderQty: Int)] = [:]
    @State private var pullActionError: String?
    @State private var pullActionSuccess: String?
    @State private var isPulling: Set<Int64> = []  // parts currently being pulled

    // Pull confirmation
    @State private var showPullConfirmation = false
    @State private var pendingPullItem: OrdersService.ProcurementItem? = nil
    @State private var pendingPullQty: Int = 0
    @State private var pendingPullOrderQty: Int = 0

    // Help
    @State private var activeSheet: ActiveSheet?

    // Toast
    @State private var showSavedToast = false

    // Cached source counts and ready-to-generate list — populated in loadData() / on input change;
    // avoids per-render filter scans in smart card filters and PO preview section.
    @State private var sourceCounts: [String: Int] = [:]
    @State private var cachedReadyToGenerate: [OrdersService.ProcurementItem] = []

    private enum ActiveSheet: Identifiable {
        case help
        var id: String { "help" }
    }

    private var generateErrorPresented: Binding<Bool> {
        Binding(
            get: { generateError != nil },
            set: { isPresented in
                if !isPresented {
                    generateError = nil
                }
            }
        )
    }

    private var generateSuccessPresented: Binding<Bool> {
        Binding(
            get: { generateSuccess != nil },
            set: { isPresented in
                if !isPresented {
                    generateSuccess = nil
                }
            }
        )
    }

    private var pullActionErrorPresented: Binding<Bool> {
        Binding(
            get: { pullActionError != nil },
            set: { isPresented in
                if !isPresented {
                    pullActionError = nil
                }
            }
        )
    }

    private var pullActionSuccessPresented: Binding<Bool> {
        Binding(
            get: { pullActionSuccess != nil },
            set: { isPresented in
                if !isPresented {
                    pullActionSuccess = nil
                }
            }
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            OnboardingBanner(pageId: "orders-procurement")
            smartCardFilters
            if isLoading {
                ProgressView("Loading procurement data...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error = loadError {
                ErrorStateView(message: error) { loadData() }
            } else if filteredItems.isEmpty {
                EmptyStateView(
                    icon: "cart",
                    title: "No Procurement Needs",
                    message: "All demand has been fulfilled."
                )
            } else {
                procurementList
            }
        }
        .navigationTitle("Procurement")
        .searchable(text: $searchText, prompt: "Search parts...")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { activeSheet = .help } label: {
                    Image(systemName: "questionmark.circle")
                }
                .accessibilityLabel("Help")
            }
        }
        .sheet(item: $activeSheet) { _ in
            PageHelpSheet(
                title: "Procurement Help",
                sections: [
                    ("What This Page Does", "Aggregates all parts that need to be ordered across all sources -- JPO requests, wishlist items, forecast needs, and overstock alerts. This is where the office decides what to buy and from whom."),
                    ("How to Use It", "1. Use the filter cards (JPO Parts, Wishlist, Forecast, Overstock) to focus on one source.\n2. Each part shows demand quantity, current shop stock, and distance to target level.\n3. Select a supplier for each part using the radio buttons.\n4. Check the parts you want to include, then scroll to the PO Preview section.\n5. Review the grouped POs and tap Generate to create them."),
                    ("Pull vs Order", "If the shop has stock, you can pull from the shelf instead of ordering. The pull options show how many to pull and how many still need ordering. Overstock items (above MAX level) require a mandatory pull."),
                    ("Supplier Tags", "Suppliers show tags: Cheapest (lowest unit price), Best Rated (highest supplier score), Fastest (shortest lead time), and Preferred (star icon, set as default for this part)."),
                    ("Split by JPO", "For parts needed by multiple jobs, tap 'Split by JPO' to assign different suppliers per JPO source. Useful when different jobs have different supplier preferences or urgency levels."),
                    ("Tips", "Use Select All to quickly include everything. The PO Preview shows grouped totals by supplier before you generate. Parts disappear from this page once POs are created for them.")
                ]
            )
        }
        .refreshable { loadData() }
        .task {
            loadData()
            appCore.onboardingManager?.markCompleted("procurement-view")
        }
        .onChange(of: checkedParts) { updateReadyToGenerate() }
        .onChange(of: selectedSupplier) { updateReadyToGenerate() }
        .onDisappear {
            NotificationCenter.default.post(name: .procurementPageInactive, object: nil)
        }
        .alert("Error", isPresented: generateErrorPresented) {
            Button("OK") { generateError = nil }
        } message: {
            Text(generateError ?? "")
        }
        .alert("POs Generated", isPresented: generateSuccessPresented) {
            Button("OK") {
                generateSuccess = nil
                loadData() // Refresh to remove generated items
            }
        } message: {
            Text(generateSuccess ?? "")
        }
        .alert("Pull Error", isPresented: pullActionErrorPresented) {
            Button("OK") { pullActionError = nil }
        } message: {
            Text(pullActionError ?? "")
        }
        .alert("Pull Complete", isPresented: pullActionSuccessPresented) {
            Button("OK") {
                pullActionSuccess = nil
                loadData() // Refresh stock levels
            }
        } message: {
            Text(pullActionSuccess ?? "")
        }
        .confirmationDialog(
            generatePOsConfirmationTitle,
            isPresented: $showGeneratePOsConfirmation,
            titleVisibility: .visible
        ) {
            Button("Generate") { generatePOs() }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text(generatePOsConfirmationMessage)
        }
        .confirmationDialog(
            pullConfirmationTitle,
            isPresented: $showPullConfirmation,
            titleVisibility: .visible
        ) {
            Button("Pull") {
                if let item = pendingPullItem {
                    executePullAction(item: item, pullQty: pendingPullQty, orderQty: pendingPullOrderQty)
                }
                pendingPullItem = nil
            }
            Button("Cancel", role: .cancel) {
                pendingPullItem = nil
            }
        } message: {
            Text(pullConfirmationMessage)
        }
        .overlay(alignment: .bottom) {
            if showSavedToast {
                Text("Selections saved — they'll persist while you're on this page")
                    .font(.subheadline)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(.ultraThinMaterial)
                    .cornerRadius(8)
                    .padding(.bottom, 20)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .onAppear {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                            withAnimation { showSavedToast = false }
                        }
                    }
            }
        }
    }

    // MARK: - Smart Card Filters

    private var smartCardFilters: some View {
        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                smartCard("JPO Parts", count: sourceCounts["jpo", default: 0], icon: "doc.text.fill", filter: "jpo")
                smartCard("Wishlist", count: sourceCounts["wishlist", default: 0], icon: "heart.fill", filter: "wishlist")
                smartCard("Forecast", count: sourceCounts["forecast", default: 0], icon: "chart.line.uptrend.xyaxis", filter: "forecast")
                smartCard("Overstock", count: sourceCounts["overstock", default: 0], icon: "exclamationmark.triangle.fill", filter: "overstock")
                smartCard("All", count: items.count, icon: "tray.full.fill", filter: nil)
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
        }
    }

    private func smartCard(_ label: String, count: Int, icon: String, filter: String?) -> some View {
        Button {
            withAnimation { sourceFilter = sourceFilter == filter ? nil : filter }
        } label: {
            VStack(spacing: 4) {
                HStack(spacing: 4) {
                    Image(systemName: icon)
                        .font(.caption)
                    Text("\(count)")
                        .font(.title3)
                        .fontWeight(.bold)
                }
                Text(label)
                    .font(.caption2)
            }
            .frame(minWidth: 70)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(sourceFilter == filter ? Color.accentColor : Color.secondary.opacity(0.12))
            )
            .foregroundStyle(sourceFilter == filter ? .white : .primary)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Filtered Items

    private var filteredItems: [OrdersService.ProcurementItem] {
        var result = items

        // Apply source filter
        if let filter = sourceFilter {
            if filter == "overstock" {
                result = result.filter { $0.urgency == "overstock" }
            } else {
                result = result.filter { $0.sources.contains { $0.sourceType == filter } }
            }
        }

        // Apply search filter
        if !searchText.isEmpty {
            result = result.filter {
                $0.partName.localizedCaseInsensitiveContains(searchText) ||
                ($0.partCode?.localizedCaseInsensitiveContains(searchText) ?? false) ||
                ($0.brandName?.localizedCaseInsensitiveContains(searchText) ?? false)
            }
        }

        return result
    }

    // MARK: - Procurement List

    private var procurementList: some View {
        List {
            // KPI summary
            Section {
                HStack {
                    Label("\(filteredItems.count) parts need attention", systemImage: "exclamationmark.circle")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    // Select/deselect all
                    Button(checkedParts.count == filteredItems.count ? "Deselect All" : "Select All") {
                        if checkedParts.count == filteredItems.count {
                            checkedParts.removeAll()
                        } else {
                            checkedParts = Set(filteredItems.map(\.id))
                        }
                    }
                    .font(.caption)
                }
            }

            ForEach(filteredItems) { item in
                procurementRow(item)
            }

            // Preview + Generate section
            if !cachedReadyToGenerate.isEmpty {
                poPreviewSection
            }
        }
        .listStyle(.insetGrouped)
    }

    /// Updates the cached ready-to-generate list. Call whenever checkedParts, selectedSupplier,
    /// pullDecisions, or items change. Avoids repeated O(N) filter scans on every render.
    /// Triggered by discrete user actions (checkbox tap, supplier pick, pull decision) — not
    /// by a hot render path — so per-call O(N) work is acceptable without debouncing.
    private func updateReadyToGenerate() {
        cachedReadyToGenerate = items.filter { item in
            checkedParts.contains(item.id) &&
            selectedSupplier[item.id] != nil &&
            effectiveOrderQty(for: item) > 0
        }
    }

    /// The effective order quantity for a part, accounting for any pull decision.
    private func effectiveOrderQty(for item: OrdersService.ProcurementItem) -> Int {
        if let decision = pullDecisions[item.id] {
            return decision.orderQty
        }
        return item.totalDemand
    }

    private func procurementRow(_ item: OrdersService.ProcurementItem) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            // Part header with checkbox
            HStack {
                // Checkbox for generation
                Button {
                    if checkedParts.contains(item.id) {
                        checkedParts.remove(item.id)
                    } else {
                        checkedParts.insert(item.id)
                    }
                } label: {
                    Image(systemName: checkedParts.contains(item.id) ? "checkmark.square.fill" : "square")
                        .foregroundStyle(checkedParts.contains(item.id) ? Color.accentColor : Color.secondary)
                        .accessibilityHidden(true)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(checkedParts.contains(item.id) ? "Deselect part" : "Select part")
                .accessibilityAddTraits(checkedParts.contains(item.id) ? .isSelected : [])

                VStack(alignment: .leading, spacing: 2) {
                    Text(item.partName)
                        .font(.subheadline)
                        .fontWeight(.medium)
                    if let code = item.partCode {
                        Text(code)
                            .font(.caption2)
                            .monospaced()
                            .foregroundStyle(.secondary)
                    }
                    if let brand = item.brandName {
                        Text(brand)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                if item.totalDemand > 0 {
                    let orderQty = effectiveOrderQty(for: item)
                    if let decision = pullDecisions[item.id], decision.pullQty > 0 {
                        VStack(alignment: .trailing, spacing: 1) {
                            Text("Order: \(orderQty)")
                                .font(.subheadline)
                                .fontWeight(.bold)
                                .foregroundStyle(orderQty > 0 ? Color.primary : Color.green)
                            Text("(\(decision.pullQty) pulled)")
                                .font(.caption2)
                                .foregroundStyle(.green)
                        }
                    } else {
                        Text("Need: \(item.totalDemand)")
                            .font(.subheadline)
                            .fontWeight(.bold)
                    }
                }
            }

            // Stock level + delta to target
            HStack(spacing: 8) {
                Text("Shop: \(item.shopStock)")
                    .font(.caption)
                Text("(Target: \(item.targetStock))")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Spacer()

                // Delta badge
                let delta = item.deltaToTarget
                if delta > 0 {
                    Text("+\(delta) to target")
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundStyle(.orange)
                } else if delta < 0 {
                    Text("\(delta) over target")
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundStyle(.red)
                } else {
                    Text("At target")
                        .font(.caption)
                        .foregroundStyle(.green)
                }
            }

            // Overstock warning
            if item.urgency == "overstock" {
                HStack(spacing: 4) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                        .accessibilityHidden(true)
                    Text("OVER MAX — mandatory pull of at least \(item.shopStock - item.maxStock)")
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }

            // Urgency indicator for understock
            if item.urgency == "understock" {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.down.circle.fill")
                        .foregroundStyle(.orange)
                        .accessibilityHidden(true)
                    Text("Below minimum stock level")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }

            // Sources
            ForEach(item.sources) { source in
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 4) {
                        sourceIcon(source.sourceType)
                        Text(source.sourceName)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text("qty: \(source.quantity)")
                            .font(.caption)
                            .monospaced()
                    }
                    if let lockedSupplierId = source.lockedSupplierId {
                        let supplierLabel = source.lockedSupplierName ?? "Supplier #\(lockedSupplierId)"
                        HStack(spacing: 4) {
                            Image(systemName: "lock.fill")
                                .font(.caption2)
                                .foregroundStyle(.orange)
                                .accessibilityHidden(true)
                            Text("Locked to \(supplierLabel)")
                                .font(.caption2)
                                .foregroundStyle(.orange)
                        }
                        .padding(.leading, 14)
                    }
                }
            }

            // Pull options
            pullOptionsView(item)

            // Generic part lock indicator
            if item.isGeneric {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 4) {
                        Image(systemName: "lock.fill")
                            .font(.caption2)
                            .foregroundStyle(.orange)
                            .accessibilityHidden(true)
                        if let lockedSupplierId = item.lockedSupplierId {
                            let supplierLabel = item.lockedSupplierName ?? "Supplier #\(lockedSupplierId)"
                            Text("Generic — locked to \(supplierLabel)")
                                .font(.caption2)
                                .foregroundStyle(.orange)
                        } else {
                            Text("Generic — supplier lock applies per job")
                                .font(.caption2)
                                .foregroundStyle(.orange)
                        }
                    }
                    if let lockSourceName = item.lockSourceName {
                        Text("Based on \(lockSourceName)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            // Supplier selection
            if !item.suppliers.isEmpty {
                supplierSelectionView(item)
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(item.partName), need \(item.totalDemand), stock \(item.shopStock), target \(item.targetStock), \(item.urgency), \(item.suppliers.count) suppliers")
    }

    // MARK: - PO Preview + Generation

    private var poPreviewSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 8) {
                // Header
                HStack {
                    Image(systemName: "doc.badge.plus")
                        .foregroundStyle(Color.accentColor)
                        .accessibilityHidden(true)
                    Text("Ready to Generate")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                    Spacer()
                    Text("\(poPreviewGroups.count) PO\(poPreviewGroups.count == 1 ? "" : "s")")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                // Grouped by supplier
                ForEach(poPreviewGroups, id: \.supplierId) { group in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(group.supplierName)
                            .font(.caption)
                            .fontWeight(.semibold)
                        ForEach(group.parts, id: \.partId) { part in
                            HStack {
                                Text(part.partName)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                // Show pull badge if this part had stock pulled
                                if let decision = pullDecisions[part.partId], decision.pullQty > 0 {
                                    Text("pulled \(decision.pullQty)")
                                        .font(.system(.caption2, weight: .medium))
                                        .padding(.horizontal, 4)
                                        .padding(.vertical, 1)
                                        .background(Capsule().fill(Color.green.opacity(0.15)))
                                        .foregroundStyle(.green)
                                }
                                Spacer()
                                Text("x\(part.quantity)")
                                    .font(.caption)
                                    .monospaced()
                                if let cost = part.unitCost {
                                    Text(String(format: "$%.2f", cost * Double(part.quantity)))
                                        .font(.caption)
                                        .monospaced()
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                        let totalCost = group.parts.compactMap { p in
                            p.unitCost.map { $0 * Double(p.quantity) }
                        }.reduce(0, +)
                        if totalCost > 0 {
                            HStack {
                                Spacer()
                                Text(String(format: "Subtotal: $%.2f", totalCost))
                                    .font(.caption)
                                    .fontWeight(.medium)
                            }
                        }
                    }
                    .padding(.vertical, 2)
                }

                // Action buttons
                HStack(spacing: 12) {
                    Button {
                        showGeneratePOsConfirmation = true
                    } label: {
                        Label(
                            isGenerating ? "Generating..." : "Generate \(poPreviewGroups.count) PO\(poPreviewGroups.count == 1 ? "" : "s")",
                            systemImage: "doc.badge.plus"
                        )
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isGenerating)

                    Button {
                        withAnimation { showSavedToast = true }
                    } label: {
                        Text("Save for Later")
                            .font(.subheadline)
                    }
                    .buttonStyle(.bordered)
                }
            }
        } header: {
            Text("PO Preview")
        }
    }

    private struct POPreviewGroup {
        let supplierId: Int64
        let supplierName: String
        let parts: [POPreviewPart]
    }

    private struct POPreviewPart {
        let partId: Int64
        let partName: String
        let quantity: Int
        let unitCost: Double?
        let jpoLineIds: [Int64]
    }

    private var poPreviewGroups: [POPreviewGroup] {
        var groups: [Int64: (name: String, parts: [POPreviewPart])] = [:]
        for item in cachedReadyToGenerate {
            guard let supplierId = selectedSupplier[item.id] else { continue }
            let supplierName = item.suppliers.first(where: { $0.id == supplierId })?.name ?? "Unknown"
            let unitCost = item.suppliers.first(where: { $0.id == supplierId })?.unitPrice
            let allLineIds = item.sources.flatMap(\.lineIds)
            let orderQty = effectiveOrderQty(for: item)

            let part = POPreviewPart(
                partId: item.id,
                partName: item.partName,
                quantity: orderQty,
                unitCost: unitCost,
                jpoLineIds: allLineIds
            )
            groups[supplierId, default: (name: supplierName, parts: [])].parts.append(part)
        }
        return groups.map { POPreviewGroup(supplierId: $0.key, supplierName: $0.value.name, parts: $0.value.parts) }
            .sorted { $0.supplierName < $1.supplierName }
    }

    // MARK: - Confirmation Dialog Content

    private var generatePOsConfirmationTitle: String {
        let count = poPreviewGroups.count
        return "Generate \(count) Purchase Order\(count == 1 ? "" : "s")?"
    }

    private var generatePOsConfirmationMessage: String {
        let totalCost = poPreviewGroups.flatMap(\.parts).compactMap { p in
            p.unitCost.map { $0 * Double(p.quantity) }
        }.reduce(0, +)
        if totalCost > 0 {
            return String(format: "This will create %d PO(s) totalling $%.2f. This action cannot be undone.", poPreviewGroups.count, totalCost)
        }
        return "This will create \(poPreviewGroups.count) PO(s). This action cannot be undone."
    }

    private var pullConfirmationTitle: String {
        guard let item = pendingPullItem else { return "Pull Stock?" }
        return "Pull \(pendingPullQty) \(item.partName)?"
    }

    private var pullConfirmationMessage: String {
        guard let item = pendingPullItem else { return "" }
        var msg = "Move \(pendingPullQty) unit(s) of \(item.partName) from Warehouse to Pulled Staging."
        if pendingPullOrderQty > 0 {
            msg += " \(pendingPullOrderQty) unit(s) will still need to be ordered."
        }
        msg += " This movement cannot be reversed without a manual return."
        return msg
    }

    private func generatePOs() {
        guard let service = appCore.ordersService else {
            generateError = "Orders service not available"
            return
        }
        isGenerating = true
        defer { isGenerating = false }

        let generateItems = poPreviewGroups.flatMap { group in
            group.parts.map { part in
                OrdersService.ProcurementGenerateItem(
                    partId: part.partId,
                    supplierId: group.supplierId,
                    quantity: part.quantity,
                    unitCost: part.unitCost,
                    jpoLineIds: part.jpoLineIds
                )
            }
        }

        do {
            let result = try service.generatePOsFromProcurement(items: generateItems)
            let poNumbers = result.createdPOs.map(\.poNumber).joined(separator: ", ")
            generateSuccess = "Created \(result.createdPOs.count) PO(s): \(poNumbers) with \(result.totalLineItems) line items"
            Haptics.success()
            // Clear checked items that were generated
            for item in cachedReadyToGenerate {
                checkedParts.remove(item.id)
            }
        } catch {
            generateError = userFriendlyError(error, context: "generate document")
        }
    }

    // MARK: - Supplier Selection

    @ViewBuilder
    private func supplierSelectionView(_ item: OrdersService.ProcurementItem) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Supplier")
                    .font(.caption)
                    .fontWeight(.semibold)
                Spacer()
                // Split by JPO button for multi-source parts
                let jpoSources = item.sources.filter { $0.sourceType == "jpo" }
                if jpoSources.count > 1 {
                    Button {
                        withAnimation {
                            splitByJPOPartId = splitByJPOPartId == item.id ? nil : item.id
                        }
                    } label: {
                        Text(splitByJPOPartId == item.id ? "Collapse" : "Split by JPO")
                            .font(.caption2)
                            .foregroundStyle(Color.accentColor)
                    }
                }
            }

            if splitByJPOPartId == item.id {
                // Per-JPO supplier selection
                perJPOSupplierView(item)
            } else {
                // Single supplier selection for the whole part
                ForEach(item.suppliers) { supplier in
                    supplierRow(supplier, isSelected: selectedSupplier[item.id] == supplier.id)
                        .onTapGesture {
                            selectedSupplier[item.id] = supplier.id
                        }
                }
            }
        }
    }

    private func perJPOSupplierView(_ item: OrdersService.ProcurementItem) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(item.sources.filter { $0.sourceType == "jpo" }) { source in
                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        Text(source.sourceName)
                            .font(.caption)
                            .fontWeight(.medium)
                        Spacer()
                        Text("qty: \(source.quantity)")
                            .font(.caption)
                            .monospaced()
                    }

                    // Supplier picker per JPO source
                    Picker("Supplier", selection: Binding(
                        get: { perJPOSupplier[source.id] ?? item.suppliers.first?.id ?? 0 },
                        set: { perJPOSupplier[source.id] = $0 }
                    )) {
                        ForEach(item.suppliers) { s in
                            HStack {
                                Text(s.name)
                                if let tag = s.tag {
                                    Text(tagLabel(tag))
                                }
                            }.tag(s.id)
                        }
                    }
                    .pickerStyle(.menu)
                    .font(.caption)
                }
                .padding(.vertical, 2)
            }
        }
        .padding(.leading, 8)
    }

    private func supplierRow(_ supplier: OrdersService.PartSupplierOption, isSelected: Bool) -> some View {
        HStack(spacing: 8) {
            // Radio button
            Image(systemName: isSelected ? "largecircle.fill.circle" : "circle")
                .foregroundStyle(Color.accentColor)
                .font(.caption)
                .accessibilityHidden(true)

            // Preferred star
            if supplier.isPreferred {
                Image(systemName: "star.fill")
                    .font(.caption2)
                    .foregroundStyle(.yellow)
                    .accessibilityLabel("Preferred supplier")
            }

            Text(supplier.name)
                .font(.caption)
                .lineLimit(1)

            if let price = supplier.unitPrice {
                Text(String(format: "$%.2f", price))
                    .font(.caption)
                    .monospaced()
                    .foregroundStyle(.secondary)
            }

            Spacer()

            // Tag badge
            if let tag = supplier.tag {
                supplierTagBadge(tag)
            }

            // Today cutoff badge
            if supplier.isToday2PM {
                HStack(spacing: 2) {
                    Image(systemName: "shippingbox.fill")
                        .font(.caption2)
                    Text("today")
                        .font(.caption2)
                }
                .foregroundStyle(.blue)
            }
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
    }

    private func supplierTagBadge(_ tag: String) -> some View {
        let (label, color) = tagInfo(tag)
        return Text(label)
            .font(.system(.caption2, weight: .semibold))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Capsule().fill(color.opacity(0.15)))
            .foregroundStyle(color)
    }

    private func tagInfo(_ tag: String) -> (String, Color) {
        switch tag {
        case "cheapest": return ("Cheapest", .green)
        case "rated": return ("Top Rated", .purple)
        case "fastest": return ("Fastest", .orange)
        default: return (tag.capitalized, .secondary)
        }
    }

    private func tagLabel(_ tag: String) -> String {
        switch tag {
        case "cheapest": return "- Cheapest"
        case "rated": return "- Top Rated"
        case "fastest": return "- Fastest"
        default: return ""
        }
    }

    // MARK: - Pull Options

    @ViewBuilder
    private func pullOptionsView(_ item: OrdersService.ProcurementItem) -> some View {
        if item.shopStock > 0 && item.totalDemand > 0 {
            let currentlyPulling = isPulling.contains(item.id)

            VStack(spacing: 4) {
                if let decision = pullDecisions[item.id] {
                    // Show the active pull decision
                    HStack(spacing: 6) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                            .font(.caption)
                        VStack(alignment: .leading, spacing: 1) {
                            if decision.pullQty > 0 {
                                Text("Pulling \(decision.pullQty) from shelf")
                                    .font(.caption)
                                    .foregroundStyle(.green)
                            }
                            if decision.orderQty > 0 {
                                Text("Ordering \(decision.orderQty)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            } else {
                                Text("No order needed")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        Button {
                            pullDecisions.removeValue(forKey: item.id)
                            updateReadyToGenerate()
                        } label: {
                            Text("Change")
                                .font(.caption2)
                                .foregroundStyle(Color.accentColor)
                        }
                    }
                    .padding(.vertical, 4)
                    .padding(.horizontal, 8)
                    .background(Color.green.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                } else {
                    // Option 1: Pull to Target + order remaining (RECOMMENDED)
                    let pullToTarget = max(0, item.shopStock - item.targetStock)
                    let orderAfterPull = max(0, item.totalDemand - pullToTarget)
                    if pullToTarget > 0 {
                        pullButton(
                            item: item,
                            label: "Pull \(pullToTarget) to target" + (orderAfterPull > 0 ? " + order \(orderAfterPull)" : ""),
                            pullQty: pullToTarget,
                            orderQty: orderAfterPull,
                            style: .recommended,
                            isLoading: currentlyPulling
                        )
                    }

                    // Option 2: Pull all + order remaining
                    let orderAfterAll = max(0, item.totalDemand - item.shopStock)
                    if item.shopStock >= item.totalDemand {
                        pullButton(
                            item: item,
                            label: "Pull \(item.totalDemand) from shelf (no order needed)",
                            pullQty: item.totalDemand,
                            orderQty: 0,
                            style: pullToTarget == 0 ? .recommended : .normal,
                            isLoading: currentlyPulling
                        )
                    } else {
                        pullButton(
                            item: item,
                            label: "Pull all \(item.shopStock) + order \(orderAfterAll)",
                            pullQty: item.shopStock,
                            orderQty: orderAfterAll,
                            style: .normal,
                            isLoading: currentlyPulling
                        )
                    }

                    // Option 3: Pull to MIN + order remaining (only if different from target)
                    if item.minStock > 0 && item.minStock != item.targetStock {
                        let pullToMin = max(0, item.shopStock - item.minStock)
                        let orderAfterMin = max(0, item.totalDemand - pullToMin)
                        if pullToMin > 0 && pullToMin != pullToTarget {
                            pullButton(
                                item: item,
                                label: "Pull \(pullToMin) to MIN + order \(orderAfterMin)",
                                pullQty: pullToMin,
                                orderQty: orderAfterMin,
                                style: .normal,
                                isLoading: currentlyPulling
                            )
                        }
                    }

                    // Option 4: Order all (no pull)
                    pullButton(
                        item: item,
                        label: "Order all \(item.totalDemand)",
                        pullQty: 0,
                        orderQty: item.totalDemand,
                        style: .subdued,
                        isLoading: false
                    )
                }

                // Over MAX: force pull at least enough to bring below MAX
                if item.maxStock > 0 && item.shopStock > item.maxStock {
                    let forcePull = item.shopStock - item.maxStock
                    HStack(spacing: 4) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                            .font(.caption2)
                            .accessibilityHidden(true)
                        Text("Over MAX by \(forcePull) — must pull at least \(forcePull)")
                            .font(.caption2)
                            .foregroundStyle(.red)
                    }
                    .padding(.vertical, 4)
                }
            }
        }
    }

    private enum PullButtonStyle {
        case recommended, normal, subdued
    }

    private func pullButton(
        item: OrdersService.ProcurementItem,
        label: String,
        pullQty: Int,
        orderQty: Int,
        style: PullButtonStyle,
        isLoading: Bool
    ) -> some View {
        Button {
            requestPullAction(item: item, pullQty: pullQty, orderQty: orderQty)
        } label: {
            HStack(spacing: 6) {
                if isLoading {
                    ProgressView()
                        .controlSize(.mini)
                }
                Text(label)
                    .font(.caption)
                Spacer()
                if style == .recommended {
                    Text("RECOMMENDED")
                        .font(.system(.caption2, weight: .bold))
                        .foregroundStyle(Color.accentColor)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 6)
            .padding(.horizontal, 10)
            .background(pullButtonBackground(style))
            .foregroundStyle(pullButtonForeground(style))
            .clipShape(RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
        .disabled(isLoading)
    }

    private func pullButtonBackground(_ style: PullButtonStyle) -> Color {
        switch style {
        case .recommended: Color.accentColor.opacity(0.15)
        case .normal: Color.secondary.opacity(0.08)
        case .subdued: Color.secondary.opacity(0.04)
        }
    }

    private func pullButtonForeground(_ style: PullButtonStyle) -> Color {
        switch style {
        case .recommended: Color.accentColor
        case .normal: Color.primary
        case .subdued: Color.secondary
        }
    }

    // MARK: - Pull Action Execution

    /// Stores the pending pull intent and shows the confirmation dialog.
    private func requestPullAction(item: OrdersService.ProcurementItem, pullQty: Int, orderQty: Int) {
        // If no pull needed (order-all), just record the decision — no confirmation required
        if pullQty == 0 {
            pullDecisions[item.id] = (pullQty: 0, orderQty: orderQty)
            updateReadyToGenerate()
            return
        }
        pendingPullItem = item
        pendingPullQty = pullQty
        pendingPullOrderQty = orderQty
        showPullConfirmation = true
    }

    /// Executes a pull from warehouse shelf to pulled-staging and records the decision.
    private func executePullAction(item: OrdersService.ProcurementItem, pullQty: Int, orderQty: Int) {
        guard let warehouseService = appCore.warehouseService else {
            pullActionError = "Warehouse service not available"
            return
        }
        guard let userId = appCore.currentUser?.id else {
            pullActionError = "Not logged in. Please log in and try again."
            return
        }

        isPulling.insert(item.id)
        defer { isPulling.remove(item.id) }

        do {
            // Verify stock is still available before pulling
            let currentStock = try warehouseService.getStockQty(
                partId: item.id,
                locationType: "warehouse",
                locationId: 1
            )

            let actualPull = min(pullQty, currentStock)
            if actualPull <= 0 {
                pullActionError = "No stock available on shelf for \(item.partName)"
                return
            }

            // Create the warehouse -> pulled movement
            try warehouseService.createMovement(
                partId: item.id,
                qty: actualPull,
                fromLocationType: "warehouse",
                fromLocationId: 1,
                toLocationType: "pulled",
                toLocationId: 1,
                movementType: StockMovement.MovementType.transfer.rawValue,
                reason: "Procurement pull",
                notes: "Pulled \(actualPull) for procurement demand of \(item.totalDemand)",
                performedBy: userId
            )

            // Calculate adjusted order quantity
            let adjustedOrder = max(0, item.totalDemand - actualPull)

            // Record the decision
            pullDecisions[item.id] = (pullQty: actualPull, orderQty: adjustedOrder)
            updateReadyToGenerate()

            // Show confirmation
            if actualPull < pullQty {
                pullActionSuccess = "Pulled \(actualPull) of \(pullQty) for \(item.partName) (stock limited). Order \(adjustedOrder) remaining."
            } else if adjustedOrder > 0 {
                pullActionSuccess = "Pulled \(actualPull) \(item.partName) to staging. Order \(adjustedOrder) remaining."
            } else {
                pullActionSuccess = "Pulled \(actualPull) \(item.partName) to staging. No order needed."
            }
            Haptics.success()

            // Reload to reflect updated stock levels
            loadData()
        } catch {
            pullActionError = userFriendlyError(error, context: "load procurement")
        }
    }

    // MARK: - Source Icons

    @ViewBuilder
    private func sourceIcon(_ type: String) -> some View {
        switch type {
        case "jpo":
            Image(systemName: "doc.text")
                .foregroundStyle(.blue)
                .font(.caption2)
                .accessibilityHidden(true)
        case "wishlist":
            Image(systemName: "heart")
                .foregroundStyle(.pink)
                .font(.caption2)
                .accessibilityHidden(true)
        case "forecast":
            Image(systemName: "chart.line.uptrend.xyaxis")
                .foregroundStyle(.green)
                .font(.caption2)
                .accessibilityHidden(true)
        case "overstock":
            Image(systemName: "exclamationmark.triangle")
                .foregroundStyle(.red)
                .font(.caption2)
                .accessibilityHidden(true)
        default:
            Image(systemName: "circle")
                .foregroundStyle(.secondary)
                .font(.caption2)
                .accessibilityHidden(true)
        }
    }

    // MARK: - Data Loading

    private func loadData() {
        guard let service = appCore.ordersService else {
            loadError = "Orders service not available"
            isLoading = false
            return
        }
        isLoading = items.isEmpty
        loadError = nil
        do {
            let newItems = try service.getProcurementDemand()
            // Clean up pull decisions for parts no longer in the list
            let currentIds = Set(newItems.map(\.id))
            pullDecisions = pullDecisions.filter { currentIds.contains($0.key) }
            items = newItems
            // Auto-select preferred suppliers
            for item in items {
                if selectedSupplier[item.id] == nil,
                   let preferred = item.suppliers.first(where: { $0.isPreferred }) {
                    selectedSupplier[item.id] = preferred.id
                }
            }
            // Single-pass source counts — avoids per-render filter scans in smart card filters.
            // seenTypes deduplicates per item: a part may have multiple JPO sources (one per job),
            // but the card should count unique parts with that source type, not source instances.
            var counts: [String: Int] = [:]
            for item in items {
                var seenTypes: Set<String> = []
                for source in item.sources {
                    let t = source.sourceType
                    if seenTypes.insert(t).inserted {
                        counts[t, default: 0] += 1
                    }
                }
                if item.urgency == "overstock" {
                    counts["overstock", default: 0] += 1
                }
            }
            sourceCounts = counts
            updateReadyToGenerate()
            postAIContext()
        } catch {
            loadError = userFriendlyError(error, context: "load procurement data")
        }
        isLoading = false
    }

    private func postAIContext() {
        let sourceText = sourceCounts
            .map { "\($0.key): \($0.value)" }
            .sorted()
            .joined(separator: ", ")
        let readyQuantity = cachedReadyToGenerate.reduce(0) { $0 + effectiveOrderQty(for: $1) }
        let selectedSupplierCount = selectedSupplier.count
        let visibleExamples = filteredItems.prefix(5).map { item in
            "\(item.partName) need \(item.totalDemand), stock \(item.shopStock)"
        }.joined(separator: "; ")
        let context = """
        Procurement page. Read-only context.
        Total demand rows: \(items.count), visible rows: \(filteredItems.count), selected rows: \(checkedParts.count), rows with supplier selected: \(selectedSupplierCount).
        Active source filter: \(sourceFilter ?? "all"), search active: \(!searchText.isEmpty), source counts: \(sourceText.isEmpty ? "none" : sourceText).
        Ready-to-generate preview groups: \(poPreviewGroups.count), ready order quantity: \(readyQuantity), pull decisions: \(pullDecisions.count).
        Visible examples: \(visibleExamples.isEmpty ? "none" : visibleExamples).
        Available read-only guidance: explain demand sources, supplier tags, pull-vs-order choices, current filters, and PO preview state. Do not generate POs or change selections directly.
        """
        NotificationCenter.default.post(
            name: .procurementPageActive,
            object: nil,
            userInfo: ["context": context]
        )
    }
}
