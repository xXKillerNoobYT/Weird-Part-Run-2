# 62J — Implement Basic Notebook Block Conflict Resolution
> Chain position: Standalone

## Task

When two devices edit the same notebook block and sync, conflicts are currently unresolved — the last write wins silently. Implement a basic conflict detection and resolution UI. AI-powered merge is a future enhancement; for now, show both versions and let the user pick.

### Step 1: Add conflict tracking model

In `core/Sources/WiredPartCore/Models/Notebooks/NotebooksModels.swift`, add a struct for tracking conflicts:

```swift
// MARK: - NotebookBlockConflict

public struct NotebookBlockConflict: Identifiable, Sendable {
    public let id: String
    public let blockId: Int64
    public let notebookId: Int64
    public let localVersion: String      // The content from this device
    public let remoteVersion: String     // The content from the other device
    public let localEditedAt: String
    public let remoteEditedAt: String
    public let localEditedBy: String     // User name
    public let remoteEditedBy: String    // User name

    public init(id: String = UUID().uuidString, blockId: Int64, notebookId: Int64,
                localVersion: String, remoteVersion: String,
                localEditedAt: String, remoteEditedAt: String,
                localEditedBy: String, remoteEditedBy: String) {
        self.id = id
        self.blockId = blockId
        self.notebookId = notebookId
        self.localVersion = localVersion
        self.remoteVersion = remoteVersion
        self.localEditedAt = localEditedAt
        self.remoteEditedAt = remoteEditedAt
        self.localEditedBy = localEditedBy
        self.remoteEditedBy = remoteEditedBy
    }
}
```

### Step 2: Add conflict detection to NotebooksService

In `core/Sources/WiredPartCore/Services/NotebooksService.swift`, add a method:

```swift
/// Check for blocks where the local updated_at differs from _change_log record,
/// indicating a conflict during sync.
public func detectBlockConflicts(notebookId: Int64) throws -> [NotebookBlockConflict] {
    do {
        return try db.writer.read { dbConn in
            // Look for blocks that have a conflict marker in their notes/metadata
            let rows = try Row.fetchAll(dbConn, sql: """
                SELECT nb.id AS block_id, nb.notebook_id, nb.content,
                       nb.updated_at,
                       COALESCE(u.display_name, u.email, 'Unknown') AS edited_by
                FROM notebook_blocks nb
                LEFT JOIN users u ON u.id = nb.updated_by
                WHERE nb.notebook_id = ? AND nb.deleted_at IS NULL
                  AND nb.conflict_content IS NOT NULL
                ORDER BY nb.sort_order
                """, arguments: [notebookId])

            return rows.compactMap { row -> NotebookBlockConflict? in
                guard let blockId = row["block_id"] as Int64?,
                      let content = row["content"] as String?,
                      let conflictContent = row["conflict_content"] as String?
                else { return nil }

                return NotebookBlockConflict(
                    blockId: blockId,
                    notebookId: notebookId,
                    localVersion: content,
                    remoteVersion: conflictContent,
                    localEditedAt: row["updated_at"] ?? "",
                    remoteEditedAt: row["conflict_updated_at"] ?? "",
                    localEditedBy: row["edited_by"] ?? "Unknown",
                    remoteEditedBy: row["conflict_edited_by"] ?? "Unknown"
                )
            }
        }
    } catch {
        if isTableNotFoundError(error) { return [] }
        throw error
    }
}

/// Resolve a conflict by choosing one version.
public func resolveBlockConflict(blockId: Int64, keepLocal: Bool) throws {
    try db.writer.write { dbConn in
        if keepLocal {
            // Keep local version, clear conflict
            try dbConn.execute(sql: """
                UPDATE notebook_blocks
                SET conflict_content = NULL, conflict_updated_at = NULL,
                    conflict_edited_by = NULL, updated_at = datetime('now')
                WHERE id = ?
                """, arguments: [blockId])
        } else {
            // Use remote version
            try dbConn.execute(sql: """
                UPDATE notebook_blocks
                SET content = conflict_content,
                    conflict_content = NULL, conflict_updated_at = NULL,
                    conflict_edited_by = NULL, updated_at = datetime('now')
                WHERE id = ?
                """, arguments: [blockId])
        }
    }
}
```

### Step 3: Add conflict resolution UI

In `IOSNotebookDetailPage.swift`, add a conflict banner and resolution sheet:

```swift
@State private var conflicts: [NotebookBlockConflict] = []
@State private var showConflictSheet = false
@State private var selectedConflict: NotebookBlockConflict?
```

Add a banner at the top of the notebook view when conflicts exist:

```swift
if !conflicts.isEmpty {
    Button {
        showConflictSheet = true
    } label: {
        Label("\(conflicts.count) conflict\(conflicts.count == 1 ? "" : "s") to resolve",
              systemImage: "exclamationmark.triangle.fill")
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding()
            .background(.orange, in: RoundedRectangle(cornerRadius: 8))
    }
    .padding(.horizontal)
}
```

Add a sheet that shows each conflict side-by-side:

```swift
.sheet(isPresented: $showConflictSheet) {
    NavigationStack {
        List(conflicts) { conflict in
            VStack(alignment: .leading, spacing: 12) {
                Text("Block Conflict")
                    .font(.headline)

                GroupBox("This Device (\(conflict.localEditedBy))") {
                    Text(conflict.localVersion)
                        .font(.body)
                }

                GroupBox("Other Device (\(conflict.remoteEditedBy))") {
                    Text(conflict.remoteVersion)
                        .font(.body)
                }

                HStack {
                    Button("Keep Mine") {
                        resolveConflict(conflict, keepLocal: true)
                    }
                    .buttonStyle(.borderedProminent)

                    Button("Keep Theirs") {
                        resolveConflict(conflict, keepLocal: false)
                    }
                    .buttonStyle(.bordered)
                }
            }
            .padding(.vertical, 4)
        }
        .navigationTitle("Resolve Conflicts")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Done") { showConflictSheet = false }
            }
        }
    }
}
```

Load conflicts in `loadData()`:

```swift
conflicts = (try? service.detectBlockConflicts(notebookId: notebookId)) ?? []
```

### Note on migration:

This requires `conflict_content`, `conflict_updated_at`, and `conflict_edited_by` columns on the `notebook_blocks` table. If these columns don't exist, add a migration. The service methods use `isTableNotFoundError` to gracefully handle missing columns/tables.

## Files to Modify

- `core/Sources/WiredPartCore/Models/Notebooks/NotebooksModels.swift` — add NotebookBlockConflict
- `core/Sources/WiredPartCore/Services/NotebooksService.swift` — add detectBlockConflicts, resolveBlockConflict
- `Weird Parts IOS/Weird Parts IOS/Features/Notebooks/IOSNotebookDetailPage.swift` — add conflict UI

## Success Criteria
- [ ] When two devices edit the same block, a conflict is detected after sync
- [ ] Orange banner appears at top of notebook showing conflict count
- [ ] Tapping the banner opens a sheet showing both versions side-by-side
- [ ] User can choose "Keep Mine" or "Keep Theirs" for each conflict
- [ ] After resolution, the conflict disappears and the chosen version is saved
- [ ] No compile errors
