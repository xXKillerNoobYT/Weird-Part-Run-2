# 62L — Implement Multi-User Audit Verification for Low-Confidence Parts
> Chain position: Standalone

## Task

When a part's audit confidence is below 60%, flag it for multi-user verification. Assign 2-3 users to count the same part independently. Compare results: if all match, boost all user ratings; if 2 match and 1 is off, boost the 2 and lower the 1.

### Step 1: Add multi-user audit models

In `core/Sources/WiredPartCore/Models/Warehouse/AuditConfidenceModels.swift`, add:

```swift
// MARK: - MultiUserAuditAssignment

public struct MultiUserAuditAssignment: Codable, FetchableRecord, MutablePersistableRecord, Sendable {
    public static let databaseTableName = "multi_user_audit_assignments"
    public var id: Int64?
    public var auditSessionId: Int64
    public var partId: Int64
    public var locationId: Int64?
    public var userId: Int64
    public var countedQty: Int?
    public var completedAt: String?
    public var createdAt: String?

    enum CodingKeys: String, CodingKey {
        case id
        case auditSessionId = "audit_session_id"
        case partId = "part_id"
        case locationId = "location_id"
        case userId = "user_id"
        case countedQty = "counted_qty"
        case completedAt = "completed_at"
        case createdAt = "created_at"
    }

    public mutating func didInsert(_ inserted: InsertionSuccess) { id = inserted.rowID }
}
```

### Step 2: Add service methods to WarehouseService

In `core/Sources/WiredPartCore/Services/WarehouseService.swift`, add methods:

```swift
// MARK: - Multi-User Audit Verification

/// Flag a part for multi-user verification when confidence < 60%.
public func flagForMultiUserAudit(
    auditSessionId: Int64,
    partId: Int64,
    locationId: Int64?,
    userIds: [Int64]
) throws {
    do {
        try db.writer.write { dbConn in
            for userId in userIds {
                var assignment = MultiUserAuditAssignment(
                    id: nil, auditSessionId: auditSessionId,
                    partId: partId, locationId: locationId,
                    userId: userId, countedQty: nil,
                    completedAt: nil, createdAt: nil
                )
                try assignment.insert(dbConn)
            }
        }
    } catch {
        if isTableNotFoundError(error) { return }
        throw error
    }
}

/// Submit a count for a multi-user audit assignment.
public func submitMultiUserCount(assignmentId: Int64, countedQty: Int) throws {
    do {
        try db.writer.write { dbConn in
            try dbConn.execute(sql: """
                UPDATE multi_user_audit_assignments
                SET counted_qty = ?, completed_at = datetime('now')
                WHERE id = ?
                """, arguments: [countedQty, assignmentId])
        }
    } catch {
        if isTableNotFoundError(error) { return }
        throw error
    }
}

/// Get pending multi-user audit assignments for a user.
public func getMultiUserAuditAssignments(userId: Int64) throws -> [(id: Int64, partName: String, locationName: String?)] {
    do {
        return try db.writer.read { dbConn in
            let rows = try Row.fetchAll(dbConn, sql: """
                SELECT mua.id, COALESCE(p.name, 'Unknown Part') AS part_name,
                       wl.name AS location_name
                FROM multi_user_audit_assignments mua
                LEFT JOIN parts p ON p.id = mua.part_id
                LEFT JOIN warehouse_locations wl ON wl.id = mua.location_id
                WHERE mua.user_id = ? AND mua.completed_at IS NULL
                ORDER BY mua.created_at
                """, arguments: [userId])
            return rows.map { row in
                (id: row["id"] as Int64? ?? 0,
                 partName: row["part_name"] as String? ?? "Unknown",
                 locationName: row["location_name"] as String?)
            }
        }
    } catch {
        if isTableNotFoundError(error) { return [] }
        throw error
    }
}

/// Resolve a multi-user audit: compare all counts, adjust user ratings.
/// Returns the consensus quantity (majority count).
public func resolveMultiUserAudit(partId: Int64, auditSessionId: Int64) throws -> Int? {
    do {
        return try db.writer.write { dbConn -> Int? in
            let rows = try Row.fetchAll(dbConn, sql: """
                SELECT id, user_id, counted_qty FROM multi_user_audit_assignments
                WHERE part_id = ? AND audit_session_id = ?
                  AND completed_at IS NOT NULL
                ORDER BY user_id
                """, arguments: [partId, auditSessionId])

            let counts = rows.compactMap { row -> (userId: Int64, qty: Int)? in
                guard let userId = row["user_id"] as Int64?,
                      let qty = row["counted_qty"] as Int? else { return nil }
                return (userId, qty)
            }

            guard counts.count >= 2 else { return nil }

            // Find majority count
            var qtyVotes: [Int: [Int64]] = [:]
            for c in counts {
                qtyVotes[c.qty, default: []].append(c.userId)
            }

            let sorted = qtyVotes.sorted { $0.value.count > $1.value.count }
            guard let winner = sorted.first else { return nil }

            let consensusQty = winner.key
            let agreeingUsers = winner.value
            let disagreeingUsers = counts.filter { $0.qty != consensusQty }.map(\.userId)

            // Boost ratings for agreeing users
            for userId in agreeingUsers {
                try dbConn.execute(sql: """
                    UPDATE user_audit_ratings
                    SET rating = MIN(rating + 2, 100), updated_at = datetime('now')
                    WHERE user_id = ?
                    """, arguments: [userId])
            }

            // Lower ratings for disagreeing users
            for userId in disagreeingUsers {
                try dbConn.execute(sql: """
                    UPDATE user_audit_ratings
                    SET rating = MAX(rating - 5, 0), updated_at = datetime('now')
                    WHERE user_id = ?
                    """, arguments: [userId])
            }

            return consensusQty
        }
    } catch {
        if isTableNotFoundError(error) { return nil }
        throw error
    }
}
```

### Step 3: Add UI trigger in IOSAuditSummaryView

In `IOSAuditSummaryView.swift`, when displaying parts with confidence < 60%, add a "Request Verification" button:

```swift
// When showing low-confidence items:
if confidence < 60 {
    Button {
        // Show user picker to assign 2-3 verifiers
        showVerificationPicker = true
        verificationPartId = partId
    } label: {
        Label("Request Verification", systemImage: "person.2.badge.gearshape")
            .font(.caption)
    }
    .tint(.orange)
}
```

Add state and a sheet for picking verifiers:

```swift
@State private var showVerificationPicker = false
@State private var verificationPartId: Int64?
@State private var selectedVerifiers: Set<Int64> = []
```

## Files to Modify

- `core/Sources/WiredPartCore/Models/Warehouse/AuditConfidenceModels.swift` — add MultiUserAuditAssignment model
- `core/Sources/WiredPartCore/Services/WarehouseService.swift` — add 4 multi-user audit methods
- `Weird Parts IOS/Weird Parts IOS/Features/Warehouse/IOSAuditSummaryView.swift` — add verification trigger UI

## Success Criteria
- [ ] Parts with confidence < 60% show a "Request Verification" button
- [ ] Can assign 2-3 users to independently count the same part
- [ ] Each assigned user sees their pending verification tasks
- [ ] When all users submit counts, the system compares results
- [ ] Agreeing users get rating boost (+2), disagreeing users get penalty (-5)
- [ ] Consensus quantity is returned for the final audit count
- [ ] No compile errors
