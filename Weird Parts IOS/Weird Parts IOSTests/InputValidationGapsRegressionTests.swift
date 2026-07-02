import XCTest

/// Regression tests for issue #1337 — verified input-validation gaps.
///
/// Source-scan tests (matching this folder's established pattern) that pin:
/// 1. CascadePriceEditSheet routes manual costs through ManualPricingInputValidator
///    so a typo can never silently clear a saved cost and negatives never persist.
/// 2. IOSCreateJobSheet / IOSEditJobSheet validate Estimated Hours and Budget Limit
///    (parseable + strictly positive) with inline errors and a disabled save button.
/// 3. IOSEstimationReviewPage requires end-of-job actual days/hours > 0 so variance %
///    and AI estimation learning cannot be corrupted.
/// 4. IOSToolDetailPage requires a usage-based maintenance threshold > 0 so tools
///    cannot become permanently overdue.
/// 5. The issue #1166 umbrella sweep: required-text validation/persist paths trim
///    with .whitespacesAndNewlines, never bare .whitespaces.
final class InputValidationGapsRegressionTests: XCTestCase {

    // MARK: - 1. Cascade pricing sheet uses the shared validator

    func testCascadePriceEditSheetRoutesCostsThroughManualPricingInputValidator() throws {
        let source = try Self.readSource(["Features", "Parts", "CascadePriceEditSheet.swift"])

        XCTAssertTrue(
            source.contains("try ManualPricingInputValidator.parseMoney(text, fieldName: fieldName)")
                && source.contains("return try ManualPricingInputValidator.parseMoney(text, fieldName: fieldName)"),
            "Cascade pricing drafts must be parsed by ManualPricingInputValidator, not raw Double()."
        )
        XCTAssertTrue(
            source.contains("cost = try parseCostDraft(typeDefaultText, fieldName: \"Default Cost\")")
                && source.contains("cost = try parseCostDraft(colorOverrideText, fieldName: \"Override Cost\")"),
            "Both the type-default and color-override save paths must go through the validated draft parser."
        )
        XCTAssertFalse(
            source.contains("Double(typeDefaultText)") || source.contains("Double(colorOverrideText)"),
            "Raw Double(text) on cascade cost drafts silently clears the saved cost on a typo and lets negatives persist."
        )
        XCTAssertTrue(
            source.contains(".disabled(isSaving || typeDefaultValidationMessage != nil)")
                && source.contains(".disabled(isSaving || colorOverrideValidationMessage != nil)"),
            "Save buttons must be disabled while a cost draft fails validation."
        )
        XCTAssertTrue(
            source.contains("if let message = typeDefaultValidationMessage {")
                && source.contains("if let message = colorOverrideValidationMessage {")
                && source.contains("Label(message, systemImage: \"exclamationmark.triangle.fill\")"),
            "Each cost field must show a visible inline validation error label."
        )
    }

    // MARK: - 2. Job create/edit numeric budget fields

    func testCreateJobSheetValidatesEstimatedHoursAndBudgetLimit() throws {
        let source = try Self.readSource(["Features", "Jobs", "IOSCreateJobSheet.swift"])

        XCTAssertTrue(
            source.contains("estimatedHours: parsedPositiveDouble(estimatedHours)")
                && source.contains("budgetLimit: parsedPositiveDouble(budgetLimit)"),
            "createJob must persist validated positive numbers, not raw Double(text)."
        )
        XCTAssertFalse(
            source.contains("estimatedHours: Double(estimatedHours)")
                || source.contains("budgetLimit: Double(budgetLimit)"),
            "Raw Double(text) silently drops unparseable estimates/budgets and lets negatives persist."
        )
        XCTAssertTrue(
            source.contains("&& estimatedHoursValidationMessage == nil")
                && source.contains("&& budgetLimitValidationMessage == nil"),
            "isValid must gate the Create button on the numeric budget fields."
        )
        XCTAssertTrue(
            source.contains("guard let number = Double(trimmed), number.isFinite else")
                && source.contains("guard number > 0 else"),
            "Numeric budget validation must require a finite, strictly positive number."
        )
        XCTAssertTrue(
            source.contains("if let message = estimatedHoursValidationMessage {")
                && source.contains("if let message = budgetLimitValidationMessage {"),
            "Create job sheet must show inline errors for invalid numeric budget fields."
        )
    }

    func testEditJobSheetRejectsNonPositiveNumericFields() throws {
        let source = try Self.readSource(["Features", "Jobs", "IOSEditJobSheet.swift"])

        XCTAssertTrue(
            source.contains("guard let number = Double(trimmed), number.isFinite else")
                && source.contains("guard number > 0 else"),
            "Edit job sheet numeric validation must reject non-positive estimated hours / budget limit."
        )
        XCTAssertTrue(
            source.contains("&& estimatedHoursValidationMessage == nil")
                && source.contains("&& budgetLimitValidationMessage == nil"),
            "Edit job sheet Save must be disabled while numeric drafts are invalid."
        )
        XCTAssertTrue(
            source.contains("must be greater than zero. Clear the field to remove it."),
            "Edit job sheet must explain the positivity rule while still allowing users to clear the field."
        )
    }

    // MARK: - 3. End-of-job review actuals must be > 0

    func testEndOfJobReviewRequiresPositiveActuals() throws {
        let source = try Self.readSource(["Features", "Jobs", "IOSEstimationReviewPage.swift"])

        XCTAssertTrue(
            source.contains("days.isFinite, days > 0")
                && source.contains("hours.isFinite, hours > 0"),
            "End-of-job review must require actual days and hours to be strictly positive before submitting."
        )
        XCTAssertFalse(
            source.contains("Please enter valid numbers for days and hours"),
            "The old combined guard accepted zero/negative actuals, corrupting variance % and AI learning."
        )
        XCTAssertTrue(
            source.contains("|| actualDaysValidationMessage != nil")
                && source.contains("|| actualHoursValidationMessage != nil"),
            "Submit must be disabled while an actual days/hours draft is invalid."
        )
        XCTAssertTrue(
            source.contains("if let message = actualDaysValidationMessage {")
                && source.contains("if let message = actualHoursValidationMessage {"),
            "Each actuals field must show a visible inline validation error."
        )
    }

