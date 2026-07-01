import Testing
import Foundation
@testable import WiredPartCore

@Suite("QR Label Generator Tests")
struct QRLabelGeneratorTests {

    @Test("Sticker sheet exposes every position when no positions are used")
    func testNoUsedStickerPositionsExposeFullSheet() throws {
        let grid = try #require(QRPaperSize.avery5160.labelGrid)

        let positions = QRLabelPDFGenerator.availableStickerPositions(grid: grid, usedPositions: [])

        #expect(positions.count == grid.totalPositions)
        #expect(QRLabelPDFGenerator.availableStickerPositionCount(grid: grid, usedPositions: []) == grid.totalPositions)
        #expect(positions.first?.col == 0)
        #expect(positions.first?.row == 0)
        #expect(positions.last?.col == grid.columns - 1)
        #expect(positions.last?.row == grid.rows - 1)
    }

    @Test("Sticker sheet skips only the already-used positions")
    func testPartialUsedStickerPositionsReduceFirstPageCapacity() throws {
        let grid = try #require(QRPaperSize.avery5160.labelGrid)
        let usedPositions: Set<Int> = [0, 1, grid.totalPositions - 1]

        let positions = QRLabelPDFGenerator.availableStickerPositions(grid: grid, usedPositions: usedPositions)

        #expect(positions.count == grid.totalPositions - usedPositions.count)
        #expect(positions.first?.col == 2)
        #expect(positions.first?.row == 0)
        #expect(positions.last?.col == grid.columns - 2)
        #expect(positions.last?.row == grid.rows - 1)
    }

    @Test("Sticker sheet reports no printable positions when every position is already used")
    func testAllUsedStickerPositionsAreRejected() throws {
        let grid = try #require(QRPaperSize.avery5160.labelGrid)
        let usedPositions = Set(0..<grid.totalPositions)
        let item = QRLabelContent(entityType: .part, entityId: 1, code: "PART-001", title: "Part 001")

        #expect(QRLabelPDFGenerator.availableStickerPositionCount(grid: grid, usedPositions: usedPositions) == 0)
        #expect(QRLabelPDFGenerator.availableStickerPositions(grid: grid, usedPositions: usedPositions).isEmpty)
        #expect(QRLabelPDFGenerator.generatePDF(
            items: [item],
            labelSize: .standard,
            layout: .qrLeft,
            paperSize: .avery5160,
            usedPositions: usedPositions
        ) == nil)
    }

    @Test("Sticker sheet ignores invalid used-position indexes")
    func testInvalidUsedStickerPositionsDoNotReducePrintableCapacity() throws {
        let grid = try #require(QRPaperSize.avery5160.labelGrid)
        let usedPositions: Set<Int> = [-1, grid.totalPositions, grid.totalPositions + 10]

        #expect(QRLabelPDFGenerator.availableStickerPositionCount(grid: grid, usedPositions: usedPositions) == grid.totalPositions)
    }

    @Test("QR label PDF generation fails closed when any label QR image cannot render")
    func testQRCodePreflightFailsWhenAnyLabelImageCannotRender() {
        let items = [
            QRLabelContent(entityType: .part, entityId: 1, code: "PART-001", title: "Part 001"),
            QRLabelContent(entityType: .part, entityId: 2, code: "PART-002", title: "Part 002")
        ]

        let canRender = QRLabelPDFGenerator.canRenderAllLabelQRCodes(
            items: items,
            labelSize: .standard,
            paperSize: .avery5160,
            qrImageProvider: { type, id, code, size in
                guard id != 2 else { return nil }
                return QRGenerator.generate(type: type, id: id, code: code, size: size)
            }
        )

        #expect(canRender == false)

        var requestedIds: [Int64] = []
        let pdfData = QRLabelPDFGenerator.generatePDF(
            items: items,
            labelSize: .standard,
            layout: .qrLeft,
            paperSize: .avery5160,
            qrImageProvider: { type, id, code, size in
                requestedIds.append(id)
                guard id != 2 else { return nil }
                return QRGenerator.generate(type: type, id: id, code: code, size: size)
            }
        )

        #expect(pdfData == nil)
        #expect(requestedIds == [1, 2])
    }
}
