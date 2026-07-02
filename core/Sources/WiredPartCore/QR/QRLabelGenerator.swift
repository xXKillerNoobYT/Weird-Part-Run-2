import Foundation
import CoreGraphics

#if canImport(UIKit)
import UIKit
#endif

// MARK: - Label Sizes

/// Physical label dimensions. All values in points (72 points = 1 inch).
public enum QRLabelSize: String, CaseIterable, Codable, Sendable {
    case square     // 2" × 2" — bins, tools
    case tall       // 1.5" × 3" — parts with long descriptions
    case wide       // 3" × 1.5" — shelf labels
    case long       // 4" × 1" — cable wraps, pipe labels
    case small      // 1" × 1" — tiny component labels
    case standard   // 2" × 1" — most common label

    public var displayName: String {
        switch self {
        case .square: return "Square (2×2\")"
        case .tall: return "Tall (1.5×3\")"
        case .wide: return "Wide (3×1.5\")"
        case .long: return "Long (4×1\")"
        case .small: return "Small (1×1\")"
        case .standard: return "Standard (2×1\")"
        }
    }

    /// Size in points (72pt = 1 inch)
    public var sizePoints: CGSize {
        switch self {
        case .square:   return CGSize(width: 144, height: 144)
        case .tall:     return CGSize(width: 108, height: 216)
        case .wide:     return CGSize(width: 216, height: 108)
        case .long:     return CGSize(width: 288, height: 72)
        case .small:    return CGSize(width: 72, height: 72)
        case .standard: return CGSize(width: 144, height: 72)
        }
    }
}

// MARK: - Paper Sizes

/// Standard paper/sticker sheet sizes.
public enum QRPaperSize: String, CaseIterable, Codable, Sendable {
    case letter         // 8.5" × 11" — US standard
    case legal          // 8.5" × 14"
    case a4             // 210mm × 297mm
    case avery5160      // Letter with 30 labels (1" × 2.625")
    case avery5163      // Letter with 10 labels (2" × 4")
    case avery5167      // Letter with 80 labels (0.5" × 1.75")
    case avery8160      // Same as 5160 (inkjet)
    case avery5164      // Letter with 6 labels (3.33" × 4")
    case avery5165      // Letter with 1 label (full sheet)
    case thermal2x1     // 2" × 1" continuous roll
    case thermal4x6     // 4" × 6" shipping label

    public var displayName: String {
        switch self {
        case .letter: return "Letter (8.5×11\")"
        case .legal: return "Legal (8.5×14\")"
        case .a4: return "A4"
        case .avery5160: return "Avery 5160 (30 labels, 1×2.625\")"
        case .avery5163: return "Avery 5163 (10 labels, 2×4\")"
        case .avery5167: return "Avery 5167 (80 labels, 0.5×1.75\")"
        case .avery8160: return "Avery 8160 (30 labels, inkjet)"
        case .avery5164: return "Avery 5164 (6 labels, 3.33×4\")"
        case .avery5165: return "Avery 5165 (1 label, full sheet)"
        case .thermal2x1: return "Thermal 2×1\""
        case .thermal4x6: return "Thermal 4×6\""
        }
    }

    /// Total paper size in points
    public var pageSizePoints: CGSize {
        switch self {
        case .letter: return CGSize(width: 612, height: 792)
        case .legal: return CGSize(width: 612, height: 1008)
        case .a4: return CGSize(width: 595, height: 842)
        case .avery5160, .avery8160: return CGSize(width: 612, height: 792)
        case .avery5163: return CGSize(width: 612, height: 792)
        case .avery5167: return CGSize(width: 612, height: 792)
        case .avery5164: return CGSize(width: 612, height: 792)
        case .avery5165: return CGSize(width: 612, height: 792)
        case .thermal2x1: return CGSize(width: 144, height: 72)
        case .thermal4x6: return CGSize(width: 288, height: 432)
        }
    }

    /// Whether this paper is exact-size thermal label media.
    ///
    /// Thermal stock is one physical label per page, printed edge-to-edge —
    /// plain-paper margins must never be applied to it (issue #1208).
    public var isThermalMedia: Bool {
        switch self {
        case .thermal2x1, .thermal4x6: return true
        default: return false
        }
    }

