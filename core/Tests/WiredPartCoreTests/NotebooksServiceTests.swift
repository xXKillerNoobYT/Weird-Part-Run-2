import Foundation
import Testing
import GRDB
@testable import WiredPartCore

/// Tests for the NotebooksService covering notebook CRUD, entries, templates,
/// stats, and filtering.
@Suite("NotebooksService Tests")
struct NotebooksServiceTests {

    // MARK: - 1. Create Notebook & List

    @Test("Create notebook and verify it appears in list")
    func testCreateNotebookAppearsInList() throws {
        let env = try E2ETestHelpers.setUp()

        let nbId = try env.notebooks.createNotebook(
            title: "Field Notes",
            notebookType: "general",
            createdBy: env.adminUserId
        )
        #expect(nbId > 0)

        let list = try env.notebooks.listNotebooks()
        #expect(list.contains { $0.id == nbId })
        #expect(list.contains { $0.title == "Field Notes" })
    }

    // MARK: - 2. Create Notebook with Job Association

    @Test("Create notebook linked to a job")
    func testCreateNotebookWithJob() throws {
        let env = try E2ETestHelpers.setUp()
        let jobId = try E2ETestHelpers.seedJob(env)

        let nbId = try env.notebooks.createNotebook(
            title: "Job Notebook",
            notebookType: "job",
            jobId: jobId,
            createdBy: env.adminUserId
        )
        #expect(nbId > 0)

        let detail = try env.notebooks.getNotebookDetail(id: nbId)
        #expect(detail.jobId == jobId)
        #expect(detail.notebookType == "job")
        #expect(detail.title == "Job Notebook")
    }

    // MARK: - 3. Create Entries and Verify

    @Test("Create block entries and verify they appear in hierarchy")
    func testAddNotebookEntries() throws {
        let env = try E2ETestHelpers.setUp()

        let nbId = try env.notebooks.createNotebook(
            title: "Notes",
            notebookType: "general",
            createdBy: env.adminUserId
        )

        let sectionId = try env.notebooks.createSection(
            notebookId: nbId, groupId: nil, name: "General"
        )

        let e1 = try env.notebooks.createBlockEntry(
            sectionId: sectionId,
            blockType: "text",
            title: "First note",
            content: "Hello world",
            createdBy: env.adminUserId,
            sortOrder: 0
        )
        let e2 = try env.notebooks.createBlockEntry(
            sectionId: sectionId,
            blockType: "text",
            title: "Second note",
            content: "Goodbye world",
            createdBy: env.adminUserId,
            sortOrder: 1
        )
        #expect(e1 > 0)
        #expect(e2 > 0)
        #expect(e1 != e2)

        // Verify entries appear in hierarchy
        let hierarchy = try env.notebooks.getNotebookHierarchy(notebookId: nbId)
        let entries = hierarchy.ungroupedSections.flatMap(\.entries)
        #expect(entries.count == 2)
        #expect(entries.contains { $0.title == "First note" })
        #expect(entries.contains { $0.title == "Second note" })
    }

    // MARK: - 4. Update Entry Content (Block Entry)

    @Test("Update a block entry's content")
    func testUpdateBlockEntry() throws {
        let env = try E2ETestHelpers.setUp()

        let nbId = try env.notebooks.createNotebook(
            title: "Updatable",
            notebookType: "general",
            createdBy: env.adminUserId
        )

        // Create a section, then a block entry
        let sectionId = try env.notebooks.createSection(
            notebookId: nbId, groupId: nil, name: "Main"
        )
        let entryId = try env.notebooks.createBlockEntry(
            sectionId: sectionId,
            blockType: "text",
            title: "Draft",
            content: "Original content",
            createdBy: env.adminUserId
        )

        // Update
        try env.notebooks.updateBlockEntry(
            entryId: entryId,
            content: "Revised content",
            blockData: nil,
            updatedBy: env.adminUserId
        )

        // Verify through hierarchy
        let hierarchy = try env.notebooks.getNotebookHierarchy(notebookId: nbId)
        let entries = hierarchy.ungroupedSections.flatMap(\.entries)
        let updated = entries.first { $0.id == entryId }
        #expect(updated != nil)
        #expect(updated?.content == "Revised content")
    }

    @Test("Editing a block entry updates title and records change history")
    func testUpdateBlockEntryTitleAndHistory() throws {
        let env = try E2ETestHelpers.setUp()

        let nbId = try env.notebooks.createNotebook(
            title: "Editable Blocks",
            notebookType: "general",
            createdBy: env.adminUserId
        )
        let sectionId = try env.notebooks.createSection(
            notebookId: nbId, groupId: nil, name: "Info"
        )
        let entryId = try env.notebooks.createBlockEntry(
            sectionId: sectionId,
            blockType: "heading",
            title: "Original heading",
            content: nil,
            createdBy: env.adminUserId
        )

        try env.notebooks.updateBlockEntry(
            entryId: entryId,
            title: "Revised heading",
            content: nil,
            blockData: nil,
            updatedBy: env.adminUserId
        )

        let hierarchy = try env.notebooks.getNotebookHierarchy(notebookId: nbId)
        let updated = hierarchy.ungroupedSections.flatMap(\.entries).first { $0.id == entryId }
        #expect(updated?.title == "Revised heading")

        let historyRows = try env.db.writer.read { dbConn in
            try Row.fetchAll(dbConn, sql: """
                SELECT changed_fields, old_values
                FROM _change_log
                WHERE table_name = 'notebook_entries'
                  AND record_id = ?
                  AND operation = 'UPDATE'
                ORDER BY id DESC
                """, arguments: [entryId])
        }
        #expect(historyRows.count == 1)
        let changedFieldsJSON = historyRows.first?["changed_fields"] as String?
        let oldValuesJSON = historyRows.first?["old_values"] as String?
        #expect(changedFieldsJSON?.contains("title") == true)
        #expect(oldValuesJSON?.contains("Original heading") == true)

        let changedFieldsData = try #require(changedFieldsJSON?.data(using: .utf8))
        let oldValuesData = try #require(oldValuesJSON?.data(using: .utf8))
        let changedFields = try #require(JSONSerialization.jsonObject(with: changedFieldsData) as? [String: Any])
        let oldValues = try #require(JSONSerialization.jsonObject(with: oldValuesData) as? [String: Any])
        #expect(changedFields["title"] as? String == "Revised heading")
        #expect(oldValues["title"] as? String == "Original heading")
    }

    @Test("Creating checklist block entries stores checklist items in the canonical column")
    func testCreateChecklistBlockEntryStoresChecklistItems() throws {
        let env = try E2ETestHelpers.setUp()

        let nbId = try env.notebooks.createNotebook(
            title: "Checklist Blocks",
            notebookType: "general",
            createdBy: env.adminUserId
        )
        let sectionId = try env.notebooks.createSection(
            notebookId: nbId, groupId: nil, name: "Checklist"
        )
        let checklistJSON = """
        [{"text":"Verify breaker labels","checked":"false"}]
        """

        let entryId = try env.notebooks.createBlockEntry(
            sectionId: sectionId,
            blockType: "checklist",
            title: "Commissioning",
            content: nil,
            blockData: nil,
            checklistItems: checklistJSON,
            createdBy: env.adminUserId
        )

        let stored = try env.db.writer.read { dbConn in
            try Row.fetchOne(dbConn, sql: """
                SELECT block_data, checklist_items
                FROM notebook_entries
                WHERE id = ?
                """, arguments: [entryId])
        }
        #expect((stored?["block_data"] as String?) == nil)
        #expect((stored?["checklist_items"] as String?) == checklistJSON)

        let hierarchy = try env.notebooks.getNotebookHierarchy(notebookId: nbId)
        let entry = hierarchy.ungroupedSections.flatMap(\.entries).first { $0.id == entryId }
        #expect(entry?.checklistItems == checklistJSON)
    }

