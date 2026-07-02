import XCTest

/// Regression tests for the tracked silent-load-failure batch —
/// issues #1102, #1174, #1177, #1178, #1196.
///
/// Five screens used to coerce picker/sub-section load failures into empty
/// states with `try? ... ?? []`, making a real DB/service failure look like
/// "no data exists". These are source-scan tests following the
/// SilentLoadFailureSurfacingRegressionTests idiom: each test asserts on code
/// fragments that exist only in the fix, so a revert back to the silent
/// pattern fails the suite.
final class TrackedSilentFailureFixesRegressionTests: XCTestCase {

    // MARK: - #1102 CreateChannelSheet (supplier picker)

    func testSupplierChannelPickerSurfacesSupplierLoadFailure() throws {
        let source = try Self.readSource(["Features", "Chat", "CreateChannelSheet.swift"])

        XCTAssertTrue(
            source.contains("@State private var supplierLoadError: String?"),
            "CreateChannelSheet must carry a dedicated supplierLoadError state for the supplier picker."
        )
        XCTAssertTrue(
            source.contains("supplierLoadError = userFriendlyError(error, context: \"load suppliers\")"),
            "A supplier list failure must set supplierLoadError via userFriendlyError instead of rendering an empty picker."
        )
        XCTAssertTrue(
            source.contains(".accessibilityLabel(\"Retry loading suppliers\")"),
            "The supplier load error row must offer a retry affordance."
        )
        XCTAssertTrue(
            source.contains("Text(\"No suppliers configured\")"),
            "The true empty state must be rendered distinctly, only after a successful load."
        )
        XCTAssertFalse(
            source.contains("suppliers = (try? service.listSuppliers()) ?? []"),
            "listSuppliers must not be silently defaulted to []."
        )

        let body = try Self.methodBody(named: "loadSuppliers", in: source)
        XCTAssertTrue(
            body.contains("suppliers = try service.listSuppliers()"),
            "loadSuppliers must use a throwing read inside do/catch (keeping prior suppliers on a failed refresh)."
        )
        XCTAssertTrue(
            body.contains("supplierLoadError = \"Parts service not available\""),
            "A missing parts service must surface as a supplier load error, not a silent return."
        )
    }

    // MARK: - #1174 CreateNotebookSheet (template picker)

    func testNotebookTemplateLoadFailureSurfacesRetryableError() throws {
        let source = try Self.readSource(["Features", "Notebooks", "CreateNotebookSheet.swift"])

        XCTAssertTrue(
            source.contains("@State private var templatesLoadError: String?"),
            "CreateNotebookSheet must track template load errors separately from saveError."
        )
        XCTAssertTrue(
            source.contains("templatesLoadError = userFriendlyError(error, context: \"load notebook templates\")"),
            "A template load failure must set templatesLoadError instead of collapsing to an empty template list."
        )
        XCTAssertTrue(
            source.contains("if !templates.isEmpty || templatesLoadError != nil {"),
            "The template section must stay visible when the load failed so the error can render."
        )
        XCTAssertTrue(
            source.contains("Button(\"Retry loading templates\") {"),
            "The template load error must offer a retry action."
        )
        XCTAssertFalse(
            source.contains("templates = (try? service.getTemplates(templateType: \"job\")) ?? []"),
            "getTemplates must not be silently defaulted to []."
        )

        let body = try Self.methodBody(named: "loadTemplates", in: source)
        XCTAssertTrue(
            body.contains("templates = try service.getTemplates(templateType: \"job\")"),
            "loadTemplates must use a throwing read inside do/catch."
        )
        XCTAssertFalse(
            body.contains("saveError"),
            "Template load failures must not be routed through saveError."
        )
    }

    // MARK: - #1177 CreateSubcontractorScheduleSheet (job/contractor pickers)

