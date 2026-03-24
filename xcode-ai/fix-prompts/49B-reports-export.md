# 49B — Reports Export (PDF + CSV)

> **Chain position:** 49A → **49B** → 49C
> **Prerequisite:** 49A (reports categories)
> **Log file:** `xcode-ai/prompt-results-log.md`

## MANDATORY RULES
1. DO NOT use `import GRDB` in UI files
2. DO NOT use empty `catch { }` blocks
3. DO NOT use `#if os(iOS)` guards
4. Use ActiveSheet enum for all sheets
5. Fix ALL silent guard returns — show errors in UI

## Instructions

**IMPORTANT:** Before implementing, read the existing report pages. Add [Export PDF] and [Export CSV] toolbar buttons to every report page. Build reusable PDF and CSV generation utilities.

## Context

Every report page needs export capability. Two formats: PDF (for printing/sharing — uses UIGraphicsPDFRenderer for proper multi-page layout) and CSV (for spreadsheet analysis — proper escaping for commas, quotes, newlines). The export buttons go in the toolbar. Tapping opens a share sheet with the generated file.

## Task

### Step 1: Reusable PDF Generator

```swift
import UIKit

struct ReportPDFGenerator {
    let title: String
    let subtitle: String?
    let columns: [String]
    let rows: [[String]]
    let generatedAt: Date

    func generatePDF() -> Data {
        let pageWidth: CGFloat = 612  // Letter width in points
        let pageHeight: CGFloat = 792
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

            func startNewPage() {
                context.beginPage()
                currentY = margin
                pageNumber += 1
                drawPageFooter(context: context, pageWidth: pageWidth,
                              pageHeight: pageHeight, margin: margin,
                              pageNumber: pageNumber)
            }

            // First page
            context.beginPage()
            drawPageFooter(context: context, pageWidth: pageWidth,
                          pageHeight: pageHeight, margin: margin, pageNumber: 1)

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
                let subFont = UIFont.systemFont(ofSize: 12)
                let subAttr: [NSAttributedString.Key: Any] = [
                    .font: subFont, .foregroundColor: UIColor.gray
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
            let headerFont = UIFont.boldSystemFont(ofSize: 10)
            let cellFont = UIFont.systemFont(ofSize: 9)
            let colWidth = contentWidth / CGFloat(columns.count)
            let rowHeight: CGFloat = 20

            // Draw header background
            let headerRect = CGRect(x: margin, y: currentY, width: contentWidth, height: rowHeight)
            UIColor.systemGray5.setFill()
            UIBezierPath(rect: headerRect).fill()

            for (i, col) in columns.enumerated() {
                let x = margin + CGFloat(i) * colWidth + 4
                let attr: [NSAttributedString.Key: Any] = [
                    .font: headerFont, .foregroundColor: UIColor.black
                ]
                (col as NSString).draw(
                    in: CGRect(x: x, y: currentY + 4, width: colWidth - 8, height: rowHeight),
                    withAttributes: attr
                )
            }
            currentY += rowHeight

            // Draw rows
            let cellAttr: [NSAttributedString.Key: Any] = [
                .font: cellFont, .foregroundColor: UIColor.darkGray
            ]

            for (rowIndex, row) in rows.enumerated() {
                if currentY + rowHeight > pageHeight - margin - 30 {
                    startNewPage()
                    // Redraw headers on new page
                    let hRect = CGRect(x: margin, y: currentY, width: contentWidth, height: rowHeight)
                    UIColor.systemGray5.setFill()
                    UIBezierPath(rect: hRect).fill()
                    for (i, col) in columns.enumerated() {
                        let x = margin + CGFloat(i) * colWidth + 4
                        (col as NSString).draw(
                            in: CGRect(x: x, y: currentY + 4, width: colWidth - 8, height: rowHeight),
                            withAttributes: [.font: headerFont, .foregroundColor: UIColor.black]
                        )
                    }
                    currentY += rowHeight
                }

                // Alternating row background
                if rowIndex % 2 == 1 {
                    let rowRect = CGRect(x: margin, y: currentY, width: contentWidth, height: rowHeight)
                    UIColor.systemGray6.setFill()
                    UIBezierPath(rect: rowRect).fill()
                }

                for (i, cell) in row.enumerated() {
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

    private func drawPageFooter(context: UIGraphicsPDFRendererContext, pageWidth: CGFloat,
                                pageHeight: CGFloat, margin: CGFloat, pageNumber: Int) {
        let footerAttr: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 8), .foregroundColor: UIColor.gray
        ]
        let footer = "Page \(pageNumber)"
        let footerSize = (footer as NSString).size(withAttributes: footerAttr)
        (footer as NSString).draw(
            at: CGPoint(x: pageWidth - margin - footerSize.width, y: pageHeight - margin + 10),
            withAttributes: footerAttr
        )
    }
}
```

