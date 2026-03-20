# 21A — QR Label PDF Generator Engine

> **Chain position:** **21A** → 21B → 21C
> **Prerequisite:** None (QR generation already exists in QRGenerator.swift)
> **Log file:** `xcode-ai/prompt-results-log.md`

## Instructions

**IMPORTANT:** Before implementing, first plan your approach by reading all files mentioned below. Understand the current state, then implement the fixes. When done, wait for the user to confirm before proceeding to the next prompt.

## Context

The app can generate QR code images (`QRGenerator.generatePNGData()`) but has no way to create printable labels. Users need to print QR labels for parts, bins, tools, and vehicles on standard printers — using regular paper, sticker sheets, or thermal label stock.

iOS has built-in printing via `UIPrintInteractionController` which accepts PDF data. We need a PDF generation engine that composes QR code + text into label layouts.

**Existing infrastructure:**
- `core/Sources/WiredPartCore/QR/QRGenerator.swift` — generates QR as CGImage/PNG
- `Weird Parts IOS/Weird Parts IOS/Features/Settings/PDFSettingsPage.swift` — has accent color, footer text settings
- iOS `PDFKit` framework — for PDF document creation
- iOS `UIPrintInteractionController` — for sending PDFs to printer

**File to create:**
- `core/Sources/WiredPartCore/QR/QRLabelGenerator.swift`

## Task

### Step 1: Define label size and layout models

```swift
import Foundation
import CoreGraphics

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
        case .avery5160, .avery8160: return CGSize(width: 612, height: 792) // Letter
        case .avery5163: return CGSize(width: 612, height: 792)
        case .avery5167: return CGSize(width: 612, height: 792)
        case .avery5164: return CGSize(width: 612, height: 792)
        case .avery5165: return CGSize(width: 612, height: 792)
        case .thermal2x1: return CGSize(width: 144, height: 72)
        case .thermal4x6: return CGSize(width: 288, height: 432)
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
    public let entityType: String     // "part", "bin", "tool", etc.
    public let entityId: Int64
    public let code: String           // primary code (part code, bin code, serial, etc.)
    public let title: String          // display name
    public let subtitle: String?      // category, location, etc.
    public let detail: String?        // additional info line

    public init(entityType: String, entityId: Int64, code: String,
                title: String, subtitle: String? = nil, detail: String? = nil) {
        self.entityType = entityType
        self.entityId = entityId
        self.code = code
        self.title = title
        self.subtitle = subtitle
        self.detail = detail
    }
}
```

### Step 2: Build the PDF label renderer

