import Foundation
import ZIPFoundation

extension PartsService {
    /// Parse and validate the first worksheet of an XLSX workbook without changing database state.
    ///
    /// XLSX rows are normalized into the same draft row path used by CSV import so duplicate
    /// detection, validation, conflict generation, and atomic commit behavior stay shared.
    public func previewPartsImportXLSX(_ data: Data) throws -> PartsImportPreview {
        let parsedSource = try PartsImportXLSXAdapter(service: self).parse(data)
        let table = parsedSource.table
        let sheetName = table.sheetName ?? "Sheet1"
        guard table.rows.count > 1 else {
            throw PartsError.invalidInput("XLSX sheet '\(sheetName)' is empty or has no data rows.")
        }

        var preview: PartsImportPreview
        do {
            preview = try previewPartsImportRows(
                table.rows.map { PartsImportTabularRow(rowNumber: $0.rowNumber, columns: $0.columns) },
                emptyDescription: "XLSX sheet '\(sheetName)' is empty or has no data rows."
            )
        } catch PartsError.invalidInput(let message) {
            throw PartsError.invalidInput("XLSX sheet '\(sheetName)' row 1: \(message)")
        }

        preview.errors = preview.errors.map { error in
            PartsImportError(
                rowNumber: error.rowNumber,
                message: "XLSX sheet '\(sheetName)' row \(error.rowNumber): \(error.message)"
            )
        }
        preview.source = parsedSource.source
        return preview
    }

}

private struct PartsImportXLSXAdapter {
    let service: PartsService

    func parse(_ data: Data) throws -> PartsService.PartsImportParsedSource {
        let hash = service.importSourceHash(data)
        let workbook = try PartsImportXLSXReader(data: data).readWorkbook()
        let firstWorksheet = workbook.worksheets[0]
        let rows = firstWorksheet.rows.map { row in
            PartsService.PartsImportDraftRow(
                rowNumber: row.rowNumber,
                columns: row.columns,
                evidence: [
                    PartsService.PartsImportSourceEvidence(
                        kind: .row,
                        sheetName: firstWorksheet.sheet.name,
                        rowNumber: row.rowNumber
                    )
                ]
            )
        }
        let table = PartsService.PartsImportExtractedTable(
            id: "xlsx:\(firstWorksheet.sheet.index)",
            sourceKind: .xlsx,
            sourceName: firstWorksheet.sheet.name,
            sheetName: firstWorksheet.sheet.name,
            headerRowNumber: rows.first?.rowNumber,
            rows: rows,
            evidence: [PartsService.PartsImportSourceEvidence(kind: .sourceHash, text: hash)]
        )
        let parserMetadata = PartsService.PartsImportParserMetadata(
            parserName: "wiredpart.xlsx",
            parserVersion: "1",
            sourceKind: .xlsx,
            sourceHash: hash,
            rowCount: rows.count,
            columnCount: rows.map(\.columns.count).max() ?? 0,
            sheetMetadata: workbook.sheetMetadata,
            boundedArchiveProtectionsApplied: true
        )
        let source = PartsService.PartsImportSourceMetadata(
            sourceKind: PartsService.PartsImportSourceKind.xlsx.rawValue,
            sheetName: firstWorksheet.sheet.name,
            sourceHash: hash,
            parserMetadata: parserMetadata,
            evidence: table.evidence
        )
        return PartsService.PartsImportParsedSource(table: table, source: source)
    }
}

private struct PartsImportXLSXWorksheet {
    let sheet: PartsService.PartsImportWorkbookSheetMetadata
    let rows: [PartsImportXLSXRow]
}

private struct PartsImportXLSXWorkbook {
    let worksheets: [PartsImportXLSXWorksheet]

    var sheetMetadata: [PartsService.PartsImportWorkbookSheetMetadata] {
        worksheets.map(\.sheet)
    }
}

private struct PartsImportXLSXRow {
    let rowNumber: Int
    let columns: [String]
}

