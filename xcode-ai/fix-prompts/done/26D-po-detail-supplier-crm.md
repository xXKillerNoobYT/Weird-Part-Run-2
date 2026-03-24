# 26D — PO Detail: Supplier CRM Section + Notes Tabs

> **Chain position:** 26A → 26B → 26C → **26D** → 26E → 26F
> **Prerequisite:** 26C complete (status-based action buttons)
> **Plan:** `docs/plans/ios-purchase-orders-page.md` — Section 6 + Q1 answer
> **Log file:** `xcode-ai/prompt-results-log.md`

## Instructions

**IMPORTANT:** Before implementing, first plan your approach by reading all files mentioned below. Understand the current state, then implement. When done, wait for user confirmation before proceeding to the next prompt.

## Context

The PO detail page currently shows only the supplier name as plain text. It needs a full mini-CRM section with contact info, reliability scores, and a tabbed notes area (PO-specific notes and supplier-wide notes as separate tabs). The `PODetail` struct already has `supplierId`, `notes`, `internalNotes`, and `supplierNotes` fields.

**Files to read first:**
- `Weird Parts IOS/Weird Parts IOS/Features/Orders/IOSPODetailPage.swift` — current page
- `core/Sources/WiredPartCore/Services/OrdersService.swift` — PODetail struct (~line 172)
- `core/Sources/WiredPartCore/Services/PartsService.swift` — search for supplier-related methods (getSupplierDetail, getSupplierScores)
- `docs/plans/ios-purchase-orders-page.md` — Section 6 design spec

**Files to modify:**
- `Weird Parts IOS/Weird Parts IOS/Features/Orders/IOSPODetailPage.swift`
- `core/Sources/WiredPartCore/Services/OrdersService.swift` (add PO notes CRUD if missing)

## Task

### Step 1: Add supplier detail loading

Load the supplier's contact info and scores alongside the PO detail:

```swift
@State private var supplierDetail: PartsService.SupplierWithScores?

// In loadData():
if let partsService = appCore.partsService {
    supplierDetail = try? partsService.getSupplierDetail(id: po.supplierId)
}
```

Check what `getSupplierDetail` returns — it should include phone, email, rep name, account number, and reliability/on-time/quality scores. If it doesn't exist, check for similar methods like `getSupplier()`.

### Step 2: Build the Supplier CRM section

Replace the simple supplier name text with a full CRM card:

```swift
@ViewBuilder
private func supplierCRMSection(_ po: OrdersService.PODetail) -> some View {
    VStack(alignment: .leading, spacing: 12) {
        // Header with name + quick actions
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(po.supplierName)
                    .font(.headline)
                if let detail = supplierDetail {
                    if let rep = detail.repName, !rep.isEmpty {
                        Text("Rep: \(rep)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if let acct = detail.accountNumber, !acct.isEmpty {
                        Text("Acct: \(acct)")
                            .font(.caption)
                            .monospaced()
                            .foregroundStyle(.secondary)
                    }
                }
            }
            Spacer()
            // Quick contact buttons
            if let detail = supplierDetail {
                HStack(spacing: 12) {
                    if let phone = detail.phone, !phone.isEmpty,
                       let url = URL(string: "tel:\(phone)") {
                        Link(destination: url) {
                            Image(systemName: "phone.fill")
                                .font(.title3)
                                .foregroundStyle(.green)
                        }
                    }
                    if let email = detail.email, !email.isEmpty,
                       let url = URL(string: "mailto:\(email)") {
                        Link(destination: url) {
                            Image(systemName: "envelope.fill")
                                .font(.title3)
                                .foregroundStyle(.blue)
                        }
                    }
                    Button {
                        activeSheet = .contactSupplier
                    } label: {
                        Image(systemName: "message.fill")
                            .font(.title3)
                            .foregroundStyle(.orange)
                    }
                }
            }
        }

        // Reliability scores (if available)
        if let detail = supplierDetail {
            HStack(spacing: 16) {
                scoreBar(label: "Reliability", value: detail.reliabilityScore, color: .blue)
                scoreBar(label: "On-Time", value: detail.onTimeScore, color: .green)
                scoreBar(label: "Quality", value: detail.qualityScore, color: .purple)
            }
        }

        // View full profile link
        NavigationLink {
            // TODO: Navigate to supplier detail page
            Text("Supplier Profile")
        } label: {
            Label("View Supplier Profile", systemImage: "person.crop.rectangle")
                .font(.caption)
        }
    }
    .padding()
    .dsCard()
}
```

### Step 3: Add score bar helper

```swift
@ViewBuilder
private func scoreBar(label: String, value: Double?, color: Color) -> some View {
    VStack(spacing: 4) {
        Text(label)
            .font(.caption2)
            .foregroundStyle(.secondary)
        if let score = value {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(color.opacity(0.15))
                    RoundedRectangle(cornerRadius: 3)
                        .fill(color)
                        .frame(width: geo.size.width * min(max(score / 100, 0), 1))
                }
            }
            .frame(height: 6)
            Text("\(Int(score))%")
                .font(.caption2)
                .fontWeight(.medium)
        } else {
            Text("--")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
    }
}
```

### Step 4: Build tabbed notes section

Create a notes section with two tabs — PO Notes (this order) and Supplier Notes (from supplier profile, read-only here):