    /// Label grid for sticker sheets: (columns, rows, labelSize, margins, spacing)
    public var labelGrid: LabelGrid? {
        switch self {
        case .avery5160, .avery8160:
            return LabelGrid(columns: 3, rows: 10,
                           labelWidth: 189, labelHeight: 72,
                           marginLeft: 14, marginTop: 36,
                           spacingH: 9, spacingV: 0)
        case .avery5163:
            return LabelGrid(columns: 2, rows: 5,
                           labelWidth: 288, labelHeight: 144,
                           marginLeft: 12, marginTop: 36,
                           spacingH: 12, spacingV: 0)
        case .avery5167:
            return LabelGrid(columns: 4, rows: 20,
                           labelWidth: 126, labelHeight: 36,
                           marginLeft: 22, marginTop: 36,
                           spacingH: 22, spacingV: 0)
        case .avery5164:
            return LabelGrid(columns: 2, rows: 3,
                           labelWidth: 288, labelHeight: 240,
                           marginLeft: 12, marginTop: 36,
                           spacingH: 12, spacingV: 0)
        case .avery5165:
            return LabelGrid(columns: 1, rows: 1,
                           labelWidth: 576, labelHeight: 756,
                           marginLeft: 18, marginTop: 18,
                           spacingH: 0, spacingV: 0)
        default: return nil
        }
    }
}

/// Grid layout for sticker sheet paper types.
public struct LabelGrid: Sendable {
    public let columns: Int
    public let rows: Int
    public let labelWidth: CGFloat   // points
    public let labelHeight: CGFloat  // points
    public let marginLeft: CGFloat   // points
    public let marginTop: CGFloat    // points
    public let spacingH: CGFloat     // horizontal gap between labels
    public let spacingV: CGFloat     // vertical gap between labels

    public var totalPositions: Int { columns * rows }

    /// Get the origin point for a label at (col, row)
    public func originFor(column: Int, row: Int) -> CGPoint {
        CGPoint(
            x: marginLeft + CGFloat(column) * (labelWidth + spacingH),
            y: marginTop + CGFloat(row) * (labelHeight + spacingV)
        )
    }
}

// MARK: - Label Content

/// What to print on a label.
public struct QRLabelContent: Sendable {
    public let entityType: QREntityType
    public let entityId: Int64
    public let code: String           // primary code (part code, bin code, serial, etc.)
    public let title: String          // display name
    public let subtitle: String?      // category, location, etc.
    public let detail: String?        // additional info line

    public init(entityType: QREntityType, entityId: Int64, code: String,
                title: String, subtitle: String? = nil, detail: String? = nil) {
        self.entityType = entityType
        self.entityId = entityId
        self.code = code
        self.title = title
        self.subtitle = subtitle
        self.detail = detail
    }
}

// MARK: - Label Layout Templates

/// How QR + text are arranged within a single label.
public enum QRLabelLayout: String, CaseIterable, Codable, Sendable {
    case qrLeft       // QR on left, text stacked right
    case qrRight      // QR on right, text stacked left
    case qrTop        // QR on top, text below
    case qrBottom     // Text on top, QR below
    case qrCenter     // QR centered, text wraps below
    case codeOnly     // Just the QR code, no text

    public var displayName: String {
        switch self {
        case .qrLeft: return "QR Left + Text"
        case .qrRight: return "Text + QR Right"
        case .qrTop: return "QR Top + Text Below"
        case .qrBottom: return "Text Top + QR Below"
        case .qrCenter: return "QR Centered"
        case .codeOnly: return "QR Only"
        }
    }
}

// MARK: - Plain Paper Layout

/// Resolved tiling layout for plain-paper (non-sticker) label printing.
///
/// Produced by `QRLabelPDFGenerator.plainPaperLayout(labelSize:paperSize:)` so the
/// print-sheet page-count estimate and the PDF renderer always share the exact same
/// geometry (issue #1208 — the two previously used slightly different math).
public struct PlainPaperLabelLayout: Sendable, Equatable {
    public let columns: Int
    public let rows: Int
    public let labelSize: CGSize
    public let margin: CGFloat
    public let spacing: CGFloat

    /// Number of labels rendered on one page.
    public var labelsPerPage: Int { columns * rows }

    /// Frame for the label at a 0-based slot index (row-major order).
    public func labelRect(forSlot slot: Int) -> CGRect {
        let col = slot % columns
        let row = slot / columns
        return CGRect(
            x: margin + CGFloat(col) * (labelSize.width + spacing),
            y: margin + CGFloat(row) * (labelSize.height + spacing),
            width: labelSize.width,
            height: labelSize.height
        )
    }
}

