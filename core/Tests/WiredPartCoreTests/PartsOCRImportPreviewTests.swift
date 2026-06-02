import Foundation
import Testing
@testable import WiredPartCore

@Suite("Parts PDF/OCR import preview tests")
struct PartsOCRImportPreviewTests {
    @Test("previewPartsImportOCR chunks extracted page text with page evidence")
    func previewPartsImportOCRChunksExtractedPageTextWithEvidence() throws {
        let env = try E2ETestHelpers.setUp()

        let preview = try env.parts.previewPartsImportOCR(pages: [
            .init(pageNumber: 1, text: """
            Vendor Quote
            Code | Name | Category | Cost
            W-14 | 14 AWG THHN Wire | Wire | 31.50
            """),
            .init(pageNumber: 2, text: """
            Continuation
            Code | Name | Category | Unit
            EMT-2 | 2 inch EMT Conduit | Conduit | each
            """)
        ], chunkLineLimit: 2)

        #expect(preview.chunks.count >= 2)
        #expect(preview.chunks.map(\.pageNumber).contains(1))
        #expect(preview.chunks.map(\.pageNumber).contains(2))
        #expect(preview.chunks.allSatisfy { !$0.snippet.isEmpty })
        #expect(preview.chunks.contains { $0.snippet.contains("14 AWG THHN Wire") })
    }

    @Test("previewPartsImportOCR detects table rows as proposed import rows with source evidence")
    func previewPartsImportOCRDetectsRowsWithConfidenceAndEvidence() throws {
        let env = try E2ETestHelpers.setUp()

        let preview = try env.parts.previewPartsImportOCR(pages: [
            .init(pageNumber: 3, text: """
            Parts List
            Code | Name | Category | Brand | Cost | Markup | Unit
            W-14 | 14 AWG THHN Wire | Wire | Southwire | 31.50 | 20 | roll
            EMT-2 | 2 inch EMT Conduit | Conduit | Allied | 12.25 | 15 | each
            """)
        ])

        #expect(preview.candidates.count == 2)
        let wire = try #require(preview.candidates.first { $0.code == "W-14" })
        #expect(wire.name == "14 AWG THHN Wire")
        #expect(wire.category == "Wire")
        #expect(wire.brand == "Southwire")
        #expect(wire.fields["cost_price"] == "31.50")
        #expect(wire.fields["markup_percent"] == "20")
        #expect(wire.fields["unit_of_measure"] == "roll")
        #expect(wire.pageNumber == 3)
        #expect(wire.confidence >= 0.85)
        #expect(wire.sourceSnippet.contains("14 AWG THHN Wire"))
    }

    @Test("previewPartsImportOCR is preview-only and does not write parts")
    func previewPartsImportOCRIsPreviewOnlyAndDoesNotWriteParts() throws {
        let env = try E2ETestHelpers.setUp()
        let before = try env.parts.getImportExportStats()

        let preview = try env.parts.previewPartsImportOCR(pages: [
            .init(pageNumber: 1, text: """
            Code | Name | Category
            X-100 | Preview Only Breaker | Electrical
            """)
        ])

        let after = try env.parts.getImportExportStats()
        #expect(preview.isCommitAllowed == false)
        #expect(preview.candidates.count == 1)
        #expect(after.totalParts == before.totalParts)
        #expect(try env.parts.findPartByCode("X-100") == nil)
    }

    @Test("previewPartsImportOCR surfaces row errors with page and snippet evidence")
    func previewPartsImportOCRSurfacesRowErrorsWithEvidence() throws {
        let env = try E2ETestHelpers.setUp()

        let preview = try env.parts.previewPartsImportOCR(pages: [
            .init(pageNumber: 4, text: """
            Code | Name | Category | Cost
            BAD-1 | Missing Category |  | 5.00
            BAD-2 | Bad Cost | Wire | not-money
            """)
        ])

        #expect(preview.candidates.isEmpty)
        #expect(preview.errors.count == 2)
        #expect(preview.errors.allSatisfy { $0.pageNumber == 4 && !$0.sourceSnippet.isEmpty })
        #expect(preview.errors.contains { $0.message.contains("category") })
        #expect(preview.errors.contains { $0.message.contains("cost_price") })
    }

    @Test("previewPartsImportOCR does not carry headers between pages")
    func previewPartsImportOCRDoesNotCarryHeadersAcrossPages() throws {
        let env = try E2ETestHelpers.setUp()

        let preview = try env.parts.previewPartsImportOCR(pages: [
            .init(pageNumber: 1, text: """
            Code | Name | Category
            A-1 | First Page Row | Wire
            """),
            .init(pageNumber: 2, text: """
            B-2 | Second Page Without Header | Conduit
            """)
        ])

        #expect(preview.candidates.count == 1)
        #expect(preview.candidates.first?.code == "A-1")
    }

    @Test("previewPartsImportOCR rejects negative cost and markup values")
    func previewPartsImportOCRRejectsNegativeNumericValues() throws {
        let env = try E2ETestHelpers.setUp()

        let preview = try env.parts.previewPartsImportOCR(pages: [
            .init(pageNumber: 5, text: """
            Code | Name | Category | Cost | Markup
            NEG-1 | Negative Cost | Wire | -1 | 10
            NEG-2 | Negative Markup | Wire | 5 | -10
            """)
        ])

        #expect(preview.candidates.isEmpty)
        #expect(preview.errors.contains { $0.message == "cost_price cannot be negative" })
        #expect(preview.errors.contains { $0.message == "markup_percent cannot be negative" })
    }
}
