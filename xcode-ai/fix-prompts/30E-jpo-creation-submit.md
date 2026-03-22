# 30E — JPO Creation: Submit Flow + Smart Routing

> **Chain position:** 30A → 30B → 30C → 30D → **30E**
> **Prerequisite:** 30D complete (feedback loop)
> **Plan:** `docs/plans/ios-jpo-creation-page.md` — Submission Flow section + `docs/plans/ios-jpo-page.md` — Smart Routing

## Instructions

Read 30D results and both plans. When done, wait for user confirmation.

## Context

The Submit button creates a NEW JPO from the cart. Each line item gets smart-routed: if the part is in stock at the shop, it auto-creates a transfer request (no approval needed). If not in stock, it goes to "pending" for manager approval. The JPO is linked to the selected job.

**Files to modify:**
- `Weird Parts IOS/Weird Parts IOS/Features/Orders/IOSJPOCreationPage.swift` — wire Submit button
- `core/Sources/WiredPartCore/Services/OrdersService.swift` — add createJPOWithLines method

## Task

### Step 1: Add createJPOWithLines service method

```swift
/// Create a JPO with all line items in one transaction. Runs smart routing on each line.
public func createJPOWithLines(
    jobId: Int64,
    requestedBy: Int64,
    priority: String,
    deliveryOption: String,
    notes: String?,
    lines: [(partId: Int64, quantity: Int, unitPrice: Double?)]
) throws -> Int64 {
    try db.writer.write { dbConn in
        // Create the JPO
        try dbConn.execute(sql: """
            INSERT INTO job_purchase_orders
            (job_id, requested_by, status, priority, delivery_option, notes, created_at, updated_at)
            VALUES (?, ?, 'pending', ?, ?, ?, datetime('now'), datetime('now'))
            """, arguments: [jobId, requestedBy, priority, deliveryOption, notes])
        let jpoId = dbConn.lastInsertedRowID

        // Add each line item
        for line in lines {
            try dbConn.execute(sql: """
                INSERT INTO jpo_lines
                (jpo_id, part_id, quantity, unit_price, priority, line_status, created_at)
                VALUES (?, ?, ?, ?, ?, 'pending', datetime('now'))
                """, arguments: [jpoId, line.partId, line.quantity, line.unitPrice, priority])
            let lineId = dbConn.lastInsertedRowID

            // Smart routing: check shop stock
            let shopStock = try Int.fetchOne(dbConn, sql: """
                SELECT COALESCE(SUM(qty), 0) FROM stock
                WHERE part_id = ? AND deleted_at IS NULL
                """, arguments: [line.partId]) ?? 0

            if shopStock >= line.quantity {
                // In stock — auto-create transfer (no approval needed)
                try dbConn.execute(sql: """
                    UPDATE jpo_lines SET line_status = 'transfer',
                    status_updated_at = datetime('now'), status_updated_by = ?
                    WHERE id = ?
                    """, arguments: [requestedBy, lineId])
            }
            // else: stays "pending" — needs approval
        }

        // Derive overall JPO status
        let statuses = try String.fetchAll(dbConn, sql:
            "SELECT line_status FROM jpo_lines WHERE jpo_id = ?", arguments: [jpoId])
        let derived = deriveJPOStatusFromRows(statuses)
        try dbConn.execute(sql:
            "UPDATE job_purchase_orders SET status = ? WHERE id = ?", arguments: [derived, jpoId])

        return jpoId
    }
}
```

### Step 2: Wire Submit button

```swift
@State private var isSubmitting = false
@State private var submitError: String?

// In toolbar:
ToolbarItem(placement: .confirmationAction) {
    Button {
        Task { await submitOrder() }
    } label: {
        if isSubmitting {
            ProgressView()
        } else {
            Text("Submit")
                .fontWeight(.semibold)
        }
    }
    .disabled(cartItems.isEmpty || selectedJobId == nil || isSubmitting)
}

private func submitOrder() async {
    guard let service = appCore.ordersService,
          let jobId = selectedJobId ?? clockedInJobId,
          let userId = appCore.currentUser?.id else {
        submitError = "Missing job or user info"
        return
    }
    isSubmitting = true
    submitError = nil

    do {
        let lines = cartItems.map {
            (partId: $0.partId, quantity: $0.quantity, unitPrice: $0.unitPrice)
        }
        let jpoId = try service.createJPOWithLines(
            jobId: jobId,
            requestedBy: userId,
            priority: priority,
            deliveryOption: deliveryOption,
            notes: notes.isEmpty ? nil : notes,
            lines: lines
        )

        // Record companion feedback for all suggestion-accepted items
        // (already handled per-item in 30D)

        await MainActor.run {
            isSubmitting = false
            dismiss()
        }
    } catch {
        await MainActor.run {
            submitError = error.localizedDescription
            isSubmitting = false
        }
    }
}
```

### Step 3: Show submit error

```swift
.alert("Error", isPresented: .constant(submitError != nil)) {
    Button("OK") { submitError = nil }
} message: {
    Text(submitError ?? "")
}
```

### Step 4: Show submission summary before dismiss

After successful submission, briefly show what was created:

```swift
@State private var showSuccessToast = false
@State private var successMessage = ""

// After successful creation:
let transfers = cartItems.filter { $0.stockStatus == .inStock }.count
let pending = cartItems.count - transfers
successMessage = "JPO #\(jpoId) created: \(transfers) auto-transfer, \(pending) pending approval"
showSuccessToast = true

// Brief delay then dismiss
DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
    dismiss()
}
```

### Step 5: Handle job verification

If user is clocked in at a different job site than selected:

```swift
// In loadJobContext:
// If clockedInJobId exists AND user changes to a different job:
@State private var showJobVerification = false

// When user changes job while clocked in elsewhere:
.alert("Different Job", isPresented: $showJobVerification) {
    Button("Yes, for \(selectedJobName)") { }
    Button("No, use clocked-in job", role: .cancel) {
        selectedJobId = clockedInJobId
    }
} message: {
    Text("You're clocked in at a different job. Create this order for \(selectedJobName)?")
}
```

## Important Notes

- `createJPOWithLines` runs everything in one transaction — either all succeeds or all fails
- Smart routing checks shop stock for EACH line independently
- If ALL lines are in stock → JPO overall status becomes "approved" (all transfers)
- If SOME lines are in stock → status becomes "in_review" (mix of transfers and pending)
- If NO lines are in stock → status becomes "pending" (all need approval)
- The `DispatchQueue.main.asyncAfter` for dismiss is a simple toast pattern — not ideal but functional. A proper SnackBar would be better in a future pass.
- Check `createJPO` vs `createJPOWithLines` — the new method replaces the old one for the creation page. The old one may still be used by other code paths.
- Verify `delivery_option` column exists on `job_purchase_orders` (added in migration 032 from prompt 27B).

## Success Criteria

- [ ] `createJPOWithLines` method creates JPO + all lines in one transaction
- [ ] Smart routing: shop stock check → "transfer" or "pending" per line
- [ ] Overall JPO status derived from line statuses
- [ ] Submit button disabled when cart empty or no job selected
- [ ] ProgressView while submitting
- [ ] Error displayed if submission fails
- [ ] Job verification alert if different from clocked-in job
- [ ] Dismisses after successful creation
- [ ] Project builds with no errors

**JPO Creation prompt chain complete. Orders section fully covered.**