private struct PartsImportXLSXReader {
    private static let maxArchiveEntries = 2_048
    private static let maxEntrySize = 5 * 1024 * 1024
    private static let maxTotalExtractedSize = 25 * 1024 * 1024

    let entries: [String: Data]

    init(data: Data) throws {
        let archive: Archive
        do {
            archive = try Archive(data: data, accessMode: .read)
        } catch {
            throw PartsService.PartsError.invalidInput("Unsupported XLSX file: unable to open workbook archive.")
        }

        var extracted = try Self.extractEntries(
            from: archive,
            wantedPaths: ["xl/workbook.xml", "xl/_rels/workbook.xml.rels"]
        )
        guard let workbookData = extracted["xl/workbook.xml"],
              let workbookXML = String(data: workbookData, encoding: .utf8) else {
            throw PartsService.PartsError.invalidInput("Unsupported XLSX file: missing workbook metadata at xl/workbook.xml.")
        }
        let relationshipXML = extracted["xl/_rels/workbook.xml.rels"].flatMap { String(data: $0, encoding: .utf8) }
        let worksheetPaths = workbookXML.xmlElements(named: "sheet").map { sheet in
            Self.resolveWorksheetPath(
                relationshipId: sheet.xmlAttribute("r:id") ?? sheet.xmlAttribute("id"),
                relationshipsXML: relationshipXML
            )
        }
        let wantedSheetPaths = worksheetPaths.isEmpty ? ["xl/worksheets/sheet1.xml"] : worksheetPaths

        let sheetEntries = try Self.extractEntries(
            from: archive,
            wantedPaths: Set(wantedSheetPaths + ["xl/sharedStrings.xml"])
        )
        for (path, data) in sheetEntries {
            extracted[path] = data
        }
        self.entries = extracted
    }

    private static func extractEntries(from archive: Archive, wantedPaths: Set<String>) throws -> [String: Data] {
        var extracted: [String: Data] = [:]
        var scannedEntryCount = 0
        var totalExtractedSize = 0
        for entry in archive {
            scannedEntryCount += 1
            guard scannedEntryCount <= maxArchiveEntries else {
                throw PartsService.PartsError.invalidInput("Unsupported XLSX file: workbook archive has too many entries.")
            }
            guard wantedPaths.contains(entry.path) else { continue }
            let advertisedSize = Int(entry.uncompressedSize)
            guard advertisedSize <= maxEntrySize else {
                throw PartsService.PartsError.invalidInput("Unsupported XLSX file: entry \(entry.path) is too large.")
            }
            totalExtractedSize += advertisedSize
            guard totalExtractedSize <= maxTotalExtractedSize else {
                throw PartsService.PartsError.invalidInput("Unsupported XLSX file: extracted workbook data is too large.")
            }

            var entryData = Data()
            _ = try archive.extract(entry) { chunk in
                entryData.append(chunk)
            }
            guard entryData.count <= maxEntrySize else {
                throw PartsService.PartsError.invalidInput("Unsupported XLSX file: entry \(entry.path) is too large.")
            }
            extracted[entry.path] = entryData
        }
        return extracted
    }

