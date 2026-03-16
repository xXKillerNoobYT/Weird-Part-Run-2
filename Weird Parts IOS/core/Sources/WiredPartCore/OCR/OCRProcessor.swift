import Foundation
import GRDB

// MARK: - OCR Processor

/// Processes OCR-recognized text and extracts structured field data.
///
/// The OCR pipeline:
/// 1. Scanner adapter captures document image (platform-specific)
/// 2. OCR adapter recognizes text blocks with confidence scores
/// 3. **OCRProcessor** extracts structured fields (this class)
/// 4. UI displays extracted fields with confidence indicators
/// 5. User confirms/edits before committing to database
///
/// Field extraction uses regex patterns and fuzzy matching against
/// the local parts/suppliers database for entity-reference fields.
public final class OCRProcessor: Sendable {
    private let db: AppDatabase

    public init(db: AppDatabase) {
        self.db = db
    }

    // MARK: - Field Extraction

    /// Extract structured fields from OCR text blocks.
    ///
    /// Identifies common business document fields: PO numbers, quantities,
    /// dates, supplier names, part codes, and amounts.
    ///
    /// - Parameter textBlocks: Recognized text blocks from OCR adapter.
    /// - Returns: Extraction result with identified fields and confidences.
    public func extractFields(from textBlocks: [RecognizedTextBlock]) throws -> OCRExtractionResult {
        let fullText = textBlocks.map(\.text).joined(separator: "\n")
        var fields: [ExtractedField] = []

        // Extract PO numbers
        if let poField = extractPONumber(from: fullText, blocks: textBlocks) {
            fields.append(poField)
        }

        // Extract dates
        fields.append(contentsOf: extractDates(from: fullText, blocks: textBlocks))

        // Extract quantities and amounts
        fields.append(contentsOf: extractQuantitiesAndAmounts(from: fullText, blocks: textBlocks))

        // Extract supplier names via DB lookup
        let supplierFields = try extractSupplierReferences(from: fullText)
        fields.append(contentsOf: supplierFields)

        // Extract part codes via DB lookup
        let partFields = try extractPartReferences(from: fullText)
        fields.append(contentsOf: partFields)

        // Calculate overall confidence
        let avgConfidence: Float = fields.isEmpty ? 0.0 :
            fields.map(\.confidence).reduce(0, +) / Float(fields.count)

        let needsRescan = avgConfidence < OCRConfidence.rescanThreshold && !fields.isEmpty

        return OCRExtractionResult(
            fields: fields,
            rawText: fullText,
            overallConfidence: avgConfidence,
            needsRescan: needsRescan,
            pageCount: 1
        )
    }

    // MARK: - PO Number Extraction

    private func extractPONumber(
        from text: String,
        blocks: [RecognizedTextBlock]
    ) -> ExtractedField? {
        // Common PO number patterns:
        // PO #12345, PO# 12345, P.O. 12345, Purchase Order 12345, PO-12345
        let patterns = [
            "(?i)(?:P\\.?O\\.?\\s*#?\\s*|Purchase\\s+Order\\s*#?\\s*)([A-Z0-9][A-Z0-9\\-]{2,20})",
        ]

        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern),
                  let match = regex.firstMatch(
                      in: text,
                      range: NSRange(text.startIndex..., in: text)
                  ),
                  let range = Range(match.range(at: 1), in: text) else { continue }

            let poNumber = String(text[range])
            // Find the block that contains this text for confidence
            let blockConfidence = blocks.first { $0.text.contains(poNumber) }?.confidence ?? 0.85

