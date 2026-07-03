import SwiftUI
import UIKit

// MARK: - PDF Generator

/// Generates multi-page PDF reports with title, headers, and tabular data.
struct ReportPDFGenerator {
    let title: String
    let subtitle: String?
    let columns: [String]
    let rows: [[String]]
    let generatedAt: Date

    func generatePDF() -> Data {
        let pageWidth: CGFloat = 612   // Letter width in points
        let pageHeight: CGFloat = 792  // Letter height in points
        let margin: CGFloat = 40
        let contentWidth = pageWidth - (margin * 2)

        let format = UIGraphicsPDFRendererFormat()
        let renderer = UIGraphicsPDFRenderer(
            bounds: CGRect(x: 0, y: 0, width: pageWidth, height: pageHeight),
            format: format
        )

        return renderer.pdfData { context in
            var currentY: CGFloat = margin
            var pageNumber = 1

            let headerFont = UIFont.boldSystemFont(ofSize: 10)
            let cellFont = UIFont.systemFont(ofSize: 9)
            let colWidth = columns.isEmpty ? contentWidth : contentWidth / CGFloat(columns.count)
            let rowHeight: CGFloat = 20

            // Local page footer drawing function
            func drawFooter(pageNum: Int) {
                let footerAttr: [NSAttributedString.Key: Any] = [
                    .font: UIFont.systemFont(ofSize: 8), .foregroundColor: UIColor.gray
                ]
                let footer = "Page \(pageNum)"
                let footerSize = (footer as NSString).size(withAttributes: footerAttr)
                (footer as NSString).draw(
                    at: CGPoint(x: pageWidth - margin - footerSize.width, y: pageHeight - margin + 10),
                    withAttributes: footerAttr
                )
            }

            func startNewPage() {
                context.beginPage()
                currentY = margin
                pageNumber += 1
                drawFooter(pageNum: pageNumber)
            }

            func drawHeaders() {
                let headerRect = CGRect(x: margin, y: currentY, width: contentWidth, height: rowHeight)
                UIColor.systemGray5.setFill()
                UIBezierPath(rect: headerRect).fill()
                for (i, col) in columns.enumerated() {
                    let x = margin + CGFloat(i) * colWidth + 4
                    (col as NSString).draw(
                        in: CGRect(x: x, y: currentY + 4, width: colWidth - 8, height: rowHeight),
                        withAttributes: [.font: headerFont, .foregroundColor: UIColor.black]
                    )
                }
                currentY += rowHeight
            }

            // First page
            context.beginPage()
            drawFooter(pageNum: 1)

            // Title
            let titleFont = UIFont.boldSystemFont(ofSize: 18)
            let titleAttr: [NSAttributedString.Key: Any] = [
                .font: titleFont, .foregroundColor: UIColor.black
            ]
            let titleSize = (title as NSString).size(withAttributes: titleAttr)
            (title as NSString).draw(at: CGPoint(x: margin, y: currentY), withAttributes: titleAttr)
            currentY += titleSize.height + 8

            // Subtitle
            if let subtitle = subtitle {
                let subAttr: [NSAttributedString.Key: Any] = [
                    .font: UIFont.systemFont(ofSize: 12), .foregroundColor: UIColor.gray
                ]
                (subtitle as NSString).draw(at: CGPoint(x: margin, y: currentY), withAttributes: subAttr)
                currentY += 20
            }

            // Generated date
            let dateStr = "Generated: \(generatedAt.formatted(.dateTime.month().day().year().hour().minute()))"
            let dateAttr: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 10), .foregroundColor: UIColor.gray
            ]
            (dateStr as NSString).draw(at: CGPoint(x: margin, y: currentY), withAttributes: dateAttr)
            currentY += 24

            // Column headers
            drawHeaders()

            // Data rows
            let cellAttr: [NSAttributedString.Key: Any] = [
                .font: cellFont, .foregroundColor: UIColor.darkGray
            ]