### Step 2: Reusable CSV Generator

```swift
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
        // Escape if contains comma, quote, or newline
        if value.contains(",") || value.contains("\"") || value.contains("\n") {
            let escaped = value.replacingOccurrences(of: "\"", with: "\"\"")
            return "\"\(escaped)\""
        }
        return value
    }
}
```

### Step 3: Export Toolbar Modifier

```swift
struct ReportExportToolbar: ViewModifier {
    let title: String
    let columns: [String]
    let rows: [[String]]
    @State private var showShareSheet = false
    @State private var exportData: Data?
    @State private var exportFilename: String = ""
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
            .sheet(isPresented: $showShareSheet) {
                if let data = exportData {
                    ShareSheet(items: [
                        TemporaryFileItem(data: data, filename: exportFilename)
                    ])
                }
            }
            .alert("Export Error", isPresented: .constant(exportError != nil)) {
                Button("OK") { exportError = nil }
            } message: {
                Text(exportError ?? "")
            }
    }

    func exportPDF() {
        let generator = ReportPDFGenerator(
            title: title, subtitle: nil,
            columns: columns, rows: rows,
            generatedAt: Date()
        )
        exportData = generator.generatePDF()
        exportFilename = "\(title.replacingOccurrences(of: " ", with: "_"))_\(Date().formatted(.dateTime.year().month().day())).pdf"
        showShareSheet = true
    }

    func exportCSV() {
        let generator = ReportCSVGenerator(columns: columns, rows: rows)
        exportData = generator.generateCSV()
        exportFilename = "\(title.replacingOccurrences(of: " ", with: "_"))_\(Date().formatted(.dateTime.year().month().day())).csv"
        showShareSheet = true
    }
}

extension View {
    func reportExportToolbar(title: String, columns: [String], rows: [[String]]) -> some View {
        modifier(ReportExportToolbar(title: title, columns: columns, rows: rows))
    }
}
```

### Step 4: ShareSheet Helper

```swift
struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

class TemporaryFileItem: NSObject, UIActivityItemSource {
    let data: Data
    let filename: String
    let tempURL: URL

    init(data: Data, filename: String) {
        self.data = data
        self.filename = filename
        self.tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(filename)
        try? data.write(to: tempURL)
        super.init()
    }

    func activityViewControllerPlaceholderItem(_ activityViewController: UIActivityViewController) -> Any {
        tempURL
    }

    func activityViewController(_ activityViewController: UIActivityViewController,
                               itemForActivityType activityType: UIActivity.ActivityType?) -> Any? {
        tempURL
    }

    func activityViewController(_ activityViewController: UIActivityViewController,
                               subjectForActivityType activityType: UIActivity.ActivityType?) -> String {
        filename
    }
}
```

### Step 5: Apply to Existing Report Pages

```swift
// Example: Apply to IOSTimesheetReportPage
// In each report page, add the modifier:

.reportExportToolbar(
    title: "Timesheet Report",
    columns: ["Employee", "Date", "Hours", "Job", "Activity"],
    rows: timesheetRows.map { row in
        [row.employeeName, row.date.formatted(), "\(row.hours)", row.jobName, row.activity]
    }
)

// Apply to ALL report pages:
// - IOSDailyReportPage
// - IOSTimesheetReportPage
// - IOSPeriodReportPage
// - IOSPreBillingPage
// - IOSBookkeeperExportPage
// - IOSJobCostReportPage
// - IOSSpendingDashboardPage
// - IOSBudgetReportPage
```

## Important Notes
- PDF uses UIGraphicsPDFRenderer for proper multi-page layout with headers on each page
- CSV properly escapes commas, quotes, and newlines
- Export menu has two options: PDF and CSV
- ShareSheet presents the system share sheet for saving/sending
- Temporary files are created in the temp directory
- Apply .reportExportToolbar() modifier to ALL existing report pages
- Each report page must expose its columns and rows for the export

## Success Criteria
- [ ] ReportPDFGenerator with multi-page support, headers, footers, alternating rows
- [ ] ReportCSVGenerator with proper escaping
- [ ] ReportExportToolbar modifier with PDF + CSV menu
- [ ] ShareSheet helper for system share
- [ ] TemporaryFileItem for proper file sharing
- [ ] Applied to all existing report pages (8+ pages)
- [ ] All errors show in UI
- [ ] Project builds with no errors

## Log Entry
```
## Prompt 49B Results (YYYY-MM-DD)
- PDF generator with multi-page layout
- CSV generator with proper escaping
- Export toolbar modifier applied to all report pages
- ShareSheet for file sharing
- Build: PASS/FAIL
```

**Wait for user confirmation before proceeding to prompt 49C.**
