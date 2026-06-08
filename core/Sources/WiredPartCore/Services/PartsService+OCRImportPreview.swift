import Foundation

// MARK: - PDF/OCR Import Preview Prototype

extension PartsService {
    /// One page of text extracted from a PDF/image OCR pass.
    ///
    /// Platform UI/adapters can use Apple Vision/VisionKit to produce these pages;
    /// the core importer stays deterministic so chunking and row normalization are
    /// testable without image fixtures or device-only frameworks.
    public struct PartsOCRTextPage: Sendable {
        public let pageNumber: Int
        public let text: String

        public init(pageNumber: Int, text: String) {
            self.pageNumber = pageNumber
            self.text = text
        }
    }

    /// Small evidence chunk from extracted OCR text.
    public struct PartsOCRImportChunk: Sendable, Identifiable {
        public let id: String
        public let sourceKind: PartsImportSourceKind
        public let pageNumber: Int
        public let text: String
        public let snippet: String

        public init(
            id: String,
            sourceKind: PartsImportSourceKind = .ocr,
            pageNumber: Int,
            text: String,
            snippet: String
        ) {
            self.id = id
            self.sourceKind = sourceKind
            self.pageNumber = pageNumber
            self.text = text
            self.snippet = snippet
        }
    }

    /// Proposed import row detected from OCR text. It is intentionally not a
    /// commit-ready CSV row: every field carries source evidence for human/AI review.
    public struct PartsOCRImportCandidate: Sendable {
        public let rowNumber: Int
        public let chunkId: String
        public let pageNumber: Int
        public let sourceSnippet: String
        public let sourceKind: PartsImportSourceKind
        public let sourceEvidence: PartsImportSourceEvidence
        public let confidence: Double
        public let isQuarantined: Bool
        public let quarantineReason: String?
        public let name: String
        public let code: String?
        public let category: String
        public let brand: String?
        public let fields: [String: String]

        public init(
            rowNumber: Int,
            chunkId: String,
            pageNumber: Int,
            sourceSnippet: String,
            sourceKind: PartsImportSourceKind = .ocr,
            sourceEvidence: PartsImportSourceEvidence? = nil,
            confidence: Double,
            isQuarantined: Bool = false,
            quarantineReason: String? = nil,
            name: String,
            code: String?,
            category: String,
            brand: String?,
            fields: [String: String]
        ) {
            self.rowNumber = rowNumber
            self.chunkId = chunkId
            self.pageNumber = pageNumber
            self.sourceSnippet = sourceSnippet
            self.sourceKind = sourceKind
            self.sourceEvidence = sourceEvidence ?? PartsImportSourceEvidence(
                kind: .textBlock,
                pageNumber: pageNumber,
                text: sourceSnippet,
                confidence: confidence
            )
            self.confidence = confidence
            self.isQuarantined = isQuarantined
            self.quarantineReason = quarantineReason
            self.name = name
            self.code = code
            self.category = category
            self.brand = brand
            self.fields = fields
        }
    }

    /// Validation issue surfaced while normalizing an OCR candidate row.
    public struct PartsOCRImportError: Error, Sendable {
        public let pageNumber: Int
        public let sourceSnippet: String
        public let message: String

        public init(pageNumber: Int, sourceSnippet: String, message: String) {
            self.pageNumber = pageNumber
            self.sourceSnippet = sourceSnippet
            self.message = message
        }
    }

    /// Preview-only result for OCR/PDF imports. No commit entry point consumes this
    /// type yet; `isCommitAllowed` remains false until evidence review UX/rules are approved.
    public struct PartsOCRImportPreview: Sendable {
        public let chunks: [PartsOCRImportChunk]
        public let tables: [PartsImportExtractedTable]
        public let candidates: [PartsOCRImportCandidate]
        public let errors: [PartsOCRImportError]
        public let isCommitAllowed: Bool
        public var quarantinedCandidates: [PartsOCRImportCandidate] {
            candidates.filter(\.isQuarantined)
        }

        public var reviewReadyCandidates: [PartsOCRImportCandidate] {
            candidates.filter { !$0.isQuarantined }
        }

        public init(
            chunks: [PartsOCRImportChunk],
            tables: [PartsImportExtractedTable] = [],
            candidates: [PartsOCRImportCandidate],
            errors: [PartsOCRImportError],
            isCommitAllowed: Bool = false
        ) {
            self.chunks = chunks
            self.tables = tables
            self.candidates = candidates
            self.errors = errors
            self.isCommitAllowed = isCommitAllowed
        }
    }

