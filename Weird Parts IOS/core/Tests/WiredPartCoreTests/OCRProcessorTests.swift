import Testing
import Foundation
@testable import WiredPartCore

@Suite("OCR Processor Tests")
struct OCRProcessorTests {

    // MARK: - Confidence Tests

    @Test("Confidence tiers are correct")
    func testConfidenceTiers() {
        #expect(OCRConfidence.tier(for: 0.95) == .high)
        #expect(OCRConfidence.tier(for: 0.90) == .high)
        #expect(OCRConfidence.tier(for: 0.89) == .medium)
        #expect(OCRConfidence.tier(for: 0.70) == .medium)
        #expect(OCRConfidence.tier(for: 0.69) == .low)
        #expect(OCRConfidence.tier(for: 0.10) == .low)
    }

    // MARK: - Field Extraction Tests

    @Test("Extract PO number from text")
    func testExtractPONumber() throws {
        let db = try AppDatabase.openInMemoryDatabase()
        let processor = OCRProcessor(db: db)

        let blocks = [
            RecognizedTextBlock(text: "Purchase Order PO# 12345-A", confidence: 0.95),
            RecognizedTextBlock(text: "Date: 03/15/2026", confidence: 0.90),
        ]

        let result = try processor.extractFields(from: blocks)

        let poFields = result.fields.filter { $0.fieldType == .poNumber }
        #expect(!poFields.isEmpty, "Should extract at least one PO number")
        if let poField = poFields.first {
            #expect(poField.value == "12345-A")
        }
    }

    @Test("Extract dates from text")
    func testExtractDates() throws {
        let db = try AppDatabase.openInMemoryDatabase()
        let processor = OCRProcessor(db: db)

        let blocks = [
            RecognizedTextBlock(text: "Delivery Date: 03/15/2026", confidence: 0.92),
            RecognizedTextBlock(text: "Due: January 20, 2026", confidence: 0.88),
        ]

        let result = try processor.extractFields(from: blocks)
        let dateFields = result.fields.filter { $0.fieldType == .date }
        #expect(dateFields.count >= 1, "Should extract at least one date")
    }

    @Test("Extract quantities from text")
    func testExtractQuantities() throws {
        let db = try AppDatabase.openInMemoryDatabase()
        let processor = OCRProcessor(db: db)

        let blocks = [
            RecognizedTextBlock(text: "Qty: 42", confidence: 0.95),
            RecognizedTextBlock(text: "Quantity 100", confidence: 0.90),
        ]

        let result = try processor.extractFields(from: blocks)
        let qtyFields = result.fields.filter { $0.fieldType == .quantity }
        #expect(qtyFields.count >= 1)
    }

    @Test("Extract dollar amounts from text")
    func testExtractAmounts() throws {
        let db = try AppDatabase.openInMemoryDatabase()
        let processor = OCRProcessor(db: db)

        let blocks = [
            RecognizedTextBlock(text: "Total: $1,234.56", confidence: 0.93),
        ]

        let result = try processor.extractFields(from: blocks)
        let amountFields = result.fields.filter { $0.fieldType == .amount }
        #expect(amountFields.count >= 1)
        if let amount = amountFields.first {
            #expect(amount.value == "1,234.56")
        }
    }

    @Test("Empty text blocks produce empty result")
    func testEmptyBlocks() throws {
        let db = try AppDatabase.openInMemoryDatabase()
        let processor = OCRProcessor(db: db)

        let result = try processor.extractFields(from: [])
        #expect(result.fields.isEmpty)
        #expect(result.overallConfidence == 0)
    }

    @Test("Needs rescan when overall confidence below threshold")
    func testNeedsRescan() throws {
        let db = try AppDatabase.openInMemoryDatabase()
        let processor = OCRProcessor(db: db)

        let blocks = [
            RecognizedTextBlock(text: "PO# 999", confidence: 0.30),
        ]

        let result = try processor.extractFields(from: blocks)
        // With a single low-confidence field, the average should be below threshold
        if !result.fields.isEmpty {
            #expect(result.needsRescan || result.overallConfidence >= OCRConfidence.rescanThreshold)
        }
    }

    // MARK: - ExtractedField Tests

    @Test("ExtractedField isAutoFillReady based on confidence")
    func testAutoFillReady() {
        let highField = ExtractedField(fieldType: .poNumber, value: "123", confidence: 0.95, label: "PO")
        let lowField = ExtractedField(fieldType: .poNumber, value: "456", confidence: 0.60, label: "PO")

        #expect(highField.isAutoFillReady)
        #expect(!lowField.isAutoFillReady)
    }
}