    @Test("Updating block entries requires manage_notebooks permission")
    func testUpdateBlockEntryRequiresManageNotebooksPermission() throws {
        let env = try E2ETestHelpers.setUp()

        let nbId = try env.notebooks.createNotebook(
            title: "Permissioned Blocks",
            notebookType: "general",
            createdBy: env.adminUserId
        )
        let sectionId = try env.notebooks.createSection(
            notebookId: nbId, groupId: nil, name: "Main"
        )
        let entryId = try env.notebooks.createBlockEntry(
            sectionId: sectionId,
            blockType: "text",
            title: "Protected",
            content: "Original",
            createdBy: env.adminUserId
        )

        #expect(throws: ServicePermissionGate.GateError.self) {
            try env.notebooks.updateBlockEntry(
                entryId: entryId,
                content: "Unauthorized",
                blockData: nil,
                updatedBy: 999_999
            )
        }
    }

    @Test("Block edit locks are visible until their five minute expiry")
    func testBlockEditLockVisibilityAndExpiry() throws {
        let env = try E2ETestHelpers.setUp()
        let nbId = try env.notebooks.createNotebook(
            title: "Lock Visibility",
            notebookType: "general",
            createdBy: env.adminUserId
        )
        let sectionId = try env.notebooks.createSection(
            notebookId: nbId,
            groupId: nil,
            name: "Main"
        )
        let entryId = try env.notebooks.createBlockEntry(
            sectionId: sectionId,
            blockType: "text",
            title: "Shared note",
            content: "Original",
            createdBy: env.adminUserId
        )

        let base = Date(timeIntervalSince1970: 1_800_000_000)
        let lock = try env.notebooks.acquireBlockEditLock(
            entryId: entryId,
            userId: env.adminUserId,
            deviceId: "field-ipad",
            now: base
        )
        #expect(lock.entryId == entryId)
        #expect(lock.deviceId == "field-ipad")

        let active = try env.notebooks.activeBlockEditLocks(notebookId: nbId, now: base.addingTimeInterval(299))
        #expect(active.count == 1)
        #expect(active.first?.entryId == entryId)
        #expect(active.first?.userName == "TestAdmin")

        let expired = try env.notebooks.activeBlockEditLocks(notebookId: nbId, now: base.addingTimeInterval(301))
        #expect(expired.isEmpty)
    }

    @Test("Foundation Models merge preserves conflicts when merge is unavailable")
    func testFoundationModelsMergeFallbackPreservesConflict() async throws {
        let env = try E2ETestHelpers.setUp()
        let nbId = try env.notebooks.createNotebook(
            title: "Merge Fallback",
            notebookType: "general",
            createdBy: env.adminUserId
        )
        let sectionId = try env.notebooks.createSection(
            notebookId: nbId,
            groupId: nil,
            name: "Main"
        )
        let entryId = try env.notebooks.createBlockEntry(
            sectionId: sectionId,
            blockType: "text",
            title: "Conflict note",
            content: "Local text",
            createdBy: env.adminUserId
        )
        let conflictId = try insertNotebookConflict(
            db: env.db,
            entryId: entryId,
            fieldName: "content",
            localValue: "Local text",
            remoteValue: "Remote text"
        )

        let merged = try await env.notebooks.resolveBlockConflictWithFoundationModels(
            conflictLogId: conflictId,
            mergeText: { _, _, _ in nil }
        )
        #expect(merged == false)

        let row = try await env.db.writer.read { dbConn in
            try Row.fetchOne(dbConn, sql: """
                SELECT ne.content, cl.reviewed, cl.local_value, cl.remote_value
                FROM notebook_entries ne
                JOIN _conflict_log cl ON CAST(cl.record_id AS INTEGER) = ne.id
                WHERE cl.id = ?
                """, arguments: [conflictId])
        }
        #expect(row?["content"] as String? == "Local text")
        #expect((row?["reviewed"] as Int?) == 0)
        #expect(row?["local_value"] as String? == "Local text")
        #expect(row?["remote_value"] as String? == "Remote text")
    }

    @Test("Foundation Models merge applies merged text and reviews conflict")
    func testFoundationModelsMergeAppliesMergedText() async throws {
        let env = try E2ETestHelpers.setUp()
        let nbId = try env.notebooks.createNotebook(
            title: "Merge Success",
            notebookType: "general",
            createdBy: env.adminUserId
        )
        let sectionId = try env.notebooks.createSection(
            notebookId: nbId,
            groupId: nil,
            name: "Main"
        )
        let entryId = try env.notebooks.createBlockEntry(
            sectionId: sectionId,
            blockType: "text",
            title: "Conflict note",
            content: "Local text",
            createdBy: env.adminUserId
        )
        let conflictId = try insertNotebookConflict(
            db: env.db,
            entryId: entryId,
            fieldName: "content",
            localValue: "Local text",
            remoteValue: "Remote text"
        )

        let merged = try await env.notebooks.resolveBlockConflictWithFoundationModels(
            conflictLogId: conflictId,
            mergeText: { local, remote, _ in "\(local) + \(remote)" }
        )
        #expect(merged == true)

        let row = try await env.db.writer.read { dbConn in
            try Row.fetchOne(dbConn, sql: """
                SELECT ne.content, cl.reviewed, cl.winner
                FROM notebook_entries ne
                JOIN _conflict_log cl ON CAST(cl.record_id AS INTEGER) = ne.id
                WHERE cl.id = ?
                """, arguments: [conflictId])
        }
        #expect(row?["content"] as String? == "Local text + Remote text")
        #expect((row?["reviewed"] as Int?) == 1)
        #expect(row?["winner"] as String? == "ai_merge")
    }

    @Test("Foundation Models merge preserves conflict when row changes before write")
    func testFoundationModelsMergeRejectsStaleConflictSnapshot() async throws {
        let env = try E2ETestHelpers.setUp()
        let nbId = try env.notebooks.createNotebook(
            title: "Merge Stale Snapshot",
            notebookType: "general",
            createdBy: env.adminUserId
        )
        let sectionId = try env.notebooks.createSection(
            notebookId: nbId,
            groupId: nil,
            name: "Main"
        )
        let entryId = try env.notebooks.createBlockEntry(
            sectionId: sectionId,
            blockType: "text",
            title: "Conflict note",
            content: "Local text",
            createdBy: env.adminUserId
        )
        let conflictId = try insertNotebookConflict(
            db: env.db,
            entryId: entryId,
            fieldName: "content",
            localValue: "Local text",
            remoteValue: "Remote text"
        )

        let merged = try await env.notebooks.resolveBlockConflictWithFoundationModels(
            conflictLogId: conflictId,
            mergeText: { _, _, _ in
                try? await env.db.writer.write { dbConn in
                    try dbConn.execute(
                        sql: "UPDATE notebook_entries SET content = ? WHERE id = ?",
                        arguments: ["Concurrent update", entryId]
                    )
                }
                return "Merged text"
            }
        )
        #expect(merged == false)

        let row = try await env.db.writer.read { dbConn in
            try Row.fetchOne(dbConn, sql: """
                SELECT ne.content, cl.reviewed, cl.winner
                FROM notebook_entries ne
                JOIN _conflict_log cl ON CAST(cl.record_id AS INTEGER) = ne.id
                WHERE cl.id = ?
                """, arguments: [conflictId])
        }
        #expect(row?["content"] as String? == "Concurrent update")
        #expect((row?["reviewed"] as Int?) == 0)
        #expect(row?["winner"] as String? == "local")
    }

    // MARK: - 5. Delete Entry (Soft Delete)

    @Test("Soft-delete a block entry removes it from hierarchy")
    func testDeleteBlockEntry() throws {
        let env = try E2ETestHelpers.setUp()

        let nbId = try env.notebooks.createNotebook(
            title: "Deletable",
            notebookType: "general",
            createdBy: env.adminUserId
        )

        let sectionId = try env.notebooks.createSection(
            notebookId: nbId, groupId: nil, name: "Section"
        )
        let entryId = try env.notebooks.createBlockEntry(
            sectionId: sectionId,
            blockType: "text",
            title: "Doomed",
            content: "Will be deleted",
            createdBy: env.adminUserId
        )

        // Verify it exists
        var hierarchy = try env.notebooks.getNotebookHierarchy(notebookId: nbId)
        var entryIds = hierarchy.ungroupedSections.flatMap(\.entries).map(\.id)
        #expect(entryIds.contains(entryId))

        // Delete
        try env.notebooks.deleteBlockEntry(entryId: entryId)

        // Verify it no longer appears
        hierarchy = try env.notebooks.getNotebookHierarchy(notebookId: nbId)
        entryIds = hierarchy.ungroupedSections.flatMap(\.entries).map(\.id)
        #expect(!entryIds.contains(entryId))
    }

    // MARK: - 6. Toggle Entry Completion

    @Test("Complete entry marks it as done")
    func testCompleteEntry() throws {
        let env = try E2ETestHelpers.setUp()

        let nbId = try env.notebooks.createNotebook(
            title: "Todo List",
            notebookType: "general",
            createdBy: env.adminUserId
        )

        let sectionId = try env.notebooks.createSection(
            notebookId: nbId, groupId: nil, name: "Tasks"
        )
        let entryId = try env.notebooks.createBlockEntry(
            sectionId: sectionId,
            blockType: "text",
            title: "Buy supplies",
            content: "Need wire and conduit",
            createdBy: env.adminUserId
        )

        // Complete the entry
        try env.notebooks.completeEntry(entryId: entryId)

        // Verify via raw DB query (task_status should be 'complete')
        let status = try env.db.writer.read { dbConn -> String? in
            try String.fetchOne(dbConn, sql: "SELECT task_status FROM notebook_entries WHERE id = ?", arguments: [entryId])
        }
        #expect(status == "complete")
    }

    // MARK: - 7. Get Notebook Detail with Entries

    @Test("getNotebookDetail returns header and entries")
    func testGetNotebookDetail() throws {
        let env = try E2ETestHelpers.setUp()

        let nbId = try env.notebooks.createNotebook(
            title: "Detailed Notebook",
            notebookType: "general",
            createdBy: env.adminUserId
        )

        // The getNotebookDetail entries query uses notebook_id on notebook_entries.
        // addNotebookEntry inserts via section_id (no notebook_id column set).
        // Use createSection + createBlockEntry which also goes through section_id.
        // Entries show up in getNotebookDetail because it queries ne.notebook_id = ?.
        // We need to insert entries that have notebook_id set. Let's use direct SQL
        // to match the migration 038 schema which added notebook_id to entries.
        let sectionId = try env.notebooks.createSection(
            notebookId: nbId, groupId: nil, name: "Main"
        )
        try env.db.writer.write { dbConn in
            try dbConn.execute(sql: """
                INSERT INTO notebook_entries
                (notebook_id, section_id, title, content, entry_type, block_type,
                 is_completed, sort_order, created_by, created_at, updated_at)
                VALUES (?, ?, 'Entry A', 'Content A', 'note', 'text', 0, 0, ?, datetime('now'), datetime('now'))
                """, arguments: [nbId, sectionId, env.adminUserId])
            try dbConn.execute(sql: """
                INSERT INTO notebook_entries
                (notebook_id, section_id, title, content, entry_type, block_type,
                 is_completed, sort_order, created_by, created_at, updated_at)
                VALUES (?, ?, 'Entry B', 'Content B', 'note', 'text', 0, 1, ?, datetime('now'), datetime('now'))
                """, arguments: [nbId, sectionId, env.adminUserId])
        }

        let detail = try env.notebooks.getNotebookDetail(id: nbId)
        #expect(detail.id == nbId)
        #expect(detail.title == "Detailed Notebook")
        #expect(detail.createdByName == "TestAdmin")
        #expect(detail.entries.count == 2)
        #expect(detail.entries[0].content == "Content A")
        #expect(detail.entries[1].content == "Content B")
    }

    // MARK: - 8. List Templates

    @Test("Seed and list notebook templates")
    func testListTemplates() throws {
        let env = try E2ETestHelpers.setUp()

        // Seed default templates
        try env.notebooks.seedDefaultTemplates(createdBy: env.adminUserId)

        let templates = try env.notebooks.getTemplates()
        #expect(templates.count >= 3) // Residential, Commercial, Service Call
        #expect(templates.contains { $0.name == "Residential Job" })
        #expect(templates.contains { $0.name == "Commercial Job" })
        #expect(templates.contains { $0.name == "Service Call" })
    }

    @Test("List templates filtered by type")
    func testListTemplatesFilteredByType() throws {
        let env = try E2ETestHelpers.setUp()
        try env.notebooks.seedDefaultTemplates(createdBy: env.adminUserId)

        let jobTemplates = try env.notebooks.getTemplates(templateType: "job")
        #expect(jobTemplates.count >= 3)

        let noMatch = try env.notebooks.getTemplates(templateType: "nonexistent")
        #expect(noMatch.isEmpty)
    }

    // MARK: - 9. Create From Template (Apply Job Template)

    @Test("Apply job template creates groups, sections, and entries")
    func testApplyJobTemplate() throws {
        let env = try E2ETestHelpers.setUp()
        try env.notebooks.seedDefaultTemplates(createdBy: env.adminUserId)

        let templates = try env.notebooks.getTemplates()
        let residential = templates.first { $0.name == "Residential Job" }
        let templateId = try #require(residential?.id)

        // Create a notebook, then apply the template
        let nbId = try env.notebooks.createNotebook(
            title: "Residential Project",
            notebookType: "job",
            createdBy: env.adminUserId
        )

        try env.notebooks.applyJobTemplate(
            templateId: templateId,
            notebookId: nbId,
            createdBy: env.adminUserId
        )

        // Verify hierarchy was populated
        let hierarchy = try env.notebooks.getNotebookHierarchy(notebookId: nbId)
        #expect(!hierarchy.groups.isEmpty)
        // Residential template has 5 groups: Safety, Materials, Daily Log, Photos, Punch List
        #expect(hierarchy.groups.count == 5)
        #expect(hierarchy.groups.contains { $0.name == "Safety & Compliance" })
        #expect(hierarchy.groups.contains { $0.name == "Daily Log" })
    }

    // MARK: - 10. Notebooks Stats

    @Test("Notebooks stats reflect actual data")
    func testNotebooksStats() throws {
        let env = try E2ETestHelpers.setUp()
        let jobId = try E2ETestHelpers.seedJob(env)

        // Create a general notebook
        _ = try env.notebooks.createNotebook(
            title: "General Notes",
            notebookType: "general",
            createdBy: env.adminUserId
        )

        // Create a job notebook
        _ = try env.notebooks.createNotebook(
            title: "Job Notes",
            notebookType: "job",
            jobId: jobId,
            createdBy: env.adminUserId
        )

        // Create a template notebook (should count in total but not in general)
        _ = try env.notebooks.createNotebook(
            title: "Template NB",
            notebookType: "template",
            createdBy: env.adminUserId
        )

        let stats = try env.notebooks.getNotebooksStats()
        #expect(stats.totalNotebooks >= 3)
        #expect(stats.jobNotebooks >= 1)
        #expect(stats.generalNotebooks >= 1)
    }

    // MARK: - 11. List Filtered by Type

    @Test("List notebooks filtered by notebook type")
    func testListNotebooksFilteredByType() throws {
        let env = try E2ETestHelpers.setUp()

        _ = try env.notebooks.createNotebook(
            title: "General A",
            notebookType: "general",
            createdBy: env.adminUserId
        )
        _ = try env.notebooks.createNotebook(
            title: "Job A",
            notebookType: "job",
            createdBy: env.adminUserId
        )
        _ = try env.notebooks.createNotebook(
            title: "Template A",
            notebookType: "template",
            createdBy: env.adminUserId
        )

        let generalOnly = try env.notebooks.listNotebooks(notebookType: "general")
        #expect(generalOnly.allSatisfy { $0.notebookType == "general" })
        #expect(generalOnly.contains { $0.title == "General A" })

        let jobOnly = try env.notebooks.listNotebooks(notebookType: "job")
        #expect(jobOnly.allSatisfy { $0.notebookType == "job" })
        #expect(jobOnly.contains { $0.title == "Job A" })

        let templateOnly = try env.notebooks.listNotebooks(notebookType: "template")
        #expect(templateOnly.allSatisfy { $0.notebookType == "template" })
        #expect(templateOnly.contains { $0.title == "Template A" })
    }

    // MARK: - 12. List Filtered by Job ID

    @Test("List notebooks filtered by jobId")
    func testListNotebooksFilteredByJobId() throws {
        let env = try E2ETestHelpers.setUp()
        let job1 = try E2ETestHelpers.seedJob(env, jobNumber: "J-100", name: "Job Alpha")
        let job2 = try E2ETestHelpers.seedJob(env, jobNumber: "J-200", name: "Job Beta")

        _ = try env.notebooks.createNotebook(
            title: "NB for Job 1",
            notebookType: "job",
            jobId: job1,
            createdBy: env.adminUserId
        )
        _ = try env.notebooks.createNotebook(
            title: "NB for Job 2",
            notebookType: "job",
            jobId: job2,
            createdBy: env.adminUserId
        )
        _ = try env.notebooks.createNotebook(
            title: "Unlinked NB",
            notebookType: "general",
            createdBy: env.adminUserId
        )

        let job1Notebooks = try env.notebooks.listNotebooks(jobId: job1)
        #expect(job1Notebooks.count == 1)
        #expect(job1Notebooks[0].title == "NB for Job 1")

        let job2Notebooks = try env.notebooks.listNotebooks(jobId: job2)
        #expect(job2Notebooks.count == 1)
        #expect(job2Notebooks[0].title == "NB for Job 2")
    }

    // MARK: - 13. Notebook Not Found Throws

    @Test("getNotebookDetail throws for non-existent ID")
    func testNotebookNotFoundThrows() throws {
        let env = try E2ETestHelpers.setUp()

        #expect(throws: NotebooksService.NotebooksError.self) {
            _ = try env.notebooks.getNotebookDetail(id: 99999)
        }
    }

    // MARK: - 14. Section Groups CRUD

    @Test("Section group lifecycle: create, update, delete")
    func testSectionGroupLifecycle() throws {
        let env = try E2ETestHelpers.setUp()

        let nbId = try env.notebooks.createNotebook(
            title: "Grouped NB",
            notebookType: "general",
            createdBy: env.adminUserId
        )

        // Create groups
        let g1 = try env.notebooks.createSectionGroup(notebookId: nbId, name: "Group A")
        let g2 = try env.notebooks.createSectionGroup(notebookId: nbId, name: "Group B")
        #expect(g1 > 0)
        #expect(g2 > 0)

        // Verify via hierarchy
        var hierarchy = try env.notebooks.getNotebookHierarchy(notebookId: nbId)
        #expect(hierarchy.groups.count == 2)

        // Update group name
        try env.notebooks.updateSectionGroup(groupId: g1, name: "Group Alpha")
        hierarchy = try env.notebooks.getNotebookHierarchy(notebookId: nbId)
        #expect(hierarchy.groups.contains { $0.name == "Group Alpha" })

        // Delete group
        try env.notebooks.deleteSectionGroup(groupId: g1)
        hierarchy = try env.notebooks.getNotebookHierarchy(notebookId: nbId)
        #expect(hierarchy.groups.count == 1)
        #expect(hierarchy.groups[0].name == "Group B")
    }

    // MARK: - 15. Section CRUD

    @Test("Section lifecycle: create, update, delete")
    func testSectionLifecycle() throws {
        let env = try E2ETestHelpers.setUp()

        let nbId = try env.notebooks.createNotebook(
            title: "Sectioned NB",
            notebookType: "general",
            createdBy: env.adminUserId
        )

        let s1 = try env.notebooks.createSection(notebookId: nbId, groupId: nil, name: "Section 1")
        let s2 = try env.notebooks.createSection(notebookId: nbId, groupId: nil, name: "Section 2")
        #expect(s1 > 0)
        #expect(s2 > 0)

        // Verify
        var hierarchy = try env.notebooks.getNotebookHierarchy(notebookId: nbId)
        #expect(hierarchy.ungroupedSections.count == 2)

        // Update
        try env.notebooks.updateSection(sectionId: s1, name: "Renamed Section")
        hierarchy = try env.notebooks.getNotebookHierarchy(notebookId: nbId)
        #expect(hierarchy.ungroupedSections.contains { $0.name == "Renamed Section" })

        // Delete
        try env.notebooks.deleteSection(sectionId: s1)
        hierarchy = try env.notebooks.getNotebookHierarchy(notebookId: nbId)
        #expect(hierarchy.ungroupedSections.count == 1)
        #expect(hierarchy.ungroupedSections[0].name == "Section 2")
    }

    // MARK: - 16. Block Entry with Sort Order

    @Test("Block entries respect sort order")
    func testBlockEntrySortOrder() throws {
        let env = try E2ETestHelpers.setUp()

        let nbId = try env.notebooks.createNotebook(
            title: "Ordered NB",
            notebookType: "general",
            createdBy: env.adminUserId
        )

        let sectionId = try env.notebooks.createSection(
            notebookId: nbId, groupId: nil, name: "Ordered"
        )

        _ = try env.notebooks.createBlockEntry(
            sectionId: sectionId, blockType: "text",
            title: "Third", content: "C", createdBy: env.adminUserId, sortOrder: 2
        )
        _ = try env.notebooks.createBlockEntry(
            sectionId: sectionId, blockType: "text",
            title: "First", content: "A", createdBy: env.adminUserId, sortOrder: 0
        )
        _ = try env.notebooks.createBlockEntry(
            sectionId: sectionId, blockType: "text",
            title: "Second", content: "B", createdBy: env.adminUserId, sortOrder: 1
        )

        let hierarchy = try env.notebooks.getNotebookHierarchy(notebookId: nbId)
        let entries = hierarchy.ungroupedSections.first?.entries ?? []
        #expect(entries.count == 3)
        // Entries come back ordered by sort_order ASC
        #expect(entries[0].title == "First")
        #expect(entries[1].title == "Second")
        #expect(entries[2].title == "Third")
    }

    // MARK: - 17. Work Classification

    @Test("Classify todo work and verify classification")
    func testWorkClassification() throws {
        let env = try E2ETestHelpers.setUp()

        let nbId = try env.notebooks.createNotebook(
            title: "Classified NB",
            notebookType: "general",
            createdBy: env.adminUserId
        )

        let sectionId = try env.notebooks.createSection(
            notebookId: nbId, groupId: nil, name: "Work"
        )
        let entryId = try env.notebooks.createBlockEntry(
            sectionId: sectionId,
            blockType: "text",
            title: "Fix outlet",
            content: "Replace outlet in kitchen",
            createdBy: env.adminUserId
        )

        // Classify as warranty
        try env.notebooks.classifyTodoWork(
            entryId: entryId,
            classification: "warranty",
            classifiedBy: env.adminUserId
        )

        // Verify via DB
        let classification = try env.db.writer.read { dbConn -> String? in
            try String.fetchOne(
                dbConn,
                sql: "SELECT work_classification FROM notebook_entries WHERE id = ?",
                arguments: [entryId]
            )
        }
        #expect(classification == "warranty")

        // Check history
        let history = try env.notebooks.getClassificationHistory(entryId: entryId)
        #expect(history.count == 1)
        #expect(history[0].newClassification == "warranty")
    }

    // MARK: - 18. Review Classification

    @Test("Manager reviews and approves classification")
    func testReviewClassification() throws {
        let env = try E2ETestHelpers.setUp()

        let nbId = try env.notebooks.createNotebook(
            title: "Review NB",
            notebookType: "general",
            createdBy: env.adminUserId
        )

        let sectionId = try env.notebooks.createSection(
            notebookId: nbId, groupId: nil, name: "Inspections"
        )
        let entryId = try env.notebooks.createBlockEntry(
            sectionId: sectionId,
            blockType: "text",
            title: "Inspect panel",
            content: "Check main panel",
            createdBy: env.adminUserId
        )

        // Classify then review/approve
        try env.notebooks.classifyTodoWork(
            entryId: entryId,
            classification: "regular",
            classifiedBy: env.adminUserId
        )

        try env.notebooks.reviewClassification(
            entryId: entryId,
            reviewedBy: env.adminUserId,
            approved: true,
            newClassification: nil
        )

        // Verify reviewed flag
        let reviewed = try env.db.writer.read { dbConn -> Int? in
            try Int.fetchOne(
                dbConn,
                sql: "SELECT classification_reviewed FROM notebook_entries WHERE id = ?",
                arguments: [entryId]
            )
        }
        #expect(reviewed == 1)
    }

    @Test("Pending warranty classifications list oldest unreviewed rows and remove after review")
    func testListPendingWarrantyClassifications() throws {
        let env = try E2ETestHelpers.setUp()
        let jobId = try E2ETestHelpers.seedJob(env)

        let nbId = try env.notebooks.createNotebook(
            title: "Warranty Job Notes",
            notebookType: "job",
            jobId: jobId,
            createdBy: env.adminUserId
        )
        let sectionId = try env.notebooks.createSection(
            notebookId: nbId,
            groupId: nil,
            name: "Work"
        )
        let entryId = try env.notebooks.createBlockEntry(
            sectionId: sectionId,
            blockType: "text",
            title: "Inspect callback",
            content: "Verify warranty classification",
            createdBy: env.adminUserId
        )

        try env.notebooks.classifyTodoWork(
            entryId: entryId,
            classification: "warranty",
            classifiedBy: env.adminUserId
        )

        let pending = try env.notebooks.listPendingWarrantyClassifications()
        #expect(pending.count == 1)
        #expect(pending[0].id == entryId)
        #expect(pending[0].requestedClassification == "warranty")
        #expect(pending[0].jobName == "Test Job")

        try env.notebooks.reviewClassification(
            entryId: entryId,
            reviewedBy: env.adminUserId,
            approved: true,
            newClassification: nil
        )

        let afterReview = try env.notebooks.listPendingWarrantyClassifications()
        #expect(afterReview.isEmpty)
    }

    @Test("Pending warranty classifications exclude entries under soft-deleted sections")
    func testListPendingWarrantyClassificationsExcludesDeletedSections() throws {
        let env = try E2ETestHelpers.setUp()
        let jobId = try E2ETestHelpers.seedJob(env)

        let nbId = try env.notebooks.createNotebook(
            title: "Deleted Section Notes",
            notebookType: "job",
            jobId: jobId,
            createdBy: env.adminUserId
        )
        let sectionId = try env.notebooks.createSection(
            notebookId: nbId,
            groupId: nil,
            name: "Doomed Section"
        )
        let entryId = try env.notebooks.createBlockEntry(
            sectionId: sectionId,
            blockType: "text",
            title: "Orphaned callback",
            content: "Should vanish with its section",
            createdBy: env.adminUserId
        )
        try env.notebooks.classifyTodoWork(
            entryId: entryId,
            classification: "warranty",
            classifiedBy: env.adminUserId
        )

        let pending = try env.notebooks.listPendingWarrantyClassifications()
        #expect(pending.contains { $0.id == entryId })

        // Soft-delete the section: its unreviewed entries must leave the review queue
        try env.notebooks.deleteSection(sectionId: sectionId)

        let afterDelete = try env.notebooks.listPendingWarrantyClassifications()
        #expect(afterDelete.allSatisfy { $0.id != entryId })
    }

    // MARK: - 19. Reclassify with Reason

    @Test("Reclassify todo resets review and logs reason")
    func testReclassifyTodoWork() throws {
        let env = try E2ETestHelpers.setUp()

        let nbId = try env.notebooks.createNotebook(
            title: "Reclass NB",
            notebookType: "general",
            createdBy: env.adminUserId
        )

        let sectionId = try env.notebooks.createSection(
            notebookId: nbId, groupId: nil, name: "Work Items"
        )
        let entryId = try env.notebooks.createBlockEntry(
            sectionId: sectionId,
            blockType: "text",
            title: "Wire run",
            content: "Run new wire to panel",
            createdBy: env.adminUserId
        )

        try env.notebooks.classifyTodoWork(
            entryId: entryId, classification: "regular",
            classifiedBy: env.adminUserId
        )
        try env.notebooks.reviewClassification(
            entryId: entryId, reviewedBy: env.adminUserId,
            approved: true, newClassification: nil
        )

        // Reclassify
        try env.notebooks.reclassifyTodoWork(
            entryId: entryId,
            newClassification: "warranty",
            changedBy: env.adminUserId,
            reason: "Customer reported pre-existing issue"
        )

        // Review should be reset
        let reviewed = try env.db.writer.read { dbConn -> Int? in
            try Int.fetchOne(
                dbConn,
                sql: "SELECT classification_reviewed FROM notebook_entries WHERE id = ?",
                arguments: [entryId]
            )
        }
        #expect(reviewed == 0)

        // History should have 2 entries (initial classify + reclassify)
        let history = try env.notebooks.getClassificationHistory(entryId: entryId)
        #expect(history.count == 2)
        // One entry should have the reclassify reason
        #expect(history.contains { $0.reason == "Customer reported pre-existing issue" })
        // One entry should have the warranty classification
        #expect(history.contains { $0.newClassification == "warranty" })
    }


    @Test("Classification mutations require explicit notebook classification permissions")
    func testClassificationMutationsRequirePermissions() throws {
        let env = try E2ETestHelpers.setUp()
        let unauthorizedUserId = try env.auth.createUser(displayName: "NoNotebookPerms", pin: "2468")
        let entryId = try createClassifiableEntry(env, title: "Unauthorized classification")

        try expectInsufficientNotebookPermission("notebooks.classify_todo") {
            try env.notebooks.classifyTodoWork(
                entryId: entryId,
                classification: "warranty",
                classifiedBy: unauthorizedUserId
            )
        }

        try env.notebooks.classifyTodoWork(
            entryId: entryId,
            classification: "regular",
            classifiedBy: env.adminUserId
        )

        try expectInsufficientNotebookPermission("notebooks.review_classification") {
            try env.notebooks.reviewClassification(
                entryId: entryId,
                reviewedBy: unauthorizedUserId,
                approved: true,
                newClassification: nil
            )
        }

        try expectInsufficientNotebookPermission("notebooks.reclassify_todo") {
            try env.notebooks.reclassifyTodoWork(
                entryId: entryId,
                newClassification: "warranty",
                changedBy: unauthorizedUserId,
                reason: "should be blocked"
            )
        }
    }

    @Test("Classification mutations reject soft-deleted entries without history leaks")
    func testClassificationMutationsRejectSoftDeletedEntriesWithoutHistoryLeaks() throws {
        let env = try E2ETestHelpers.setUp()

        let classifyEntryId = try createClassifiableEntry(env, title: "Soft-deleted classify")
        try softDeleteEntry(env, entryId: classifyEntryId)
        try expectNotebookEntryNotFound(classifyEntryId) {
            try env.notebooks.classifyTodoWork(
                entryId: classifyEntryId,
                classification: "warranty",
                classifiedBy: env.adminUserId
            )
        }
        #expect(try historyCount(env, entryId: classifyEntryId) == 0)

        let reviewEntryId = try createClassifiableEntry(env, title: "Soft-deleted review")
        try env.notebooks.classifyTodoWork(
            entryId: reviewEntryId,
            classification: "regular",
            classifiedBy: env.adminUserId
        )
        let reviewHistoryBeforeDelete = try historyCount(env, entryId: reviewEntryId)
        try softDeleteEntry(env, entryId: reviewEntryId)
        try expectNotebookEntryNotFound(reviewEntryId) {
            try env.notebooks.reviewClassification(
                entryId: reviewEntryId,
                reviewedBy: env.adminUserId,
                approved: false,
                newClassification: "warranty"
            )
        }
        #expect(try historyCount(env, entryId: reviewEntryId) == reviewHistoryBeforeDelete)

        let reclassifyEntryId = try createClassifiableEntry(env, title: "Soft-deleted reclassify")
        try env.notebooks.classifyTodoWork(
            entryId: reclassifyEntryId,
            classification: "regular",
            classifiedBy: env.adminUserId
        )
        let reclassifyHistoryBeforeDelete = try historyCount(env, entryId: reclassifyEntryId)
        try softDeleteEntry(env, entryId: reclassifyEntryId)
        try expectNotebookEntryNotFound(reclassifyEntryId) {
            try env.notebooks.reclassifyTodoWork(
                entryId: reclassifyEntryId,
                newClassification: "warranty",
                changedBy: env.adminUserId,
                reason: "should not leak"
            )
        }
        #expect(try historyCount(env, entryId: reclassifyEntryId) == reclassifyHistoryBeforeDelete)
    }

    private func createClassifiableEntry(
        _ env: E2ETestHelpers.TestEnvironment,
        title: String
    ) throws -> Int64 {
        let nbId = try env.notebooks.createNotebook(
            title: "Classification Regression NB \(UUID().uuidString.prefix(8))",
            notebookType: "general",
            createdBy: env.adminUserId
        )
        let sectionId = try env.notebooks.createSection(
            notebookId: nbId,
            groupId: nil,
            name: "Work"
        )
        return try env.notebooks.createBlockEntry(
            sectionId: sectionId,
            blockType: "text",
            title: title,
            content: "Regression coverage",
            createdBy: env.adminUserId
        )
    }

    private func softDeleteEntry(_ env: E2ETestHelpers.TestEnvironment, entryId: Int64) throws {
        try env.db.writer.write { dbConn in
            try dbConn.execute(
                sql: "UPDATE notebook_entries SET deleted_at = datetime('now') WHERE id = ?",
                arguments: [entryId]
            )
        }
    }

    private func historyCount(_ env: E2ETestHelpers.TestEnvironment, entryId: Int64) throws -> Int {
        try env.db.writer.read { dbConn in
            try Int.fetchOne(
                dbConn,
                sql: "SELECT COUNT(*) FROM classification_history WHERE entry_id = ?",
                arguments: [entryId]
            ) ?? 0
        }
    }

    private func expectInsufficientNotebookPermission(
        _ required: String,
        operation: () throws -> Void
    ) throws {
        do {
            try operation()
            Issue.record("Expected insufficientPermissions(\(required))")
        } catch NotebooksService.NotebooksError.insufficientPermissions(let actual) {
            #expect(actual == required)
        }
    }

    private func expectNotebookEntryNotFound(
        _ entryId: Int64,
        operation: () throws -> Void
    ) throws {
        do {
            try operation()
            Issue.record("Expected entryNotFound(\(entryId))")
        } catch NotebooksService.NotebooksError.entryNotFound(let actual) {
            #expect(actual == entryId)
        }
    }

    // MARK: - 20. Ensure Warranty Section

    @Test("Ensure warranty section creates group if missing")
    func testEnsureWarrantySection() throws {
        let env = try E2ETestHelpers.setUp()

        let nbId = try env.notebooks.createNotebook(
            title: "Warranty NB",
            notebookType: "general",
            createdBy: env.adminUserId
        )

        let groupId1 = try env.notebooks.ensureWarrantySection(notebookId: nbId)
        #expect(groupId1 > 0)

        // Calling again should return the same group
        let groupId2 = try env.notebooks.ensureWarrantySection(notebookId: nbId)
        #expect(groupId1 == groupId2)

        let hierarchy = try env.notebooks.getNotebookHierarchy(notebookId: nbId)
        #expect(hierarchy.groups.contains { $0.name == "Warranty Work" })
    }

    // MARK: - 21. Seed Default Templates is Idempotent

    @Test("Seeding default templates twice does not duplicate")
    func testSeedTemplatesIdempotent() throws {
        let env = try E2ETestHelpers.setUp()

        try env.notebooks.seedDefaultTemplates(createdBy: env.adminUserId)
        try env.notebooks.seedDefaultTemplates(createdBy: env.adminUserId)

        let templates = try env.notebooks.getTemplates()
        let defaultCount = templates.filter(\.isDefault).count
        #expect(defaultCount == 3) // Residential, Commercial, Service Call
    }

    // MARK: - 22. Delete Template (Soft Delete)

    @Test("Delete template removes it from list")
    func testDeleteTemplate() throws {
        let env = try E2ETestHelpers.setUp()
        try env.notebooks.seedDefaultTemplates(createdBy: env.adminUserId)

        let before = try env.notebooks.getTemplates()
        let target = try #require(before.first)

        try env.notebooks.deleteTemplate(templateId: target.id)

        let after = try env.notebooks.getTemplates()
        #expect(!after.contains { $0.id == target.id })
        #expect(after.count == before.count - 1)
    }

    // MARK: - 23. Create Custom Template

    @Test("Create a custom template and retrieve it")
    func testCreateCustomTemplate() throws {
        let env = try E2ETestHelpers.setUp()

        let templateData = NotebooksService.NotebookTemplateData(groups: [
            .init(name: "Custom Group", sections: [
                .init(name: "Custom Section", entries: [
                    .init(blockType: "text", title: "Note", content: "Template note", headingLevel: nil, checklistItems: nil),
                ]),
            ]),
        ])

        let tplId = try env.notebooks.createTemplate(
            name: "My Custom Template",
            description: "A test template",
            templateType: "job",
            category: "custom",
            templateData: templateData,
            createdBy: env.adminUserId
        )
        #expect(tplId > 0)

        let templates = try env.notebooks.getTemplates()
        #expect(templates.contains { $0.id == tplId && $0.name == "My Custom Template" })
    }

    // MARK: - 24. Reorder Section Groups

    @Test("Reorder section groups changes sort order")
    func testReorderSectionGroups() throws {
        let env = try E2ETestHelpers.setUp()

        let nbId = try env.notebooks.createNotebook(
            title: "Reorder NB",
            notebookType: "general",
            createdBy: env.adminUserId
        )

        let g1 = try env.notebooks.createSectionGroup(notebookId: nbId, name: "First")
        let g2 = try env.notebooks.createSectionGroup(notebookId: nbId, name: "Second")
        let g3 = try env.notebooks.createSectionGroup(notebookId: nbId, name: "Third")

        // Reverse the order
        try env.notebooks.reorderSectionGroups(notebookId: nbId, orderedIds: [g3, g2, g1])

        let hierarchy = try env.notebooks.getNotebookHierarchy(notebookId: nbId)
        #expect(hierarchy.groups[0].name == "Third")
        #expect(hierarchy.groups[1].name == "Second")
        #expect(hierarchy.groups[2].name == "First")
    }

    // MARK: - 25. Reorder Block Entries

    @Test("Reorder block entries within a section")
    func testReorderBlockEntries() throws {
        let env = try E2ETestHelpers.setUp()

        let nbId = try env.notebooks.createNotebook(
            title: "Reorder Entries NB",
            notebookType: "general",
            createdBy: env.adminUserId
        )

        let sectionId = try env.notebooks.createSection(
            notebookId: nbId, groupId: nil, name: "Reorderable"
        )

        let e1 = try env.notebooks.createBlockEntry(
            sectionId: sectionId, blockType: "text",
            title: "A", createdBy: env.adminUserId, sortOrder: 0
        )
        let e2 = try env.notebooks.createBlockEntry(
            sectionId: sectionId, blockType: "text",
            title: "B", createdBy: env.adminUserId, sortOrder: 1
        )
        let e3 = try env.notebooks.createBlockEntry(
            sectionId: sectionId, blockType: "text",
            title: "C", createdBy: env.adminUserId, sortOrder: 2
        )

        // Reorder: C, A, B
        try env.notebooks.reorderBlockEntries(sectionId: sectionId, orderedIds: [e3, e1, e2])

        let hierarchy = try env.notebooks.getNotebookHierarchy(notebookId: nbId)
        let entries = hierarchy.ungroupedSections.first?.entries ?? []
        #expect(entries.count == 3)
        #expect(entries[0].title == "C")
        #expect(entries[1].title == "A")
        #expect(entries[2].title == "B")
    }

    // MARK: - 26. Move Section Between Groups

    @Test("Move section to a different group")
    func testMoveSection() throws {
        let env = try E2ETestHelpers.setUp()

        let nbId = try env.notebooks.createNotebook(
            title: "Move NB",
            notebookType: "general",
            createdBy: env.adminUserId
        )

        let g1 = try env.notebooks.createSectionGroup(notebookId: nbId, name: "Group A")
        let g2 = try env.notebooks.createSectionGroup(notebookId: nbId, name: "Group B")

        // Create section in group A
        let sId = try env.notebooks.createSection(notebookId: nbId, groupId: g1, name: "Movable")

        // Verify it's in group A
        var hierarchy = try env.notebooks.getNotebookHierarchy(notebookId: nbId)
        let groupA = hierarchy.groups.first { $0.id == g1 }
        #expect(groupA?.sections.count == 1)

        // Move to group B
        try env.notebooks.moveSection(sectionId: sId, toGroupId: g2, sortOrder: 0)

        hierarchy = try env.notebooks.getNotebookHierarchy(notebookId: nbId)
        let groupAAfter = hierarchy.groups.first { $0.id == g1 }
        let groupBAfter = hierarchy.groups.first { $0.id == g2 }
        #expect(groupAAfter?.sections.count == 0)
        #expect(groupBAfter?.sections.count == 1)
        #expect(groupBAfter?.sections.first?.name == "Movable")
    }

    // MARK: - 27. Empty Notebook Hierarchy

    @Test("Empty notebook returns empty hierarchy")
    func testEmptyNotebookHierarchy() throws {
        let env = try E2ETestHelpers.setUp()

        let nbId = try env.notebooks.createNotebook(
            title: "Empty NB",
            notebookType: "general",
            createdBy: env.adminUserId
        )

        let hierarchy = try env.notebooks.getNotebookHierarchy(notebookId: nbId)
        #expect(hierarchy.groups.isEmpty)
        #expect(hierarchy.ungroupedSections.isEmpty)
    }

    // MARK: - 28. listTemplates Convenience

    @Test("listTemplates returns only template-type notebooks")
    func testListTemplatesConvenience() throws {
        let env = try E2ETestHelpers.setUp()

        _ = try env.notebooks.createNotebook(
            title: "Regular NB",
            notebookType: "general",
            createdBy: env.adminUserId
        )
        _ = try env.notebooks.createNotebook(
            title: "Template NB",
            notebookType: "template",
            createdBy: env.adminUserId
        )

        let templates = try env.notebooks.listTemplates()
        #expect(templates.allSatisfy { $0.notebookType == "template" })
        #expect(templates.contains { $0.title == "Template NB" })
        #expect(!templates.contains { $0.title == "Regular NB" })
    }

    // MARK: - 30. startWarrantyTimer

    @Test("startWarrantyTimer sets warranty_timer_start and warranty_timer_end on an entry")
    func testStartWarrantyTimer() throws {
        let env = try E2ETestHelpers.setUp()

        let nbId = try env.notebooks.createNotebook(
            title: "Warranty Test NB",
            notebookType: "general",
            createdBy: env.adminUserId
        )
        let groupId = try env.notebooks.createSectionGroup(notebookId: nbId, name: "Group A")
        let sectionId = try env.notebooks.createSection(notebookId: nbId, groupId: groupId, name: "Sec A")
        let entryId = try env.notebooks.createBlockEntry(
            sectionId: sectionId,
            blockType: "text",
            content: "Warranty item",
            createdBy: env.adminUserId
        )

        // startWarrantyTimer should not throw
        try env.notebooks.startWarrantyTimer(entryId: entryId, warrantyDurationDays: 365)

        // Verify via hierarchy — warranty_timer_end should be non-nil
        let hierarchy = try env.notebooks.getNotebookHierarchy(notebookId: nbId)
        let allEntries = hierarchy.groups.flatMap { $0.sections }.flatMap { $0.entries }
        let entry = try #require(allEntries.first { $0.id == entryId })
        #expect(entry.warrantyTimerEnd != nil)
    }

    // MARK: - 31. getTodosNeedingReview

    @Test("getTodosNeedingReview returns classified-but-unreviewed entries for a job")
    func testGetTodosNeedingReview() throws {
        let env = try E2ETestHelpers.setUp()

        let jobId = try E2ETestHelpers.seedJob(env)
        let nbId = try env.notebooks.createNotebook(
            title: "Job NB",
            notebookType: "job",
            jobId: jobId,
            createdBy: env.adminUserId
        )
        let groupId = try env.notebooks.createSectionGroup(notebookId: nbId, name: "Work")
        let sectionId = try env.notebooks.createSection(notebookId: nbId, groupId: groupId, name: "Tasks")

        let entryId = try env.notebooks.createBlockEntry(
            sectionId: sectionId,
            blockType: "todo",
            content: "Fix breaker",
            createdBy: env.adminUserId
        )

        // notebook_id is a denormalized column — set it so getTodosNeedingReview can JOIN
        try env.db.writer.write { db in
            try db.execute(
                sql: "UPDATE notebook_entries SET notebook_id = ? WHERE id = ?",
                arguments: [nbId, entryId]
            )
        }

        // Before classification, nothing needs review
        let beforeClassify = try env.notebooks.getTodosNeedingReview(jobId: jobId)
        #expect(beforeClassify.isEmpty)

        // Classify the entry — now it needs review
        try env.notebooks.classifyTodoWork(
            entryId: entryId,
            classification: "warranty",
            classifiedBy: env.adminUserId
        )

        let needsReview = try env.notebooks.getTodosNeedingReview(jobId: jobId)
        #expect(needsReview.contains { $0.id == entryId })

        // After review, it should drop out
        try env.notebooks.reviewClassification(
            entryId: entryId,
            reviewedBy: env.adminUserId,
            approved: true,
            newClassification: nil
        )
        let afterReview = try env.notebooks.getTodosNeedingReview(jobId: jobId)
        #expect(!afterReview.contains { $0.id == entryId })
    }

    // MARK: - 24. Reorder Sections

    @Test("reorderSections updates sort_order within a group")
    func testReorderSections() throws {
        let env = try E2ETestHelpers.setUp()

        let nbId = try env.notebooks.createNotebook(
            title: "Sort Test NB",
            notebookType: "general",
            createdBy: env.adminUserId
        )

        // Create 3 sections in default order (s1=0, s2=1, s3=2)
        let s1 = try env.notebooks.createSection(notebookId: nbId, groupId: nil, name: "Alpha")
        let s2 = try env.notebooks.createSection(notebookId: nbId, groupId: nil, name: "Beta")
        let s3 = try env.notebooks.createSection(notebookId: nbId, groupId: nil, name: "Gamma")

        // Reverse the order: Gamma, Beta, Alpha
        try env.notebooks.reorderSections(groupId: nil, orderedIds: [s3, s2, s1])

        // Hierarchy returns sections ordered by sort_order ASC
        let hierarchy = try env.notebooks.getNotebookHierarchy(notebookId: nbId)
        let names = hierarchy.ungroupedSections.map { $0.name }
        #expect(names == ["Gamma", "Beta", "Alpha"])

        // Verify sort_order values are contiguous indices (0, 1, 2)
        let sortOrders = hierarchy.ungroupedSections.map { $0.sortOrder }
        #expect(sortOrders == [0, 1, 2])
    }

    // MARK: - 25. Apply Page Template

    @Test("applyPageTemplate creates block entries in target section")
    func testApplyPageTemplate() throws {
        let env = try E2ETestHelpers.setUp()

        // Build a minimal page template with 2 entries
        let templateData = NotebooksService.NotebookTemplateData(groups: [
            .init(name: "Page Group", sections: [
                .init(name: "Checklist", entries: [
                    .init(blockType: "text", title: "Step 1", content: "Do the first thing", headingLevel: nil, checklistItems: nil),
                    .init(blockType: "text", title: "Step 2", content: "Do the second thing", headingLevel: nil, checklistItems: nil)
                ])
            ])
        ])

        let templateId = try env.notebooks.createTemplate(
            name: "Test Page Template",
            description: nil,
            templateType: "page",
            category: nil,
            templateData: templateData,
            createdBy: env.adminUserId
        )
        #expect(templateId > 0)

        // Create a notebook and section to apply the template into
        let nbId = try env.notebooks.createNotebook(
            title: "Page Template NB",
            notebookType: "general",
            createdBy: env.adminUserId
        )
        let sectionId = try env.notebooks.createSection(
            notebookId: nbId,
            groupId: nil,
            name: "Target Section"
        )

        // Apply the page template
        try env.notebooks.applyPageTemplate(
            templateId: templateId,
            sectionId: sectionId,
            createdBy: env.adminUserId
        )

        // Verify 2 block entries were created in the section
        let hierarchy = try env.notebooks.getNotebookHierarchy(notebookId: nbId)
        let section = try #require(hierarchy.ungroupedSections.first { $0.id == sectionId })
        #expect(section.entries.count == 2)
        #expect(section.entries.contains { $0.title == "Step 1" })
        #expect(section.entries.contains { $0.title == "Step 2" })
    }

    @Test("applyPageTemplate is no-op for non-existent template")
    func testApplyPageTemplateNotFound() throws {
        let env = try E2ETestHelpers.setUp()

        let nbId = try env.notebooks.createNotebook(
            title: "NB",
            notebookType: "general",
            createdBy: env.adminUserId
        )
        let sectionId = try env.notebooks.createSection(
            notebookId: nbId,
            groupId: nil,
            name: "Empty Section"
        )

        // Applying a non-existent template should be a no-op (not throw)
        try env.notebooks.applyPageTemplate(
            templateId: 99999,
            sectionId: sectionId,
            createdBy: env.adminUserId
        )

        let hierarchy = try env.notebooks.getNotebookHierarchy(notebookId: nbId)
        let section = try #require(hierarchy.ungroupedSections.first { $0.id == sectionId })
        #expect(section.entries.isEmpty)
    }

    // MARK: - 26. Block Conflict Detection & Resolution

    @Test("detectBlockConflicts returns empty on fresh database")
    func testDetectBlockConflictsEmpty() throws {
        let env = try E2ETestHelpers.setUp()

        let nbId = try env.notebooks.createNotebook(
            title: "Conflict NB",
            notebookType: "general",
            createdBy: env.adminUserId
        )

        let conflicts = try env.notebooks.detectBlockConflicts(notebookId: nbId)
        #expect(conflicts.isEmpty)
    }

    @Test("detectBlockConflicts returns unreviewed conflicts for notebook entries")
    func testDetectBlockConflictsWithData() throws {
        let env = try E2ETestHelpers.setUp()

        let nbId = try env.notebooks.createNotebook(
            title: "Conflicted NB",
            notebookType: "general",
            createdBy: env.adminUserId
        )
        let sectionId = try env.notebooks.createSection(
            notebookId: nbId, groupId: nil, name: "Sec"
        )
        let entryId = try env.notebooks.createBlockEntry(
            sectionId: sectionId,
            blockType: "text",
            title: "Contested Entry",
            content: "local content",
            createdBy: env.adminUserId
        )

        // detectBlockConflicts filters by ne.notebook_id — set it since createBlockEntry leaves it NULL
        try env.db.writer.write { dbConn in
            try dbConn.execute(
                sql: "UPDATE notebook_entries SET notebook_id = ? WHERE id = ?",
                arguments: [nbId, entryId]
            )
        }

        // Insert a fake conflict into _conflict_log directly
        try env.db.writer.write { dbConn in
            try dbConn.execute(sql: """
                INSERT INTO _conflict_log
                    (table_name, record_id, field_name, local_value, remote_value,
                     winner, local_device, remote_device, local_ts, remote_ts,
                     resolved_at, reviewed)
                VALUES ('notebook_entries', ?, 'content',
                        'local content', 'remote content',
                        'local', 'dev-A', 'dev-B',
                        '2026-04-01T10:00:00Z', '2026-04-01T11:00:00Z',
                        datetime('now'), 0)
                """, arguments: [String(entryId)])
        }

        let conflicts = try env.notebooks.detectBlockConflicts(notebookId: nbId)
        #expect(conflicts.count == 1)
        #expect(conflicts[0].entryId == entryId)
        #expect(conflicts[0].fieldName == "content")
        #expect(conflicts[0].localValue == "local content")
        #expect(conflicts[0].remoteValue == "remote content")
        #expect(conflicts[0].winner == "local")
    }

    @Test("resolveBlockConflict marks conflict reviewed when keeping winner")
    func testResolveBlockConflictKeepWinner() throws {
        let env = try E2ETestHelpers.setUp()

        let nbId = try env.notebooks.createNotebook(
            title: "Resolve NB",
            notebookType: "general",
            createdBy: env.adminUserId
        )
        let sectionId = try env.notebooks.createSection(
            notebookId: nbId, groupId: nil, name: "Sec"
        )
        let entryId = try env.notebooks.createBlockEntry(
            sectionId: sectionId,
            blockType: "text",
            content: "local content",
            createdBy: env.adminUserId
        )
        // detectBlockConflicts filters by ne.notebook_id — set it since createBlockEntry leaves it NULL
        try env.db.writer.write { dbConn in
            try dbConn.execute(
                sql: "UPDATE notebook_entries SET notebook_id = ? WHERE id = ?",
                arguments: [nbId, entryId]
            )
        }

        // Insert conflict where "local" already won
        var conflictLogId: Int64 = 0
        try env.db.writer.write { dbConn in
            try dbConn.execute(sql: """
                INSERT INTO _conflict_log
                    (table_name, record_id, field_name, local_value, remote_value,
                     winner, local_device, remote_device, local_ts, remote_ts,
                     resolved_at, reviewed)
                VALUES ('notebook_entries', ?, 'content',
                        'local content', 'remote content',
                        'local', 'dev-A', 'dev-B',
                        '2026-04-01T10:00:00Z', '2026-04-01T11:00:00Z',
                        datetime('now'), 0)
                """, arguments: [String(entryId)])
            conflictLogId = dbConn.lastInsertedRowID
        }

        // Resolve keeping "local" (same as winner → just marks reviewed)
        try env.notebooks.resolveBlockConflict(conflictLogId: conflictLogId, keepVersion: "local")

        // Conflict should no longer appear in detectBlockConflicts (reviewed=1)
        let remaining = try env.notebooks.detectBlockConflicts(notebookId: nbId)
        #expect(remaining.isEmpty)
    }

    @Test("resolveBlockConflict overrides LWW winner and applies remote value")
    func testResolveBlockConflictOverrideWinner() throws {
        let env = try E2ETestHelpers.setUp()

        let nbId = try env.notebooks.createNotebook(
            title: "Override NB",
            notebookType: "general",
            createdBy: env.adminUserId
        )
        let sectionId = try env.notebooks.createSection(
            notebookId: nbId, groupId: nil, name: "Sec"
        )
        let entryId = try env.notebooks.createBlockEntry(
            sectionId: sectionId,
            blockType: "text",
            content: "local content",
            createdBy: env.adminUserId
        )
        // detectBlockConflicts filters by ne.notebook_id — set it since createBlockEntry leaves it NULL
        try env.db.writer.write { dbConn in
            try dbConn.execute(
                sql: "UPDATE notebook_entries SET notebook_id = ? WHERE id = ?",
                arguments: [nbId, entryId]
            )
        }

        // LWW chose "local" — user wants to keep "remote" instead
        var conflictLogId: Int64 = 0
        try env.db.writer.write { dbConn in
            try dbConn.execute(sql: """
                INSERT INTO _conflict_log
                    (table_name, record_id, field_name, local_value, remote_value,
                     winner, local_device, remote_device, local_ts, remote_ts,
                     resolved_at, reviewed)
                VALUES ('notebook_entries', ?, 'content',
                        'local content', 'remote preferred content',
                        'local', 'dev-A', 'dev-B',
                        '2026-04-01T10:00:00Z', '2026-04-01T11:00:00Z',
                        datetime('now'), 0)
                """, arguments: [String(entryId)])
            conflictLogId = dbConn.lastInsertedRowID
        }

        try env.notebooks.resolveBlockConflict(conflictLogId: conflictLogId, keepVersion: "remote")

        // Conflict marked reviewed
        let remaining = try env.notebooks.detectBlockConflicts(notebookId: nbId)
        #expect(remaining.isEmpty)

        // Entry content should now reflect the remote value
        let hierarchy = try env.notebooks.getNotebookHierarchy(notebookId: nbId)
        let entry = hierarchy.ungroupedSections.first?.entries.first
        #expect(entry?.content == "remote preferred content")
    }

    @Test("resolveAllBlockConflicts resolves all unreviewed conflicts in bulk")
    func testResolveAllBlockConflicts() throws {
        let env = try E2ETestHelpers.setUp()

        let nbId = try env.notebooks.createNotebook(
            title: "Bulk Resolve NB",
            notebookType: "general",
            createdBy: env.adminUserId
        )
        let sectionId = try env.notebooks.createSection(
            notebookId: nbId, groupId: nil, name: "Sec"
        )

        // Create 3 entries each with an unreviewed conflict
        for i in 1...3 {
            let entryId = try env.notebooks.createBlockEntry(
                sectionId: sectionId,
                blockType: "text",
                content: "entry \(i)",
                createdBy: env.adminUserId
            )
            // detectBlockConflicts filters by ne.notebook_id — set it since createBlockEntry leaves it NULL
            try env.db.writer.write { dbConn in
                try dbConn.execute(
                    sql: "UPDATE notebook_entries SET notebook_id = ? WHERE id = ?",
                    arguments: [nbId, entryId]
                )
                try dbConn.execute(sql: """
                    INSERT INTO _conflict_log
                        (table_name, record_id, field_name, local_value, remote_value,
                         winner, local_device, remote_device, local_ts, remote_ts,
                         resolved_at, reviewed)
                    VALUES ('notebook_entries', ?, 'content',
                            'entry \(i)', 'remote \(i)',
                            'local', 'dev-A', 'dev-B',
                            '2026-04-01T10:00:00Z', '2026-04-01T11:00:00Z',
                            datetime('now'), 0)
                    """, arguments: [String(entryId)])
            }
        }

        // Verify 3 conflicts detected before resolution
        let before = try env.notebooks.detectBlockConflicts(notebookId: nbId)
        #expect(before.count == 3)

        // Bulk resolve, keeping local versions
        try env.notebooks.resolveAllBlockConflicts(notebookId: nbId, keepVersion: "local")

        // All should be marked reviewed
        let after = try env.notebooks.detectBlockConflicts(notebookId: nbId)
        #expect(after.isEmpty)
    }

    // MARK: - createBlockEntry notebook_id regression

    @Test("createBlockEntry populates notebook_id so detectBlockConflicts can find the entry")
    func testCreateBlockEntryPopulatesNotebookId() throws {
        let env = try E2ETestHelpers.setUp()
        let nbId = try env.notebooks.createNotebook(
            title: "Block Notebook",
            notebookType: "general",
            jobId: nil,
            createdBy: env.adminUserId
        )
        let sectionId = try env.notebooks.createSection(
            notebookId: nbId, groupId: nil, name: "Section A"
        )
        let entryId = try env.notebooks.createBlockEntry(
            sectionId: sectionId,
            blockType: "text",
            title: "Block title",
            createdBy: env.adminUserId
        )

        // notebook_id must be populated on the inserted row
        let notebookId = try env.db.writer.read { dbConn in
            try Int64.fetchOne(dbConn, sql: "SELECT notebook_id FROM notebook_entries WHERE id = ?",
                               arguments: [entryId])
        }
        #expect(notebookId == nbId)
    }

    @Test("createBlockEntry preserves palette block metadata")
    func testCreateBlockEntryPreservesPaletteBlockMetadata() throws {
        let env = try E2ETestHelpers.setUp()
        let nbId = try env.notebooks.createNotebook(
            title: "Palette Notebook",
            notebookType: "general",
            jobId: nil,
            createdBy: env.adminUserId
        )
        let sectionId = try env.notebooks.createSection(
            notebookId: nbId, groupId: nil, name: "Section A"
        )
        let panelJson = "{\"panelType\":\"Load Center\",\"circuits\":[{\"position\":1,\"label\":\"Kitchen\"}]}"
        let tableNotes = "Part, Qty\nEMT, 12"

        let headingId = try env.notebooks.createBlockEntry(
            sectionId: sectionId,
            blockType: "heading",
            title: "Panel Notes",
            headingLevel: 2,
            createdBy: env.adminUserId
        )
        let photoId = try env.notebooks.createBlockEntry(
            sectionId: sectionId,
            blockType: "photo",
            title: "Panel photo",
            photoPath: "file:///tmp/panel.jpg",
            createdBy: env.adminUserId
        )
        let partId = try env.notebooks.createBlockEntry(
            sectionId: sectionId,
            blockType: "part_reference",
            title: "Breaker",
            referenceType: "part",
            referenceId: 42,
            createdBy: env.adminUserId
        )
        let panelId = try env.notebooks.createBlockEntry(
            sectionId: sectionId,
            blockType: "panel_schedule",
            title: "Main Panel",
            blockData: panelJson,
            createdBy: env.adminUserId
        )
        let tableId = try env.notebooks.createBlockEntry(
            sectionId: sectionId,
            blockType: "table",
            title: "Materials",
            content: tableNotes,
            createdBy: env.adminUserId
        )
        let todoId = try env.notebooks.createBlockEntry(
            sectionId: sectionId,
            blockType: "todo",
            title: "Return for warranty check",
            taskStatus: "in_progress",
            taskDueDate: "2026-05-20",
            taskAssignedTo: env.adminUserId,
            taskPartsNote: "Bring replacement GFCI",
            workClassification: "warranty",
            warrantyTimerEnd: "2026-06-20T00:00:00Z",
            isQuestion: true,
            createdBy: env.adminUserId
        )

        let hierarchy = try env.notebooks.getNotebookHierarchy(notebookId: nbId)
        let entries = hierarchy.ungroupedSections.flatMap(\.entries)
        let byId = Dictionary(uniqueKeysWithValues: entries.map { ($0.id, $0) })

        #expect(byId[headingId]?.blockType == "heading")
        #expect(byId[headingId]?.headingLevel == 2)
        #expect(byId[photoId]?.photoPath == "file:///tmp/panel.jpg")
        #expect(byId[partId]?.referenceType == "part")
        #expect(byId[partId]?.referenceId == 42)
        #expect(byId[panelId]?.blockData == panelJson)
        #expect(byId[tableId]?.content == tableNotes)
        #expect(byId[todoId]?.taskStatus == "in_progress")
        #expect(byId[todoId]?.taskDueDate == "2026-05-20")
        #expect(byId[todoId]?.taskAssignedTo == env.adminUserId)
        #expect(byId[todoId]?.taskPartsNote == "Bring replacement GFCI")
        #expect(byId[todoId]?.workClassification == "warranty")
        #expect(byId[todoId]?.warrantyTimerEnd == "2026-06-20T00:00:00Z")
        #expect(byId[todoId]?.isQuestion == true)

        let detail = try env.notebooks.getNotebookDetail(id: nbId)
        let detailTodo = try #require(detail.entries.first { $0.id == todoId })
        #expect(detailTodo.taskStatus == "in_progress")
        #expect(detailTodo.taskPartsNote == "Bring replacement GFCI")
    }

    @Test("listNotebooks hides job name for soft-deleted job")
    func testListNotebooksHidesDeletedJobName() throws {
        let env = try E2ETestHelpers.setUp()
        let jobId = try E2ETestHelpers.seedJob(env)
        _ = try env.notebooks.createNotebook(title: "Job NB", notebookType: "job", jobId: jobId, createdBy: env.adminUserId)
        try env.db.writer.write { db in
            try db.execute(sql: "UPDATE jobs SET deleted_at = datetime('now') WHERE id = ?", arguments: [jobId])
        }
        let notebooks = try env.notebooks.listNotebooks()
        #expect(notebooks.isEmpty == false)
        // jobName is nil when the job is soft-deleted (LEFT JOIN returns NULL)
        #expect(notebooks.first?.jobName == nil)
    }

    // MARK: - Write-path soft-delete guard regression tests

    @Test("completeEntry is a no-op on soft-deleted notebook entry")
    func testCompleteEntry_noOpOnSoftDeletedEntry() throws {
        let env = try E2ETestHelpers.setUp()
        let nbId = try env.notebooks.createNotebook(title: "NB", notebookType: "general", jobId: nil, createdBy: env.adminUserId)
        let sectionId = try env.notebooks.createSection(notebookId: nbId, groupId: nil, name: "Sec")
        let entryId = try env.notebooks.createBlockEntry(sectionId: sectionId, blockType: "text", title: "Task", createdBy: env.adminUserId)
        try env.db.writer.write { db in
            try db.execute(sql: "UPDATE notebook_entries SET deleted_at = datetime('now'), is_deleted = 1 WHERE id = ?", arguments: [entryId])
        }
        try env.notebooks.completeEntry(entryId: entryId)
        let status = try env.db.writer.read { db in
            try String.fetchOne(db, sql: "SELECT task_status FROM notebook_entries WHERE id = ?", arguments: [entryId])
        }
        #expect(status != "complete")
    }

    @Test("updateBlockEntry is a no-op on soft-deleted notebook entry")
    func testUpdateBlockEntry_noOpOnSoftDeletedEntry() throws {
        let env = try E2ETestHelpers.setUp()
        let nbId = try env.notebooks.createNotebook(title: "NB", notebookType: "general", jobId: nil, createdBy: env.adminUserId)
        let sectionId = try env.notebooks.createSection(notebookId: nbId, groupId: nil, name: "Sec")
        let entryId = try env.notebooks.createBlockEntry(sectionId: sectionId, blockType: "text", title: "Original", createdBy: env.adminUserId)
        try env.db.writer.write { db in
            try db.execute(sql: "UPDATE notebook_entries SET deleted_at = datetime('now'), is_deleted = 1 WHERE id = ?", arguments: [entryId])
        }
        try env.notebooks.updateBlockEntry(entryId: entryId, content: "MUTATED", blockData: nil, updatedBy: env.adminUserId)
        let content = try env.db.writer.read { db in
            try String.fetchOne(db, sql: "SELECT content FROM notebook_entries WHERE id = ?", arguments: [entryId])
        }
        #expect(content != "MUTATED")
    }

    @Test("updateSection is a no-op on soft-deleted section")
    func testUpdateSection_noOpOnSoftDeletedSection() throws {
        let env = try E2ETestHelpers.setUp()
        let nbId = try env.notebooks.createNotebook(title: "NB", notebookType: "general", jobId: nil, createdBy: env.adminUserId)
        let sectionId = try env.notebooks.createSection(notebookId: nbId, groupId: nil, name: "Original Name")
        try env.notebooks.deleteSection(sectionId: sectionId)
        try env.notebooks.updateSection(sectionId: sectionId, name: "MUTATED NAME")
        let name = try env.db.writer.read { db in
            try String.fetchOne(db, sql: "SELECT name FROM notebook_sections WHERE id = ?", arguments: [sectionId])
        }
        #expect(name != "MUTATED NAME")
    }

    @Test("createNotebook throws requiredFieldEmpty when title is blank")
    func testCreateNotebook_throwsForBlankTitle() throws {
        let env = try E2ETestHelpers.setUp()
        var threw = false
        do {
            _ = try env.notebooks.createNotebook(title: "   ", notebookType: "general", jobId: nil, createdBy: env.adminUserId)
        } catch NotebooksService.NotebooksError.requiredFieldEmpty {
            threw = true
        } catch {}
        #expect(threw, "createNotebook must throw requiredFieldEmpty when title is whitespace-only")
    }

    @Test("addNotebookEntry throws requiredFieldEmpty when title is blank")
    func testAddNotebookEntry_throwsForBlankTitle() throws {
        let env = try E2ETestHelpers.setUp()
        let nbId = try env.notebooks.createNotebook(title: "Test Notebook", notebookType: "general", jobId: nil, createdBy: env.adminUserId)
        var threw = false
        do {
            _ = try env.notebooks.addNotebookEntry(notebookId: nbId, title: "", createdBy: env.adminUserId)
        } catch NotebooksService.NotebooksError.requiredFieldEmpty {
            threw = true
        } catch {}
        #expect(threw, "addNotebookEntry must throw requiredFieldEmpty when title is empty")
    }

    @Test("createSectionGroup throws requiredFieldEmpty when name is blank")
    func testCreateSectionGroup_throwsForBlankName() throws {
        let env = try E2ETestHelpers.setUp()
        let nbId = try env.notebooks.createNotebook(title: "Test Notebook", notebookType: "general", jobId: nil, createdBy: env.adminUserId)
        var threw = false
        do {
            _ = try env.notebooks.createSectionGroup(notebookId: nbId, name: "   ")
        } catch NotebooksService.NotebooksError.requiredFieldEmpty {
            threw = true
        } catch {}
        #expect(threw, "createSectionGroup must throw requiredFieldEmpty when name is whitespace-only")
    }

    @Test("createSection throws requiredFieldEmpty when name is blank")
    func testCreateSection_throwsForBlankName() throws {
        let env = try E2ETestHelpers.setUp()
        let nbId = try env.notebooks.createNotebook(title: "Test Notebook", notebookType: "general", jobId: nil, createdBy: env.adminUserId)
        var threw = false
        do {
            _ = try env.notebooks.createSection(notebookId: nbId, groupId: nil, name: "")
        } catch NotebooksService.NotebooksError.requiredFieldEmpty {
            threw = true
        } catch {}
        #expect(threw, "createSection must throw requiredFieldEmpty when name is empty")
    }

    @Test("startWarrantyTimer throws invalidDuration when duration is zero")
    func testStartWarrantyTimer_throwsForZeroDuration() throws {
        let env = try E2ETestHelpers.setUp()
        let nbId = try env.notebooks.createNotebook(title: "WB", notebookType: "general", jobId: nil, createdBy: env.adminUserId)
        let entryId = try env.notebooks.addNotebookEntry(notebookId: nbId, title: "Task", createdBy: env.adminUserId)
        var threw = false
        do {
            try env.notebooks.startWarrantyTimer(entryId: entryId, warrantyDurationDays: 0)
        } catch NotebooksService.NotebooksError.invalidDuration {
            threw = true
        } catch {}
        #expect(threw, "startWarrantyTimer must throw invalidDuration when warrantyDurationDays is 0")
    }

    @Test("startWarrantyTimer throws invalidDuration when duration is negative")
    func testStartWarrantyTimer_throwsForNegativeDuration() throws {
        let env = try E2ETestHelpers.setUp()
        let nbId = try env.notebooks.createNotebook(title: "WB2", notebookType: "general", jobId: nil, createdBy: env.adminUserId)
        let entryId = try env.notebooks.addNotebookEntry(notebookId: nbId, title: "Task2", createdBy: env.adminUserId)
        var threw = false
        do {
            try env.notebooks.startWarrantyTimer(entryId: entryId, warrantyDurationDays: -5)
        } catch NotebooksService.NotebooksError.invalidDuration {
            threw = true
        } catch {}
        #expect(threw, "startWarrantyTimer must throw invalidDuration when warrantyDurationDays is negative")
    }

    @Test("updateSectionGroup throws requiredFieldEmpty when name is blank")
    func testUpdateSectionGroup_throwsForBlankName() throws {
        let env = try E2ETestHelpers.setUp()
        let nbId = try env.notebooks.createNotebook(title: "NB", notebookType: "general", createdBy: env.adminUserId)
        let groupId = try env.notebooks.createSectionGroup(notebookId: nbId, name: "Group A")
        var threw = false
        do {
            try env.notebooks.updateSectionGroup(groupId: groupId, name: "   ")
        } catch NotebooksService.NotebooksError.requiredFieldEmpty {
            threw = true
        } catch {}
        #expect(threw, "updateSectionGroup must throw requiredFieldEmpty when name is whitespace-only")
    }

    @Test("updateSection throws requiredFieldEmpty when name is blank")
    func testUpdateSection_throwsForBlankName() throws {
        let env = try E2ETestHelpers.setUp()
        let nbId = try env.notebooks.createNotebook(title: "NB2", notebookType: "general", createdBy: env.adminUserId)
        let sectionId = try env.notebooks.createSection(notebookId: nbId, groupId: nil, name: "Section A")
        var threw = false
        do {
            try env.notebooks.updateSection(sectionId: sectionId, name: "")
        } catch NotebooksService.NotebooksError.requiredFieldEmpty {
            threw = true
        } catch {}
        #expect(threw, "updateSection must throw requiredFieldEmpty when name is empty")
    }

    @Test("createTemplate throws requiredFieldEmpty when name is blank")
    func testCreateTemplate_throwsForBlankName() throws {
        let env = try E2ETestHelpers.setUp()
        var threw = false
        let emptyTemplate = NotebooksService.NotebookTemplateData(groups: [])
        do {
            _ = try env.notebooks.createTemplate(
                name: "   ",
                description: nil,
                templateType: "job",
                category: nil,
                templateData: emptyTemplate,
                createdBy: env.adminUserId
            )
        } catch NotebooksService.NotebooksError.requiredFieldEmpty {
            threw = true
        } catch {}
        #expect(threw, "createTemplate must throw requiredFieldEmpty when name is whitespace-only")
    }

    // MARK: - Atomicity tests

    @Test("applyJobTemplate places entries under correct group sections")
    func testApplyJobTemplateGroupSectionEntryMapping() throws {
        let env = try E2ETestHelpers.setUp()

        let templateData = NotebooksService.NotebookTemplateData(groups: [
            .init(name: "Group A", sections: [
                .init(name: "Section A1", entries: [
                    .init(blockType: "text", title: "Entry A1-1", content: nil, headingLevel: nil, checklistItems: nil)
                ])
            ]),
            .init(name: "Group B", sections: [
                .init(name: "Section B1", entries: [
                    .init(blockType: "text", title: "Entry B1-1", content: nil, headingLevel: nil, checklistItems: nil),
                    .init(blockType: "text", title: "Entry B1-2", content: nil, headingLevel: nil, checklistItems: nil)
                ])
            ])
        ])

        let templateId = try env.notebooks.createTemplate(
            name: "Multi-Group Template",
            description: nil, templateType: "job", category: nil,
            templateData: templateData, createdBy: env.adminUserId
        )

        let nbId = try env.notebooks.createNotebook(
            title: "Atomic NB", notebookType: "job", createdBy: env.adminUserId
        )
        try env.notebooks.applyJobTemplate(templateId: templateId, notebookId: nbId, createdBy: env.adminUserId)

        let hierarchy = try env.notebooks.getNotebookHierarchy(notebookId: nbId)
        #expect(hierarchy.groups.count == 2)

        let groupA = try #require(hierarchy.groups.first { $0.name == "Group A" })
        #expect(groupA.sections.count == 1)
        #expect(groupA.sections.first?.entries.count == 1)
        #expect(groupA.sections.first?.entries.first?.title == "Entry A1-1")

        let groupB = try #require(hierarchy.groups.first { $0.name == "Group B" })
        #expect(groupB.sections.count == 1)
        #expect(groupB.sections.first?.entries.count == 2)
    }

    @Test("applyPageTemplate preserves checklist_items JSON")
    func testApplyPageTemplateChecklistItems() throws {
        let env = try E2ETestHelpers.setUp()

        let templateData = NotebooksService.NotebookTemplateData(groups: [
            .init(name: "G", sections: [
                .init(name: "S", entries: [
                    .init(blockType: "checklist", title: "Checklist Entry", content: nil,
                          headingLevel: nil, checklistItems: [["text": "item1", "done": "false"], ["text": "item2", "done": "false"]])
                ])
            ])
        ])

        let templateId = try env.notebooks.createTemplate(
            name: "Checklist Template", description: nil, templateType: "page",
            category: nil, templateData: templateData, createdBy: env.adminUserId
        )

        let nbId = try env.notebooks.createNotebook(
            title: "Checklist NB", notebookType: "general", createdBy: env.adminUserId
        )
        let sectionId = try env.notebooks.createSection(notebookId: nbId, groupId: nil, name: "Test Section")
        try env.notebooks.applyPageTemplate(templateId: templateId, sectionId: sectionId, createdBy: env.adminUserId)

        let hierarchy = try env.notebooks.getNotebookHierarchy(notebookId: nbId)
        let section = try #require(hierarchy.ungroupedSections.first { $0.id == sectionId })
        #expect(section.entries.count == 1)
        let entry = try #require(section.entries.first)
        #expect(entry.blockType == "checklist")
        #expect(entry.checklistItems != nil, "checklist_items must be preserved through applyPageTemplate")
    }

    @Test("getNotebookHierarchy with groups sections and entries")
    func testNotebookHierarchyFullTree() throws {
        let env = try E2ETestHelpers.setUp()

        let nbId = try env.notebooks.createNotebook(
            title: "Full Tree NB", notebookType: "general", createdBy: env.adminUserId
        )
        let groupId = try env.notebooks.createSectionGroup(notebookId: nbId, name: "My Group")
        let sectionId = try env.notebooks.createSection(notebookId: nbId, groupId: groupId, name: "My Section")
        _ = try env.notebooks.createBlockEntry(
            sectionId: sectionId, blockType: "text", title: "Block 1",
            content: "Hello", createdBy: env.adminUserId
        )
        _ = try env.notebooks.createBlockEntry(
            sectionId: sectionId, blockType: "text", title: "Block 2",
            content: "World", createdBy: env.adminUserId
        )

        let hierarchy = try env.notebooks.getNotebookHierarchy(notebookId: nbId)
        #expect(hierarchy.groups.count == 1)
        #expect(hierarchy.ungroupedSections.isEmpty)

        let group = try #require(hierarchy.groups.first)
        #expect(group.name == "My Group")
        #expect(group.sections.count == 1)

        let section = try #require(group.sections.first)
        #expect(section.name == "My Section")
        #expect(section.entries.count == 2)
        #expect(section.entries.map { $0.title }.contains("Block 1"))
        #expect(section.entries.map { $0.title }.contains("Block 2"))
    }

    @discardableResult
    private func insertNotebookConflict(
        db: AppDatabase,
        entryId: Int64,
        fieldName: String,
        localValue: String,
        remoteValue: String
    ) throws -> Int64 {
        try db.writer.write { dbConn in
            try dbConn.execute(sql: """
                INSERT INTO _conflict_log
                    (table_name, record_id, field_name, local_value, remote_value, winner,
                     local_device, remote_device, local_ts, remote_ts, resolved_at, reviewed)
                VALUES ('notebook_entries', ?, ?, ?, ?, 'local',
                        'local-device', 'remote-device',
                        '2026-05-26T10:00:00Z', '2026-05-26T10:01:00Z',
                        '2026-05-26T10:02:00Z', 0)
                """, arguments: ["\(entryId)", fieldName, localValue, remoteValue])
            return dbConn.lastInsertedRowID
        }
    }
}
