import XCTest

final class JobNotebookRecoveryRegressionTests: XCTestCase {
    func testJobDetailRecoveryUsesEnsureJobNotebookWithJobTypeTemplateMatching() throws {
        let source = try Self.readJobDetailSource()

        XCTAssertTrue(
            source.contains("service.ensureJobNotebook("),
            "Job notebook recovery should reuse NotebooksService.ensureJobNotebook so missing notebooks follow canonical duplicate-safe creation."
        )
        XCTAssertTrue(
            source.contains("jobType: job.jobType"),
            "Job notebook recovery must pass the job type so template selection matches job category defaults."
        )
        XCTAssertFalse(
            source.contains("service.createNotebook("),
            "Job notebook recovery should not bypass template selection by creating a generic notebook directly."
        )
    }

    private static func readJobDetailSource(file: StaticString = #filePath) throws -> String {
        let testFileURL = URL(fileURLWithPath: "\(file)")
        let projectRoot = testFileURL
            .deletingLastPathComponent() // Weird Parts IOSTests
            .deletingLastPathComponent() // Weird Parts IOS
        let sourceURL = projectRoot
            .appendingPathComponent("Weird Parts IOS")
            .appendingPathComponent("Features")
            .appendingPathComponent("Jobs")
            .appendingPathComponent("IOSJobDetailTabView.swift")
        return try String(contentsOf: sourceURL, encoding: .utf8)
    }
}
