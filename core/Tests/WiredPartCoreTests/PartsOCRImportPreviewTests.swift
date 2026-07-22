import Foundation
import Testing
@testable import WiredPartCore

@Suite("Parts PDF/OCR import preview tests")
struct PartsOCRImportPreviewTests {
    @Test("previewPartsImportDigitalPDF rejects an empty page list")
    func previewPartsImportDigitalPDFRejectsEmptyPages() throws {
        let env = try E2ETestHelpers.setUp()

        #expect(throws: PartsService.PartsError.invalidInput(
            "Digital PDF import preview requires at least one page of extracted text."
        )) {
            _ = try env.parts.previewPartsImportDigitalPDF(pages: [])
        }
    }

    @Test("OCR and digital-PDF previews reject blank pages even when another page is valid")
    func previewPartsImportRejectsBlankPages() throws {
        let env = try E2ETestHelpers.setUp()
        let blankPage = PartsService.PartsOCRTextPage(pageNumber: 1, text: " \n\t ")
        let validPage = PartsService.PartsOCRTextPage(pageNumber: 2, text: """
        Code | Name | Category
        VALID-1 | Valid Preview Row | Electrical
        """)
        let invalidPageSets = [
            [blankPage],
            [blankPage, validPage]
        ]

        for pages in invalidPageSets {
            #expect(throws: PartsService.PartsError.invalidInput(
                "OCR import preview requires at least one page of extracted text."
            )) {
                _ = try env.parts.previewPartsImportOCR(pages: pages)
            }
            #expect(throws: PartsService.PartsError.invalidInput(
                "Digital PDF import preview requires at least one page of extracted text."
            )) {
                _ = try env.parts.previewPartsImportDigitalPDF(pages: pages)
            }
        }
    }

    @Test("previewPartsImportDigitalPDF extracts text-layer tables with page evidence")
    func previewPartsImportDigitalPDFExtractsTablesWithEvidence() throws {
        let env = try E2ETestHelpers.setUp()
        let before = try env.parts.getImportExportStats()

        let preview = try env.parts.previewPartsImportDigitalPDF(pages: [
            .init(pageNumber: 7, text: """
            Supplier PDF Quote
            Part # | Description | Category | Unit Cost | UOM
            PDF-1 | Digital PDF Breaker | Electrical | 42.25 | each
            PDF-2 | Digital PDF Wire | Wire | 18.00 | roll
            Terms net 30
            """)
        ])
        let after = try env.parts.getImportExportStats()

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
        #expect(breaker.rowNumber == 1)
        #expect(breaker.sourceEvidence.rowNumber == 3)
        #expect(table.rows.first { $0.columns.first == "PDF-1" }?.rowNumber == breaker.sourceEvidence.rowNumber)
        #expect(breaker.sourceEvidence.text?.contains("Digital PDF Breaker") == true)
        #expect(breaker.sourceSnippet.contains("Digital PDF Breaker"))
        #expect(preview.isCommitAllowed == false)
        #expect(after.totalParts == before.totalParts)
        #expect(try env.parts.findPartByCode("PDF-1") == nil)
    }

    @Test("previewPartsImportDigitalPDF preserves exact normalized source lines in table evidence")
    func previewPartsImportDigitalPDFPreservesExactSourceLinesInTableEvidence() throws {
        let env = try E2ETestHelpers.setUp()

        let preview = try env.parts.previewPartsImportDigitalPDF(pages: [
            .init(pageNumber: 4, text: """
            Code\tName\tCategory
            PDF-EXACT\tExact   Source\tElectrical
            """)
        ])

        let table = try #require(preview.tables.first)
        #expect(table.evidence.first?.text == "Code\tName\tCategory PDF-EXACT\tExact   Source\tElectrical")
    }

    @Test("previewPartsImportDigitalPDF preserves source rows across chunks")
    func previewPartsImportDigitalPDFPreservesSourceRowsAcrossChunks() throws {
        let env = try E2ETestHelpers.setUp()

        let preview = try env.parts.previewPartsImportDigitalPDF(pages: [
            .init(pageNumber: 9, text: """
            Supplier Quote
            Prepared for WiredPart
            Code | Name | Category
            PDF-10 | First Chunk Row | Electrical
            PDF-11 | Second Chunk Row | Wire
            PDF-12 | Third Chunk Row | Conduit
            """)
        ], chunkLineLimit: 2)

        let table = try #require(preview.tables.first)
        #expect(preview.chunks.count == 3)
        #expect(preview.candidates.map(\.rowNumber) == [1, 2, 3])

        for code in ["PDF-10", "PDF-11", "PDF-12"] {
            let candidate = try #require(preview.candidates.first { $0.code == code })
            let tableRow = try #require(table.rows.first { $0.columns.first == code })
            #expect(candidate.pageNumber == table.pageNumber)
            #expect(candidate.sourceEvidence.rowNumber == tableRow.rowNumber)
            #expect(candidate.sourceEvidence.rowNumber == tableRow.evidence.first?.rowNumber)
        }
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

    @Test("previewPartsImportOCR bridge rejects empty chunks and candidates")
    func previewPartsImportOCRBridgeRejectsEmptyInput() throws {
        let env = try E2ETestHelpers.setUp()

        #expect(throws: PartsService.PartsError.invalidInput(
            "OCR import preview requires at least one chunk or candidate."
        )) {
            _ = try env.parts.previewPartsImportOCR(chunks: [], candidates: [])
        }
    }

    @Test("previewPartsImportOCR chunks safely when the public line limit is Int.max")
    func previewPartsImportOCRChunksSafelyWithMaximumLineLimit() throws {
        let env = try E2ETestHelpers.setUp()

        let preview = try env.parts.previewPartsImportOCR(
            pages: [
                .init(pageNumber: 1, text: """
                Code | Name | Category
                MAX-1 | Maximum Chunk Limit | Wire
                """)
            ],
            chunkLineLimit: .max
        )

        #expect(preview.chunks.count == 1)
        #expect(preview.candidates.first?.code == "MAX-1")
    }

    @Test("previewPartsImportOCR rejects malformed confidence and threshold values")
    func previewPartsImportOCRRejectsMalformedConfidenceAndThresholdValues() throws {
        let env = try E2ETestHelpers.setUp()

        for confidence in [Double.nan, .infinity, -.infinity, -0.01, 1.01] {
            let candidate = bridgeCandidate(confidence: confidence)
            #expect(throws: PartsService.PartsError.invalidInput(
                "OCR candidate confidence must be a finite value between 0 and 1."
            )) {
                _ = try env.parts.previewPartsImportOCR(chunks: [], candidates: [candidate])
            }
        }

        for threshold in [Double.nan, .infinity, -.infinity, -0.01, 1.01] {
            let candidate = bridgeCandidate(confidence: 0.92)
            #expect(throws: PartsService.PartsError.invalidInput(
                "OCR quarantine threshold must be a finite value between 0 and 1."
            )) {
                _ = try env.parts.previewPartsImportOCR(
                    chunks: [],
                    candidates: [candidate],
                    quarantineThreshold: threshold
                )
            }
        }

        let malformedEvidence = bridgeCandidate(confidence: 0.92, evidenceConfidence: .nan)
        #expect(throws: PartsService.PartsError.invalidInput(
            "OCR candidate evidence confidence must be a finite value between 0 and 1."
        )) {
            _ = try env.parts.previewPartsImportOCR(chunks: [], candidates: [malformedEvidence])
        }
    }

    @Test("previewPartsImportOCR rejects non-OCR bridge inputs")
    func previewPartsImportOCRRejectsNonOCRBridgeInputs() throws {
        let env = try E2ETestHelpers.setUp()

        for sourceKind in [PartsService.PartsImportSourceKind.digitalPDFText, .vision] {
            let candidate = bridgeCandidate(confidence: 0.92, sourceKind: sourceKind)
            #expect(throws: PartsService.PartsError.invalidInput(
                "OCR import preview only accepts OCR chunks and candidates."
            )) {
                _ = try env.parts.previewPartsImportOCR(chunks: [], candidates: [candidate])
            }
        }

        let nonOCRChunk = PartsService.PartsOCRImportChunk(
            id: "pdf-p1-c1",
            sourceKind: .digitalPDFText,
            pageNumber: 1,
            text: "PDF-1 | Not OCR | Wire",
            snippet: "PDF-1 | Not OCR | Wire"
        )
        #expect(throws: PartsService.PartsError.invalidInput(
            "OCR import preview only accepts OCR chunks and candidates."
        )) {
            _ = try env.parts.previewPartsImportOCR(chunks: [nonOCRChunk], candidates: [])
        }
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

    @Test("previewPartsImportOCR uses an exact default threshold and stable quarantine reason")
    func previewPartsImportOCRUsesExactThresholdAndStableQuarantineReason() throws {
        let env = try E2ETestHelpers.setUp()
        let candidate = bridgeCandidate(confidence: 0.69999999)

        let preview = try env.parts.previewPartsImportOCR(chunks: [], candidates: [candidate])

        let quarantined = try #require(preview.quarantinedCandidates.first)
        #expect(quarantined.quarantineReason == "OCR confidence 0.70 is below import preview threshold 0.70.")
        #expect(preview.reviewReadyCandidates.isEmpty)
    }

    @Test("previewPartsImportOCR preserves an upstream quarantine reason")
    func previewPartsImportOCRPreservesExistingQuarantine() throws {
        let env = try E2ETestHelpers.setUp()
        let candidate = PartsService.PartsOCRImportCandidate(
            rowNumber: 1,
            chunkId: "ocr-upstream",
            pageNumber: 2,
            sourceSnippet: "UPSTREAM-1 | Upstream Quarantine | Wire",
            confidence: 0.20,
            isQuarantined: true,
            quarantineReason: "Upstream parser rejected an ambiguous row.",
            name: "Upstream Quarantine",
            code: "UPSTREAM-1",
            category: "Wire",
            brand: nil,
            fields: [:]
        )

        let preview = try env.parts.previewPartsImportOCR(chunks: [], candidates: [candidate])

        let quarantined = try #require(preview.quarantinedCandidates.first)
        #expect(quarantined.quarantineReason == "Upstream parser rejected an ambiguous row.")
        #expect(preview.reviewReadyCandidates.isEmpty)
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

    private func bridgeCandidate(
        confidence: Double,
        sourceKind: PartsService.PartsImportSourceKind = .ocr,
        evidenceConfidence: Double? = nil
    ) -> PartsService.PartsOCRImportCandidate {
        let snippet = "OCR-1 | Bridge Candidate | Wire"
        let evidence = evidenceConfidence.map {
            PartsService.PartsImportSourceEvidence(
                kind: .textBlock,
                pageNumber: 1,
                rowNumber: 1,
                text: snippet,
                confidence: $0
            )
        }
        return PartsService.PartsOCRImportCandidate(
            rowNumber: 1,
            chunkId: "ocr-p1-c1",
            pageNumber: 1,
            sourceSnippet: snippet,
            sourceKind: sourceKind,
            sourceEvidence: evidence,
            confidence: confidence,
            name: "Bridge Candidate",
            code: "OCR-1",
            category: "Wire",
            brand: nil,
            fields: [:]
        )
    }
}
