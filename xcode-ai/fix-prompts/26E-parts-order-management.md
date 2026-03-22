# 26E — Parts Order Management Page (NEW)

> **Chain position:** 26A → 26B → 26C → 26D → **26E** → 26F
> **Prerequisite:** 26D complete (supplier CRM on PO detail)
> **Plan:** `docs/plans/ios-purchase-orders-page.md` — Section 7
> **Log file:** `xcode-ai/prompt-results-log.md`

## Instructions

**IMPORTANT:** Before implementing, first plan your approach by reading all files mentioned below. Understand the current state, then implement. When done, wait for user confirmation before proceeding to the next prompt.

## Context

This is a NEW page — `IOSPartsOrderManagementPage.swift`. It's a supplier-centric view showing ALL parts across ALL POs for one supplier, grouped by PO then by Job. It lives as its own tab under Orders AND is accessible via [Manage Parts] button on the PO Detail page.

The purpose: the office person needs to see ALL parts they've ordered from a supplier across multiple POs and jobs. They can multi-select parts to move between POs, change quantities, or remove + hold for a different supplier.

**Files to read first:**
- `docs/plans/ios-purchase-orders-page.md` — Section 7 (Parts Order Management design)
- `Weird Parts IOS/Weird Parts IOS/Features/Orders/OrdersRouter.swift` — current Orders nav tabs
- `core/Sources/WiredPartCore/Services/OrdersService.swift` — PO listing/detail methods
- `Weird Parts IOS/Weird Parts IOS/Navigation/NavigationConfig.swift` — route definitions

**Files to create:**
- `Weird Parts IOS/Weird Parts IOS/Features/Orders/IOSPartsOrderManagementPage.swift`

**Files to modify:**
- `Weird Parts IOS/Weird Parts IOS/Features/Orders/OrdersRouter.swift` — add new tab
- `Weird Parts IOS/Weird Parts IOS/Navigation/NavigationConfig.swift` — add route
- `core/Sources/WiredPartCore/Services/OrdersService.swift` — add query methods

## Task

### Step 1: Add service methods

In `OrdersService.swift`, add methods to query parts across POs grouped by supplier:

```swift
/// A part across POs for the parts management page.
public struct PartsManagementRow: Sendable, Identifiable {
    public let id: Int64          // po_line_items.id
    public let poId: Int64
    public let poNumber: String
    public let poStatus: String
    public let jobId: Int64?
    public let jobName: String?
    public let source: String     // "job", "forecast", "wishlist", "auto"
    public let partId: Int64?
    public let partName: String
    public let partCode: String?
    public let quantityOrdered: Int
    public let quantityReceived: Int
    public let unitPrice: Double?
    public let lineStatus: String  // "pending", "received", "backorder", "cancelled"
    public let expectedDelivery: String?
    public let orderDate: String?
}

/// Get all parts across all POs for a specific supplier.
public func getPartsForSupplier(supplierId: Int64, poStatuses: [String]? = nil) throws -> [PartsManagementRow] {
    try db.writer.read { dbConn in
        var where_clauses = ["po.supplier_id = ?", "po.deleted_at IS NULL"]
        var args: [DatabaseValueConvertible?] = [supplierId]

        if let statuses = poStatuses, !statuses.isEmpty {
            let placeholders = statuses.map { _ in "?" }.joined(separator: ", ")
            where_clauses.append("po.status IN (\(placeholders))")
            args.append(contentsOf: statuses)
        }

        let sql = """
            SELECT li.id, li.po_id, po.po_number, po.status AS po_status,
                   li.part_id, COALESCE(p.name, li.description, 'Item') AS part_name,
                   p.code AS part_code,
                   li.quantity_ordered, li.quantity_received, li.unit_price,
                   li.status AS line_status, li.notes,
                   po.expected_delivery, po.order_date
            FROM po_line_items li
            JOIN purchase_orders po ON po.id = li.po_id
            LEFT JOIN parts p ON p.id = li.part_id
            WHERE \(where_clauses.joined(separator: " AND "))
            ORDER BY po.po_number ASC, li.id ASC
            """

        return try Row.fetchAll(dbConn, sql: sql, arguments: StatementArguments(args)).map { row in
            PartsManagementRow(
                id: row["id"],
                poId: row["po_id"],
                poNumber: row["po_number"],
                poStatus: row["po_status"],
                jobId: nil, // TODO: link via jpo_line_id → jpo → job
                jobName: nil, // TODO: resolve job name
                source: "job",
                partId: row["part_id"],
                partName: row["part_name"],
                partCode: row["part_code"],
                quantityOrdered: row["quantity_ordered"],
                quantityReceived: row["quantity_received"],
                unitPrice: row["unit_price"],
                lineStatus: row["line_status"],
                expectedDelivery: row["expected_delivery"],
                orderDate: row["order_date"]
            )
        }
    }
}

/// Get list of suppliers that have active POs.
public func getSuppliersWithActivePOs() throws -> [(id: Int64, name: String, poCount: Int)] {
    try db.writer.read { dbConn in
        let rows = try Row.fetchAll(dbConn, sql: """
            SELECT s.id, s.name, COUNT(DISTINCT po.id) AS po_count
            FROM suppliers s
            JOIN purchase_orders po ON po.supplier_id = s.id
            WHERE po.deleted_at IS NULL AND po.status NOT IN ('received', 'cancelled')
            GROUP BY s.id
            ORDER BY s.name ASC
            """)
        return rows.map { (id: $0["id"] as Int64, name: $0["name"] as String, poCount: $0["po_count"] as Int) }
    }
}
```

