import Foundation
import GRDB

// MARK: - NotebookTemplate

public struct NotebookTemplate: Codable, FetchableRecord, MutablePersistableRecord, Sendable {
    public static let databaseTableName = "notebook_templates"
    public var id: Int64?
    public var name: String
    public var description: String?
    public var jobType: String?
    public var isDefault: Int
    public var createdBy: Int64?
    public var deletedAt: String?
    public var createdAt: String?
    public var updatedAt: String?

    enum CodingKeys: String, CodingKey {
        case id, name, description
        case jobType = "job_type"
        case isDefault = "is_default"
        case createdBy = "created_by"
        case deletedAt = "deleted_at"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    public mutating func didInsert(_ inserted: InsertionSuccess) { id = inserted.rowID }
}

// MARK: - TemplateSection

public struct TemplateSection: Codable, FetchableRecord, MutablePersistableRecord, Sendable {
    public static let databaseTableName = "template_sections"
    public var id: Int64?
    public var templateId: Int64
    public var name: String
    public var sectionType: String
    public var sortOrder: Int
    public var isLocked: Int
    public var deletedAt: String?

    enum CodingKeys: String, CodingKey {
        case id, name
        case templateId = "template_id"
        case sectionType = "section_type"
        case sortOrder = "sort_order"
        case isLocked = "is_locked"
        case deletedAt = "deleted_at"
    }

    public mutating func didInsert(_ inserted: InsertionSuccess) { id = inserted.rowID }
}

// MARK: - TemplateEntry

public struct TemplateEntry: Codable, FetchableRecord, MutablePersistableRecord, Sendable {
    public static let databaseTableName = "template_entries"
    public var id: Int64?
    public var sectionId: Int64
    public var title: String
    public var defaultContent: String?
    public var entryType: String
    public var fieldType: String?
    public var fieldRequired: Int
    public var sortOrder: Int
    public var deletedAt: String?

    enum CodingKeys: String, CodingKey {
        case id, title
        case sectionId = "section_id"
        case defaultContent = "default_content"
        case entryType = "entry_type"
        case fieldType = "field_type"
        case fieldRequired = "field_required"
        case sortOrder = "sort_order"
        case deletedAt = "deleted_at"
    }

    public mutating func didInsert(_ inserted: InsertionSuccess) { id = inserted.rowID }
}

// MARK: - Notebook

public struct Notebook: Codable, FetchableRecord, MutablePersistableRecord, Sendable {
    public static let databaseTableName = "notebooks"
    public var id: Int64?
    public var title: String
    public var description: String?
    public var jobId: Int64?
    public var templateId: Int64?
    public var createdBy: Int64
    public var isArchived: Int
    public var deletedAt: String?
    public var createdAt: String?
    public var updatedAt: String?

    enum CodingKeys: String, CodingKey {
        case id, title, description
        case jobId = "job_id"
        case templateId = "template_id"
        case createdBy = "created_by"
        case isArchived = "is_archived"
        case deletedAt = "deleted_at"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    public mutating func didInsert(_ inserted: InsertionSuccess) { id = inserted.rowID }
}

// MARK: - NotebookSectionGroup

public struct NotebookSectionGroup: Codable, FetchableRecord, MutablePersistableRecord, Sendable, Identifiable {
    public static let databaseTableName = "notebook_section_groups"
    public var id: Int64?
    public var notebookId: Int64
    public var name: String
    public var sortOrder: Int
    public var isCollapsed: Int
    public var createdAt: String?
    public var updatedAt: String?
    public var deletedAt: String?

    enum CodingKeys: String, CodingKey {
        case id, name
        case notebookId = "notebook_id"
        case sortOrder = "sort_order"
        case isCollapsed = "is_collapsed"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case deletedAt = "deleted_at"
    }

