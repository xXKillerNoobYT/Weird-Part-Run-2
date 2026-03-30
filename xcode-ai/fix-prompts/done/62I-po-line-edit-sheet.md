# 62I — Replace Alert-Based Line Item Editing with a Proper Sheet on IOSPODetailPage
> Chain position: Standalone

## Task

On `IOSPODetailPage`, editing a PO line item (quantity and unit price) currently uses an `.alert` with text fields, which is cramped and hard to use on mobile. Replace it with a proper `.sheet` that has full-size input fields.

### Step 1: Create the edit sheet view

Add a new struct (can be in the same file or a new file) for the line item edit sheet:

```swift
struct POLineEditSheet: View {
    let lineItem: POLineDetail  // Or whatever the line item type is called
    let onSave: (Int, Double) -> Void  // (newQty, newUnitCost)

    @Environment(\.dismiss) private var dismiss
    @State private var quantity: String
    @State private var unitPrice: String

    init(lineItem: POLineDetail, onSave: @escaping (Int, Double) -> Void) {
        self.lineItem = lineItem
        self.onSave = onSave
        _quantity = State(initialValue: "\(lineItem.qtyOrdered)")
        _unitPrice = State(initialValue: String(format: "%.2f", lineItem.unitCost ?? 0))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Part") {
                    Text(lineItem.partName)
                        .font(.headline)
                    if let code = lineItem.partCode {
                        Text("Code: \(code)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Section("Quantity") {
                    TextField("Quantity", text: $quantity)
                        .keyboardType(.numberPad)
                        .font(.title2)
                }

                Section("Unit Price") {
                    HStack {
                        Text("$")
                        TextField("0.00", text: $unitPrice)
                            .keyboardType(.decimalPad)
                            .font(.title2)
                    }
                }

                Section {
                    let qty = Int(quantity) ?? 0
                    let price = Double(unitPrice) ?? 0
                    HStack {
                        Text("Line Total")
                            .font(.headline)
                        Spacer()
                        Text(String(format: "$%.2f", Double(qty) * price))
                            .font(.headline)
                    }
                }
            }
            .navigationTitle("Edit Line Item")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        let qty = Int(quantity) ?? lineItem.qtyOrdered
                        let price = Double(unitPrice) ?? lineItem.unitCost ?? 0
                        onSave(qty, price)
                        dismiss()
                    }
                    .disabled(Int(quantity) == nil || Int(quantity)! <= 0)
                }
            }
        }
    }
}
```

### Step 2: Replace the alert with a sheet

In `IOSPODetailPage`, find the edit-related state variables. Replace:
- Any `@State var showEditAlert = false` with `@State private var showEditLineSheet = false`
- Any `@State var editingLine: ...` — keep this, it identifies which line is being edited

Replace the `.alert` modifier with:
```swift
.sheet(item: $editingLine) { line in
    POLineEditSheet(lineItem: line) { newQty, newPrice in
        Task {
            // Call the service to update the line item
            guard let service = appCore.ordersService else { return }
            try? service.updatePOLineItem(
                lineId: line.id,
                qtyOrdered: newQty,
                unitCost: newPrice
            )
            loadData()
        }
    }
}
```

### Step 3: Adapt to actual code

Read the file first. The line item type might be called `POLineDetail`, `POLineItem`, `LineItemRow`, etc. The edit trigger might be a swipe action, a button, or a long-press menu. Adapt the sheet binding accordingly.

If `editingLine` is not currently `Identifiable`, you'll need to use a separate `@State var showEditLineSheet = false` plus `@State var editingLine: LineType?` and trigger the sheet with `.sheet(isPresented: $showEditLineSheet)`.

## Files to Modify

- `Weird Parts IOS/Weird Parts IOS/Features/Orders/IOSPODetailPage.swift`

## Success Criteria
- [ ] Tapping "Edit" on a PO line item opens a sheet (not an alert)
- [ ] Sheet shows part name, current quantity, current unit price
- [ ] Quantity and price fields are full-width, easy to type in
- [ ] Line total updates live as user types
- [ ] Save button calls the service to update the line item
- [ ] Cancel dismisses without saving
- [ ] No compile errors
