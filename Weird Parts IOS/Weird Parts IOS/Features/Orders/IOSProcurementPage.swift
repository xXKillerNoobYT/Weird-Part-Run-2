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

    var body: some View {
        VStack(spacing: 0) {
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
        .refreshable { loadData() }
        .task { loadData() }
    }

    // MARK: - Smart Card Filters

    private var smartCardFilters: some View {
        let jpoCount = items.filter { $0.sources.contains { $0.sourceType == "jpo" } }.count
        let wishlistCount = items.filter { $0.sources.contains { $0.sourceType == "wishlist" } }.count
        let forecastCount = items.filter { $0.sources.contains { $0.sourceType == "forecast" } }.count
        let overstockCount = items.filter { $0.urgency == "overstock" }.count

        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                smartCard("JPO Parts", count: jpoCount, icon: "doc.text.fill", filter: "jpo")
                smartCard("Wishlist", count: wishlistCount, icon: "heart.fill", filter: "wishlist")
                smartCard("Forecast", count: forecastCount, icon: "chart.line.uptrend.xyaxis", filter: "forecast")
                smartCard("Overstock", count: overstockCount, icon: "exclamationmark.triangle.fill", filter: "overstock")
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
        guard let filter = sourceFilter else { return items }
        if filter == "overstock" {
            return items.filter { $0.urgency == "overstock" }
        }
        return items.filter { $0.sources.contains { $0.sourceType == filter } }
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
                }
            }

            ForEach(filteredItems) { item in
                procurementRow(item)
            }
        }
        .listStyle(.insetGrouped)
    }

    private func procurementRow(_ item: OrdersService.ProcurementItem) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            // Part header
            HStack {
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
                    Text("Need: \(item.totalDemand)")
                        .font(.subheadline)
                        .fontWeight(.bold)
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
                    Text("Below minimum stock level")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }

            // Sources
            ForEach(item.sources) { source in
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
            }

            // Pull options
            pullOptionsView(item)

            // Generic part lock indicator
            if item.isGeneric {
                HStack(spacing: 4) {
                    Image(systemName: "lock.fill")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                    Text("Generic — supplier locked per job")
                        .font(.caption2)
                        .foregroundStyle(.orange)
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

            // Preferred star
            if supplier.isPreferred {
                Image(systemName: "star.fill")
                    .font(.caption2)
                    .foregroundStyle(.yellow)
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
            VStack(spacing: 4) {
                // Option 1: Pull to Target + order remaining (RECOMMENDED)
                let pullToTarget = max(0, item.shopStock - item.targetStock)
                let orderAfterPull = max(0, item.totalDemand - pullToTarget)
                if pullToTarget > 0 {
                    pullButton(
                        label: "Pull \(pullToTarget) to target" + (orderAfterPull > 0 ? " + order \(orderAfterPull)" : ""),
                        isRecommended: true
                    )
                }

                // Option 2: Pull all + order remaining
                let orderAfterAll = max(0, item.totalDemand - item.shopStock)
                if item.shopStock >= item.totalDemand {
                    pullButton(
                        label: "Pull \(item.totalDemand) from shelf (no order needed)",
                        isRecommended: pullToTarget == 0
                    )
                } else {
                    pullButton(
                        label: "Pull all \(item.shopStock) + order \(orderAfterAll)",
                        isRecommended: false
                    )
                }

                // Option 3: Order all
                pullButton(label: "Order all \(item.totalDemand)", isRecommended: false)
            }
        }
    }

    private func pullButton(label: String, isRecommended: Bool) -> some View {
        Button { /* TODO: execute pull/order action — wired in 28C */ } label: {
            Text(label)
                .font(.caption)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 6)
                .padding(.horizontal, 10)
                .background(isRecommended ? Color.accentColor.opacity(0.12) : Color.secondary.opacity(0.08))
                .foregroundStyle(isRecommended ? Color.accentColor : Color.secondary)
                .clipShape(RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Source Icons

    @ViewBuilder
    private func sourceIcon(_ type: String) -> some View {
        switch type {
        case "jpo":
            Image(systemName: "doc.text")
                .foregroundStyle(.blue)
                .font(.caption2)
        case "wishlist":
            Image(systemName: "heart")
                .foregroundStyle(.pink)
                .font(.caption2)
        case "forecast":
            Image(systemName: "chart.line.uptrend.xyaxis")
                .foregroundStyle(.green)
                .font(.caption2)
        case "overstock":
            Image(systemName: "exclamationmark.triangle")
                .foregroundStyle(.red)
                .font(.caption2)
        default:
            Image(systemName: "circle")
                .foregroundStyle(.secondary)
                .font(.caption2)
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
            items = try service.getProcurementDemand()
            // Auto-select preferred suppliers
            for item in items {
                if selectedSupplier[item.id] == nil,
                   let preferred = item.suppliers.first(where: { $0.isPreferred }) {
                    selectedSupplier[item.id] = preferred.id
                }
            }
        } catch {
            loadError = error.localizedDescription
        }
        isLoading = false
    }
}
