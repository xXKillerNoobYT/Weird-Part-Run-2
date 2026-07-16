import Foundation
import Testing
@testable import WiredPartCore

@Suite("Parts PDF/OCR import preview tests")
struct PartsOCRImportPreviewTests {
    @Test("previewPartsImportDigitalPDF extracts text-layer tables with page evidence")
    func previewPartsImportDigitalPDFExtractsTablesWithEvidence() throws {
        let env = try E2ETestHelpers.setUp()

        let preview = try env.parts.previewPartsImportDigitalPDF(pages: [
            .init(pageNumber: 7, text: """
            Supplier PDF Quote
            Part # | Description | Category | Unit Cost | UOM
            PDF-1 | Digital PDF Breaker | Electrical | 42.25 | each
            PDF-2 | Digital PDF Wire | Wire | 18.00 | roll
            Terms net 30
            """)
        ])

        let table = try #require(preview.tables.first)
        #expect(table.id == "pdf-p7-t1")
        #expect(table.sourceKind == .digitalPDFText)
        #expect(table.pageNumber == 7)
        #expect(table.headerRowNumber == 2)
        #expect(table.rows.count == 2)
        #expect(table.evidence.contains { $0.text?.contains("Digital PDF Breaker") == true })

        let breaker = try #require(preview.candidates.first { $0.code == "PDF-1" })
        #expect(breaker.sourceKind == .digitalPDFText)
        #expect(breaker.sourceEvidence.kind == .textBlock)
        #expect(breaker.sourceEvidence.pageNumber == 7)
        #expect(breaker.sourceEvidence.text?.contains("Digital PDF Breaker") == true)
        #expect(breaker.sourceSnippet.contains("Digital PDF Breaker"))
    }

    @Test("previewPartsImportOCR bridges existing OCR chunks and candidates into shared preview")
    func previewPartsImportOCRBridgesExistingChunksAndCandidates() throws {
        let env = try E2ETestHelpers.setUp()

        let chunk = PartsService.PartsOCRImportChunk(
            id: "ocr-p1-c1",
            pageNumber: 1,
            text: "OCR-1 | Existing OCR Candidate | Wire",
            snippet: "OCR-1 | Existing OCR Candidate | Wire"
        )
        let candidate = PartsService.PartsOCRImportCandidate(
            rowNumber: 1,
            chunkId: chunk.id,
            pageNumber: 1,
            sourceSnippet: chunk.snippet,
            confidence: 0.92,
            name: "Existing OCR Candidate",
            code: "OCR-1",
            category: "Wire",
            brand: nil,
            fields: [:]
        )

        let preview = try env.parts.previewPartsImportOCR(chunks: [chunk], candidates: [candidate])

        #expect(preview.chunks.count == 1)
        #expect(preview.candidates.count == 1)
        #expect(preview.candidates.first?.sourceKind == .ocr)
        #expect(preview.candidates.first?.sourceEvidence.rowNumber == 1)
        #expect(preview.reviewReadyCandidates.count == 1)
        #expect(preview.quarantinedCandidates.isEmpty)
        #expect(preview.isCommitAllowed == false)
    }

    @Test("previewPartsImportOCR retains Description when an explicit Name header exists")
    func previewPartsImportOCRRetainsDescriptionAlongsideExplicitName() throws {
        let env = try E2ETestHelpers.setUp()

        let preview = try env.parts.previewPartsImportOCR(pages: [
            .init(pageNumber: 6, text: """
            Description | Name | Code | Category
            Flexible copper conductor | 14 AWG THHN Wire | W-14 | Wire
            """)
        ])

        let candidate = try #require(preview.candidates.first)
        #expect(candidate.name == "14 AWG THHN Wire")
        #expect(candidate.fields["description"] == "Flexible copper conductor")
    }

    @Test("previewPartsImportOCR uses Description as name when no Name header exists")
    func previewPartsImportOCRUsesDescriptionAsNameFallback() throws {
        let env = try E2ETestHelpers.setUp()

        let preview = try env.parts.previewPartsImportOCR(pages: [
            .init(pageNumber: 7, text: """
            Description | Code | Category
            Description Only Breaker | BRK-1 | Electrical
            """)
        ])

        let candidate = try #require(preview.candidates.first)
        #expect(candidate.name == "Description Only Breaker")
        #expect(candidate.fields["description"] == nil)
    }

    @Test("previewPartsImportOCR quarantines low-confidence OCR candidates and does not write parts")
    func previewPartsImportOCRQuarantinesLowConfidenceCandidates() throws {
        let env = try E2ETestHelpers.setUp()
        let before = try env.parts.getImportExportStats()

        let candidate = PartsService.PartsOCRImportCandidate(
            rowNumber: 1,
            chunkId: "ocr-p2-c1",
            pageNumber: 2,
            sourceSnippet: "LOW-1 | Low Confidence OCR | Electrical",
            confidence: 0.42,
            name: "Low Confidence OCR",
            code: "LOW-1",
            category: "Electrical",
            brand: nil,
            fields: [:]
        )

        let preview = try env.parts.previewPartsImportOCR(chunks: [], candidates: [candidate])
        let after = try env.parts.getImportExportStats()

        let quarantined = try #require(preview.quarantinedCandidates.first)
        #expect(quarantined.code == "LOW-1")
        #expect(quarantined.isQuarantined)
        #expect(quarantined.quarantineReason?.contains("below import preview threshold") == true)
        #expect(preview.reviewReadyCandidates.isEmpty)
        #expect(preview.isCommitAllowed == false)
        #expect(after.totalParts == before.totalParts)
        #expect(try env.parts.findPartByCode("LOW-1") == nil)
    }

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