    func testSubcontractorScheduleSheetSurfacesJobAndContractorLoadFailures() throws {
        let source = try Self.readSource(["Features", "Scheduling", "CreateSubcontractorScheduleSheet.swift"])

        XCTAssertTrue(
            source.contains("@State private var jobsLoadError: String?"),
            "The sheet must carry a jobsLoadError state for the job picker."
        )
        XCTAssertTrue(
            source.contains("@State private var contractorsLoadError: String?"),
            "The sheet must carry a contractorsLoadError state so the operator knows which prerequisite failed."
        )
        XCTAssertTrue(
            source.contains("jobsLoadError = userFriendlyError(error, context: \"load active jobs\")"),
            "A job list failure must set jobsLoadError instead of an empty picker."
        )
        XCTAssertTrue(
            source.contains("contractorsLoadError = userFriendlyError(error, context: \"load subcontractors\")"),
            "A contractor list failure must set contractorsLoadError instead of an empty picker."
        )
        XCTAssertTrue(
            source.contains(".accessibilityLabel(\"Retry loading jobs\")"),
            "The job load error must offer a retry affordance."
        )
        XCTAssertTrue(
            source.contains(".accessibilityLabel(\"Retry loading subcontractors\")"),
            "The contractor load error must offer a retry affordance."
        )
        XCTAssertFalse(
            source.contains("jobs = (try? jobsService.listJobs(status: \"active\", limit: 300)) ?? []"),
            "listJobs must not be silently defaulted to []."
        )
        XCTAssertFalse(
            source.contains("contractors = (try? peopleService.listContractors()) ?? []"),
            "listContractors must not be silently defaulted to []."
        )

        let jobsBody = try Self.methodBody(named: "loadJobList", in: source)
        XCTAssertTrue(
            jobsBody.contains("jobs = try jobsService.listJobs(status: \"active\", limit: 300)"),
            "loadJobList must use a throwing read inside do/catch (retry must not re-apply existing values over user edits)."
        )
        let contractorsBody = try Self.methodBody(named: "loadContractorList", in: source)
        XCTAssertTrue(
            contractorsBody.contains("contractors = try peopleService.listContractors()"),
            "loadContractorList must use a throwing read inside do/catch."
        )
    }

    // MARK: - #1178 IOSMessageThreadView (attach-to-message reference picker)

    func testChatAttachmentPickerSurfacesLookupFailures() throws {
        let source = try Self.readSource(["Features", "Chat", "IOSMessageThreadView.swift"])

        XCTAssertTrue(
            source.contains("loadError = userFriendlyError(error, context: \"load parts\")"),
            "A part lookup failure in the reference picker must set a visible loadError."
        )
        XCTAssertTrue(
            source.contains("loadError = userFriendlyError(error, context: \"load purchase orders\")"),
            "A PO lookup failure in the reference picker must set a visible loadError."
        )
        XCTAssertTrue(
            source.contains("loadError = userFriendlyError(error, context: \"load jobs\")"),
            "A job lookup failure in the reference picker must set a visible loadError."
        )
        XCTAssertTrue(
            source.contains(".accessibilityLabel(\"Retry loading references\")"),
            "The picker error row must offer a retry affordance."
        )
        XCTAssertFalse(
            source.contains("parts = (try? appCore.partsService?.listParts(search: search, limit: 50)) ?? []"),
            "listParts must not be silently defaulted to []."
        )
        XCTAssertFalse(
            source.contains("pos = (try? appCore.ordersService?.listPurchaseOrders(limit: 50)) ?? []"),
            "listPurchaseOrders must not be silently defaulted to []."
        )
        XCTAssertFalse(
            source.contains("jobs = (try? appCore.jobsService?.listJobs(search: search, limit: 50)) ?? []"),
            "listJobs must not be silently defaulted to []."
        )

        let body = try Self.methodBody(named: "loadData", in: source)
        XCTAssertTrue(
            body.contains("parts = try service.listParts(search: search, limit: 50)"),
            "The part lookup must be a throwing read inside do/catch."
        )
        XCTAssertTrue(
            body.contains("pos = try service.listPurchaseOrders(limit: 50)"),
            "The PO lookup must be a throwing read inside do/catch."
        )
        XCTAssertTrue(
            body.contains("jobs = try service.listJobs(search: search, limit: 50)"),
            "The job lookup must be a throwing read inside do/catch."
        )
    }

    // MARK: - #1196 IOSToolDetailPage (pending trades + maintenance sub-loads)