### Step 2: Create the page

Create `IOSPartsOrderManagementPage.swift`:

```swift
import SwiftUI
import WiredPartCore

/// Supplier-centric parts view across all POs.
///
/// Shows all parts ordered from a supplier across all active POs,
/// grouped by PO then by job. Supports multi-select for part-level
/// actions: move to different PO, change qty, remove + hold.
struct IOSPartsOrderManagementPage: View {
    @EnvironmentObject private var appCore: AppCore

    /// Optional pre-filter to a specific supplier (from PO Detail "Manage Parts" button).
    var preSelectedSupplierId: Int64? = nil

    @State private var suppliers: [(id: Int64, name: String, poCount: Int)] = []
    @State private var selectedSupplierId: Int64?
    @State private var allRows: [OrdersService.PartsManagementRow] = []
    @State private var isLoading = true
    @State private var loadError: String?

    // Filter state
    @State private var showDraft = true
    @State private var showActive = true
    @State private var showPartial = true
    @State private var showReceived = false
    @State private var showCancelled = false

    @State private var showWaiting = true
    @State private var showBackorder = true
    @State private var showPriceChanged = true
    @State private var showReceivedParts = false

    // Selection
    @State private var selectedPartIds: Set<Int64> = []

    var body: some View {
        VStack(spacing: 0) {
            // Supplier picker
            supplierPicker

            // PO status filters
            poStatusFilters

            // Part status filters
            partStatusFilters

            // Parts list or loading/error
            if isLoading {
                ProgressView("Loading parts...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error = loadError {
                ErrorStateView(message: error) { Task { await loadParts() } }
            } else if filteredRows.isEmpty {
                EmptyStateView(
                    icon: "shippingbox",
                    title: "No Parts",
                    message: "No parts match the current filters."
                )
            } else {
                partsList
            }

            // Selection action bar
            if !selectedPartIds.isEmpty {
                selectionActionBar
            }
        }
        .navigationTitle("Parts Management")
        .task {
            await loadSuppliers()
            if let pre = preSelectedSupplierId {
                selectedSupplierId = pre
            } else if let first = suppliers.first {
                selectedSupplierId = first.id
            }
            await loadParts()
        }
    }

    // MARK: - Supplier Picker

    private var supplierPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(suppliers, id: \.id) { supplier in
                    Button {
                        selectedSupplierId = supplier.id
                        selectedPartIds.removeAll()
                        Task { await loadParts() }
                    } label: {
                        VStack(spacing: 2) {
                            Text(supplier.name)
                                .font(.caption)
                                .fontWeight(selectedSupplierId == supplier.id ? .bold : .regular)
                            Text("\(supplier.poCount) POs")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(selectedSupplierId == supplier.id ? Color.accentColor : Color.secondary.opacity(0.15))
                        )
                        .foregroundStyle(selectedSupplierId == supplier.id ? .white : .primary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
        }
    }

    // MARK: - PO Status Filters

    private var poStatusFilters: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                filterToggle("Draft", isOn: $showDraft, color: .secondary)
                filterToggle("Active", isOn: $showActive, color: .blue)
                filterToggle("Partial", isOn: $showPartial, color: .purple)
                filterToggle("Received", isOn: $showReceived, color: .green)
                filterToggle("Cancelled", isOn: $showCancelled, color: .red)
            }
            .padding(.horizontal)
            .padding(.vertical, 4)
        }
    }

    // MARK: - Part Status Filters

    private var partStatusFilters: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                filterToggle("✅ Received", isOn: $showReceivedParts, color: .green)
                filterToggle("⏳ Waiting", isOn: $showWaiting, color: .blue)
                filterToggle("🔴 Backorder", isOn: $showBackorder, color: .red)
                filterToggle("⚠️ Price Chg", isOn: $showPriceChanged, color: .orange)
            }
            .padding(.horizontal)
            .padding(.vertical, 4)
        }
    }

    private func filterToggle(_ label: String, isOn: Binding<Bool>, color: Color) -> some View {
        Button {
            isOn.wrappedValue.toggle()
        } label: {
            Text(label)
                .font(.caption2)
                .fontWeight(.medium)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(
                    Capsule().fill(isOn.wrappedValue ? color.opacity(0.2) : Color.clear)
                )
                .overlay(Capsule().stroke(color.opacity(0.4), lineWidth: 1))
                .foregroundStyle(isOn.wrappedValue ? color : .secondary)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Filtered Data

    private var filteredRows: [OrdersService.PartsManagementRow] {
        allRows.filter { row in
            // PO status filter
            let poPass: Bool = {
                switch row.poStatus {
                case "draft": return showDraft
                case "submitted", "ordered": return showActive
                case "partial": return showPartial
                case "received": return showReceived
                case "cancelled": return showCancelled
                default: return true
                }
            }()

            // Part status filter
            let partPass: Bool = {
                switch row.lineStatus {
                case "received": return showReceivedParts
                case "pending": return showWaiting
                case "backorder": return showBackorder
                default: return true
                }
            }()

            return poPass && partPass
        }
    }

    /// Group filtered rows by PO, then by job within each PO.
    private var groupedByPO: [(poNumber: String, poStatus: String, rows: [OrdersService.PartsManagementRow])] {
        let dict = Dictionary(grouping: filteredRows, by: \.poNumber)
        return dict.map { (poNumber: $0.key, poStatus: $0.value.first?.poStatus ?? "", rows: $0.value) }
            .sorted { $0.poNumber < $1.poNumber }
    }

    // MARK: - Parts List

    private var partsList: some View {
        List {
            ForEach(groupedByPO, id: \.poNumber) { group in
                Section {
                    ForEach(group.rows) { row in
                        partRow(row)
                    }
                } header: {
                    HStack {
                        Text(group.poNumber)
                            .font(.caption)
                            .fontWeight(.bold)
                        StatusBadge(text: group.poStatus.capitalized, color: statusColor(group.poStatus))
                        Spacer()
                        if let eta = group.rows.first?.expectedDelivery {
                            Text("ETA: \(eta)")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
    }

    @ViewBuilder
    private func partRow(_ row: OrdersService.PartsManagementRow) -> some View {
        HStack(spacing: 10) {
            // Checkbox
            Button {
                if selectedPartIds.contains(row.id) {
                    selectedPartIds.remove(row.id)
                } else {
                    selectedPartIds.insert(row.id)
                }
            } label: {
                Image(systemName: selectedPartIds.contains(row.id) ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(selectedPartIds.contains(row.id) ? .accentColor : .secondary)
                    .font(.title3)
            }
            .buttonStyle(.plain)

            // Status icon
            statusIcon(row.lineStatus)

            // Part info
            VStack(alignment: .leading, spacing: 2) {
                Text(row.partName)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .lineLimit(1)
                if let code = row.partCode {
                    Text(code)
                        .font(.caption2)
                        .monospaced()
                        .foregroundStyle(.secondary)
                }
                if let job = row.jobName {
                    Text(job)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            // Qty + price
            VStack(alignment: .trailing, spacing: 2) {
                Text("qty: \(row.quantityOrdered)")
                    .font(.caption)
                if row.quantityReceived > 0 {
                    Text("\(row.quantityReceived) recv'd")
                        .font(.caption2)
                        .foregroundStyle(.green)
                }
                if let price = row.unitPrice {
                    Text(String(format: "$%.2f", price * Double(row.quantityOrdered)))
                        .font(.caption)
                        .fontWeight(.medium)
                }
            }
        }
        .frame(minHeight: 50)
    }

    @ViewBuilder
    private func statusIcon(_ status: String) -> some View {
        switch status {
        case "received":
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .font(.caption)
        case "backorder":
            Image(systemName: "clock.badge.exclamationmark")
                .foregroundStyle(.red)
                .font(.caption)
        case "pending":
            Image(systemName: "hourglass")
                .foregroundStyle(.blue)
                .font(.caption)
        default:
            Image(systemName: "circle")
                .foregroundStyle(.secondary)
                .font(.caption)
        }
    }

    // MARK: - Selection Action Bar

    private var selectionActionBar: some View {
        VStack(spacing: 0) {
            Divider()
            HStack(spacing: 12) {
                Text("\(selectedPartIds.count) selected")
                    .font(.subheadline)
                    .fontWeight(.medium)
                Spacer()
                Button("Move to PO") {
                    // TODO: Move to different PO sheet
                }
                .font(.caption)
                .buttonStyle(.bordered)
                Button("Change Qty") {
                    // TODO: Change quantity sheet
                }
                .font(.caption)
                .buttonStyle(.bordered)
                Button("Remove + Hold") {
                    // TODO: Remove and hold for different supplier
                }
                .font(.caption)
                .buttonStyle(.bordered)
                .tint(.red)
            }
            .padding(.horizontal)
            .padding(.vertical, 10)
            .background(.ultraThinMaterial)
        }
    }

    // MARK: - Helpers

    private func statusColor(_ status: String) -> Color {
        switch status {
        case "draft": .secondary
        case "submitted": .orange
        case "ordered": .blue
        case "partial": .purple
        case "received": .green
        case "cancelled": .red
        default: .secondary
        }
    }

    // MARK: - Data Loading

    private func loadSuppliers() async {
        guard let service = appCore.ordersService else { return }
        do {
            suppliers = try service.getSuppliersWithActivePOs()
        } catch {
            loadError = error.localizedDescription
        }
    }

    private func loadParts() async {
        guard let service = appCore.ordersService, let suppId = selectedSupplierId else {
            isLoading = false
            return
        }
        isLoading = allRows.isEmpty
        loadError = nil
        do {
            allRows = try service.getPartsForSupplier(supplierId: suppId)
        } catch {
            loadError = error.localizedDescription
        }
        isLoading = false
    }
}
```

