import XCTest

final class JobsListPageRegressionTests: XCTestCase {
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

    func testSwipeStatusAndDetailActionsAreWiredToRealFlows() throws {
        let source = try Self.readJobsListPageSource()

        XCTAssertTrue(
            source.contains("quickStatusTarget = QuickStatusTarget(job: job)"),
            "Status swipe action should open a real status flow instead of an empty closure."
        )
        XCTAssertTrue(
            source.contains("confirmationDialog(") && source.contains("\"Change Job Status\""),
            "Jobs list should present a status-change dialog for the selected swipe target."
        )
        XCTAssertTrue(
            source.contains("try service.updateJob(id: job.id, status: status)"),
            "Status flow should persist the new status through JobsService.updateJob."
        )
        XCTAssertTrue(
            source.contains("jobDetailTarget = JobDetailTarget(jobId: job.id)"),
            "Detail swipe action should route to a real destination."
        )
        XCTAssertTrue(
            source.contains(".sheet(item: $jobDetailTarget)") && source.contains("IOSJobDetailTabView(jobId: target.jobId)"),
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
}
