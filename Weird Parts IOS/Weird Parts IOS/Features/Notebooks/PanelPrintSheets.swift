import PDFKit
import SwiftUI
import UniformTypeIdentifiers
import WiredPartCore

// Panel Schedule Builder redesign — print system UI (plan §5, slice 4b).
// Renders `PanelPrintDocument` (slice 4a) into a real PDF and hosts the
// print preview + print setup sheets. The document model decides all
// content; this file only draws and presents.

// MARK: - PDF renderer

enum PanelSchedulePDFRenderer {
    /// Draws the assembled document at the configured paper size.
    static func render(document: PanelPrintDocument, config: PanelPrintConfig, logo: UIImage?) -> Data {
        let size = config.paper.pointSize
        let pageRect = CGRect(x: 0, y: 0, width: size.width, height: size.height)
        let margin: CGFloat = 36
        let contentWidth = pageRect.width - margin * 2

        let renderer = UIGraphicsPDFRenderer(bounds: pageRect)
        return renderer.pdfData { context in
            context.beginPage()
            var y: CGFloat = margin

            func color(_ hex: String) -> UIColor {
                guard !config.grayscale else { return .darkGray }

                var cleaned = hex.trimmingCharacters(in: .whitespacesAndNewlines)
                if cleaned.hasPrefix("#") { cleaned.removeFirst() }
                guard cleaned.count == 6, let rgb = UInt64(cleaned, radix: 16) else { return .gray }

                return UIColor(
                    red: CGFloat((rgb >> 16) & 0xFF) / 255,
                    green: CGFloat((rgb >> 8) & 0xFF) / 255,
                    blue: CGFloat(rgb & 0xFF) / 255,
                    alpha: 1
                )
            }
            func draw(_ text: String, font: UIFont, color: UIColor = .black,
                      at point: CGPoint, width: CGFloat, alignment: NSTextAlignment = .left) {
                let paragraph = NSMutableParagraphStyle()
                paragraph.alignment = alignment
                paragraph.lineBreakMode = .byTruncatingTail
                (text as NSString).draw(
                    in: CGRect(x: point.x, y: point.y, width: width, height: font.lineHeight * 2),
                    withAttributes: [.font: font, .foregroundColor: color, .paragraphStyle: paragraph]
                )
            }

            // Letterhead
            if let logo {
                let logoRect = CGRect(x: margin, y: y, width: 48, height: 48)
                logo.draw(in: logoRect)
            }
            let leftX = margin + (logo == nil ? 0 : 56)
            draw(config.companyName, font: .boldSystemFont(ofSize: 14), at: CGPoint(x: leftX, y: y), width: contentWidth / 2)
            let contactLines = [config.licenseNumber, config.phone, config.address,
                                [config.email, config.website].filter { !$0.isEmpty }.joined(separator: " · ")]
                .filter { !$0.isEmpty }
            for (index, line) in contactLines.enumerated() {
                draw(line, font: .systemFont(ofSize: 8), color: .darkGray,
                     at: CGPoint(x: leftX, y: y + 18 + CGFloat(index) * 10), width: contentWidth / 2)
            }
            for (index, line) in document.titleRight.enumerated() {
                draw(line, font: index == 0 ? .boldSystemFont(ofSize: 16) : .systemFont(ofSize: 10),
                     at: CGPoint(x: margin + contentWidth / 2, y: y + CGFloat(index) * 16),
                     width: contentWidth / 2, alignment: .right)
            }
            y += max(56, CGFloat(18 + contactLines.count * 10)) + 8
            draw(document.meta, font: .systemFont(ofSize: 9), color: .darkGray,
                 at: CGPoint(x: margin, y: y), width: contentWidth)
            y += 16

            // Title block — 3-column grid
            let cellWidth = contentWidth / 3
            let cellHeight: CGFloat = 24
            for (index, field) in document.titleBlock.enumerated() {
                let column = index % 3
                let row = index / 3
                let x = margin + CGFloat(column) * cellWidth
                let cellY = y + CGFloat(row) * cellHeight
                let rect = CGRect(x: x, y: cellY, width: cellWidth, height: cellHeight)
                UIColor.separator.setStroke()
                UIBezierPath(rect: rect).stroke()
                draw(field.label.uppercased(), font: .systemFont(ofSize: 6), color: .gray,
                     at: CGPoint(x: x + 3, y: cellY + 2), width: cellWidth - 6)
                draw(field.value, font: .systemFont(ofSize: 9),
                     at: CGPoint(x: x + 3, y: cellY + 10), width: cellWidth - 6)
            }
            y += CGFloat((document.titleBlock.count + 2) / 3) * cellHeight + 12

            // Table header
            let showWire = document.rows.contains { $0.wire != nil }
            let showVA = document.rows.contains { $0.va != nil }
            var columns: [(title: String, width: CGFloat)] = [("CKT", 44)]
            columns.append(("CIRCUIT / LOAD SERVED", 0))   // flexible
            if showWire { columns.append(("WIRE", 48)) }
            columns.append(("BREAKER", 60))
            if showVA { columns.append(("VA", 44)) }
            columns.append(("PH", 30))
            let fixed = columns.reduce(0) { $0 + $1.width }
            let flexWidth = contentWidth - fixed
            let headerRect = CGRect(x: margin, y: y, width: contentWidth, height: 14)
            (config.grayscale ? UIColor.darkGray : UIColor.black).setFill()
            UIBezierPath(rect: headerRect).fill()
            var x = margin
            for column in columns {
                let width = column.width == 0 ? flexWidth : column.width
                draw(column.title, font: .boldSystemFont(ofSize: 7), color: .white,
                     at: CGPoint(x: x + 3, y: y + 3), width: width - 6)
                x += width
            }
            y += 14

            // Rows
            for row in document.rows {
                if y > pageRect.height - margin - 120 {
                    context.beginPage()
                    y = margin
                }
                var x = margin
                let rowFont = UIFont.systemFont(ofSize: 8)
                let rowHeight: CGFloat = 12
                if row.isEmpty {
                    draw(row.slot, font: rowFont, color: .gray, at: CGPoint(x: x + 3, y: y + 1), width: 40)
                    draw(row.loadServed, font: .italicSystemFont(ofSize: 8), color: .gray,
                         at: CGPoint(x: x + 47, y: y + 1), width: flexWidth)
                } else {
                    draw("\(row.slot) \(row.typeShortCode)", font: rowFont, at: CGPoint(x: x + 3, y: y + 1), width: 40)
                    x += 44
                    draw(row.loadServed, font: rowFont, at: CGPoint(x: x + 3, y: y + 1), width: flexWidth - 6)
                    x += flexWidth
                    if showWire {
                        draw(row.wire ?? "", font: rowFont, at: CGPoint(x: x + 3, y: y + 1), width: 42)
                        x += 48
                    }
                    draw(row.breaker, font: rowFont, color: color(row.typeColorHex),
                         at: CGPoint(x: x + 3, y: y + 1), width: 54)
                    x += 60
                    if showVA {
                        draw(row.va.map(String.init) ?? "", font: rowFont, at: CGPoint(x: x + 3, y: y + 1), width: 38)
                        x += 44
                    }
                    draw(row.phases, font: rowFont, at: CGPoint(x: x + 3, y: y + 1), width: 26)
                }
                UIColor.separator.setStroke()
                let line = UIBezierPath()
                line.move(to: CGPoint(x: margin, y: y + rowHeight))
                line.addLine(to: CGPoint(x: margin + contentWidth, y: y + rowHeight))
                line.stroke()
                y += rowHeight
            }
            y += 10

            // Load summary box
            let summary = document.summary
            var summaryLines: [String] = []
            for (index, va) in summary.perLegVA.enumerated() {
                let letter = PanelPhaseLeg(rawValue: index)?.letter ?? "?"
                summaryLines.append("Leg \(letter): \(va) VA · \(summary.perLegAmps[index]) A · \(summary.perLegPercent[index])%")
            }
            summaryLines.append("Total connected: \(summary.totalConnectedVA) VA · Service (balanced): \(summary.serviceAmps) A")
            summaryLines.append("Imbalance: \(summary.imbalancePercent)%")
            if let factor = summary.demandFactorPercent,
               let demandVA = summary.demandVA, let demandAmps = summary.demandAmps,
               let minService = summary.minServiceAmps {
                summaryLines.append("Demand \(factor)%: \(demandVA) VA · \(demandAmps) A → Min. service \(minService) A")
            }
            let boxHeight = CGFloat(summaryLines.count) * 11 + 16
            if y > pageRect.height - margin - boxHeight - 60 {
                context.beginPage()
                y = margin
            }
            let box = CGRect(x: margin, y: y, width: contentWidth, height: boxHeight)
            UIColor.separator.setStroke()
            UIBezierPath(rect: box).stroke()
            draw("LOAD SUMMARY", font: .boldSystemFont(ofSize: 7), color: .gray,
                 at: CGPoint(x: margin + 4, y: y + 3), width: contentWidth)
            for (index, line) in summaryLines.enumerated() {
                let isImbalanceWarning = line.hasPrefix("Imbalance") && summary.imbalancePercent > 20
                draw(line, font: .systemFont(ofSize: 8),
                     color: isImbalanceWarning && !config.grayscale ? .orange : .black,
                     at: CGPoint(x: margin + 4, y: y + 13 + CGFloat(index) * 11), width: contentWidth - 8)
            }
            y += boxHeight + 10

            // Notes
            if !document.notes.isEmpty {
                draw("NOTES", font: .boldSystemFont(ofSize: 7), color: .gray,
                     at: CGPoint(x: margin, y: y), width: contentWidth)
                y += 10
                for note in document.notes {
                    draw(note, font: .systemFont(ofSize: 8), at: CGPoint(x: margin, y: y), width: contentWidth)
                    y += 11
                }
                y += 6
            }

            // Signatures
            if config.showSignatures {
                let thirds = contentWidth / 3
                for (index, label) in ["Drawn", "Checked", "Approved"].enumerated() {
                    let x = margin + CGFloat(index) * thirds
                    let line = UIBezierPath()
                    line.move(to: CGPoint(x: x, y: y + 18))
                    line.addLine(to: CGPoint(x: x + thirds - 20, y: y + 18))
                    UIColor.black.setStroke()
                    line.stroke()
                    draw(label, font: .systemFont(ofSize: 7), color: .gray,
                         at: CGPoint(x: x, y: y + 21), width: thirds - 20)
                }
                y += 40
            }

            // Footer (always)
            draw(document.footer, font: .systemFont(ofSize: 7), color: .gray,
                 at: CGPoint(x: margin, y: pageRect.height - margin + 8), width: contentWidth)
        }
    }
}