### Step 3: Add to Orders router

In `OrdersRouter.swift`, add a new tab/case for Parts Management. Find the existing tab definitions and add:

```swift
// Add alongside existing tabs (Purchase Orders, JPOs, Procurement, Returns):
NavigationLink(value: "parts-management") {
    Label("Parts Management", systemImage: "list.bullet.rectangle.portrait")
}
// And handle the route:
case "parts-management":
    IOSPartsOrderManagementPage()
```

### Step 4: Add route in NavigationConfig

Add the route mapping so navigation works:

```swift
// In the orders section of routes:
"/orders/parts-management": OrdersRouter "parts-management"
```

### Step 5: Wire PO Detail [Manage Parts] button

In `IOSPODetailPage.swift`, update the `.managesParts` sheet case to pass the supplier ID:

```swift
case .managesParts:
    NavigationStack {
        IOSPartsOrderManagementPage(preSelectedSupplierId: po?.supplierId)
            .environmentObject(appCore)
    }
```

## Important Notes

- The page has TWO filter layers: PO status (Draft/Active/Partial/Received/Cancelled) and Part status (Received/Waiting/Backorder/PriceChanged)
- **Default filters:** PO: Draft+Active+Partial ON, Received+Cancelled OFF. Parts: Received OFF, all others ON.
- Multi-select uses checkboxes — selected parts show action bar at bottom
- Action bar buttons (Move/Change/Remove) are TODO stubs for now — full implementation comes in a follow-up prompt
- The page works both as a standalone Orders tab AND from PO Detail via [Manage Parts]
- `preSelectedSupplierId` pre-selects the supplier when coming from PO Detail
- Check the exact table/column names in the database — `po_line_items` or `purchase_order_lines` etc.

## Success Criteria

- [ ] New file `IOSPartsOrderManagementPage.swift` created
- [ ] Service methods: `getPartsForSupplier`, `getSuppliersWithActivePOs`
- [ ] Supplier picker at top with PO count badges
- [ ] Two filter rows: PO status toggles + Part status toggles
- [ ] Default filters match spec (Received OFF, others ON)
- [ ] Parts grouped by PO number with status badges
- [ ] Checkboxes for multi-select
- [ ] Selection action bar appears with 3 action buttons
- [ ] Page accessible from Orders nav as its own tab
- [ ] Page accessible from PO Detail via [Manage Parts] button
- [ ] Project builds with no errors

## Log Entry

```
## Prompt 26E Results (YYYY-MM-DD)
- New IOSPartsOrderManagementPage with supplier picker, dual filters
- Service methods for cross-PO parts queries
- Added to Orders router + NavigationConfig
- Wired to PO Detail [Manage Parts] button
- Build: [PASS/FAIL]
```

**Wait for user confirmation before proceeding to prompt 26F.**
