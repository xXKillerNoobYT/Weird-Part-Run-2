import UIKit
import WiredPartCore

// MARK: - PO PDF Generator

/// Renders a Purchase Order to a PDF suitable for emailing to a supplier.
/// Letter-size (612 × 792 pt), single or multi-page.
@MainActor
struct POPDFGenerator {

    let po: OrdersService.PODetail
    let supplierEmail: String?
    let companyName: String

    // Layout constants
    private let pageW: CGFloat = 612
    private let pageH: CGFloat = 792
    private let margin: CGFloat = 44
    private var contentW: CGFloat { pageW - margin * 2 }

    // Fonts
    private let fontTitle   = UIFont.boldSystemFont(ofSize: 20)
    private let fontH2      = UIFont.boldSystemFont(ofSize: 13)
    private let fontLabel   = UIFont.systemFont(ofSize: 10)
    private let fontBold    = UIFont.boldSystemFont(ofSize: 10)
    private let fontCell    = UIFont.systemFont(ofSize: 9)
    private let fontCellB   = UIFont.boldSystemFont(ofSize: 9)
    private let fontFooter  = UIFont.systemFont(ofSize: 8)

    // Colors
    private let colorPrimary  = UIColor(red: 0.11, green: 0.35, blue: 0.82, alpha: 1) // WiredPart blue
    private let colorHeader   = UIColor(red: 0.95, green: 0.97, blue: 1.00, alpha: 1)
    private let colorAlt      = UIColor(red: 0.97, green: 0.97, blue: 0.97, alpha: 1)
    private let colorBorder   = UIColor(red: 0.82, green: 0.82, blue: 0.82, alpha: 1)

