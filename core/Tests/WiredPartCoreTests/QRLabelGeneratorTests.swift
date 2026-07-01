import Testing
import Foundation
import CoreGraphics
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

    @Test("PDF generation preflight rejects any label whose QR image cannot render")
    func testQRCodeRenderFailureRejectsWholeBatch() throws {
        let renderedImage = try #require(Self.makeTestImage())
        let items = [
            QRLabelContent(entityType: .part, entityId: 1, code: "PART-001", title: "Good part"),
            QRLabelContent(entityType: .part, entityId: 2, code: "PART-002", title: "Failing part")
        ]

        let canRender = QRLabelPDFGenerator.canRenderQRCodesForPDF(
            items: items,
            labelSize: .standard,
            paperSize: .avery5160
        ) { _, id, _, _ in
            id == 2 ? nil : renderedImage
        }

        #expect(canRender == false)
    }

    @Test("PDF generation preflight accepts a batch only when every QR image renders")
    func testQRCodeRenderPreflightAcceptsCompleteBatch() throws {
        let renderedImage = try #require(Self.makeTestImage())
        let items = [
            QRLabelContent(entityType: .part, entityId: 1, code: "PART-001", title: "Part 001"),
            QRLabelContent(entityType: .bin, entityId: 2, code: "BIN-002", title: "Bin 002")
        ]

        let canRender = QRLabelPDFGenerator.canRenderQRCodesForPDF(
            items: items,
            labelSize: .standard,
            paperSize: .letter
        ) { _, _, _, _ in
            renderedImage
        }

        #expect(canRender == true)
    }

    private static func makeTestImage() -> CGImage? {
        let colorSpace = CGColorSpaceCreateDeviceGray()
        guard let context = CGContext(
            data: nil,
            width: 1,
            height: 1,
            bitsPerComponent: 8,
            bytesPerRow: 1,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.none.rawValue
        ) else {
            return nil
        }
        return context.makeImage()
    }
}
