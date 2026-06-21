import XCTest

final class JobsListPageRegressionTests: XCTestCase {
    func testSwipeStatusAndDetailActionsAreWiredAndPermissionGated() throws {
        let source = try Self.readJobsListPageSource()

        XCTAssertTrue(
            source.contains("if appCore.hasPermission(\"manage_jobs\") {\n                        Button { quickStatusTarget = QuickStatusTarget(job: job) }"),
            "Status swipe action should be gated to manage_jobs and open a real status flow."
        )
        XCTAssertTrue(
            source.contains(".confirmationDialog(") && source.contains("\"Change Status\""),
            "Jobs list should present a status-change dialog for the selected swipe target."
        )
        XCTAssertTrue(
            source.contains("try service.updateJob(id: job.id, status: newStatus)"),
            "Status flow should persist changes through JobsService.updateJob."
        )
        XCTAssertTrue(
            source.contains("Button { activeSheet = .jobDetail(job.id) }"),
            "Detail swipe action should route to a real destination."
        )
        XCTAssertTrue(
            source.contains("case .jobDetail(let jobId):") && source.contains("IOSJobDetailTabView(jobId: jobId)"),
            "Detail swipe action should present job detail content."
        )
        XCTAssertFalse(
            source.contains("Button { } label: {\n                        Label(\"Status\""),
            "Status swipe action must not remain an empty dead button."
        )
        XCTAssertFalse(
            source.contains("Button { } label: {\n                        Label(\"Detail\""),
            "Detail swipe action must not remain an empty dead button."
        )
    }

    func testStageProgressUsesTemplateScopedStageCache() throws {
        let source = try Self.readJobsListPageSource()

        XCTAssertTrue(
            source.contains("@State private var stagesByTemplateId"),
            "Jobs list should cache stage definitions by template so per-job workflows render correctly."
        )
        XCTAssertTrue(
            source.contains("let templateIds = Set(jobs.compactMap(\\.stageTemplateId))"),
            "Jobs list should collect template ids from jobs and load stage definitions per template."
        )
        XCTAssertTrue(
            source.contains("service.listAllJobStages(templateId: templateId)"),
            "Stage cache loading should request stages for each template id instead of using a shared global list."
        )
        XCTAssertFalse(
            source.contains("@State private var globalStages"),
            "Jobs list should not keep a single global stage list because custom templates have different stage orders."
        )
    }

    func testJobDetailEditWorkflowPersistsThroughJobsServiceAndReloads() throws {
        let source = try Self.readJobDetailPageSource()

        XCTAssertTrue(
            source.contains("case editJob") && source.contains("jobEditSheet"),
            "Job detail should expose a real edit sheet instead of only read-only quick-action placeholders."
        )
        XCTAssertTrue(
            source.contains("try service.updateJob(")
                && source.contains("jobName: editJobName")
                && source.contains("status: trimmedStatus")
                && source.contains("priority: trimmedPriority")
                && source.contains("jobType: trimmedJobType")
                && source.contains("customerName: editCustomerName.trimmingCharacters")
                && source.contains("addressLine1: editAddressLine1.trimmingCharacters")
                && source.contains("notes: editNotes.trimmingCharacters"),
            "Edit save should persist supported identity, workflow, metadata, and notes fields through JobsService.updateJob."
        )
        XCTAssertFalse(
            source.contains("customerName: editCustomerName.nilIfEmpty")
                || source.contains("addressLine1: editAddressLine1.nilIfEmpty")
                || source.contains("notes: editNotes.nilIfEmpty"),
            "Edit save must pass blank optional fields explicitly so JobsService.updateJob clears existing persisted values instead of treating nil as no change."
        )
        XCTAssertTrue(
            source.contains("validateJobEditForm()") && source.contains("Job name is required") && source.contains("Status is required"),
            "Edit flow should validate required local-first fields before saving."
        )
        XCTAssertTrue(
            source.contains("loadData()") && source.contains("jobEditSuccessMessage"),
            "Successful edits should reload persisted local data and announce a saved state."
        )
    }

    func testJobDetailShowsStableIdentityMetadataAndAccessibleEditControls() throws {
        let source = try Self.readJobDetailPageSource()

        XCTAssertTrue(
            source.contains("labelRow(\"Created\"") && source.contains("labelRow(\"Updated\""),
            "Job detail should show available created/updated local-first timestamps."
        )
        XCTAssertTrue(
            source.contains("Label(\"Edit Job\", systemImage: \"square.and.pencil\")"),
            "Detail header should provide an explicit edit entry point."
        )
        XCTAssertTrue(
            source.contains(".accessibilityIdentifier(\"jobDetailEditButton\")")
                && source.contains(".accessibilityIdentifier(\"jobDetailEditSummaryButton\")")
                && source.contains(".accessibilityIdentifier(\"jobEditSaveButton\")"),
            "Edit entry and save controls should have stable, distinct accessibility identifiers for user-like QA."
        )
        XCTAssertTrue(
            source.contains("(\"scheduled\", \"Scheduled\")")
                && source.contains("(\"pending\", \"Pending\")")
                && source.contains("(\"in_progress\", \"In Progress\")"),
            "Edit status picker should include workflow states that core logic can produce."
        )
        XCTAssertFalse(
            source.contains("(\"payment_hold\", \"Payment Hold\")")
                || source.contains("(\"warranty\", \"Warranty\")"),
            "Edit status picker should not expose payment hold or warranty transitions that require dedicated metadata APIs."
        )
        XCTAssertTrue(
            source.contains("accessibilityHint(\"Saves changes to this local job record\")"),
            "Save action should expose an accessibility hint for the persistence boundary."
        )
    }

    private static func readJobsListPageSource(file: StaticString = #filePath) throws -> String {
        let testFileURL = URL(fileURLWithPath: "\(file)")
        let projectRoot = testFileURL
            .deletingLastPathComponent() // Weird Parts IOSTests
            .deletingLastPathComponent() // Weird Parts IOS
        let sourceURL = projectRoot
            .appendingPathComponent("Weird Parts IOS")
            .appendingPathComponent("Features")
            .appendingPathComponent("Jobs")
            .appendingPathComponent("JobsListPage.swift")
        return try String(contentsOf: sourceURL, encoding: .utf8)
    }

    private static func readJobDetailPageSource(file: StaticString = #filePath) throws -> String {
        let testFileURL = URL(fileURLWithPath: "\(file)")
        let projectRoot = testFileURL
            .deletingLastPathComponent() // Weird Parts IOSTests
            .deletingLastPathComponent() // Weird Parts IOS
        let sourceURL = projectRoot
            .appendingPathComponent("Weird Parts IOS")
            .appendingPathComponent("Features")
            .appendingPathComponent("Jobs")
            .appendingPathComponent("IOSJobDetailPage.swift")
        return try String(contentsOf: sourceURL, encoding: .utf8)
    }
}
