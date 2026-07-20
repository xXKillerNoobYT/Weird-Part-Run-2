import XCTest

/// Regression tests for issue #1484 (XPIA / prompt injection):
/// every postAIContext that embeds user-editable free-text fields must wrap
/// those values inside a <record-data> … </record-data> envelope so the LLM
/// cannot be tricked into treating user-supplied content as instructions.
final class AIContextPromptInjectionRegressionTests: XCTestCase {

    // MARK: - IOSJobDetailPage

    func testJobDetailContextWrapsUserFieldsInRecordDataEnvelope() throws {
        let source = try Self.readSource("Jobs", "IOSJobDetailPage.swift")
        XCTAssertTrue(
            source.contains("<record-data>"),
            "IOSJobDetailPage.postAIContext must wrap user-supplied fields in a <record-data> envelope to prevent prompt injection."
        )
        // Job name must appear inside the envelope, not directly in the system prompt narrative
        XCTAssertFalse(
            source.contains("Job: \\(job.jobNumber) - \\(job.jobName)"),
            "IOSJobDetailPage.postAIContext must not interpolate job.jobName directly into the narrative context string."
        )
    }

    // MARK: - IOSJPODetailPage

    func testJPODetailContextWrapsJobNameInRecordDataEnvelope() throws {
        let source = try Self.readSource("Orders", "IOSJPODetailPage.swift")
        XCTAssertTrue(
            source.contains("<record-data>"),
            "IOSJPODetailPage.postAIContext must wrap user-supplied fields in a <record-data> envelope to prevent prompt injection."
        )
        XCTAssertFalse(
            source.contains("Job: \\(detail.jobName)"),
            "IOSJPODetailPage.postAIContext must not interpolate detail.jobName directly into the narrative context string."
        )
    }

    // MARK: - IOSPODetailPage

    func testPODetailContextWrapsSupplierAndJobNamesInRecordDataEnvelope() throws {
        let source = try Self.readSource("Orders", "IOSPODetailPage.swift")
        XCTAssertTrue(
            source.contains("<record-data>"),
            "IOSPODetailPage.postAIContext must wrap user-supplied fields in a <record-data> envelope to prevent prompt injection."
        )
        XCTAssertFalse(
            source.contains("supplier: \\(detail.supplierName)"),
            "IOSPODetailPage.postAIContext must not interpolate detail.supplierName directly into the narrative context string."
        )
    }

    // MARK: - LaborPage

    func testLaborPageContextWrapsJobNamesInRecordDataEnvelope() throws {
        let source = try Self.readSource("Jobs", "LaborPage.swift")
        XCTAssertTrue(
            source.contains("<record-data>"),
            "LaborPage.postAIContext must wrap user-supplied fields in a <record-data> envelope to prevent prompt injection."
        )
        XCTAssertFalse(
            source.contains("active jobs shown: \\(activeJobs"),
            "LaborPage.postAIContext must not interpolate job names directly into the narrative context string."
        )
    }

    // MARK: - IOSOrderStagingPage

    func testOrderStagingContextWrapsJobNameInRecordDataEnvelope() throws {
        let source = try Self.readSource("Orders", "IOSOrderStagingPage.swift")
        XCTAssertTrue(
            source.contains("<record-data>"),
            "IOSOrderStagingPage.postAIContext must wrap user-supplied fields in a <record-data> envelope to prevent prompt injection."
        )
        XCTAssertFalse(
            source.contains("Selected job: \\(selectedJob)"),
            "IOSOrderStagingPage.postAIContext must not interpolate the job name directly into the narrative context string."
        )
    }

    // MARK: - IOSPartsOrderManagementPage

    func testPartsOrderManagementContextWrapsSupplierNameInRecordDataEnvelope() throws {
        let source = try Self.readSource("Orders", "IOSPartsOrderManagementPage.swift")
        XCTAssertTrue(
            source.contains("<record-data>"),
            "IOSPartsOrderManagementPage.postAIContext must wrap user-supplied fields in a <record-data> envelope to prevent prompt injection."
        )
        XCTAssertFalse(
            source.contains("Selected supplier: \\(supplierName)"),
            "IOSPartsOrderManagementPage.postAIContext must not interpolate supplier name directly into the narrative context string."
        )
    }

    // MARK: - IOSJPOCreationPage

    func testJPOCreationContextWrapsJobNameInRecordDataEnvelope() throws {
        let source = try Self.readSource("Orders", "IOSJPOCreationPage.swift")
        XCTAssertTrue(
            source.contains("<record-data>"),
            "IOSJPOCreationPage.postAIContext must wrap user-supplied fields in a <record-data> envelope to prevent prompt injection."
        )
        XCTAssertFalse(
            source.contains("Selected job: \\(selectedJobName"),
            "IOSJPOCreationPage.postAIContext must not interpolate selectedJobName directly into the narrative context string."
        )
    }

    // MARK: - Helpers

    private static func readSource(_ featureFolder: String, _ fileName: String, file: StaticString = #filePath) throws -> String {
        let testFileURL = URL(fileURLWithPath: "\(file)")
        let projectRoot = testFileURL
            .deletingLastPathComponent() // Weird Parts IOSTests
            .deletingLastPathComponent() // Weird Parts IOS
        let sourceURL = projectRoot
            .appendingPathComponent("Weird Parts IOS")
            .appendingPathComponent("Features")
            .appendingPathComponent(featureFolder)
            .appendingPathComponent(fileName)
        return try String(contentsOf: sourceURL, encoding: .utf8)
    }
}