    public mutating func didInsert(_ inserted: InsertionSuccess) { id = inserted.rowID }
}

// MARK: - NotebookSection

public struct NotebookSection: Codable, FetchableRecord, MutablePersistableRecord, Sendable {
    public static let databaseTableName = "notebook_sections"
    public var id: Int64?
    public var notebookId: Int64
    public var groupId: Int64?
    public var name: String
    public var sectionType: String
    public var sortOrder: Int
    public var isLocked: Int
    public var isCollapsed: Int
    public var deletedAt: String?
    public var createdAt: String?
    public var updatedAt: String?

    enum CodingKeys: String, CodingKey {
        case id, name
        case notebookId = "notebook_id"
        case groupId = "group_id"
        case sectionType = "section_type"
        case sortOrder = "sort_order"
        case isLocked = "is_locked"
        case isCollapsed = "is_collapsed"
        case deletedAt = "deleted_at"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    public mutating func didInsert(_ inserted: InsertionSuccess) { id = inserted.rowID }
}

// MARK: - Block Types

/// Types of content blocks in notebook entries.
public enum BlockType: String, Codable, Sendable, CaseIterable {
    case text
    case heading
    case photo
    case checklist
    case partReference = "part_reference"
    case divider
    case callout
    case table
    case todo
    case panelSchedule = "panel_schedule"
}

/// A single item in a checklist block.
public struct ChecklistItem: Codable, Sendable {
    public var text: String
    public var checked: Bool

    public init(text: String, checked: Bool = false) {
        self.text = text
        self.checked = checked
    }
}

// MARK: - NotebookEntry

public struct NotebookEntry: Codable, FetchableRecord, MutablePersistableRecord, Sendable {
    public static let databaseTableName = "notebook_entries"
    public var id: Int64?
    public var sectionId: Int64
    public var notebookId: Int64?
    public var title: String
    public var content: String?
    public var entryType: String
    public var fieldType: String?
    public var fieldRequired: Int
    public var fieldFilledBy: Int64?
    public var taskStatus: String?
    public var taskDueDate: String?
    public var taskAssignedTo: Int64?
    public var taskPartsNote: String?
    public var createdBy: Int64
    public var updatedBy: Int64?
    public var isDeleted: Int
    public var deletedBy: Int64?
    public var deletedAt: String?
    public var sortOrder: Int
    public var isCompleted: Int
    public var createdAt: String?
    public var updatedAt: String?

    // Block content fields
    public var blockType: String
    public var blockData: String?         // JSON for type-specific data
    public var headingLevel: Int?         // 1, 2, 3 for headings
    public var checklistItems: String?    // JSON array of {text, checked}
    public var photoPath: String?
    public var referenceType: String?     // "part", "po", "jpo", "job"
    public var referenceId: Int64?

    // Block provenance (#1817 / #Isaac-14)
    /// Device that last wrote this block. Previously only `_conflict_log` knew this,
    /// which meant provenance existed only *after* a conflict, never before one.
    public var deviceId: String?
    /// General block lifecycle status. Distinct from `taskStatus`, which is to-do-specific.
    public var blockStatus: String?
    // NOTE: there is deliberately no `editingUserId` here. The live-editor concept is served
    // by `notebook_entry_edit_locks` (migration 098) via `activeBlockEditLocks`; a column here
    // would be a second, competing source of truth that disagrees whenever a lock expires.

    enum CodingKeys: String, CodingKey {
        case id, title, content
        case sectionId = "section_id"
        case notebookId = "notebook_id"
        case entryType = "entry_type"
        case fieldType = "field_type"
        case fieldRequired = "field_required"
        case fieldFilledBy = "field_filled_by"
        case taskStatus = "task_status"
        case taskDueDate = "task_due_date"
        case taskAssignedTo = "task_assigned_to"
        case taskPartsNote = "task_parts_note"
        case createdBy = "created_by"
        case updatedBy = "updated_by"
        case isDeleted = "is_deleted"
        case deletedBy = "deleted_by"
        case deletedAt = "deleted_at"
        case sortOrder = "sort_order"
        case isCompleted = "is_completed"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case blockType = "block_type"
        case blockData = "block_data"
        case headingLevel = "heading_level"
        case checklistItems = "checklist_items"
        case photoPath = "photo_path"
        case referenceType = "reference_type"
        case referenceId = "reference_id"
        case deviceId = "device_id"
        case blockStatus = "block_status"
    }

