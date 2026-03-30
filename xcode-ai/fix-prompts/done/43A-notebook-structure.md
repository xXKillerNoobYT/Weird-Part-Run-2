# 43A — Notebook Structure: Migration + Models

> **Chain position:** **43A** → 43B → 43C → 43D → 43E
> **Log file:** `xcode-ai/prompt-results-log.md`

## MANDATORY RULES
1. DO NOT use `import GRDB` in UI files
2. DO NOT use empty `catch { }` blocks
3. DO NOT use `#if os(iOS)` guards

## Instructions

**IMPORTANT:** Before implementing, read `NotebooksService.swift` and `AppDatabase+Migrations.swift` to understand the current notebook data model. Then extend it with section groups, sections, and block-based content.

## Context

The current notebook system has notebooks and entries (flat list). This needs to become a proper hierarchical structure: Notebooks → Section Groups → Sections → Pages (entries). Each page contains blocks (text, heading, photo, checklist, etc.) instead of a single text blob. This enables structured documentation like panel schedules, daily reports, and professional notebooks.

## Task

### Step 1: Migration — Section Groups

```sql
CREATE TABLE notebook_section_groups (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    notebook_id INTEGER NOT NULL REFERENCES notebooks(id) ON DELETE CASCADE,
    name TEXT NOT NULL,
    sort_order INTEGER NOT NULL DEFAULT 0,
    is_collapsed INTEGER NOT NULL DEFAULT 0,
    created_at TEXT DEFAULT (datetime('now')),
    updated_at TEXT DEFAULT (datetime('now')),
    deleted_at TEXT
);
```

### Step 2: Migration — Sections

```sql
CREATE TABLE notebook_sections (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    group_id INTEGER REFERENCES notebook_section_groups(id) ON DELETE CASCADE,
    notebook_id INTEGER NOT NULL REFERENCES notebooks(id) ON DELETE CASCADE,
    name TEXT NOT NULL,
    sort_order INTEGER NOT NULL DEFAULT 0,
    is_collapsed INTEGER NOT NULL DEFAULT 0,
    created_at TEXT DEFAULT (datetime('now')),
    updated_at TEXT DEFAULT (datetime('now')),
    deleted_at TEXT
);
```

### Step 3: Migration — Update notebook_entries for Block Content

```sql
-- Add block support columns to notebook_entries
ALTER TABLE notebook_entries ADD COLUMN section_id INTEGER REFERENCES notebook_sections(id) ON DELETE CASCADE;
ALTER TABLE notebook_entries ADD COLUMN block_type TEXT NOT NULL DEFAULT 'text';
-- block_type values: 'text', 'heading', 'photo', 'checklist', 'part_reference',
--                    'divider', 'callout', 'table', 'todo'
ALTER TABLE notebook_entries ADD COLUMN block_data TEXT;  -- JSON for type-specific data
ALTER TABLE notebook_entries ADD COLUMN heading_level INTEGER;  -- 1, 2, 3 for headings
ALTER TABLE notebook_entries ADD COLUMN checklist_items TEXT;  -- JSON array of {text, checked}
ALTER TABLE notebook_entries ADD COLUMN photo_path TEXT;
ALTER TABLE notebook_entries ADD COLUMN reference_type TEXT;  -- 'part', 'po', 'jpo', 'job'
ALTER TABLE notebook_entries ADD COLUMN reference_id INTEGER;
```

### Step 4: Models

```swift
// In a new file or extend existing models

struct NotebookSectionGroup: Codable, Identifiable, Sendable, MutablePersistableRecord, FetchableRecord {
    var id: Int64?
    var notebookId: Int64
    var name: String
    var sortOrder: Int
    var isCollapsed: Bool
    var createdAt: String?
    var updatedAt: String?
    var deletedAt: String?

    static let databaseTableName = "notebook_section_groups"

    enum CodingKeys: String, CodingKey {
        case id, name
        case notebookId = "notebook_id"
        case sortOrder = "sort_order"
        case isCollapsed = "is_collapsed"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case deletedAt = "deleted_at"
    }
}

struct NotebookSection: Codable, Identifiable, Sendable, MutablePersistableRecord, FetchableRecord {
    var id: Int64?
    var groupId: Int64?
    var notebookId: Int64
    var name: String
    var sortOrder: Int
    var isCollapsed: Bool
    var createdAt: String?
    var updatedAt: String?
    var deletedAt: String?

    static let databaseTableName = "notebook_sections"

    enum CodingKeys: String, CodingKey {
        case id, name
        case groupId = "group_id"
        case notebookId = "notebook_id"
        case sortOrder = "sort_order"
        case isCollapsed = "is_collapsed"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case deletedAt = "deleted_at"
    }
}

// Block types enum
enum BlockType: String, Codable, Sendable {
    case text
    case heading
    case photo
    case checklist
    case partReference = "part_reference"
    case divider
    case callout
    case table
    case todo
}

struct ChecklistItem: Codable, Sendable {
    var text: String
    var checked: Bool
}
```

