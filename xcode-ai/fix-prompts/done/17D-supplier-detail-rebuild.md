# 17D — Supplier Detail Rebuild: Brands, PO History, Traceability

> **Chain position:** 17A → 17B → 17C → **17D** → 17E–17H
> **Prerequisite:** 17C complete (performance scores calculated)
> **Log file:** `xcode-ai/prompt-results-log.md`

## Instructions

**IMPORTANT:** Before implementing, first plan your approach by reading all files mentioned below. Understand the current state, then implement the fixes. When done, wait for the user to confirm before proceeding to the next prompt.

## Context

The current `SupplierDetailSheet` shows contact info and performance scores but is missing critical business information:

1. **Which brands this supplier carries** — reverse of the brand-supplier link
2. **Part traceability** — ability to trace any part back to this supplier for returns/warranty
3. **Recent PO history** — last few orders placed with this supplier

Note: Supplier-specific pricing per part does NOT belong on this page — that goes on the Pricing page and Categories page instead.

**Key file:** `Weird Parts IOS/Weird Parts IOS/Features/Parts/PartsSuppliersPage.swift` — the `SupplierDetailSheet`

## Task

### Step 1: Add service methods for supplier relationships

In `PartsService.swift`, add:

```swift
// =========================================================================
// MARK: - 12. Supplier Detail Data
// =========================================================================

/// Get brands linked to a supplier.
public func getSupplierBrands(supplierId: Int64) throws -> [(brandId: Int64, brandName: String, partCount: Int)] {
    try db.writer.read { dbConn in
        let rows = try Row.fetchAll(dbConn, sql: """
            SELECT b.id, b.name, COUNT(DISTINCT ps.part_id) AS part_count
            FROM brand_suppliers bs
            JOIN brands b ON b.id = bs.brand_id AND b.deleted_at IS NULL
            LEFT JOIN part_suppliers ps ON ps.supplier_id = bs.supplier_id AND ps.deleted_at IS NULL
            WHERE bs.supplier_id = ? AND bs.deleted_at IS NULL
            GROUP BY b.id
            ORDER BY b.name ASC
            """, arguments: [supplierId])

        return rows.map { row in
            (brandId: row["id"] as Int64? ?? 0,
             brandName: row["name"] as String? ?? "",
             partCount: row["part_count"] as Int? ?? 0)
        }
    }
}

/// Get recent POs for a supplier.
public func getSupplierRecentPOs(supplierId: Int64, limit: Int = 10) throws -> [(poId: Int64, poNumber: String, status: String, total: Double, date: String)] {
    try db.writer.read { dbConn in
        let rows = try Row.fetchAll(dbConn, sql: """
            SELECT id, po_number, status,
                   COALESCE((SELECT SUM(qty * unit_price) FROM po_line_items WHERE po_id = purchase_orders.id AND deleted_at IS NULL), 0) AS total,
                   created_at
            FROM purchase_orders
            WHERE supplier_id = ? AND deleted_at IS NULL
            ORDER BY created_at DESC
            LIMIT ?
            """, arguments: [supplierId, limit])

        return rows.map { row in
            (poId: row["id"] as Int64? ?? 0,
             poNumber: row["po_number"] as String? ?? "",
             status: row["status"] as String? ?? "",
             total: row["total"] as Double? ?? 0,
             date: row["created_at"] as String? ?? "")
        }
    }
}

/// Count total parts this supplier is linked to.
public func getSupplierPartCount(supplierId: Int64) throws -> Int {
    try db.writer.read { dbConn in
        let row = try Row.fetchOne(dbConn, sql: """
            SELECT COUNT(*) AS cnt FROM part_suppliers
            WHERE supplier_id = ? AND deleted_at IS NULL
            """, arguments: [supplierId])
        return row?["cnt"] ?? 0
    }
}
```

### Step 2: Rebuild SupplierDetailSheet

Replace the existing `SupplierDetailSheet` with a comprehensive detail view. This page shows everything about a supplier EXCEPT per-part pricing (that belongs on the Pricing page).

