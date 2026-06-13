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