// MARK: - PDF Generator

public struct QRLabelPDFGenerator {
    private static let labelPadding: CGFloat = 4
    private static let plainPaperMargin: CGFloat = 36 // 0.5" margin
    private static let plainPaperSpacing: CGFloat = 8

    /// Compute the tiling layout used for plain-paper (non-sticker) printing.
    ///
    /// - Thermal media is exact-size label stock: the label IS the page, so the layout
    ///   is a single full-bleed label with zero margins regardless of the selected label
    ///   size (issue #1208 — plain-paper margins used to push thermal labels off-page).
    /// - Regular paper keeps the 0.5" margin grid. Returns `nil` when the requested
    ///   label cannot fit inside the printable area at all, so callers can block the
    ///   print instead of silently rendering a clipped PDF.
    public static func plainPaperLayout(labelSize: QRLabelSize, paperSize: QRPaperSize) -> PlainPaperLabelLayout? {
        let pageSize = paperSize.pageSizePoints

        if paperSize.isThermalMedia {
            return PlainPaperLabelLayout(
                columns: 1, rows: 1,
                labelSize: pageSize,
                margin: 0, spacing: 0
            )
        }

        let labelDim = labelSize.sizePoints
        let usableWidth = pageSize.width - plainPaperMargin * 2
        let usableHeight = pageSize.height - plainPaperMargin * 2
        guard labelDim.width <= usableWidth, labelDim.height <= usableHeight else { return nil }

        // Max n such that n*label + (n-1)*spacing <= usable.
        let cols = Int((usableWidth + plainPaperSpacing) / (labelDim.width + plainPaperSpacing))
        let rows = Int((usableHeight + plainPaperSpacing) / (labelDim.height + plainPaperSpacing))
        guard cols >= 1, rows >= 1 else { return nil }

        return PlainPaperLabelLayout(
            columns: cols, rows: rows,
            labelSize: labelDim,
            margin: plainPaperMargin, spacing: plainPaperSpacing
        )
    }

    typealias QRImageGenerator = @Sendable (
        _ type: QREntityType,
        _ id: Int64,
        _ code: String,
        _ size: CGFloat
    ) -> CGImage?

    static let defaultQRImageGenerator: QRImageGenerator = { type, id, code, size in
        QRGenerator.generate(type: type, id: id, code: code, size: size)
    }

    /// Positions on a sticker sheet that can receive labels after already-used slots are skipped.
    /// Invalid position indexes are ignored so callers cannot accidentally reduce the first page to
    /// zero printable labels by carrying stale state between different paper grids.
    public static func availableStickerPositions(grid: LabelGrid, usedPositions: Set<Int>) -> [(col: Int, row: Int)] {
        (0..<grid.totalPositions).compactMap { position in
            guard !usedPositions.contains(position) else { return nil }
            return (col: position % grid.columns, row: position / grid.columns)
        }
    }

    /// Printable label slots available on the first sticker-sheet page.
    public static func availableStickerPositionCount(grid: LabelGrid, usedPositions: Set<Int>) -> Int {
        availableStickerPositions(grid: grid, usedPositions: usedPositions).count
    }

    /// Generate a PDF containing labels for the given content items.
    ///
    /// - Parameters:
    ///   - items: The label content to print
    ///   - labelSize: Physical label size
    ///   - layout: How QR + text are arranged
    ///   - paperSize: Paper/sticker sheet type
    ///   - usedPositions: Set of 0-based positions on a sticker sheet that are already used
    ///                    (for partial sheet printing). Empty = all positions available.
    /// - Returns: PDF data ready for printing
    public static func generatePDF(
        items: [QRLabelContent],
        labelSize: QRLabelSize,
        layout: QRLabelLayout,
        paperSize: QRPaperSize,
        usedPositions: Set<Int> = []
    ) -> Data? {
        generatePDF(
            items: items,
            labelSize: labelSize,
            layout: layout,
            paperSize: paperSize,
            usedPositions: usedPositions,
            qrImageGenerator: defaultQRImageGenerator
        )
    }