### Step 5: Service Methods in NotebooksService

```swift
// MARK: - Section Groups

func createSectionGroup(notebookId: Int64, name: String) async throws -> NotebookSectionGroup
func updateSectionGroup(groupId: Int64, name: String) async throws
func deleteSectionGroup(groupId: Int64) async throws  // soft delete
func reorderSectionGroups(notebookId: Int64, orderedIds: [Int64]) async throws

// MARK: - Sections

func createSection(notebookId: Int64, groupId: Int64?, name: String) async throws -> NotebookSection
func updateSection(sectionId: Int64, name: String) async throws
func deleteSection(sectionId: Int64) async throws  // soft delete
func moveSection(sectionId: Int64, toGroupId: Int64?, sortOrder: Int) async throws
func reorderSections(groupId: Int64, orderedIds: [Int64]) async throws

// MARK: - Block Entries

func createBlockEntry(
    sectionId: Int64,
    blockType: BlockType,
    title: String?,
    content: String?,
    blockData: String?,  // JSON
    sortOrder: Int
) async throws -> NotebookEntry

func updateBlockEntry(entryId: Int64, content: String?, blockData: String?) async throws
func deleteBlockEntry(entryId: Int64) async throws
func reorderBlockEntries(sectionId: Int64, orderedIds: [Int64]) async throws

// MARK: - Hierarchy Queries

/// Get full notebook hierarchy: groups → sections → entries
func getNotebookHierarchy(notebookId: Int64) async throws -> NotebookHierarchy

struct NotebookHierarchy: Sendable {
    let groups: [SectionGroupWithChildren]
    let ungroupedSections: [SectionWithEntries]
}

struct SectionGroupWithChildren: Identifiable, Sendable {
    let group: NotebookSectionGroup
    let sections: [SectionWithEntries]
    var id: Int64? { group.id }
}

struct SectionWithEntries: Identifiable, Sendable {
    let section: NotebookSection
    let entries: [NotebookEntry]
    var id: Int64? { section.id }
}
```

### Step 6: Update ConflictResolver

Add `notebook_section_groups`, `notebook_sections` to the whitelist. The new columns on `notebook_entries` are already covered.

## Important Notes
- Existing notebook_entries should continue to work (block_type defaults to "text")
- Section groups are OPTIONAL — sections can exist without a group (ungrouped sections)
- Block data is JSON for flexibility (checklist items, table data, callout style, etc.)
- The hierarchy query should use LEFT JOINs to handle notebooks with no groups/sections
- Sort order uses integer values — reordering updates sort_order for affected items
- Soft delete (deleted_at) on all new tables for sync safety

## Success Criteria
- [ ] Migration creates notebook_section_groups and notebook_sections tables
- [ ] Migration adds block columns to notebook_entries
- [ ] NotebookSectionGroup and NotebookSection models with CodingKeys + Sendable
- [ ] BlockType enum with all 9 types
- [ ] 12+ service methods for CRUD on groups, sections, block entries
- [ ] getNotebookHierarchy returns full tree structure
- [ ] ConflictResolver whitelist updated
- [ ] Existing notebooks still work (backward compatible)
- [ ] Project builds with no errors

## Log Entry
```
## Prompt 43A Results (YYYY-MM-DD)
- Migration: 2 new tables, X new columns on notebook_entries
- Models: NotebookSectionGroup, NotebookSection, BlockType enum
- Service: X methods added to NotebooksService
- Build: PASS/FAIL
```

**Wait for user confirmation before proceeding to prompt 43B.**