    func generatePDF() -> Data {
        let renderer = UIGraphicsPDFRenderer(
            bounds: CGRect(x: 0, y: 0, width: pageW, height: pageH)
        )
        return renderer.pdfData { ctx in
            var y: CGFloat = 0
            var page = 0

            func newPage() {
                ctx.beginPage()
                page += 1
                y = margin
                drawPageFooter(page: page)
            }

            func ensureSpace(_ needed: CGFloat) {
                if y + needed > pageH - margin - 24 {
                    drawPageFooter(page: page)
                    newPage()
                }
            }

            func drawPageFooter(page: Int) {
                let attr: [NSAttributedString.Key: Any] = [
                    .font: fontFooter, .foregroundColor: UIColor.gray
                ]
                let left = "\(companyName) — Confidential"
                let right = "Page \(page)  |  PO \(po.poNumber)"
                (left as NSString).draw(at: CGPoint(x: margin, y: pageH - margin + 6), withAttributes: attr)
                let rSize = (right as NSString).size(withAttributes: attr)
                (right as NSString).draw(
                    at: CGPoint(x: pageW - margin - rSize.width, y: pageH - margin + 6),
                    withAttributes: attr
                )
                // Footer rule
                let path = UIBezierPath()
                path.move(to: CGPoint(x: margin, y: pageH - margin + 4))
                path.addLine(to: CGPoint(x: pageW - margin, y: pageH - margin + 4))
                colorBorder.setStroke()
                path.lineWidth = 0.5
                path.stroke()
            }

            // ── Page 1 ──────────────────────────────────────────────────────
            newPage()

            // Header bar
            colorPrimary.setFill()
            UIBezierPath(rect: CGRect(x: 0, y: 0, width: pageW, height: 56)).fill()
            let titleAttr: [NSAttributedString.Key: Any] = [
                .font: fontTitle, .foregroundColor: UIColor.white
            ]
            ("PURCHASE ORDER" as NSString).draw(at: CGPoint(x: margin, y: 16), withAttributes: titleAttr)
            let poNumAttr: [NSAttributedString.Key: Any] = [
                .font: UIFont.boldSystemFont(ofSize: 14), .foregroundColor: UIColor.white.withAlphaComponent(0.85)
            ]
            let poNumStr = po.poNumber
            let poNumSize = (poNumStr as NSString).size(withAttributes: poNumAttr)
            (poNumStr as NSString).draw(
                at: CGPoint(x: pageW - margin - poNumSize.width, y: 20),
                withAttributes: poNumAttr
            )
            y = 56 + 16

            // ── Meta block ──────────────────────────────────────────────────
            func metaRow(_ label: String, _ value: String) {
                let lAttr: [NSAttributedString.Key: Any] = [.font: fontBold, .foregroundColor: UIColor.gray]
                let vAttr: [NSAttributedString.Key: Any] = [.font: fontLabel, .foregroundColor: UIColor.black]
                (label as NSString).draw(at: CGPoint(x: margin, y: y), withAttributes: lAttr)
                (value as NSString).draw(at: CGPoint(x: margin + 110, y: y), withAttributes: vAttr)
                y += 14
            }

            metaRow("Supplier:",      po.supplierName)
            if let email = supplierEmail { metaRow("Supplier Email:", email) }
            if let relatedJobSummary = po.supplierRelatedJobSummary { metaRow("Related Job(s):", relatedJobSummary) }
            metaRow("Order Date:",    po.orderDate ?? "—")
            metaRow("Expected By:",   po.expectedDelivery ?? "—")
            if let tracking = po.trackingNumber { metaRow("Tracking:", tracking) }
            metaRow("Status:",        po.status.replacingOccurrences(of: "_", with: " ").capitalized)
            if let notes = po.notes, !notes.isEmpty { metaRow("Notes:", notes) }
            y += 8

            // Divider
            colorBorder.setStroke()
            let div = UIBezierPath()
            div.move(to: CGPoint(x: margin, y: y))
            div.addLine(to: CGPoint(x: pageW - margin, y: y))
            div.lineWidth = 0.5
            div.stroke()
            y += 12

            // ── Line items table ─────────────────────────────────────────────
            let tableWidth = contentW
            let cols: [(label: String, width: CGFloat, right: Bool)] = [
                ("Part / Description",    tableWidth * 0.40, false),
                ("Job",                   tableWidth * 0.22, false),
                ("Qty",                   tableWidth * 0.08, true),
                ("Unit Price",            tableWidth * 0.15, true),
                ("Line Total",            tableWidth * 0.15, true)
            ]
            let rowH: CGFloat = 18

            func xFor(_ col: Int) -> CGFloat {
                var x = margin
                for i in 0..<col { x += cols[i].width }
                return x
            }

            func drawTableHeader() {
                colorHeader.setFill()
                UIBezierPath(rect: CGRect(x: margin, y: y, width: tableWidth, height: rowH)).fill()
                colorBorder.setStroke()
                UIBezierPath(rect: CGRect(x: margin, y: y, width: tableWidth, height: rowH)).stroke()
                for (i, col) in cols.enumerated() {
                    let attr: [NSAttributedString.Key: Any] = [
                        .font: fontCellB, .foregroundColor: colorPrimary
                    ]
                    let x = xFor(i)
                    let strSize = (col.label as NSString).size(withAttributes: attr)
                    let tx = col.right ? x + col.width - strSize.width - 4 : x + 4
                    (col.label as NSString).draw(at: CGPoint(x: tx, y: y + 4), withAttributes: attr)
                }
                y += rowH
            }

            drawTableHeader()

            let fmt = NumberFormatter()
            fmt.numberStyle = .currency
            fmt.currencyCode = "USD"

            for (idx, line) in po.lines.enumerated() {
                ensureSpace(rowH)
                if idx > 0 && y == margin { drawTableHeader() } // after page break

                // Alternating row bg
                if idx % 2 == 1 {
                    colorAlt.setFill()
                    UIBezierPath(rect: CGRect(x: margin, y: y, width: contentW, height: rowH)).fill()
                }

                let cellAttr: [NSAttributedString.Key: Any] = [
                    .font: fontCell, .foregroundColor: UIColor.darkGray
                ]

                let partName  = line.partName ?? line.description ?? "—"
                let jobName   = line.jobName ?? "General Stock"
                let qty       = "\(line.quantityOrdered)"
                let unitStr   = line.unitPrice.map { fmt.string(from: NSNumber(value: $0)) ?? "—" } ?? "—"
                let lineTotal = line.unitPrice.map { $0 * Double(line.quantityOrdered) }
                let totalStr  = lineTotal.map { fmt.string(from: NSNumber(value: $0)) ?? "—" } ?? "—"

                let cellValues = [partName, jobName, qty, unitStr, totalStr]
                for (i, val) in cellValues.enumerated() {
                    let x = xFor(i)
                    let col = cols[i]
                    let strSize = (val as NSString).size(withAttributes: cellAttr)
                    let tx = col.right ? x + col.width - strSize.width - 4 : x + 4
                    // Clip to column width
                    let clipRect = CGRect(x: x + 2, y: y + 3, width: col.width - 6, height: rowH - 4)
                    (val as NSString).draw(in: clipRect, withAttributes: cellAttr)
                    _ = tx // suppress warning; using draw(in:) for clipping
                }
                y += rowH
            }

            // Table bottom border
            colorBorder.setStroke()
            let bottomLine = UIBezierPath()
            bottomLine.move(to: CGPoint(x: margin, y: y))
            bottomLine.addLine(to: CGPoint(x: pageW - margin, y: y))
            bottomLine.lineWidth = 0.5
            bottomLine.stroke()
            y += 16

            // ── Totals block ────────────────────────────────────────────────
            let totalsX = pageW - margin - 200
            func totalRow(_ label: String, _ value: String?, bold: Bool = false) {
                guard let value else { return }
                ensureSpace(16)
                let lAttr: [NSAttributedString.Key: Any] = [
                    .font: bold ? fontBold : fontLabel,
                    .foregroundColor: bold ? UIColor.black : UIColor.darkGray
                ]
                let vAttr: [NSAttributedString.Key: Any] = [
                    .font: bold ? fontCellB : fontCell,
                    .foregroundColor: UIColor.black
                ]
                (label as NSString).draw(at: CGPoint(x: totalsX, y: y), withAttributes: lAttr)
                let vSize = (value as NSString).size(withAttributes: vAttr)
                (value as NSString).draw(
                    at: CGPoint(x: pageW - margin - vSize.width, y: y),
                    withAttributes: vAttr
                )
                y += 16
            }

            totalRow("Subtotal:",      po.subtotal.map    { fmt.string(from: NSNumber(value: $0)) ?? "—" })
            totalRow("Tax:",           po.taxAmount.map   { fmt.string(from: NSNumber(value: $0)) ?? "—" })
            totalRow("Shipping:",      po.shippingCost.map{ fmt.string(from: NSNumber(value: $0)) ?? "—" })

            // Grand total line
            if let total = po.totalCost {
                ensureSpace(24)
                colorPrimary.setFill()
                UIBezierPath(rect: CGRect(x: totalsX - 8, y: y, width: pageW - margin - totalsX + 8, height: 22)).fill()
                let grandAttr: [NSAttributedString.Key: Any] = [
                    .font: UIFont.boldSystemFont(ofSize: 11), .foregroundColor: UIColor.white
                ]
                ("TOTAL" as NSString).draw(at: CGPoint(x: totalsX, y: y + 5), withAttributes: grandAttr)
                let totalStr2 = fmt.string(from: NSNumber(value: total)) ?? "—"
                let tSize = (totalStr2 as NSString).size(withAttributes: grandAttr)
                (totalStr2 as NSString).draw(
                    at: CGPoint(x: pageW - margin - tSize.width, y: y + 5),
                    withAttributes: grandAttr
                )
                y += 30
            }

            // ── Signature line ───────────────────────────────────────────────
            ensureSpace(60)
            y += 20
            let sigY = y + 30
            colorBorder.setStroke()
            let sigLine = UIBezierPath()
            sigLine.move(to: CGPoint(x: margin, y: sigY))
            sigLine.addLine(to: CGPoint(x: margin + 200, y: sigY))
            sigLine.lineWidth = 0.5
            sigLine.stroke()
            let sigAttr: [NSAttributedString.Key: Any] = [.font: fontFooter, .foregroundColor: UIColor.gray]
            ("Authorized Signature / Date" as NSString).draw(
                at: CGPoint(x: margin, y: sigY + 4), withAttributes: sigAttr
            )
        }
    }
}