```swift
@State private var selectedNotesTab = 0
@State private var newNoteText = ""
@State private var poNotes: [PONoteEntry] = []
@State private var supplierNotes: [PONoteEntry] = []

struct PONoteEntry: Identifiable {
    let id = UUID()
    let text: String
    let author: String?
    let date: String
}

@ViewBuilder
private func notesTabSection(_ po: OrdersService.PODetail) -> some View {
    VStack(alignment: .leading, spacing: 8) {
        // Tab picker
        Picker("Notes", selection: $selectedNotesTab) {
            Text("PO Notes (\(poNotes.count))").tag(0)
            Text("Supplier Notes (\(supplierNotes.count))").tag(1)
        }
        .pickerStyle(.segmented)

        if selectedNotesTab == 0 {
            // PO-specific notes — editable
            ForEach(poNotes) { note in
                noteRow(note)
            }

            // Add note field
            HStack {
                TextField("Add a note...", text: $newNoteText)
                    .textFieldStyle(.roundedBorder)
                Button {
                    guard !newNoteText.trimmingCharacters(in: .whitespaces).isEmpty else { return }
                    Task { await addPONote() }
                } label: {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.title3)
                        .foregroundStyle(.accentColor)
                }
                .disabled(newNoteText.trimmingCharacters(in: .whitespaces).isEmpty)
            }

            if poNotes.isEmpty {
                Text("No notes yet. Add communication history for this order.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .padding(.vertical, 4)
            }
        } else {
            // Supplier-wide notes — read-only
            ForEach(supplierNotes) { note in
                noteRow(note)
            }

            if supplierNotes.isEmpty {
                Text("No supplier notes. Add them from the Supplier Profile page.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .padding(.vertical, 4)
            }
        }
    }
    .padding()
    .dsCard()
}

@ViewBuilder
private func noteRow(_ note: PONoteEntry) -> some View {
    VStack(alignment: .leading, spacing: 2) {
        HStack {
            if let author = note.author {
                Text(author)
                    .font(.caption)
                    .fontWeight(.medium)
            }
            Spacer()
            Text(note.date)
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        Text(note.text)
            .font(.subheadline)
    }
    .padding(.vertical, 4)
}
```

### Step 5: Add PO note service method

In `OrdersService.swift`, add a method to save PO notes if one doesn't exist. Check if `purchase_orders` table has a `notes` TEXT column (it likely does). The simplest approach: append to the existing `notes` field with timestamps, or create a `po_notes` table for proper note history.

For now, use the existing `notes` field — append with timestamp:

```swift
public func addPONote(poId: Int64, note: String, author: String) throws {
    try db.writer.write { dbConn in
        let existing = try String.fetchOne(
            dbConn,
            sql: "SELECT notes FROM purchase_orders WHERE id = ?",
            arguments: [poId]
        ) ?? ""
        let timestamp = ISO8601DateFormatter().string(from: Date())
        let newNote = "\(timestamp) [\(author)]: \(note)"
        let combined = existing.isEmpty ? newNote : "\(existing)\n\(newNote)"
        try dbConn.execute(
            sql: "UPDATE purchase_orders SET notes = ?, updated_at = datetime('now') WHERE id = ?",
            arguments: [combined, poId]
        )
    }
}
```

### Step 6: Wire it all into poContent

In the `poContent` function, replace the simple supplier text and notes section with the new CRM and tabbed notes:

```swift
// Replace the "Supplier" VStack with:
supplierCRMSection(po)

// Replace the notes section at the bottom with:
notesTabSection(po)
```

### Step 7: Load notes in loadData

Parse the existing notes string into `PONoteEntry` objects by splitting on newlines and parsing timestamps:

```swift
// In loadData(), after loading PO:
if let notesStr = po?.notes, !notesStr.isEmpty {
    poNotes = notesStr.components(separatedBy: "\n").compactMap { line in
        // Parse "2026-03-20T14:30:00Z [Sarah]: Called about ETA"
        let parts = line.components(separatedBy: "]: ")
        guard parts.count >= 2 else {
            return PONoteEntry(text: line, author: nil, date: "")
        }
        let prefix = parts[0] // "2026-03-20T14:30:00Z [Sarah"
        let text = parts.dropFirst().joined(separator: "]: ")
        let prefixParts = prefix.components(separatedBy: " [")
        let date = prefixParts.first ?? ""
        let author = prefixParts.count > 1 ? prefixParts[1] : nil
        return PONoteEntry(text: text, author: author, date: String(date.prefix(10)))
    }
}
```

## Important Notes

- The supplier CRM section replaces the simple name-only supplier display
- Score bars show percentage visually — no score data → show "--"
- PO Notes tab is editable (add new notes). Supplier Notes tab is READ-ONLY on this page.
- Quick contact buttons (phone, email) use native iOS deep links (`tel:`, `mailto:`)
- Message button opens the supplier bridge channel (from prompt 22B)
- Check what fields `getSupplierDetail` or equivalent method returns — adapt property names accordingly
- The note parsing is a simple approach. A proper `po_notes` table would be better long-term but this works for now.

## Success Criteria

- [ ] Supplier CRM section shows name, rep, account #, phone/email/message buttons
- [ ] Reliability/On-Time/Quality score bars display correctly
- [ ] "View Supplier Profile" navigation link present
- [ ] PO Notes tab — shows existing notes, allows adding new ones
- [ ] Supplier Notes tab — shows supplier-wide notes (read-only)
- [ ] Tab picker switches between PO and Supplier notes
- [ ] Quick contact buttons work (phone, email deep links)
- [ ] Project builds with no errors

## Log Entry

```
## Prompt 26D Results (YYYY-MM-DD)
- Supplier CRM section: contact info, scores, quick actions
- Tabbed notes: PO-specific (editable) + Supplier-wide (read-only)
- Score bars with percentage visualization
- Build: [PASS/FAIL]
```

**Wait for user confirmation before proceeding to prompt 26E.**
