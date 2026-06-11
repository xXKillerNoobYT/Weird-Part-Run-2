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
