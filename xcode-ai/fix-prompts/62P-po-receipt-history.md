# 62P — Add Receipt History Section to IOSPODetailPage
> Chain position: Standalone

## Task

Add a "Receipt History" section to `IOSPODetailPage` showing when each batch was received: date, quantities, who received it, and any discrepancies.

### Step 1: Add a service method for receipt history

In `core/Sources/WiredPartCore/Services/OrdersService.swift`, add:

```swift
/// Get the receipt history for a PO — all receiving sessions with their items.
public struct ReceiptHistoryEntry: Sendable {
    public let sessionId: Int64
    public let receivedDate: String
    public let receivedBy: String
    public let mode: String
    public let items: [ReceiptHistoryItem]
    public let notes: String?
}

public struct ReceiptHistoryItem: Sendable {
    public let partName: String
    public let expectedQty: Int
    public let receivedQty: Int
    public let hasDiscrepancy: Bool
}

public func getReceiptHistory(poId: Int64) throws -> [ReceiptHistoryEntry] {
    do {
        return try db.writer.read { dbConn in
            // Get all receiving sessions for this PO
            let sessionRows = try Row.fetchAll(dbConn, sql: """
                SELECT rs.id, rs.completed_at, rs.mode, rs.notes,
                       COALESCE(u.display_name, u.email, 'Unknown') AS received_by
                FROM receiving_sessions rs
                LEFT JOIN users u ON u.id = rs.started_by
                WHERE rs.po_id = ? AND rs.status = 'completed' AND rs.deleted_at IS NULL
                ORDER BY rs.completed_at DESC
                """, arguments: [poId])

            return try sessionRows.map { sessionRow in
                let sessionId = sessionRow["id"] as Int64? ?? 0

                let itemRows = try Row.fetchAll(dbConn, sql: """
                    SELECT COALESCE(p.name, 'Unknown Part') AS part_name,
                           rsi.expected_qty, rsi.received_qty
                    FROM receiving_session_items rsi
                    LEFT JOIN po_line_items pli ON pli.id = rsi.po_line_id
                    LEFT JOIN parts p ON p.id = pli.part_id
                    WHERE rsi.session_id = ? AND rsi.deleted_at IS NULL
                    ORDER BY p.name
                    """, arguments: [sessionId])

                let items = itemRows.map { itemRow in
                    let expected = itemRow["expected_qty"] as Int? ?? 0
                    let received = itemRow["received_qty"] as Int? ?? 0
                    return ReceiptHistoryItem(
                        partName: itemRow["part_name"] ?? "Unknown",
                        expectedQty: expected,
                        receivedQty: received,
                        hasDiscrepancy: expected != received
                    )
                }

                return ReceiptHistoryEntry(
                    sessionId: sessionId,
                    receivedDate: sessionRow["completed_at"] ?? "",
                    receivedBy: sessionRow["received_by"] ?? "Unknown",
                    mode: sessionRow["mode"] ?? "standard",
                    items: items,
                    notes: sessionRow["notes"] as String?
                )
            }
        }
    } catch {
        if isTableNotFoundError(error) { return [] }
        throw error
    }
}
```

### Step 2: Add the Receipt History section to IOSPODetailPage

In `IOSPODetailPage.swift`, add state:

```swift
@State private var receiptHistory: [OrdersService.ReceiptHistoryEntry] = []
```

Load it in `loadData()`:

```swift
receiptHistory = (try? appCore.ordersService?.getReceiptHistory(poId: poId)) ?? []
```

Add the section to the view (after the line items section):

```swift
if !receiptHistory.isEmpty {
    Section("Receipt History") {
        ForEach(receiptHistory, id: \.sessionId) { entry in
            DisclosureGroup {
                // Items received in this session
                ForEach(entry.items, id: \.partName) { item in
                    HStack {
                        VStack(alignment: .leading) {
                            Text(item.partName)
                                .font(.subheadline)
                            if item.hasDiscrepancy {
                                Text("Expected: \(item.expectedQty) | Received: \(item.receivedQty)")
                                    .font(.caption)
                                    .foregroundStyle(.orange)
                            }
                        }
                        Spacer()
                        Text("×\(item.receivedQty)")
                            .font(.subheadline.monospacedDigit())
                            .foregroundStyle(item.hasDiscrepancy ? .orange : .primary)
                    }
                }

                // Session notes
                if let notes = entry.notes, !notes.isEmpty {
                    Text("Notes: \(notes)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.top, 4)
                }
            } label: {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(formatDate(entry.receivedDate))
                            .font(.subheadline.weight(.medium))
                        Text("By \(entry.receivedBy)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    let totalReceived = entry.items.reduce(0) { $0 + $1.receivedQty }
                    let hasAnyDiscrepancy = entry.items.contains { $0.hasDiscrepancy }
                    Text("\(totalReceived) items")
                        .font(.caption)
                    if hasAnyDiscrepancy {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                }
            }
        }
    }
}
```

### Step 3: Add date formatting helper

If not already present, add:

```swift
private func formatDate(_ dateStr: String) -> String {
    let input = ISO8601DateFormatter()
    input.formatOptions = [.withInternetDateTime]
    guard let date = input.date(from: dateStr) else { return dateStr }
    let output = DateFormatter()
    output.dateStyle = .medium
    output.timeStyle = .short
    return output.string(from: date)
}
```

## Files to Modify

- `core/Sources/WiredPartCore/Services/OrdersService.swift` — add ReceiptHistoryEntry, ReceiptHistoryItem structs and getReceiptHistory method
- `Weird Parts IOS/Weird Parts IOS/Features/Orders/IOSPODetailPage.swift` — add Receipt History section with DisclosureGroups

## Success Criteria
- [ ] Receipt History section appears on IOSPODetailPage when there are completed receiving sessions
- [ ] Each session shows date, who received, and total items
- [ ] Expanding a session shows individual items with quantities
- [ ] Discrepancies (expected != received) are highlighted in orange
- [ ] Session notes are shown when present
- [ ] Section is hidden when no receipt history exists
- [ ] No compile errors