            return ExtractedField(
                fieldType: .poNumber,
                value: poNumber,
                confidence: blockConfidence,
                label: "PO Number"
            )
        }
        return nil
    }

    // MARK: - Date Extraction

    private func extractDates(
        from text: String,
        blocks: [RecognizedTextBlock]
    ) -> [ExtractedField] {
        var fields: [ExtractedField] = []

        // Common date patterns: MM/DD/YYYY, MM-DD-YYYY, Month DD, YYYY
        let datePatterns = [
            ("\\b(\\d{1,2}[/\\-]\\d{1,2}[/\\-]\\d{2,4})\\b", "date"),
            ("(?i)\\b((?:Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec)[a-z]*\\s+\\d{1,2},?\\s*\\d{4})\\b", "date"),
        ]

        for (pattern, _) in datePatterns {
            guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
            let matches = regex.matches(in: text, range: NSRange(text.startIndex..., in: text))

            for match in matches.prefix(3) { // Limit to 3 dates
                guard let range = Range(match.range(at: 1), in: text) else { continue }
                let dateString = String(text[range])
                let blockConfidence = blocks.first { $0.text.contains(dateString) }?.confidence ?? 0.80

                fields.append(ExtractedField(
                    fieldType: .date,
                    value: dateString,
                    confidence: blockConfidence,
                    label: "Date"
                ))
            }
        }

        return fields
    }

    // MARK: - Quantity & Amount Extraction

    private func extractQuantitiesAndAmounts(
        from text: String,
        blocks: [RecognizedTextBlock]
    ) -> [ExtractedField] {
        var fields: [ExtractedField] = []

        // Quantity patterns: "Qty: 42", "Quantity 42", "x42", "42 ea", "42 pcs"
        let qtyPattern = "(?i)(?:qty\\.?|quantity):?\\s*(\\d+)"
        if let regex = try? NSRegularExpression(pattern: qtyPattern) {
            let matches = regex.matches(in: text, range: NSRange(text.startIndex..., in: text))
            for match in matches.prefix(5) {
                guard let range = Range(match.range(at: 1), in: text) else { continue }
                let value = String(text[range])
                let blockConfidence = blocks.first { $0.text.contains(value) }?.confidence ?? 0.80
                fields.append(ExtractedField(
                    fieldType: .quantity,
                    value: value,
                    confidence: blockConfidence,
                    label: "Quantity"
                ))
            }
        }

        // Dollar amount patterns: $1,234.56
        let amountPattern = "\\$([\\d,]+\\.\\d{2})"
        if let regex = try? NSRegularExpression(pattern: amountPattern) {
            let matches = regex.matches(in: text, range: NSRange(text.startIndex..., in: text))
            for match in matches.prefix(5) {
                guard let range = Range(match.range(at: 1), in: text) else { continue }
                let value = String(text[range])
                let blockConfidence = blocks.first { $0.text.contains(value) }?.confidence ?? 0.80
                fields.append(ExtractedField(
                    fieldType: .amount,
                    value: value,
                    confidence: blockConfidence,
                    label: "Amount"
                ))
            }
        }

        return fields
    }

    // MARK: - Supplier Reference Extraction

    private func extractSupplierReferences(from text: String) throws -> [ExtractedField] {
        // Load supplier names from DB and fuzzy-match against OCR text
        let supplierNames: [String] = try db.writer.read { dbConnection in
            try String.fetchAll(
                dbConnection,
                sql: "SELECT name FROM suppliers WHERE deleted_at IS NULL"
            )
        }

        var fields: [ExtractedField] = []
        let lowered = text.lowercased()

        for name in supplierNames {
            if lowered.contains(name.lowercased()) {
                fields.append(ExtractedField(
                    fieldType: .supplierName,
                    value: name,
                    confidence: 0.95,
                    label: "Supplier"
                ))
            }
        }

        return fields
    }

    // MARK: - Part Reference Extraction

    private func extractPartReferences(from text: String) throws -> [ExtractedField] {
        // Load part codes from DB and match against OCR text
        let partCodes: [(code: String, name: String)] = try db.writer.read { dbConnection in
            try Row.fetchAll(
                dbConnection,
                sql: "SELECT code, name FROM parts WHERE code IS NOT NULL AND deleted_at IS NULL"
            ).compactMap { row in
                guard let code = row["code"] as? String,
                      let name = row["name"] as? String else { return nil }
                return (code: code, name: name)
            }
        }

        var fields: [ExtractedField] = []
        let uppered = text.uppercased()

        for part in partCodes {
            if uppered.contains(part.code.uppercased()) {
                fields.append(ExtractedField(
                    fieldType: .partCode,
                    value: part.code,
                    confidence: 0.90,
                    label: "Part: \(part.name)"
                ))
            }
        }

        return fields
    }
}

// MARK: - Extraction Result

/// Result of OCR field extraction from a scanned document.
public struct OCRExtractionResult: Sendable {
    public let fields: [ExtractedField]
    public let rawText: String
    public let overallConfidence: Float
    public let needsRescan: Bool
    public let pageCount: Int

    /// Fields grouped by confidence tier for display.
    public var highConfidenceFields: [ExtractedField] {
        fields.filter { OCRConfidence.tier(for: $0.confidence) == .high }
    }

    public var mediumConfidenceFields: [ExtractedField] {
        fields.filter { OCRConfidence.tier(for: $0.confidence) == .medium }
    }

    public var lowConfidenceFields: [ExtractedField] {
        fields.filter { OCRConfidence.tier(for: $0.confidence) == .low }
    }
}

// MARK: - Extracted Field

/// A single field extracted from OCR text.
public struct ExtractedField: Sendable, Identifiable {
    public let id = UUID()
    public let fieldType: OCRFieldType
    public let value: String
    public let confidence: Float
    public let label: String

    /// The confidence tier for this field.
    public var tier: ConfidenceTier {
        OCRConfidence.tier(for: confidence)
    }

    /// Whether this field is reliable enough for auto-fill.
    public var isAutoFillReady: Bool {
        confidence >= OCRConfidence.high
    }
}

// MARK: - OCR Field Types

/// Types of fields that can be extracted from scanned documents.
public enum OCRFieldType: String, Sendable {
    case poNumber = "po_number"
    case date
    case quantity
    case amount
    case supplierName = "supplier_name"
    case partCode = "part_code"
    case address
    case phoneNumber = "phone_number"
    case description
    case notes
}