// MARK: - Print preview sheet

struct PanelPrintPreviewSheet: View {
    @Environment(\.dismiss) private var dismiss
    let panelName: String
    let panel: DesignPanelState
    @Binding var config: PanelPrintConfig
    @State private var pdfData: Data?
    @State private var showSetup = false

    var body: some View {
        NavigationStack {
            Group {
                if let pdfData {
                    PanelPDFKitView(data: pdfData)
                        .ignoresSafeArea(edges: .bottom)
                } else {
                    ProgressView("Building document…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .navigationTitle("Print Preview")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                        .accessibilityIdentifier("panelPrintClose")
                }
                ToolbarItem(placement: .primaryAction) {
                    if let pdfData {
                        ShareLink(
                            item: PanelPDFFile(data: pdfData, name: panelName),
                            preview: SharePreview("\(panelName) Panel Schedule")
                        ) {
                            Label("Print / Save PDF", systemImage: "printer")
                        }
                        .accessibilityIdentifier("panelPrintShare")
                    }
                }
                ToolbarItem(placement: .bottomBar) {
                    Button("Customize") { showSetup = true }
                        .frame(minHeight: 44)
                        .accessibilityIdentifier("panelPrintCustomize")
                }
            }
            .sheet(isPresented: $showSetup, onDismiss: rebuild) {
                PanelPrintSetupSheet(config: $config)
            }
            .task { rebuild() }
        }
    }

    private func rebuild() {
        let document = PanelPrintDocument.assemble(panelName: panelName, panel: panel, config: config)
        let logo = config.logoPath.flatMap { UIImage(contentsOfFile: $0) }
        pdfData = PanelSchedulePDFRenderer.render(document: document, config: config, logo: logo)
    }
}

private struct PanelPDFKitView: UIViewRepresentable {
    let data: Data
    func makeUIView(context: Context) -> PDFView {
        let view = PDFView()
        view.autoScales = true
        view.document = PDFDocument(data: data)
        return view
    }
    func updateUIView(_ view: PDFView, context: Context) {
        view.document = PDFDocument(data: data)
    }
}

private struct PanelPDFFile: Transferable {
    let data: Data
    let name: String
    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .pdf) { $0.data }
            .suggestedFileName { "\($0.name) Panel Schedule.pdf" }
    }
}