    static func generatePDF(
        items: [QRLabelContent],
        labelSize: QRLabelSize,
        layout: QRLabelLayout,
        paperSize: QRPaperSize,
        usedPositions: Set<Int> = [],
        qrImageGenerator: QRImageGenerator
    ) -> Data? {
        if let grid = paperSize.labelGrid,
           !items.isEmpty,
           availableStickerPositions(grid: grid, usedPositions: usedPositions).isEmpty {
            return nil
        }

        // Plain paper / thermal: refuse combinations whose labels cannot fit the
        // physical media instead of silently printing clipped labels (issue #1208).
        if paperSize.labelGrid == nil,
           plainPaperLayout(labelSize: labelSize, paperSize: paperSize) == nil {
            return nil
        }

        guard canRenderQRCodesForPDF(
            items: items,
            labelSize: labelSize,
            paperSize: paperSize,
            qrImageGenerator: qrImageGenerator
        ) else {
            return nil
        }

        #if canImport(UIKit)
        let pdfRenderer = UIGraphicsPDFRenderer(bounds: CGRect(origin: .zero,
                                                                size: paperSize.pageSizePoints))

        var renderSucceeded = true
        let data = pdfRenderer.pdfData { context in
            if let grid = paperSize.labelGrid {
                // Sticker sheet mode: lay out labels in grid, skip used positions
                renderSucceeded = renderStickerSheet(context: context, items: items, grid: grid,
                                                     layout: layout, paperSize: paperSize,
                                                     usedPositions: usedPositions,
                                                     qrImageGenerator: qrImageGenerator)
            } else {
                // Plain paper mode: tile labels with auto-calculated grid
                renderSucceeded = renderPlainPaper(context: context, items: items,
                                                   labelSize: labelSize, layout: layout,
                                                   paperSize: paperSize,
                                                   qrImageGenerator: qrImageGenerator)
            }
        }
        return renderSucceeded ? data : nil
        #else
        return nil
        #endif
    }

    static func canRenderQRCodesForPDF(
        items: [QRLabelContent],
        labelSize: QRLabelSize,
        paperSize: QRPaperSize,
        qrImageGenerator: QRImageGenerator = defaultQRImageGenerator
    ) -> Bool {
        let labelDimensions: CGSize
        if let grid = paperSize.labelGrid {
            labelDimensions = CGSize(width: grid.labelWidth, height: grid.labelHeight)
        } else if let layout = plainPaperLayout(labelSize: labelSize, paperSize: paperSize) {
            // Thermal media renders one full-page label, so the QR must be sized
            // against the physical page — not the nominal label selection (#1208).
            labelDimensions = layout.labelSize
        } else {
            return false
        }
        let qrSide = min(labelDimensions.width, labelDimensions.height) - labelPadding * 2

        return items.allSatisfy { item in
            qrImageGenerator(item.entityType, item.entityId, item.code, qrSide) != nil
        }
    }

    #if canImport(UIKit)

    // MARK: - Sticker Sheet Rendering

    private static func renderStickerSheet(
        context: UIGraphicsPDFRendererContext,
        items: [QRLabelContent],
        grid: LabelGrid,
        layout: QRLabelLayout,
        paperSize: QRPaperSize,
        usedPositions: Set<Int>,
        qrImageGenerator: QRImageGenerator
    ) -> Bool {
        // Build list of available positions (skip used ones)
        var availablePositions = availableStickerPositions(grid: grid, usedPositions: usedPositions)
        guard !availablePositions.isEmpty else { return true }

        var itemIndex = 0
        var posIndex = 0

        while itemIndex < items.count {
            // Start new page
            context.beginPage()

            // Fill available positions on this page
            while posIndex < availablePositions.count && itemIndex < items.count {
                let pos = availablePositions[posIndex]
                let origin = grid.originFor(column: pos.col, row: pos.row)
                let labelRect = CGRect(x: origin.x, y: origin.y,
                                       width: grid.labelWidth, height: grid.labelHeight)

                guard renderSingleLabel(in: context.cgContext,
                                        rect: labelRect,
                                        content: items[itemIndex],
                                        layout: layout,
                                        qrImageGenerator: qrImageGenerator) else {
                    return false
                }
                itemIndex += 1
                posIndex += 1
            }

            // If we used all positions on this page, reset for next page
            // (next pages have all positions available)
            if posIndex >= availablePositions.count && itemIndex < items.count {
                posIndex = 0
                availablePositions = (0..<grid.totalPositions).map { pos in
                    (col: pos % grid.columns, row: pos / grid.columns)
                }
            }
        }
        return true
    }

    // MARK: - Plain Paper Rendering

