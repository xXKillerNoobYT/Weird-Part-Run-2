# 30A — JPO Creation: 3-Panel Layout + Job Auto-Fill + Cart

> **Chain position:** **30A** → 30B → 30C → 30D → 30E
> **Prerequisite:** 27A complete (JPO list with Create button)
> **Plan:** `docs/plans/ios-jpo-creation-page.md`

## Instructions

Read the full plan first. This REPLACES `IOSUnifiedOrderPage.swift` with a proper 3-panel order builder. When done, wait for user confirmation.

## Context

Field workers need to build parts lists for jobs. The current page creates an empty JPO then sends users elsewhere to add parts. The new page is a full cart-builder: search on the left, cart in the center, suggestions on the right (mobile: stacked vertically).

**Files to create:**
- `Weird Parts IOS/Weird Parts IOS/Features/Orders/IOSJPOCreationPage.swift` — NEW file

**Files to read:**
- `docs/plans/ios-jpo-creation-page.md` — full design spec
- `core/Sources/WiredPartCore/Services/JobsService.swift` — clock-in methods for auto-fill
- `core/Sources/WiredPartCore/Services/PartsService.swift` — searchParts method

## Task

### Step 1: Create the 3-panel layout

Desktop/tablet: HStack with 3 columns (search | cart | suggestions). iPhone: VStack (search → cart → collapsible suggestions).

```swift
struct IOSJPOCreationPage: View {
    @EnvironmentObject private var appCore: AppCore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.horizontalSizeClass) private var sizeClass

    // Job context
    @State private var selectedJobId: Int64?
    @State private var selectedJobName = ""
    @State private var clockedInJobId: Int64?
    @State private var priority = "normal"
    @State private var deliveryOption = "partial"
    @State private var notes = ""

    // Cart
    @State private var cartItems: [CartItem] = []

    // Search
    @State private var searchText = ""
    @State private var searchResults: [Part] = []

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Header: Job + Priority + Delivery
                jobHeader

                if sizeClass == .regular {
                    // iPad/Desktop: side-by-side
                    HStack(spacing: 0) {
                        searchPanel.frame(maxWidth: .infinity)
                        Divider()
                        cartPanel.frame(maxWidth: .infinity)
                        Divider()
                        suggestionsPanel.frame(maxWidth: .infinity)
                    }
                } else {
                    // iPhone: stacked
                    ScrollView {
                        VStack(spacing: 16) {
                            searchPanel
                            cartPanel
                            suggestionsSection // collapsible
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
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Submit") { /* 30E handles this */ }
                        .disabled(cartItems.isEmpty || selectedJobId == nil)
                        .fontWeight(.semibold)
                }
            }
            .task { await loadJobContext() }
        }
    }
}
```

### Step 2: Cart item model

```swift
struct CartItem: Identifiable {
    let id = UUID()
    let partId: Int64
    let partName: String
    let partCode: String?
    var quantity: Int
    let unitPrice: Double?
    let shopStock: Int
    let stockStatus: StockStatus  // .inStock, .lowStock, .outOfStock
    var isSelected: Bool = false   // for suggestion context

    enum StockStatus: String {
        case inStock    // enough for the order
        case lowStock   // some available, not enough
        case outOfStock // none available
    }
}
```

### Step 3: Job header with auto-fill

```swift
private var jobHeader: some View {
    VStack(spacing: 8) {
        if let jobName = clockedInJobId != nil ? selectedJobName : nil {
            HStack {
                VStack(alignment: .leading) {
                    Text(jobName).fontWeight(.medium)
                    Text("Clocked in").font(.caption).foregroundStyle(.green)
                }
                Spacer()
                Button("Change") { clockedInJobId = nil; selectedJobId = nil }
                    .font(.caption)
            }
        } else {
            // Job picker
            // Load active jobs, let user pick
        }

        HStack {
            Picker("Priority", selection: $priority) {
                Text("Normal").tag("normal")
                Text("High").tag("high")
                Text("Urgent").tag("urgent")
            }
            .pickerStyle(.segmented)

            Picker("Delivery", selection: $deliveryOption) {
                Text("As available").tag("partial")
                Text("Wait for full").tag("full")
            }
            .pickerStyle(.menu)
        }
    }
    .padding()
}
```