    /// Deterministically chunk OCR text and detect likely parts table rows.
    ///
    /// This is a preview-only prototype: it normalizes likely rows and evidence,
    /// but does not write to the database and deliberately does not expose a commit flow.
    public func previewPartsImportOCR(
        pages: [PartsOCRTextPage],
        chunkLineLimit: Int = 8
    ) throws -> PartsOCRImportPreview {
        let cleanedPages = pages
            .filter { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .sorted { $0.pageNumber < $1.pageNumber }
        guard !cleanedPages.isEmpty else {
            throw PartsError.invalidInput("OCR import preview requires at least one page of extracted text.")
        }

        let safeChunkLineLimit = max(1, chunkLineLimit)
        let chunks = makeOCRImportChunks(pages: cleanedPages, chunkLineLimit: safeChunkLineLimit)
        let parsed = detectOCRImportRows(in: chunks)
        return PartsOCRImportPreview(
            chunks: chunks,
            tables: [],
            candidates: parsed.candidates,
            errors: parsed.errors,
            isCommitAllowed: false
        )
    }

    /// Preview text-layer PDF tables through the same evidence-bearing import contract.
    ///
    /// The caller owns actual PDF text extraction. Core receives deterministic page text,
    /// identifies table-shaped regions, then normalizes rows without writing to storage.
    public func previewPartsImportDigitalPDF(
        pages: [PartsOCRTextPage],
        chunkLineLimit: Int = 12
    ) throws -> PartsOCRImportPreview {
        let cleanedPages = pages
            .filter { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .sorted { $0.pageNumber < $1.pageNumber }
        guard !cleanedPages.isEmpty else {
            throw PartsError.invalidInput("Digital PDF import preview requires at least one page of extracted text.")
        }

        let tables = extractDigitalPDFTables(pages: cleanedPages)
        let chunks = makeOCRImportChunks(
            pages: cleanedPages,
            chunkLineLimit: max(1, chunkLineLimit),
            sourceKind: .digitalPDFText
        )
        let parsed = detectOCRImportRows(in: chunks)
        return PartsOCRImportPreview(
            chunks: chunks,
            tables: tables,
            candidates: parsed.candidates,
            errors: parsed.errors,
            isCommitAllowed: false
        )
    }

    /// Bridge externally generated OCR preview chunks/candidates into the shared preview model.
    public func previewPartsImportOCR(
        chunks: [PartsOCRImportChunk],
        candidates: [PartsOCRImportCandidate],
        errors: [PartsOCRImportError] = [],
        quarantineThreshold: Double = Double(OCRConfidence.medium)
    ) throws -> PartsOCRImportPreview {
        guard !chunks.isEmpty || !candidates.isEmpty else {
            throw PartsError.invalidInput("OCR import preview requires at least one chunk or candidate.")
        }
        let normalizedCandidates = candidates.map {
            quarantineOCRCandidateIfNeeded($0, threshold: quarantineThreshold)
        }
        return PartsOCRImportPreview(
            chunks: chunks,
            tables: [],
            candidates: normalizedCandidates,
            errors: errors,
            isCommitAllowed: false
        )
    }

    private func makeOCRImportChunks(
        pages: [PartsOCRTextPage],
        chunkLineLimit: Int,
        sourceKind: PartsImportSourceKind = .ocr
    ) -> [PartsOCRImportChunk] {
        var chunks: [PartsOCRImportChunk] = []
        for page in pages {
            let lines = normalizedOCRLines(page.text)
            guard !lines.isEmpty else { continue }

            var chunkNumber = 1
            var startIndex = 0
            while startIndex < lines.count {
                let endIndex = min(startIndex + chunkLineLimit, lines.count)
                let chunkLines = Array(lines[startIndex..<endIndex])
                let text = chunkLines.joined(separator: "\n")
                let id = "p\(page.pageNumber)-c\(chunkNumber)"
                chunks.append(PartsOCRImportChunk(
                    id: id,
                    sourceKind: sourceKind,
                    pageNumber: page.pageNumber,
                    text: text,
                    snippet: makeOCRSnippet(from: text)
                ))
                chunkNumber += 1
                startIndex = endIndex
            }
        }
        return chunks
    }

    private func detectOCRImportRows(
        in chunks: [PartsOCRImportChunk]
    ) -> (candidates: [PartsOCRImportCandidate], errors: [PartsOCRImportError]) {
        var candidates: [PartsOCRImportCandidate] = []
        var errors: [PartsOCRImportError] = []
        var activeHeader: OCRPartsHeader?
        var activePageNumber: Int?
        var rowNumber = 1

        for chunk in chunks {
            if activePageNumber != chunk.pageNumber {
                activePageNumber = chunk.pageNumber
                activeHeader = nil
            }
            for line in normalizedOCRLines(chunk.text) {
                let cells = splitOCRTableLine(line)
                guard cells.count >= 2 else { continue }

                if let header = parseOCRPartsHeader(cells) {
                    activeHeader = header
                    continue
                }
                guard let header = activeHeader else { continue }
                guard cells.count >= min(2, header.headers.count) else { continue }

                let normalized = normalizeOCRCandidate(cells: cells, header: header)
                let sourceSnippet = makeOCRSnippet(from: line)
                var rowErrors: [String] = []
                if normalized.name == nil || normalized.name?.isEmpty == true {
                    rowErrors.append("Missing required name")
                }
                if normalized.category == nil || normalized.category?.isEmpty == true {
                    rowErrors.append("Missing required category")
                }
                for numericHeader in ["cost_price", "markup_percent"] {
                    if let raw = normalized.fields[numericHeader] {
                        guard let value = Double(raw) else {
                            rowErrors.append("Invalid number for \(numericHeader): \(raw)")
                            continue
                        }
                        if value < 0 {
                            rowErrors.append("\(numericHeader) cannot be negative")
                        }
                    }
                }

                if !rowErrors.isEmpty {
                    for message in rowErrors {
                        errors.append(PartsOCRImportError(
                            pageNumber: chunk.pageNumber,
                            sourceSnippet: sourceSnippet,
                            message: message
                        ))
                    }
                    continue
                }

                guard let name = normalized.name, let category = normalized.category else { continue }
                let recognizedFieldCount = 2
                    + (normalized.code == nil ? 0 : 1)
                    + (normalized.brand == nil ? 0 : 1)
                    + normalized.fields.count
                let confidence = min(0.98, 0.70 + (Double(recognizedFieldCount) * 0.04))
                let sourceKind = chunk.sourceKind
                let evidence = PartsImportSourceEvidence(
                    kind: .textBlock,
                    pageNumber: chunk.pageNumber,
                    rowNumber: rowNumber,
                    text: sourceSnippet,
                    confidence: confidence
                )
                candidates.append(PartsOCRImportCandidate(
                    rowNumber: rowNumber,
                    chunkId: chunk.id,
                    pageNumber: chunk.pageNumber,
                    sourceSnippet: sourceSnippet,
                    sourceKind: sourceKind,
                    sourceEvidence: evidence,
                    confidence: confidence,
                    name: name,
                    code: normalized.code,
                    category: category,
                    brand: normalized.brand,
                    fields: normalized.fields
                ))
                rowNumber += 1
            }
        }
        return (candidates, errors)
    }

    private func extractDigitalPDFTables(pages: [PartsOCRTextPage]) -> [PartsImportExtractedTable] {
        var tables: [PartsImportExtractedTable] = []
        for page in pages {
            let lines = normalizedOCRLines(page.text)
            var tableNumber = 1
            var index = 0

            while index < lines.count {
                let headerCells = splitOCRTableLine(lines[index])
                guard parseOCRPartsHeader(headerCells) != nil else {
                    index += 1
                    continue
                }

                var rows: [PartsImportDraftRow] = []
                var rowIndex = index + 1
                while rowIndex < lines.count {
                    let rowCells = splitOCRTableLine(lines[rowIndex])
                    if parseOCRPartsHeader(rowCells) != nil { break }
                    if rowCells.count >= 2 {
                        let snippet = makeOCRSnippet(from: lines[rowIndex])
                        rows.append(PartsImportDraftRow(
                            rowNumber: rowIndex + 1,
                            columns: rowCells,
                            evidence: [
                                PartsImportSourceEvidence(
                                    kind: .row,
                                    pageNumber: page.pageNumber,
                                    rowNumber: rowIndex + 1,
                                    text: snippet
                                )
                            ]
                        ))
                    } else if !rows.isEmpty {
                        break
                    }
                    rowIndex += 1
                }

                if !rows.isEmpty {
                    let id = "pdf-p\(page.pageNumber)-t\(tableNumber)"
                    let sourceText = ([lines[index]] + rows.map { $0.columns.joined(separator: " | ") })
                        .joined(separator: "\n")
                    tables.append(PartsImportExtractedTable(
                        id: id,
                        sourceKind: .digitalPDFText,
                        pageNumber: page.pageNumber,
                        headerRowNumber: index + 1,
                        rows: rows,
                        evidence: [
                            PartsImportSourceEvidence(
                                kind: .textBlock,
                                pageNumber: page.pageNumber,
                                rowNumber: index + 1,
                                text: makeOCRSnippet(from: sourceText)
                            )
                        ]
                    ))
                    tableNumber += 1
                }
                index = max(rowIndex, index + 1)
            }
        }
        return tables
    }

    private func quarantineOCRCandidateIfNeeded(
        _ candidate: PartsOCRImportCandidate,
        threshold: Double
    ) -> PartsOCRImportCandidate {
        guard candidate.sourceKind == .ocr, candidate.confidence < threshold else { return candidate }
        return PartsOCRImportCandidate(
            rowNumber: candidate.rowNumber,
            chunkId: candidate.chunkId,
            pageNumber: candidate.pageNumber,
            sourceSnippet: candidate.sourceSnippet,
            sourceKind: candidate.sourceKind,
            sourceEvidence: candidate.sourceEvidence,
            confidence: candidate.confidence,
            isQuarantined: true,
            quarantineReason: "OCR confidence \(candidate.confidence) is below import preview threshold \(threshold).",
            name: candidate.name,
            code: candidate.code,
            category: candidate.category,
            brand: candidate.brand,
            fields: candidate.fields
        )
    }

    private struct OCRPartsHeader {
        let headers: [String]
    }

    private func parseOCRPartsHeader(_ cells: [String]) -> OCRPartsHeader? {
        let headers = cells.map(normalizeOCRHeader)
        let hasName = headers.contains("name") || headers.contains("description")
        let hasCategory = headers.contains("category")
        let hasCode = headers.contains("code") || headers.contains("part_number")
        guard hasName && (hasCategory || hasCode) else { return nil }
        return OCRPartsHeader(headers: headers)
    }

    private func normalizeOCRCandidate(
        cells: [String],
        header: OCRPartsHeader
    ) -> (name: String?, code: String?, category: String?, brand: String?, fields: [String: String]) {
        var name: String?
        var code: String?
        var category: String?
        var brand: String?
        var fields: [String: String] = [:]

        for (index, headerName) in header.headers.enumerated() {
            guard index < cells.count else { continue }
            let value = cells[index].trimmingCharacters(in: .whitespacesAndNewlines)
            guard !value.isEmpty else { continue }

            switch headerName {
            case "name": name = value
            case "code", "part_number": code = value
            case "category": category = value
            case "brand": brand = value
            case "cost", "cost_price", "price": fields["cost_price"] = value
            case "markup", "markup_percent": fields["markup_percent"] = value
            case "unit", "unit_of_measure", "uom": fields["unit_of_measure"] = value
            case "description":
                if name == nil {
                    name = value
                } else {
                    fields["description"] = value
                }
            case "shelf", "shelf_location": fields["shelf_location"] = value
            case "bin", "bin_location": fields["bin_location"] = value
            case "part_type": fields["part_type"] = value
            default: break
            }
        }
        return (name, code, category, brand, fields)
    }

    private func normalizedOCRLines(_ text: String) -> [String] {
        text.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private func splitOCRTableLine(_ line: String) -> [String] {
        if line.contains("|") {
            return line.components(separatedBy: "|").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        }
        if line.contains("\t") {
            return line.components(separatedBy: "\t").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        }
        return splitOnRepeatedSpaces(line)
    }

    private func splitOnRepeatedSpaces(_ line: String) -> [String] {
        var cells: [String] = []
        var current = ""
        var spaceRun = 0
        for char in line {
            if char == " " {
                spaceRun += 1
                if spaceRun < 2 {
                    current.append(char)
                }
            } else {
                if spaceRun >= 2 {
                    let trimmed = current.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !trimmed.isEmpty { cells.append(trimmed) }
                    current = ""
                }
                spaceRun = 0
                current.append(char)
            }
        }
        let trimmed = current.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { cells.append(trimmed) }
        return cells
    }

    private func normalizeOCRHeader(_ raw: String) -> String {
        let lowered = raw
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "#", with: " number ")
            .replacingOccurrences(of: "%", with: " percent ")
        let tokens = lowered
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
        let joined = tokens.joined(separator: "_")

        switch joined {
        case "part", "part_name", "item", "item_name", "description_name": return "name"
        case "sku", "part_no", "part_number", "part_num", "item_no", "item_number": return "part_number"
        case "code", "part_code", "item_code": return "code"
        case "cat", "category", "class": return "category"
        case "brand", "manufacturer", "mfr": return "brand"
        case "cost", "unit_cost", "price", "unit_price": return "cost_price"
        case "markup", "markup_percent", "margin": return "markup_percent"
        case "unit", "uom", "unit_of_measure": return "unit_of_measure"
        case "desc", "description", "notes": return "description"
        case "shelf", "shelf_location": return "shelf_location"
        case "bin", "bin_location": return "bin_location"
        case "type", "part_type": return "part_type"
        default: return joined
        }
    }

    private func makeOCRSnippet(from text: String, limit: Int = 160) -> String {
        let singleLine = text
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard singleLine.count > limit else { return singleLine }
        return String(singleLine.prefix(limit)).trimmingCharacters(in: .whitespacesAndNewlines) + "…"
    }
}