```swift
import CoreGraphics

#if canImport(UIKit)
import UIKit
#endif

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

// MARK: - PDF Generator

public struct QRLabelPDFGenerator {

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
        #if canImport(UIKit)
        let pdfRenderer = UIGraphicsPDFRenderer(bounds: CGRect(origin: .zero,
                                                                size: paperSize.pageSizePoints))

        let data = pdfRenderer.pdfData { context in
            if let grid = paperSize.labelGrid {
                // Sticker sheet mode: lay out labels in grid, skip used positions
                renderStickerSheet(context: context, items: items, grid: grid,
                                   layout: layout, paperSize: paperSize,
                                   usedPositions: usedPositions)
            } else {
                // Plain paper mode: tile labels with auto-calculated grid
                renderPlainPaper(context: context, items: items,
                                 labelSize: labelSize, layout: layout,
                                 paperSize: paperSize)
            }
        }
        return data
        #else
        return nil
        #endif
    }

    #if canImport(UIKit)

    // MARK: - Sticker Sheet Rendering

    private static func renderStickerSheet(
        context: UIGraphicsPDFRendererContext,
        items: [QRLabelContent],
        grid: LabelGrid,
        layout: QRLabelLayout,
        paperSize: QRPaperSize,
        usedPositions: Set<Int>
    ) {
        // Build list of available positions (skip used ones)
        var availablePositions: [(col: Int, row: Int)] = []
        for row in 0..<grid.rows {
            for col in 0..<grid.columns {
                let pos = row * grid.columns + col
                if !usedPositions.contains(pos) {
                    availablePositions.append((col, row))
                }
            }
        }

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

                renderSingleLabel(in: context.cgContext,
                                  rect: labelRect,
                                  content: items[itemIndex],
                                  layout: layout)
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
    }

    // MARK: - Plain Paper Rendering

    private static func renderPlainPaper(
        context: UIGraphicsPDFRendererContext,
        items: [QRLabelContent],
        labelSize: QRLabelSize,
        layout: QRLabelLayout,
        paperSize: QRPaperSize
    ) {
        let pageSize = paperSize.pageSizePoints
        let labelDim = labelSize.sizePoints
        let margin: CGFloat = 36 // 0.5" margin
        let spacing: CGFloat = 8

        let usableWidth = pageSize.width - margin * 2
        let usableHeight = pageSize.height - margin * 2

        let cols = max(1, Int(usableWidth / (labelDim.width + spacing)))
        let rows = max(1, Int(usableHeight / (labelDim.height + spacing)))
        let labelsPerPage = cols * rows

        var itemIndex = 0
        while itemIndex < items.count {
            context.beginPage()

            for slot in 0..<labelsPerPage {
                guard itemIndex < items.count else { break }

                let col = slot % cols
                let row = slot / cols
                let x = margin + CGFloat(col) * (labelDim.width + spacing)
                let y = margin + CGFloat(row) * (labelDim.height + spacing)
                let labelRect = CGRect(x: x, y: y, width: labelDim.width, height: labelDim.height)

                renderSingleLabel(in: context.cgContext,
                                  rect: labelRect,
                                  content: items[itemIndex],
                                  layout: layout)
                itemIndex += 1
            }
        }
    }

    // MARK: - Single Label Rendering

    private static func renderSingleLabel(
        in cgContext: CGContext,
        rect: CGRect,
        content: QRLabelContent,
        layout: QRLabelLayout
    ) {
        let padding: CGFloat = 4

        // Generate QR code image
        let qrSize: CGFloat = min(rect.width, rect.height) - padding * 2
        guard let qrImage = QRGenerator.generate(
            type: content.entityType,
            id: content.entityId,
            code: content.code,
            size: CGSize(width: qrSize, height: qrSize)
        ) else { return }

        switch layout {
        case .qrLeft:
            let qrRect = CGRect(x: rect.minX + padding,
                                y: rect.minY + padding,
                                width: qrSize, height: qrSize)
            cgContext.draw(qrImage, in: qrRect)

            let textX = qrRect.maxX + padding
            let textWidth = rect.maxX - textX - padding
            drawTextBlock(in: cgContext, x: textX, y: rect.minY + padding,
                         width: textWidth, height: rect.height - padding * 2,
                         content: content)

        case .qrRight:
            let qrRect = CGRect(x: rect.maxX - qrSize - padding,
                                y: rect.minY + padding,
                                width: qrSize, height: qrSize)
            cgContext.draw(qrImage, in: qrRect)

            let textWidth = qrRect.minX - rect.minX - padding * 2
            drawTextBlock(in: cgContext, x: rect.minX + padding, y: rect.minY + padding,
                         width: textWidth, height: rect.height - padding * 2,
                         content: content)

        case .qrTop:
            let scaledQR = min(qrSize, rect.height * 0.6)
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
            let scaledQR = min(qrSize, rect.height * 0.6)
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
            let scaledQR = min(qrSize, min(rect.width, rect.height) * 0.7)
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
```

### Step 3: Add batch label generation helper

Add a convenience method to generate labels for multiple entities at once:

```swift
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
                entityType: "part",
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
                entityType: "bin",
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
                entityType: "tool",
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
```

## Important Notes

- Uses `UIGraphicsPDFRenderer` which is UIKit/iOS only. The `#if canImport(UIKit)` guard ensures it compiles for all platforms, returning nil on non-UIKit platforms.
- The Avery label dimensions are approximate. Real-world accuracy depends on printer margins. The common Avery templates are included as presets.
- `usedPositions` is a Set of 0-based indices (left-to-right, top-to-bottom). Position 0 = top-left. This enables the "used sticker picker" feature in the UI (prompt 21C).
- Font sizes auto-scale based on label height to fit any label size.
- QR code auto-sizes to fit within the label while leaving room for text.
- For plain paper, labels are auto-tiled with 0.5" margins and 8pt spacing.

## Success Criteria

- [ ] `QRLabelSize` enum with 6 sizes (square, tall, wide, long, small, standard)
- [ ] `QRPaperSize` enum with letter, legal, A4, 5 Avery templates, 2 thermal sizes
- [ ] `QRLabelLayout` enum with 6 layout options (qrLeft, qrRight, qrTop, qrBottom, qrCenter, codeOnly)
- [ ] `LabelGrid` struct with position calculation for sticker sheets
- [ ] `QRLabelPDFGenerator.generatePDF()` produces valid PDF data
- [ ] Sticker sheet mode respects `usedPositions` (skips used positions)
- [ ] Plain paper mode auto-tiles labels with margins
- [ ] Batch helpers for parts, bins, and tools
- [ ] Project builds with no errors

## Log Entry

```
## Prompt 21A Results (YYYY-MM-DD)
- Created QRLabelGenerator.swift with full PDF generation engine
- 6 label sizes, 11 paper sizes (incl 5 Avery), 6 layouts
- Sticker sheet mode with used-position skipping
- Batch helpers for parts, bins, tools
- Build: [PASS/FAIL]
```

**Wait for user confirmation before proceeding to prompt 21B.**