    func testToolDetailSurfacesTradeAndMaintenanceSubLoadFailures() throws {
        let source = try Self.readSource(["Features", "Tools", "IOSToolDetailPage.swift"])

        XCTAssertTrue(
            source.contains("@State private var pendingTradesError: String?"),
            "Tool detail must carry a scoped pendingTradesError state."
        )
        XCTAssertTrue(
            source.contains("@State private var maintenanceError: String?"),
            "Tool detail must carry a scoped maintenanceError state."
        )
        XCTAssertTrue(
            source.contains("pendingTradesError = userFriendlyError(error, context: \"load pending trades\")"),
            "Trade expiration/pending-trade failures must set pendingTradesError instead of rendering no pending trades."
        )
        XCTAssertTrue(
            source.contains("maintenanceError = userFriendlyError(error, context: \"load maintenance data\")"),
            "Maintenance config/next-due failures must set maintenanceError instead of a clean maintenance state."
        )
        XCTAssertTrue(
            source.contains("if pendingTradesError != nil || maintenanceError != nil {"),
            "The tool content list must render the scoped sub-section failure banner."
        )
        XCTAssertTrue(
            source.contains(".accessibilityLabel(\"Retry loading trade and maintenance data\")"),
            "The sub-section failure banner must offer a retry affordance."
        )
        XCTAssertFalse(
            source.contains("_ = try? service.expireOldTrades()"),
            "expireOldTrades must not be swallowed with try?."
        )
        XCTAssertFalse(
            source.contains("maintenanceConfigs = (try? service.getMaintenanceConfigs(toolId: toolId)) ?? []"),
            "getMaintenanceConfigs must not be silently defaulted to []."
        )
        XCTAssertFalse(
            source.contains("nextMaintenanceDue = try? service.calculateNextMaintenanceDate(toolId: toolId)"),
            "calculateNextMaintenanceDate must not be swallowed with try?."
        )

        let body = try Self.methodBody(named: "loadAllData", in: source)
        XCTAssertTrue(
            body.contains("_ = try service.expireOldTrades()"),
            "expireOldTrades must be a throwing call inside the scoped do/catch."
        )
        XCTAssertTrue(
            body.contains("pendingTrades = try service.getPendingTradesForUser(userId: userId)"),
            "getPendingTradesForUser must be a throwing read (keeping prior trades on a failed refresh)."
        )
        XCTAssertTrue(
            body.contains("maintenanceConfigs = try service.getMaintenanceConfigs(toolId: toolId)"),
            "getMaintenanceConfigs must be a throwing read inside the scoped do/catch."
        )
        XCTAssertTrue(
            body.contains("nextMaintenanceDue = try service.calculateNextMaintenanceDate(toolId: toolId)"),
            "calculateNextMaintenanceDate must be a throwing read inside the scoped do/catch."
        )
    }

    // MARK: - Helpers

    /// Read an app source file relative to the project root, mirroring the
    /// SilentLoadFailureSurfacingRegressionTests path idiom.
    private static func readSource(
        _ pathComponents: [String],
        file: StaticString = #filePath
    ) throws -> String {
        let projectRoot = URL(fileURLWithPath: "\(file)")
            .deletingLastPathComponent() // Weird Parts IOSTests
            .deletingLastPathComponent() // Weird Parts IOS (project folder)
        var sourceURL = projectRoot.appendingPathComponent("Weird Parts IOS")
        for component in pathComponents {
            sourceURL = sourceURL.appendingPathComponent(component)
        }
        return try String(contentsOf: sourceURL, encoding: .utf8)
    }

    /// Extract a brace-balanced method body so assertions can be scoped to a
    /// single function instead of the whole file.
    private static func methodBody(named methodName: String, in source: String) throws -> String {
        guard let nameRange = source.range(of: "func \(methodName)(") else {
            throw XCTSkip("Expected method \(methodName) in source")
        }
        guard let openBrace = source[nameRange.upperBound...].firstIndex(of: "{") else {
            throw XCTSkip("Expected opening brace for \(methodName)")
        }

        var depth = 0
        var index = openBrace
        while index < source.endIndex {
            let char = source[index]
            if char == "{" { depth += 1 }
            if char == "}" { depth -= 1 }
            let next = source.index(after: index)
            if depth == 0 {
                return String(source[openBrace..<next])
            }
            index = next
        }

        throw XCTSkip("Expected closing brace for \(methodName)")
    }
}