### Step 4: Search panel

```swift
private var searchPanel: some View {
    VStack(alignment: .leading, spacing: 8) {
        HStack {
            Image(systemName: "magnifyingglass")
            TextField("Search parts...", text: $searchText)
                .onChange(of: searchText) { searchParts() }
        }
        .padding(8)
        .background(Color.secondary.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 8))

        Button { /* QR scan — use QRScanSheet */ } label: {
            Label("Scan QR/Barcode", systemImage: "qrcode.viewfinder")
                .font(.caption)
        }

        // Search results
        ForEach(searchResults, id: \.id) { part in
            searchResultRow(part)
        }

        // Recent searches (last 5)
        if searchText.isEmpty {
            // Show recent searches
        }
    }
}
```

### Step 5: Cart panel

```swift
private var cartPanel: some View {
    VStack(alignment: .leading, spacing: 8) {
        Text("Cart (\(cartItems.count))")
            .font(.headline)

        if cartItems.isEmpty {
            Text("Add parts from search or suggestions")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, minHeight: 100)
        } else {
            ForEach($cartItems) { $item in
                cartRow(item: $item)
            }

            // Summary
            HStack {
                Text("\(cartItems.count) parts")
                    .font(.caption)
                Spacer()
                let total = cartItems.reduce(0.0) { $0 + (($1.unitPrice ?? 0) * Double($1.quantity)) }
                Text(String(format: "Est: $%.2f", total))
                    .font(.caption)
                    .fontWeight(.medium)
            }

            let transfers = cartItems.filter { $0.stockStatus == .inStock }.count
            let ordering = cartItems.count - transfers
            Text("\(transfers) transfer · \(ordering) ordering")
                .font(.caption2)
                .foregroundStyle(.secondary)

            TextEditor(text: $notes)
                .frame(height: 44)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color.secondary.opacity(0.2))
                )
                .overlay(alignment: .topLeading) {
                    if notes.isEmpty {
                        Text("Notes for the office...")
                            .font(.body)
                            .foregroundStyle(.tertiary)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 8)
                            .allowsHitTesting(false)
                    }
                }
        }
    }
}
```

### Step 6: Add-to-cart function

```swift
private func addToCart(part: Part, quantity: Int = 1) {
    // Check if already in cart
    if let idx = cartItems.firstIndex(where: { $0.partId == part.id }) {
        cartItems[idx].quantity += quantity
        return
    }

    // Check stock
    let stock = getShopStock(partId: part.id!)
    let status: CartItem.StockStatus
    if stock >= quantity { status = .inStock }
    else if stock > 0 { status = .lowStock }
    else { status = .outOfStock }

    cartItems.append(CartItem(
        partId: part.id!,
        partName: part.name,
        partCode: part.code,
        quantity: quantity,
        unitPrice: part.companySellPrice ?? part.companyCostPrice,
        shopStock: stock,
        stockStatus: status
    ))
}
```

### Step 7: Suggestions panel (placeholder for 30C)

```swift
private var suggestionsPanel: some View {
    VStack(alignment: .leading, spacing: 8) {
        Text("Suggestions")
            .font(.headline)
        Text("Companion rules and AI suggestions will appear here.")
            .font(.caption)
            .foregroundStyle(.secondary)
        // 30C fills this in
    }
}
```

## Important Notes

- The `sizeClass` detection handles iPad (side-by-side) vs iPhone (stacked)
- The suggestions panel is a placeholder — 30C adds the full companion/AI logic
- The Submit button is disabled until cart has items AND job is selected — 30E handles submission
- Stock status is calculated when adding to cart (green/yellow/red indicators)
- This file is NEW — does not modify the old IOSUnifiedOrderPage (29D removes that later)

## Success Criteria

- [ ] New IOSJPOCreationPage file created
- [ ] 3-panel layout: search/cart/suggestions
- [ ] iPad: side-by-side. iPhone: stacked vertically
- [ ] Job auto-fill from clock-in state
- [ ] Priority picker (segmented) + Delivery option picker
- [ ] Search with results showing [+ Add] buttons
- [ ] Cart with quantity steppers + stock indicators
- [ ] Cart summary: count, estimated total, transfer vs ordering
- [ ] Project builds with no errors

**Wait for user confirmation before proceeding to prompt 30B.**