    public mutating func didInsert(_ inserted: InsertionSuccess) { id = inserted.rowID }
}

// MARK: - NotebookEntryEdit

/// One saved revision of a block, retained as a bounded per-user ring buffer (#1817).
///
/// The bound is **6 per user, per block** — not 6 per block. Three users editing one block
/// retain 6 + 6 + 6 rows. Eviction is scoped to `(entryId, userId)` so one user's saves never
/// evict another's; the multi-editor case is the entire reason the history exists.
///
/// `editOrdinal` is monotonic per `(entryId, userId)` and is the ordering key. `savedAt` is
/// second-resolution `datetime('now')`, so two saves within one second tie and "the newest 6"
/// becomes ambiguous — an ordinal cannot tie, and is stable across devices whose clocks disagree.
public struct NotebookEntryEdit: Codable, FetchableRecord, MutablePersistableRecord, Sendable, Identifiable {
    public static let databaseTableName = "notebook_entry_edits"
    public var id: Int64?
    public var entryId: Int64
    public var userId: Int64
    public var deviceId: String?
    public var editOrdinal: Int64
    public var titleSnapshot: String?
    public var contentSnapshot: String?
    public var blockDataSnapshot: String?
    public var savedAt: String?

    enum CodingKeys: String, CodingKey {
        case id
        case entryId = "entry_id"
        case userId = "user_id"
        case deviceId = "device_id"
        case editOrdinal = "edit_ordinal"
        case titleSnapshot = "title_snapshot"
        case contentSnapshot = "content_snapshot"
        case blockDataSnapshot = "block_data_snapshot"
        case savedAt = "saved_at"
    }

    public init(
        id: Int64? = nil,
        entryId: Int64,
        userId: Int64,
        deviceId: String? = nil,
        editOrdinal: Int64,
        titleSnapshot: String? = nil,
        contentSnapshot: String? = nil,
        blockDataSnapshot: String? = nil,
        savedAt: String? = nil
    ) {
        self.id = id
        self.entryId = entryId
        self.userId = userId
        self.deviceId = deviceId
        self.editOrdinal = editOrdinal
        self.titleSnapshot = titleSnapshot
        self.contentSnapshot = contentSnapshot
        self.blockDataSnapshot = blockDataSnapshot
        self.savedAt = savedAt
    }

    public mutating func didInsert(_ inserted: InsertionSuccess) { id = inserted.rowID }
}

// MARK: - NotebookEntryPermission

public struct NotebookEntryPermission: Codable, FetchableRecord, MutablePersistableRecord, Sendable {
    public static let databaseTableName = "notebook_entry_permissions"
    public var id: Int64?
    public var entryId: Int64
    public var userId: Int64
    public var grantedBy: Int64
    public var deletedAt: String?
    public var grantedAt: String?

    enum CodingKeys: String, CodingKey {
        case id
        case entryId = "entry_id"
        case userId = "user_id"
        case grantedBy = "granted_by"
        case deletedAt = "deleted_at"
        case grantedAt = "granted_at"
    }

    public mutating func didInsert(_ inserted: InsertionSuccess) { id = inserted.rowID }
}

// MARK: - NotebookEntryTool

public struct NotebookEntryTool: Codable, FetchableRecord, MutablePersistableRecord, Sendable {
    public static let databaseTableName = "notebook_entry_tools"
    public var id: Int64?
    public var entryId: Int64
    public var toolId: Int64
    public var notes: String?
    public var createdBy: Int64
    public var deletedAt: String?
    public var createdAt: String?