```swift
private struct SupplierDetailSheet: View {
    let supplier: SupplierListRow
    var onEdit: () -> Void
    let onUpdate: () async -> Void
    @EnvironmentObject private var appCore: AppCore
    @Environment(\.dismiss) private var dismiss

    @State private var linkedBrands: [(brandId: Int64, brandName: String, partCount: Int)] = []
    @State private var recentPOs: [(poId: Int64, poNumber: String, status: String, total: Double, date: String)] = []
    @State private var supplierScores: PartsService.SupplierScores?
    @State private var partCount = 0
    @State private var isLoading = true

    var body: some View {
        NavigationStack {
            List {
                // Section 1: Overview
                overviewSection

                // Section 2: Contact Info (tappable)
                contactSection

                // Section 3: Sales Rep
                if supplier.repName != nil || supplier.repEmail != nil || supplier.repPhone != nil {
                    repSection
                }

                // Section 4: Performance Scores (auto-calculated)
                scoresSection

                // Section 5: Brands (which brands they carry)
                brandsSection

                // Section 6: Parts Summary (count only — pricing is on the Pricing page)
                partsSummarySection

                // Section 7: Recent Orders
                recentOrdersSection

                // Section 8: Notes
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
        }
    }

    // MARK: - Overview

    @ViewBuilder
    private var overviewSection: some View {
        Section {
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
            }
            if let email = supplier.email, !email.isEmpty {
                Button {
                    if let url = URL(string: "mailto:\(email)") { UIApplication.shared.open(url) }
                } label: {
                    LabeledContent("Email") {
                        Text(email).foregroundStyle(.blue)
                    }
                }
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
            }
            if let email = supplier.repEmail, !email.isEmpty {
                Button {
                    if let url = URL(string: "mailto:\(email)") { UIApplication.shared.open(url) }
                } label: {
                    LabeledContent("Email") {
                        Text(email).foregroundStyle(.blue)
                    }
                }
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
                LabeledContent("On-Time") {
                    Text(String(format: "%.0f%%", scores.onTimeRate))
                        .fontWeight(.bold)
                        .foregroundStyle(scoreColor(scores.onTimeRate))
                }
                LabeledContent("Reliability") {
                    Text(String(format: "%.0f%%", scores.reliabilityScore))
                        .fontWeight(.bold)
                        .foregroundStyle(scoreColor(scores.reliabilityScore))
                }
                LabeledContent("Total Orders", value: "\(scores.totalOrderCount)")
                if let avg = scores.avgDeliveryDays {
                    LabeledContent("Avg Delivery", value: String(format: "%.1f days", avg))
                }
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
        Section("Brands Carried (\(linkedBrands.count))") {
            if linkedBrands.isEmpty {
                Text("No brands linked. Link brands from the Brands tab.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(linkedBrands, id: \.brandId) { item in
                    HStack {
                        Image(systemName: "tag.fill")
                            .foregroundStyle(.accentColor)
                        Text(item.brandName)
                            .font(.subheadline)
                        Spacer()
                        Text("\(item.partCount) parts")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .frame(minHeight: 40)
                }
            }
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
        Section("Recent Orders (\(recentPOs.count))") {
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
        guard let service = appCore.partsService else { isLoading = false; return }
        do {
            linkedBrands = try service.getSupplierBrands(supplierId: supplier.id)
            recentPOs = try service.getSupplierRecentPOs(supplierId: supplier.id)
            partCount = try service.getSupplierPartCount(supplierId: supplier.id)
            supplierScores = try service.calculateSupplierScores(supplierId: supplier.id)
            isLoading = false
        } catch {
            print("[SupplierDetailSheet] Load error: \(error)")
            isLoading = false
        }
    }
}
```

## Important Notes

- **No per-part pricing on this page.** Supplier-specific pricing (from `part_suppliers.supplier_cost_price`) is displayed on the Pricing page and Categories page instead — see prompt 17F.
- The parts section shows only a count and directs users to the Pricing page for supplier cost details.
- The Brand model is not used directly — we return simple tuples to avoid init issues.
- `part_suppliers` is the join table. Verify it exists and has the expected columns.
- The `getSupplierPartCount` method is lightweight — just a COUNT query.

## Success Criteria

- [ ] Detail sheet shows: overview, contacts (tappable), rep, scores, brands, parts count, recent POs, notes
- [ ] NO per-part pricing on the supplier detail page
- [ ] Parts section shows count only with pointer to Pricing page
- [ ] Brands section shows which brands with part counts
- [ ] Recent POs show number, date, total, status badge
- [ ] All phone/email fields are tappable (tel:/mailto:)
- [ ] Website opens in browser
- [ ] Scores show live calculated values (or "no data" message)
- [ ] Project builds with no errors

## Log Entry

Append to `xcode-ai/prompt-results-log.md`:
```
## Prompt 17D Results (YYYY-MM-DD)
- Service: getSupplierBrands, getSupplierRecentPOs, getSupplierPartCount
- SupplierDetailSheet rebuilt: 8 sections (no per-part pricing — that's on Pricing page)
- Brands, PO history, scores, tappable contacts
- Build: [PASS/FAIL]
```

**Wait for user confirmation before proceeding to prompt 17E.**
