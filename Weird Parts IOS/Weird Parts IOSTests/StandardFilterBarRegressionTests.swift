import XCTest
@testable import Weird_Parts

final class StandardFilterBarRegressionTests: XCTestCase {
    func testQuickChipsExposeMinimumTapTargetAndSelectedAccessibilityContract() throws {
        let source = try Self.readSharedSource(named: "StandardFilterBar.swift")

        XCTAssertTrue(
            source.contains("static let minimumChipTapTarget: CGFloat = 44"),
            "StandardFilterBar chips should lock the platform minimum 44pt tap target."
        )
        XCTAssertTrue(
            source.contains(".frame(minWidth: Self.minimumChipTapTarget, minHeight: Self.minimumChipTapTarget)"),
            "Quick chips should apply the minimum hit target directly to the label."
        )
        XCTAssertTrue(
            source.contains(".accessibilityIdentifier(\"dateRangeChip_\\(option.accessibilityIdentifier)\")"),
            "Quick chips should expose stable per-option accessibility identifiers for UI tests and assistive tooling."
        )
        XCTAssertTrue(
            source.contains(".accessibilityAddTraits(selectedRange == option ? .isSelected : [])"),
            "The active chip should expose the selected accessibility trait."
        )
        XCTAssertTrue(
            source.contains(".accessibilityValue(selectedRange == option ? \"Selected\" : \"Not selected\")"),
            "VoiceOver should announce whether each chip is selected."
        )
    }

    func testCustomRangePickersNormalizeReversedDates() throws {
        let source = try Self.readSharedSource(named: "StandardFilterBar.swift")

        XCTAssertTrue(source.contains("DatePicker(\"From\", selection: normalizedCustomStart"))
        XCTAssertTrue(source.contains("DatePicker(\"To\", selection: normalizedCustomEnd"))
        XCTAssertTrue(
            source.contains("guard customStart > customEnd else { return }") && source.contains("customEnd = customStart"),
            "Custom mode should normalize reversed ranges instead of leaving start > end."
        )
        XCTAssertTrue(
            source.contains("customEnd = max(newEnd, customStart)"),
            "The end-date picker should use the same clamp-forward policy as custom range normalization."
        )
    }

    func testQuickChipIdentifiersAreStablePerCase() throws {
        let source = try Self.readSharedSource(named: "StandardFilterBar.swift")

        XCTAssertTrue(source.contains("case .thisWeek: return \"this_week\""))
        XCTAssertTrue(source.contains("case .lastPeriod: return \"last_period\""))
        XCTAssertFalse(
            source.contains("rawValue\n            .lowercased()"),
            "Accessibility identifiers must not be derived from user-facing copy."
        )
    }

    func testReportDateRangeLivesInSharedLayer() throws {
        let testFileURL = URL(fileURLWithPath: "\(#filePath)")
        let projectRoot = testFileURL
            .deletingLastPathComponent() // Weird Parts IOSTests
            .deletingLastPathComponent() // Weird Parts IOS
        let sharedURL = projectRoot
            .appendingPathComponent("Weird Parts IOS")
            .appendingPathComponent("Shared")
            .appendingPathComponent("ReportDateRange.swift")
        let reportsURL = projectRoot
            .appendingPathComponent("Weird Parts IOS")
            .appendingPathComponent("Features")
            .appendingPathComponent("Reports")
            .appendingPathComponent("ReportDateRange.swift")

        XCTAssertTrue(FileManager.default.fileExists(atPath: sharedURL.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: reportsURL.path))
    }

    func testCoreJobsAndOrdersPagesUseStandardFilterBarBeforePageSpecificFilters() throws {
        let jobsSource = try Self.readFeatureSource(pathComponents: ["Jobs", "JobsListPage.swift"])
        let jposSource = try Self.readFeatureSource(pathComponents: ["Orders", "IOSJPOsPage.swift"])
        let partsManagementSource = try Self.readFeatureSource(pathComponents: ["Orders", "IOSPartsOrderManagementPage.swift"])

        XCTAssertLessThan(
            try XCTUnwrap(jobsSource.range(of: "StandardFilterBar")?.lowerBound),
            try XCTUnwrap(jobsSource.range(of: "smartCards")?.lowerBound),
            "Jobs list should place the standard date bar before its status smart cards."
        )
        XCTAssertLessThan(
            try XCTUnwrap(jposSource.range(of: "StandardFilterBar")?.lowerBound),
            try XCTUnwrap(jposSource.range(of: "statusPicker")?.lowerBound),
            "JPO list should place the standard date bar before its status chips."
        )
        XCTAssertLessThan(
            try XCTUnwrap(partsManagementSource.range(of: "StandardFilterBar")?.lowerBound),
            try XCTUnwrap(partsManagementSource.range(of: "supplierPicker")?.lowerBound),
            "Parts management should place the standard date bar before supplier and status filters."
        )
    }

    func testCoreJobsAndOrdersPagesFilterRowsBySelectedStandardDateRange() throws {
        let jobsSource = try Self.readFeatureSource(pathComponents: ["Jobs", "JobsListPage.swift"])
        let jposSource = try Self.readFeatureSource(pathComponents: ["Orders", "IOSJPOsPage.swift"])
        let partsManagementSource = try Self.readFeatureSource(pathComponents: ["Orders", "IOSPartsOrderManagementPage.swift"])

        XCTAssertTrue(jobsSource.contains("dateStringFallsInSelectedRange(job.startDate ?? job.dueDate)"))
        XCTAssertTrue(jposSource.contains("dateStringFallsInSelectedRange($0.createdAt ?? $0.dueDate)"))
        XCTAssertTrue(partsManagementSource.contains("dateStringFallsInSelectedRange(row.orderDate ?? row.expectedDelivery)"))
    }