            for (rowIndex, row) in rows.enumerated() {
                if currentY + rowHeight > pageHeight - margin - 30 {
                    startNewPage()
                    drawHeaders()
                }

                // Alternating row background
                if rowIndex % 2 == 1 {
                    let rowRect = CGRect(x: margin, y: currentY, width: contentWidth, height: rowHeight)
                    UIColor.systemGray6.setFill()
                    UIBezierPath(rect: rowRect).fill()
                }

                for (i, cell) in row.enumerated() {
                    guard i < columns.count else { break }
                    let x = margin + CGFloat(i) * colWidth + 4
                    (cell as NSString).draw(
                        in: CGRect(x: x, y: currentY + 4, width: colWidth - 8, height: rowHeight),
                        withAttributes: cellAttr
                    )
                }
                currentY += rowHeight
            }
        }
    }


}

// MARK: - CSV Generator

/// Generates CSV data with proper escaping for commas, quotes, and newlines.
struct ReportCSVGenerator {
    let columns: [String]
    let rows: [[String]]

    func generateCSV() -> Data {
        var csv = ""

        // Header row
        csv += columns.map { escapeCSV($0) }.joined(separator: ",") + "\n"

        // Data rows
        for row in rows {
            csv += row.map { escapeCSV($0) }.joined(separator: ",") + "\n"
        }

        return csv.data(using: .utf8) ?? Data()
    }

    private func escapeCSV(_ value: String) -> String {
        if value.contains(",") || value.contains("\"") || value.contains("\n") {
            let escaped = value.replacingOccurrences(of: "\"", with: "\"\"")
            return "\"\(escaped)\""
        }
        return value
    }
}

// MARK: - Export Toolbar Modifier

/// ViewModifier that adds PDF and CSV export buttons to the toolbar.
struct ReportExportToolbar: ViewModifier {
    let title: String
    let columns: [String]
    let rows: [[String]]
    private enum ExportSheet: Identifiable {
        case share(URL)
        var id: String { "share" }
    }
    @State private var activeExportSheet: ExportSheet?
    @State private var exportError: String?

    func body(content: Content) -> some View {
        content
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button {
                            exportPDF()
                        } label: {
                            Label("Export PDF", systemImage: "doc.fill")
                        }

                        Button {
                            exportCSV()
                        } label: {
                            Label("Export CSV", systemImage: "tablecells")
                        }
                    } label: {
                        Label("Export", systemImage: "square.and.arrow.up")
                    }
                }
            }
            .sheet(item: $activeExportSheet) { sheet in
                switch sheet {
                case .share(let url):
                    ReportShareSheet(items: [url])
                }
            }
            .alert("Export Error", isPresented: Binding(
                get: { exportError != nil },
                set: { if !$0 { exportError = nil } }
            )) {
                Button("OK") { exportError = nil }
            } message: {
                Text(exportError ?? "")
            }
    }

    private func exportPDF() {
        let generator = ReportPDFGenerator(
            title: title, subtitle: nil,
            columns: columns, rows: rows,
            generatedAt: Date()
        )
        let data = generator.generatePDF()
        let filename = sanitizedFilename(title, ext: "pdf")
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(filename)
        do {
            try data.write(to: url)
            activeExportSheet = .share(url)
        } catch {
            exportError = userFriendlyError(error, context: "create pdf")
        }
    }

    private func exportCSV() {
        let generator = ReportCSVGenerator(columns: columns, rows: rows)
        let data = generator.generateCSV()
        let filename = sanitizedFilename(title, ext: "csv")
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(filename)
        do {
            try data.write(to: url)
            activeExportSheet = .share(url)
        } catch {
            exportError = userFriendlyError(error, context: "create csv")
        }
    }

    private func sanitizedFilename(_ title: String, ext: String) -> String {
        let dateStr = {
            let fmt = DateFormatter()
            fmt.dateFormat = "yyyy-MM-dd"
            return fmt.string(from: Date())
        }()
        let safe = title.replacingOccurrences(of: " ", with: "_")
        return "\(safe)_\(dateStr).\(ext)"
    }
}

extension View {
    /// Adds PDF and CSV export buttons to the toolbar.
    func reportExportToolbar(title: String, columns: [String], rows: [[String]]) -> some View {
        modifier(ReportExportToolbar(title: title, columns: columns, rows: rows))
    }
}

// MARK: - Share Sheet

/// System share sheet wrapper for sharing files.
struct ReportShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