    enum CodingKeys: String, CodingKey {
        case id, notes
        case entryId = "entry_id"
        case toolId = "tool_id"
        case createdBy = "created_by"
        case deletedAt = "deleted_at"
        case createdAt = "created_at"
    }

    public mutating func didInsert(_ inserted: InsertionSuccess) { id = inserted.rowID }
}

// MARK: - NotebookBlockConflict

/// Represents a sync conflict on a notebook entry (block).
/// Built from `_conflict_log` rows where the table is `notebook_entries`
/// and the conflict has not yet been reviewed.
///
/// Each conflict captures both versions of a field so the user can
/// choose which to keep ("local" or "remote").
public struct NotebookBlockConflict: Identifiable, Sendable {
    public let id: String               // Composite key: "\(conflictLogId)"
    public let conflictLogId: Int64      // Row ID in _conflict_log
    public let entryId: Int64            // notebook_entries.id
    public let fieldName: String         // Which field conflicted (e.g. "content", "block_data")
    public let localValue: String?
    public let remoteValue: String?
    public let localTimestamp: String     // ISO 8601 from _conflict_log.local_ts
    public let remoteTimestamp: String    // ISO 8601 from _conflict_log.remote_ts
    public let localDeviceId: String
    public let remoteDeviceId: String
    public let winner: String            // "local" or "remote" — what LWW chose
    public let resolvedAt: String?
    // Contextual info about the entry
    public let entryTitle: String?
    public let blockType: String?

    public init(
        conflictLogId: Int64,
        entryId: Int64,
        fieldName: String,
        localValue: String?,
        remoteValue: String?,
        localTimestamp: String,
        remoteTimestamp: String,
        localDeviceId: String,
        remoteDeviceId: String,
        winner: String,
        resolvedAt: String?,
        entryTitle: String?,
        blockType: String?
    ) {
        self.id = "\(conflictLogId)"
        self.conflictLogId = conflictLogId
        self.entryId = entryId
        self.fieldName = fieldName
        self.localValue = localValue
        self.remoteValue = remoteValue
        self.localTimestamp = localTimestamp
        self.remoteTimestamp = remoteTimestamp
        self.localDeviceId = localDeviceId
        self.remoteDeviceId = remoteDeviceId
        self.winner = winner
        self.resolvedAt = resolvedAt
        self.entryTitle = entryTitle
        self.blockType = blockType
    }
}

// MARK: - NotebookEntryEditLock

/// Advisory lock for a notebook block currently being edited on a device.
public struct NotebookEntryEditLock: Identifiable, Sendable {
    public let id: Int64
    public let entryId: Int64
    public let userId: Int64
    public let userName: String
    public let deviceId: String
    public let lockedAt: String
    public let expiresAt: String

    public init(
        id: Int64,
        entryId: Int64,
        userId: Int64,
        userName: String,
        deviceId: String,
        lockedAt: String,
        expiresAt: String
    ) {
        self.id = id
        self.entryId = entryId
        self.userId = userId
        self.userName = userName
        self.deviceId = deviceId
        self.lockedAt = lockedAt
        self.expiresAt = expiresAt
    }
}

// MARK: - TaskOrderLink

public struct TaskOrderLink: Codable, FetchableRecord, MutablePersistableRecord, Sendable {
    public static let databaseTableName = "task_order_links"
    public var id: Int64?
    public var entryId: Int64
    public var poId: Int64?
    public var status: String?
    public var deletedAt: String?
    public var createdAt: String?

    enum CodingKeys: String, CodingKey {
        case id, status
        case entryId = "entry_id"
        case poId = "po_id"
        case deletedAt = "deleted_at"
        case createdAt = "created_at"
    }

    public mutating func didInsert(_ inserted: InsertionSuccess) { id = inserted.rowID }
}