    // MARK: - 4. Usage-based maintenance threshold must be > 0

    func testMaintenanceConfigRequiresPositiveUsageThreshold() throws {
        let source = try Self.readSource(["Features", "Tools", "IOSToolDetailPage.swift"])

        XCTAssertTrue(
            source.contains("guard usageThreshold.isFinite, usageThreshold > 0 else"),
            "Usage-based maintenance threshold must be strictly positive or the tool is flagged overdue forever."
        )
        XCTAssertTrue(
            source.contains(".disabled(isSaving || usageThresholdValidationMessage != nil)"),
            "Maintenance config Save must be disabled while the usage threshold is invalid."
        )
        XCTAssertTrue(
            source.contains("if let message = usageThresholdValidationMessage {"),
            "The usage threshold section must show a visible inline validation error."
        )
        XCTAssertTrue(
            source.contains("saveError = message")
                && source.contains("if let message = usageThresholdValidationMessage {"),
            "saveConfig must keep a validation backstop even though the button is disabled."
        )
    }

    // MARK: - 5. Umbrella: .whitespacesAndNewlines on validation/persist paths

    /// The bare pattern `.whitespaces)` lets newline-only text pass required-field
    /// checks and persist embedded newlines (issue #1166 class). These files carry
    /// required-text validation or persist paths and must be fully converted.
    private static let sweptValidationPathFiles: [[String]] = [
        ["Features", "Jobs", "IOSCreateJobSheet.swift"],
        ["Features", "Jobs", "IOSEditJobSheet.swift"],
        ["Features", "Jobs", "IOSEstimationReviewPage.swift"],
        ["Features", "Parts", "CascadePriceEditSheet.swift"],
        ["Features", "Tools", "IOSToolDetailPage.swift"],
        ["Features", "People", "IOSContactDetailPage.swift"],
        ["Features", "People", "IOSContactsPage.swift"],
        ["Features", "People", "IOSTeamsPage.swift"],
        ["Features", "People", "IOSTeamDetailPage.swift"],
        ["Features", "People", "IOSHatsPage.swift"],
        ["Features", "People", "IOSCustomersPage.swift"],
        ["Features", "People", "IOSCustomerDetailPage.swift"],
        ["Features", "People", "IOSEmployeesPage.swift"],
        ["Features", "People", "IOSEmployeeDetailPage.swift"],
        ["Features", "Settings", "IOSReportTemplatesPage.swift"],
        ["Features", "Warehouse", "WizardStepShelves.swift"],
        ["Features", "Dashboard", "DashboardDailyReportPage.swift"],
        ["Features", "Dashboard", "IOSDashboardQRScannerPage.swift"],
        ["Features", "Notebooks", "AddNotebookEntrySheet.swift"],
        ["Features", "Notebooks", "IOSNotebookDetailPage.swift"],
    ]

    func testValidationPersistPathsTrimWhitespacesAndNewlines() throws {
        for components in Self.sweptValidationPathFiles {
            let source = try Self.readSource(components)
            XCTAssertFalse(
                source.contains("trimmingCharacters(in: .whitespaces)"),
                "\(components.last ?? "?") has a required-text validation/persist path trimming with bare .whitespaces; use .whitespacesAndNewlines so newline-only input cannot pass required checks or persist."
            )
        }
    }

    func testOrdersServiceBulkHoldReasonUsesRequiredTextHelper() throws {
        let source = try Self.readCoreSource(["Services", "OrdersService.swift"])

        XCTAssertTrue(
            source.contains("let trimmedReason = holdReason.trimmedRequiredText"),
            "bulkHoldJPOLinesWithChat must trim the hold reason with the shared trimmedRequiredText helper (.whitespacesAndNewlines)."
        )
        XCTAssertFalse(
            source.contains("holdReason.trimmingCharacters(in: .whitespaces)"),
            "A newline-only hold reason must not pass the requiredFieldEmpty guard."
        )
    }

    // MARK: - Helpers

    private static func readSource(_ pathComponents: [String], file: StaticString = #filePath) throws -> String {
        let testFileURL = URL(fileURLWithPath: "\(file)")
        let projectRoot = testFileURL
            .deletingLastPathComponent() // Weird Parts IOSTests
            .deletingLastPathComponent() // Weird Parts IOS
        var sourceURL = projectRoot.appendingPathComponent("Weird Parts IOS")
        for component in pathComponents {
            sourceURL = sourceURL.appendingPathComponent(component)
        }
        return try String(contentsOf: sourceURL, encoding: .utf8)
    }

    private static func readCoreSource(_ pathComponents: [String], file: StaticString = #filePath) throws -> String {
        let testFileURL = URL(fileURLWithPath: "\(file)")
        let repoRoot = testFileURL
            .deletingLastPathComponent() // Weird Parts IOSTests
            .deletingLastPathComponent() // Weird Parts IOS
            .deletingLastPathComponent() // repo root
        var sourceURL = repoRoot
            .appendingPathComponent("core")
            .appendingPathComponent("Sources")
            .appendingPathComponent("WiredPartCore")
        for component in pathComponents {
            sourceURL = sourceURL.appendingPathComponent(component)
        }
        return try String(contentsOf: sourceURL, encoding: .utf8)
    }
}