    private static func renderPlainPaper(
        context: UIGraphicsPDFRendererContext,
        items: [QRLabelContent],
        labelSize: QRLabelSize,
        layout: QRLabelLayout,
        paperSize: QRPaperSize,
        qrImageGenerator: QRImageGenerator
    ) -> Bool {
        // Shared geometry with the print-sheet estimate; thermal media resolves to a
        // single full-bleed label per page, other paper keeps the margin grid (#1208).
        guard let pageLayout = plainPaperLayout(labelSize: labelSize, paperSize: paperSize) else {
            return false
        }

        var itemIndex = 0
        while itemIndex < items.count {
            context.beginPage()

            for slot in 0..<pageLayout.labelsPerPage {
                guard itemIndex < items.count else { break }

                let labelRect = pageLayout.labelRect(forSlot: slot)

                guard renderSingleLabel(in: context.cgContext,
                                        rect: labelRect,
                                        content: items[itemIndex],
                                        layout: layout,
                                        qrImageGenerator: qrImageGenerator) else {
                    return false
                }
                itemIndex += 1
            }
        }
        return true
    }

    // MARK: - Single Label Rendering

    private static func renderSingleLabel(
        in cgContext: CGContext,
        rect: CGRect,
        content: QRLabelContent,
        layout: QRLabelLayout,
        qrImageGenerator: QRImageGenerator
    ) -> Bool {
        let padding = labelPadding

        // Generate QR code image — use the smaller dimension for square QR
        let qrSide: CGFloat = min(rect.width, rect.height) - padding * 2
        guard let qrImage = qrImageGenerator(content.entityType, content.entityId, content.code, qrSide) else { return false }

        switch layout {
        case .qrLeft:
            let qrRect = CGRect(x: rect.minX + padding,
                                y: rect.minY + padding,
                                width: qrSide, height: qrSide)
            cgContext.draw(qrImage, in: qrRect)

            let textX = qrRect.maxX + padding
            let textWidth = rect.maxX - textX - padding
            drawTextBlock(in: cgContext, x: textX, y: rect.minY + padding,
                         width: textWidth, height: rect.height - padding * 2,
                         content: content)

        case .qrRight:
            let qrRect = CGRect(x: rect.maxX - qrSide - padding,
                                y: rect.minY + padding,
                                width: qrSide, height: qrSide)
            cgContext.draw(qrImage, in: qrRect)

            let textWidth = qrRect.minX - rect.minX - padding * 2
            drawTextBlock(in: cgContext, x: rect.minX + padding, y: rect.minY + padding,
                         width: textWidth, height: rect.height - padding * 2,
                         content: content)

        case .qrTop:
            let scaledQR = min(qrSide, rect.height * 0.6)
            let qrRect = CGRect(x: rect.midX - scaledQR / 2,
                                y: rect.minY + padding,
                                width: scaledQR, height: scaledQR)
            cgContext.draw(qrImage, in: qrRect)

            drawTextBlock(in: cgContext, x: rect.minX + padding,
                         y: qrRect.maxY + 2,
                         width: rect.width - padding * 2,
                         height: rect.maxY - qrRect.maxY - padding,
                         content: content)

        case .qrBottom:
            let scaledQR = min(qrSide, rect.height * 0.6)
            let textHeight = rect.height - scaledQR - padding * 3
            drawTextBlock(in: cgContext, x: rect.minX + padding,
                         y: rect.minY + padding,
                         width: rect.width - padding * 2,
                         height: textHeight,
                         content: content)

            let qrRect = CGRect(x: rect.midX - scaledQR / 2,
                                y: rect.maxY - scaledQR - padding,
                                width: scaledQR, height: scaledQR)
            cgContext.draw(qrImage, in: qrRect)

        case .qrCenter:
            let scaledQR = min(qrSide, min(rect.width, rect.height) * 0.7)
            let qrRect = CGRect(x: rect.midX - scaledQR / 2,
                                y: rect.midY - scaledQR / 2,
                                width: scaledQR, height: scaledQR)
            cgContext.draw(qrImage, in: qrRect)

            // Code text below QR
            let codeAttr: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 7, weight: .medium),
                .foregroundColor: UIColor.black
            ]
            let codeStr = NSString(string: content.code)
            let codeSize = codeStr.size(withAttributes: codeAttr)
            codeStr.draw(at: CGPoint(x: rect.midX - codeSize.width / 2,
                                     y: qrRect.maxY + 2),
                         withAttributes: codeAttr)

