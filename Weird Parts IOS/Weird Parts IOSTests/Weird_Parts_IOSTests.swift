//
//  Weird_Parts_IOSTests.swift
//  Weird Parts IOSTests
//
//  Created by Isaac Aznoe on 3/15/26.
//

import Testing
@testable import Weird_Parts


struct Weird_Parts_IOSTests {

    @Test func example() async throws {
        // Write your test here and use APIs like `#expect(...)` to check expected conditions.
    }

    @MainActor
    @Test func qaResolvedStatusBucketIncludesServiceResolvedStatus() async throws {
        #expect(QAThreadStatusBuckets.isResolved("resolved"))
        #expect(QAThreadStatusBuckets.isResolved("answered"))
        #expect(QAThreadStatusBuckets.isResolved("closed"))
        #expect(!QAThreadStatusBuckets.isResolved("open"))
        #expect(!QAThreadStatusBuckets.isResolved("escalated"))
    }

    @Test func partsCSVImportRejectsInvalidNumericValues() async throws {
        let fields = [
            "cost_price": "N/A",
            "markup_percent": "forty",
        ]

        let issues = PartsCSVImportParser.validateNumericFields(fieldValues: fields, rowNumber: 2)

        #expect(issues.count == 2)
        #expect(issues.contains(PartsCSVImportValidationIssue(
            rowNumber: 2,
            columnName: "cost_price",
            rawValue: "N/A"
        )))
        #expect(issues.contains(PartsCSVImportValidationIssue(
            rowNumber: 2,
            columnName: "markup_percent",
            rawValue: "forty"
        )))
    }

    @Test func partsCSVImportAcceptsValidNumericValues() async throws {
        let fields = [
            "cost_price": "12.50",
            "markup_percent": "40",
        ]

        let issues = PartsCSVImportParser.validateNumericFields(fieldValues: fields, rowNumber: 2)

        #expect(issues.isEmpty)
    }
}