// MARK: - Print setup sheet

struct PanelPrintSetupSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var config: PanelPrintConfig

    var body: some View {
        NavigationStack {
            Form {
                Section("Company letterhead") {
                    TextField("Company name", text: $config.companyName)
                    TextField("License #", text: $config.licenseNumber)
                    TextField("Phone", text: $config.phone)
                    TextField("Address", text: $config.address)
                    TextField("Email", text: $config.email)
                    TextField("Website", text: $config.website)
                }
                Section("Project") {
                    TextField("Project", text: $config.project)
                    TextField("Job #", text: $config.jobNumber)
                    TextField("Location", text: $config.location)
                    TextField("Fed from", text: $config.fedFrom)
                    TextField("Revision", text: $config.revision)
                    TextField("Drawn by", text: $config.drawnBy)
                    TextField("Checked by", text: $config.checkedBy)
                }
                Section("Panel details") {
                    TextField("AIC (kA)", text: $config.aicKA)
                    TextField("Feeder conductor", text: $config.feederConductor)
                    Picker("Mounting", selection: $config.mounting) {
                        ForEach(PanelPrintConfig.Mounting.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                    }
                    Picker("Enclosure", selection: $config.enclosure) {
                        ForEach(PanelPrintConfig.Enclosure.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                    }
                }
                Section("Demand") {
                    Stepper("Demand factor: \(config.demandFactorPercent)%",
                            value: $config.demandFactorPercent, in: 25...150, step: 5)
                        .accessibilityIdentifier("panelDemandStepper")
                }
                Section("Show on schedule") {
                    Toggle("VA column", isOn: $config.showVAColumn)
                    Toggle("Wire size column", isOn: $config.showWireColumn)
                    Toggle("Empty spaces", isOn: $config.showEmptySpaces)
                    Toggle("Phase bars", isOn: $config.showPhaseBars)
                    Toggle("Demand calc", isOn: $config.showDemandCalc)
                    Toggle("Notes", isOn: $config.showNotes)
                    Toggle("Signature blocks", isOn: $config.showSignatures)
                    Toggle("Grayscale / B&W", isOn: $config.grayscale)
                }
                Section("Paper") {
                    Picker("Paper size", selection: $config.paper) {
                        ForEach(PanelPrintConfig.Paper.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                }
            }
            .navigationTitle("Print Setup")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .accessibilityIdentifier("panelPrintSetupDone")
                }
            }
        }
    }
}