        case .codeOnly:
            let scaledQR = min(rect.width, rect.height) - padding * 2
            let qrRect = CGRect(x: rect.midX - scaledQR / 2,
                                y: rect.midY - scaledQR / 2,
                                width: scaledQR, height: scaledQR)
            cgContext.draw(qrImage, in: qrRect)
        }
        return true
    }

    private static func drawTextBlock(
        in cgContext: CGContext,
        x: CGFloat, y: CGFloat,
        width: CGFloat, height: CGFloat,
        content: QRLabelContent
    ) {
        var currentY = y

        // Title (bold, larger)
        let titleAttr: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: min(10, height * 0.35), weight: .bold),
            .foregroundColor: UIColor.black
        ]
        let titleStr = NSString(string: content.title)
        let titleRect = CGRect(x: x, y: currentY, width: width, height: height * 0.35)
        titleStr.draw(in: titleRect, withAttributes: titleAttr)
        currentY += height * 0.35

        // Code (monospace, medium)
        let codeAttr: [NSAttributedString.Key: Any] = [
            .font: UIFont.monospacedSystemFont(ofSize: min(8, height * 0.25), weight: .medium),
            .foregroundColor: UIColor.darkGray
        ]
        let codeStr = NSString(string: content.code)
        codeStr.draw(at: CGPoint(x: x, y: currentY), withAttributes: codeAttr)
        currentY += height * 0.25

        // Subtitle (light, smaller)
        if let subtitle = content.subtitle {
            let subAttr: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: min(7, height * 0.2), weight: .regular),
                .foregroundColor: UIColor.gray
            ]
            NSString(string: subtitle).draw(at: CGPoint(x: x, y: currentY), withAttributes: subAttr)
            currentY += height * 0.2
        }

        // Detail (light, smallest)
        if let detail = content.detail {
            let detailAttr: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: min(6, height * 0.15), weight: .light),
                .foregroundColor: UIColor.gray
            ]
            NSString(string: detail).draw(at: CGPoint(x: x, y: currentY), withAttributes: detailAttr)
        }
    }

    #endif
}

// MARK: - Batch Label Helpers

extension QRLabelPDFGenerator {

    /// Generate a print-ready PDF for a batch of parts.
    public static func generatePartLabels(
        parts: [(id: Int64, code: String, name: String, category: String?, binLocation: String?)],
        labelSize: QRLabelSize = .standard,
        layout: QRLabelLayout = .qrLeft,
        paperSize: QRPaperSize = .letter,
        usedPositions: Set<Int> = []
    ) -> Data? {
        let items = parts.map { part in
            QRLabelContent(
                entityType: .part,
                entityId: part.id,
                code: part.code,
                title: part.name,
                subtitle: part.category,
                detail: part.binLocation
            )
        }
        return generatePDF(items: items, labelSize: labelSize,
                          layout: layout, paperSize: paperSize,
                          usedPositions: usedPositions)
    }

    /// Generate a print-ready PDF for bin labels.
    public static func generateBinLabels(
        bins: [(id: Int64, code: String, warehouse: String, aisle: String?, shelf: String?)],
        labelSize: QRLabelSize = .wide,
        layout: QRLabelLayout = .qrLeft,
        paperSize: QRPaperSize = .letter,
        usedPositions: Set<Int> = []
    ) -> Data? {
        let items = bins.map { bin in
            QRLabelContent(
                entityType: .bin,
                entityId: bin.id,
                code: bin.code,
                title: bin.code,
                subtitle: bin.warehouse,
                detail: [bin.aisle, bin.shelf].compactMap { $0 }.joined(separator: " / ")
            )
        }
        return generatePDF(items: items, labelSize: labelSize,
                          layout: layout, paperSize: paperSize,
                          usedPositions: usedPositions)
    }

    /// Generate a print-ready PDF for tool labels.
    public static func generateToolLabels(
        tools: [(id: Int64, serial: String, name: String, owner: String?)],
        labelSize: QRLabelSize = .standard,
        layout: QRLabelLayout = .qrLeft,
        paperSize: QRPaperSize = .letter,
        usedPositions: Set<Int> = []
    ) -> Data? {
        let items = tools.map { tool in
            QRLabelContent(
                entityType: .tool,
                entityId: tool.id,
                code: tool.serial,
                title: tool.name,
                subtitle: tool.owner
            )
        }
        return generatePDF(items: items, labelSize: labelSize,
                          layout: layout, paperSize: paperSize,
                          usedPositions: usedPositions)
    }
}
