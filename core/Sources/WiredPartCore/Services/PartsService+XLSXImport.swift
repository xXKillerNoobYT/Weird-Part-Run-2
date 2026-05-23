import Foundation
import ZIPFoundation

extension PartsService {
    /// Parse and validate the first worksheet of an XLSX workbook without changing database state.
    ///
    /// XLSX rows are normalized into the same draft row path used by CSV import so duplicate
    /// detection, validation, conflict generation, and atomic commit behavior stay shared.
    public func previewPartsImportXLSX(_ data: Data) throws -> PartsImportPreview {
        let workbook = try PartsImportXLSXReader(data: data).readFirstWorksheet()
        guard workbook.rows.count > 1 else {
            throw PartsError.invalidInput("XLSX sheet '\(workbook.sheetName)' is empty or has no data rows.")
        }

        let csv = workbook.rows
            .map { row in row.map(Self.escapeImportCSVField).joined(separator: ",") }
            .joined(separator: "\n")
        var preview: PartsImportPreview
        do {
            preview = try previewPartsImportCSV(csv)
        } catch PartsError.invalidInput(let message) {
            throw PartsError.invalidInput("XLSX sheet '\(workbook.sheetName)' row 1: \(message)")
        }

        preview.errors = preview.errors.map { error in
            PartsImportError(
                rowNumber: error.rowNumber,
                message: "XLSX sheet '\(workbook.sheetName)' row \(error.rowNumber): \(error.message)"
            )
        }
        return preview
    }

    private static func escapeImportCSVField(_ field: String) -> String {
        if field.contains(",") || field.contains("\"") || field.contains("\n") || field.contains("\r") {
            return "\"\(field.replacingOccurrences(of: "\"", with: "\"\""))\""
        }
        return field
    }
}

private struct PartsImportXLSXWorksheet {
    let sheetName: String
    let rows: [[String]]
}

private struct PartsImportXLSXReader {
    let entries: [String: Data]

    init(data: Data) throws {
        let archive: Archive
        do {
            archive = try Archive(data: data, accessMode: .read)
        } catch {
            throw PartsService.PartsError.invalidInput("Unsupported XLSX file: unable to open workbook archive.")
        }
        var extracted: [String: Data] = [:]
        for entry in archive {
            var entryData = Data()
            _ = try archive.extract(entry) { chunk in
                entryData.append(chunk)
            }
            extracted[entry.path] = entryData
        }
        self.entries = extracted
    }

    func readFirstWorksheet() throws -> PartsImportXLSXWorksheet {
        let workbookXML = try stringEntry("xl/workbook.xml", description: "workbook metadata")
        let sheets = workbookXML.xmlElements(named: "sheet")
        guard let firstSheet = sheets.first else {
            throw PartsService.PartsError.invalidInput("Unsupported XLSX file: workbook has no worksheets.")
        }

        let sheetName = firstSheet.xmlAttribute("name") ?? "Sheet1"
        let relationshipId = firstSheet.xmlAttribute("r:id") ?? firstSheet.xmlAttribute("id")
        let worksheetPath = try resolveWorksheetPath(relationshipId: relationshipId)
        let worksheetXML = try stringEntry(worksheetPath, description: "first worksheet")
        let sharedStrings = try readSharedStrings()
        let rows = try parseRows(from: worksheetXML, sharedStrings: sharedStrings)
        guard !rows.isEmpty else {
            throw PartsService.PartsError.invalidInput("Unsupported XLSX sheet '\(sheetName)': no readable rows found.")
        }
        return PartsImportXLSXWorksheet(sheetName: sheetName, rows: rows)
    }

    private func resolveWorksheetPath(relationshipId: String?) throws -> String {
        guard let relationshipId,
              let relsXML = try? stringEntry("xl/_rels/workbook.xml.rels", description: "workbook relationships") else {
            return "xl/worksheets/sheet1.xml"
        }

        for relationship in relsXML.xmlElements(named: "Relationship") {
            guard relationship.xmlAttribute("Id") == relationshipId,
                  var target = relationship.xmlAttribute("Target") else { continue }
            if target.hasPrefix("/") {
                target.removeFirst()
                return target
            }
            return "xl/\(target)".replacingOccurrences(of: "//", with: "/")
        }
        return "xl/worksheets/sheet1.xml"
    }