    private static func resolveWorksheetPath(relationshipId: String?, relationshipsXML: String?) -> String {
        guard let relationshipId, let relationshipsXML else {
            return "xl/worksheets/sheet1.xml"
        }
        for relationship in relationshipsXML.xmlElements(named: "Relationship") {
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

    func readWorkbook() throws -> PartsImportXLSXWorkbook {
        let workbookXML = try stringEntry("xl/workbook.xml", description: "workbook metadata")
        let sheets = workbookXML.xmlElements(named: "sheet")
        guard !sheets.isEmpty else {
            throw PartsService.PartsError.invalidInput("Unsupported XLSX file: workbook has no worksheets.")
        }
        let sharedStrings = try readSharedStrings()
        let worksheets = try sheets.enumerated().map { offset, sheetElement -> PartsImportXLSXWorksheet in
            let sheetName = sheetElement.xmlAttribute("name") ?? "Sheet\(offset + 1)"
            let relationshipId = sheetElement.xmlAttribute("r:id") ?? sheetElement.xmlAttribute("id")
            let worksheetPath = try resolveWorksheetPath(relationshipId: relationshipId)
            let worksheetXML = try stringEntry(worksheetPath, description: "worksheet \(sheetName)")
            let rows = try parseRows(from: worksheetXML, sharedStrings: sharedStrings)
            let metadata = PartsService.PartsImportWorkbookSheetMetadata(
                index: offset,
                name: sheetName,
                relationshipId: relationshipId,
                path: worksheetPath,
                rowCount: rows.count,
                columnCount: rows.map(\.columns.count).max() ?? 0
            )
            return PartsImportXLSXWorksheet(sheet: metadata, rows: rows)
        }
        guard let first = worksheets.first, !first.rows.isEmpty else {
            throw PartsService.PartsError.invalidInput("Unsupported XLSX sheet '\(worksheets.first?.sheet.name ?? "Sheet1")': no readable rows found.")
        }
        return PartsImportXLSXWorkbook(worksheets: worksheets)
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

    private func parseRows(from worksheetXML: String, sharedStrings: [String]) throws -> [PartsImportXLSXRow] {
        let rowElements = worksheetXML.xmlElements(named: "row")
        return rowElements.enumerated().compactMap { offset, rowElement in
            var cellsByColumn: [Int: String] = [:]
            var maxColumn = -1
            var spreadsheetRowNumber = rowElement.xmlAttribute("r").flatMap(Int.init) ?? offset + 1
            for cell in rowElement.xmlElements(named: "c") {
                guard let reference = cell.xmlAttribute("r"), let column = Self.columnIndex(from: reference) else { continue }
                if let cellRowNumber = Self.rowNumber(from: reference) {
                    spreadsheetRowNumber = cellRowNumber
                }
                maxColumn = max(maxColumn, column)
                cellsByColumn[column] = value(for: cell, sharedStrings: sharedStrings)
            }
            guard maxColumn >= 0 else { return nil }
            return PartsImportXLSXRow(
                rowNumber: spreadsheetRowNumber,
                columns: (0...maxColumn).map { cellsByColumn[$0] ?? "" }
            )
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

    private static func rowNumber(from cellReference: String) -> Int? {
        let digits = cellReference.drop { $0.isLetter }
        guard !digits.isEmpty else { return nil }
        return Int(digits)
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
        let tagEnd = firstIndex(of: ">") ?? endIndex
        var cursor = startIndex

        func advancePastWhitespace() {
            while cursor < tagEnd, self[cursor].isWhitespace {
                cursor = index(after: cursor)
            }
        }

        while cursor < tagEnd {
            advancePastWhitespace()
            guard cursor < tagEnd else { break }
            if self[cursor] == "<" || self[cursor] == "/" {
                cursor = index(after: cursor)
                continue
            }

            let keyStart = cursor
            while cursor < tagEnd,
                  !self[cursor].isWhitespace,
                  self[cursor] != "=",
                  self[cursor] != "/",
                  self[cursor] != ">" {
                cursor = index(after: cursor)
            }
            let key = String(self[keyStart..<cursor])
            advancePastWhitespace()
            guard cursor < tagEnd, self[cursor] == "=" else { continue }
            cursor = index(after: cursor)
            advancePastWhitespace()
            guard cursor < tagEnd, self[cursor] == "\"" || self[cursor] == "'" else { continue }

            let quote = self[cursor]
            let valueStart = index(after: cursor)
            cursor = valueStart
            while cursor < tagEnd, self[cursor] != quote {
                cursor = index(after: cursor)
            }
            guard cursor < tagEnd else { break }
            let value = String(self[valueStart..<cursor])
            cursor = index(after: cursor)
            if key == name {
                return value.xmlUnescaped
            }
        }
        return nil
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