    @MainActor
    func testPayPeriodRangesUseInjectedAnchorAndLength() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let anchor = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 2, day: 4)))
        let now = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 2, day: 20, hour: 12)))
        let config = ReportDateRange.PayPeriodConfiguration(anchorDate: anchor, lengthInDays: 7)

        let thisPeriod = try XCTUnwrap(ReportDateRange.thisPeriod.dateInterval(now: now, calendar: calendar, payPeriod: config))
        XCTAssertEqual(thisPeriod.start, try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 2, day: 18))))
        XCTAssertEqual(thisPeriod.end, now)

        let lastPeriod = try XCTUnwrap(ReportDateRange.lastPeriod.dateInterval(now: now, calendar: calendar, payPeriod: config))
        XCTAssertEqual(lastPeriod.start, try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 2, day: 11))))
        XCTAssertEqual(lastPeriod.end, try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 2, day: 17, hour: 23, minute: 59, second: 59))))
    }

    @MainActor
    func testPayPeriodRangesFloorDivideWhenAnchorIsAfterNow() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let anchor = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 2, day: 18)))
        let now = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 2, day: 15, hour: 12)))
        let config = ReportDateRange.PayPeriodConfiguration(anchorDate: anchor, lengthInDays: 7)

        let thisPeriod = try XCTUnwrap(ReportDateRange.thisPeriod.dateInterval(now: now, calendar: calendar, payPeriod: config))
        XCTAssertEqual(thisPeriod.start, try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 2, day: 11))))
        XCTAssertEqual(thisPeriod.end, now)

        let lastPeriod = try XCTUnwrap(ReportDateRange.lastPeriod.dateInterval(now: now, calendar: calendar, payPeriod: config))
        XCTAssertEqual(lastPeriod.start, try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 2, day: 4))))
        XCTAssertEqual(lastPeriod.end, try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 2, day: 10, hour: 23, minute: 59, second: 59))))
    }

    @MainActor
    func testPayPeriodRangesNormalizeAnchorTimeToDayBoundaries() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let anchor = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 2, day: 4, hour: 15, minute: 30)))
        let now = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 2, day: 20, hour: 6)))
        let config = ReportDateRange.PayPeriodConfiguration(anchorDate: anchor, lengthInDays: 7)

        let thisPeriod = try XCTUnwrap(ReportDateRange.thisPeriod.dateInterval(now: now, calendar: calendar, payPeriod: config))
        XCTAssertEqual(thisPeriod.start, try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 2, day: 18))))
        XCTAssertEqual(thisPeriod.end, now)

        let lastPeriod = try XCTUnwrap(ReportDateRange.lastPeriod.dateInterval(now: now, calendar: calendar, payPeriod: config))
        XCTAssertEqual(lastPeriod.start, try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 2, day: 11))))
        XCTAssertEqual(lastPeriod.end, try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 2, day: 17, hour: 23, minute: 59, second: 59))))
    }

    @MainActor
    func testLastMonthReturnsInclusiveEndOfFinalDay() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let now = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 3, day: 15, hour: 12)))

        let lastMonth = try XCTUnwrap(ReportDateRange.lastMonth.dateInterval(now: now, calendar: calendar))
        XCTAssertEqual(lastMonth.start, try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 2, day: 1))))
        XCTAssertEqual(lastMonth.end, try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 2, day: 28, hour: 23, minute: 59, second: 59))))
    }

    func testReportDateRangeIdentityDoesNotUseDisplayCopy() throws {
        let source = try Self.readSharedSource(named: "ReportDateRange.swift")

        XCTAssertTrue(source.contains("var id: Self { self }"))
        XCTAssertFalse(
            source.contains("var id: String { rawValue }"),
            "ReportDateRange identity must stay stable when display strings change."
        )
    }

    func testPayPeriodConfigurationCannotMutateIntoInvalidLength() throws {
        let source = try Self.readSharedSource(named: "ReportDateRange.swift")

        XCTAssertTrue(source.contains("let lengthInDays: Int"))
        XCTAssertFalse(
            source.contains("var lengthInDays: Int"),
            "Pay-period length is clamped during initialization and should remain immutable after that."
        )
    }

    private static func readSharedSource(named fileName: String, file: StaticString = #filePath) throws -> String {
        let testFileURL = URL(fileURLWithPath: "\(file)")
        let projectRoot = testFileURL
            .deletingLastPathComponent() // Weird Parts IOSTests
            .deletingLastPathComponent() // Weird Parts IOS
        let sourceURL = projectRoot
            .appendingPathComponent("Weird Parts IOS")
            .appendingPathComponent("Shared")
            .appendingPathComponent(fileName)
        return try String(contentsOf: sourceURL, encoding: .utf8)
    }

    private static func readFeatureSource(pathComponents: [String], file: StaticString = #filePath) throws -> String {
        let testFileURL = URL(fileURLWithPath: "\(file)")
        var sourceURL = testFileURL
            .deletingLastPathComponent() // Weird Parts IOSTests
            .deletingLastPathComponent() // Weird Parts IOS
            .appendingPathComponent("Weird Parts IOS")
            .appendingPathComponent("Features")
        for component in pathComponents {
            sourceURL.appendPathComponent(component)
        }
        return try String(contentsOf: sourceURL, encoding: .utf8)
    }
}