    private func readSharedStrings() throws -> [String] {
        guard let sharedXML = try? stringEntry("xl/sharedStrings.xml", description: "shared strings") else { return [] }
        return sharedXML.xmlElements(named: "si").map { item in
            let textRuns = item.xmlElements(named: "t")
            if textRuns.isEmpty { return "" }
            return textRuns.map { $0.xmlInnerText().xmlUnescaped }.joined()
        }
    }

    private func parseRows(from worksheetXML: String, sharedStrings: [String]) throws -> [[String]] {
        let rowElements = worksheetXML.xmlElements(named: "row")
        return rowElements.compactMap { rowElement in
            var cellsByColumn: [Int: String] = [:]
            var maxColumn = -1
            for cell in rowElement.xmlElements(named: "c") {
                guard let reference = cell.xmlAttribute("r"), let column = Self.columnIndex(from: reference) else { continue }
                maxColumn = max(maxColumn, column)
                cellsByColumn[column] = value(for: cell, sharedStrings: sharedStrings)
            }
            guard maxColumn >= 0 else { return nil }
            return (0...maxColumn).map { cellsByColumn[$0] ?? "" }
        }
    }

    private func value(for cell: String, sharedStrings: [String]) -> String {
        let type = cell.xmlAttribute("t")
        if type == "inlineStr" {
            return cell.xmlElements(named: "t").map { $0.xmlInnerText().xmlUnescaped }.joined()
        }
        let rawValue = cell.xmlFirstElement(named: "v")?.xmlInnerText().xmlUnescaped ?? ""
        if type == "s", let index = Int(rawValue), sharedStrings.indices.contains(index) {
            return sharedStrings[index]
        }
        return rawValue
    }

    private func stringEntry(_ path: String, description: String) throws -> String {
        guard let data = entries[path], let string = String(data: data, encoding: .utf8) else {
            throw PartsService.PartsError.invalidInput("Unsupported XLSX file: missing \(description) at \(path).")
        }
        return string
    }

    private static func columnIndex(from cellReference: String) -> Int? {
        let letters = cellReference.prefix { $0.isLetter }
        guard !letters.isEmpty else { return nil }
        var value = 0
        for scalar in String(letters).uppercased().unicodeScalars {
            guard scalar.value >= 65 && scalar.value <= 90 else { return nil }
            value = value * 26 + Int(scalar.value - 64)
        }
        return value - 1
    }
}

private extension String {
    func xmlElements(named name: String) -> [String] {
        var results: [String] = []
        var searchStart = startIndex
        let openingPrefix = "<\(name)"
        let closingTag = "</\(name)>"

        while let openRange = range(of: openingPrefix, range: searchStart..<endIndex) {
            let afterName = index(openRange.lowerBound, offsetBy: openingPrefix.count)
            guard afterName == endIndex || self[afterName].isWhitespace || self[afterName] == ">" || self[afterName] == "/" else {
                searchStart = afterName
                continue
            }
            guard let openEnd = range(of: ">", range: openRange.lowerBound..<endIndex)?.upperBound else { break }
            let tagEnd = index(before: openEnd)
            if tagEnd > openRange.lowerBound && self[index(before: tagEnd)] == "/" {
                results.append(String(self[openRange.lowerBound..<openEnd]))
                searchStart = openEnd
                continue
            }
            guard let closeRange = range(of: closingTag, range: openEnd..<endIndex) else { break }
            results.append(String(self[openRange.lowerBound..<closeRange.upperBound]))
            searchStart = closeRange.upperBound
        }

        return results
    }

    func xmlFirstElement(named name: String) -> String? {
        xmlElements(named: name).first
    }

    func xmlAttribute(_ name: String) -> String? {
        let escaped = NSRegularExpression.escapedPattern(for: name)
        let pattern = #"\b\#(escaped)\s*=\s*(["'])(.*?)\1"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { return nil }
        let range = NSRange(startIndex..<endIndex, in: self)
        guard let match = regex.firstMatch(in: self, options: [], range: range),
              match.numberOfRanges >= 3,
              let valueRange = Range(match.range(at: 2), in: self) else { return nil }
        return String(self[valueRange]).xmlUnescaped
    }

    func xmlInnerText() -> String {
        guard let openEnd = firstIndex(of: ">") else { return "" }
        if self[index(before: openEnd)] == "/" { return "" }
        guard let closeStart = range(of: "</", options: .backwards)?.lowerBound else { return "" }
        return String(self[index(after: openEnd)..<closeStart])
    }

    var xmlUnescaped: String {
        replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&apos;", with: "'")
            .replacingOccurrences(of: "&amp;", with: "&")
    }
}
