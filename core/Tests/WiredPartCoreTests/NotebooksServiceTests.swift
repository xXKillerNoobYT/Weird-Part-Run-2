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
            blockData: nil
        )

        // Verify through hierarchy
        let hierarchy = try env.notebooks.getNotebookHierarchy(notebookId: nbId)
        let entries = hierarchy.ungroupedSections.flatMap(\.entries)
        let updated = entries.first { $0.id == entryId }
        #expect(updated != nil)
        #expect(updated?.content == "Revised content")
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
}
