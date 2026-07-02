import SwiftUI
import UIKit
import WiredPartCore

// MARK: - Panel Schedule PDF Export

enum PanelScheduleExportError: LocalizedError {
    case outputPathUnavailable

    var errorDescription: String? {
        switch self {
        case .outputPathUnavailable:
            return "The generated PDF could not be validated."
        }
    }
}

enum PanelSchedulePaperSize: String, CaseIterable, Identifiable {
    case letter = "Letter"
    case legal = "Legal"
    case a4 = "A4"
    case cardStock = "Card Stock"

    var id: String { rawValue }

    var pageSize: CGSize {
        switch self {
        case .letter:
            return CGSize(width: 612, height: 792)
        case .legal:
            return CGSize(width: 612, height: 1008)
        case .a4:
            return CGSize(width: 595, height: 842)
        case .cardStock:
            return CGSize(width: 576, height: 720)
        }
    }
}

struct PanelScheduleExportOptions {
    var paperSize: PanelSchedulePaperSize = .letter
    var companyName = "WiredPart"
    var address = ""
    var phone = ""
    var licenseNumber = ""
    var preparedBy = ""
    var footerNote = ""
}

struct PanelSchedulePDFExporter {
    let schedule: PanelSchedule
    let options: PanelScheduleExportOptions

    func writeToTemporaryFile(fileManager: FileManager = .default) throws -> URL {
        // Persist-time normalization (clamped totalSpaces, pruned out-of-range
        // circuits) is the closest equivalent to a "validated" schedule on
        // current main — `PanelSchedule` does not expose a `validated()`
        // throwing method here, unlike the donor branch's later panel-editing
        // lane. Rendering against the normalized copy keeps the export in
        // sync with what `PanelScheduleBuilder`'s Save action persists.
        let normalizedSchedule = schedule.normalizedForPersistence()

        let directory = fileManager.temporaryDirectory.appendingPathComponent("PanelSchedules", isDirectory: true)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)

        let url = directory.appendingPathComponent(filename)
        let data = renderPDF(schedule: normalizedSchedule)
        try data.write(to: url, options: .atomic)

        guard fileManager.fileExists(atPath: url.path),
              ((try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0) > 0 else {
            throw PanelScheduleExportError.outputPathUnavailable
        }
        return url
    }

    private var filename: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        let date = formatter.string(from: Date())
        let safePanelName = schedule.panelName
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: "_")
        return "\((safePanelName.isEmpty ? "Panel_Schedule" : safePanelName))_\(date).pdf"
    }

    private func renderPDF(schedule: PanelSchedule) -> Data {
        let pageSize = options.paperSize.pageSize
        let renderer = UIGraphicsPDFRenderer(bounds: CGRect(origin: .zero, size: pageSize))
        let margin: CGFloat = 36

        return renderer.pdfData { context in
            context.beginPage()

            var y = margin
            drawHeader(in: pageSize, margin: margin, y: &y)
            y += 14
            drawPanelInfo(schedule: schedule, margin: margin, y: &y)
            y += 10
            drawScheduleTable(schedule: schedule, in: pageSize, margin: margin, y: &y)
            drawFooter(in: pageSize, margin: margin)
        }
    }

    private func drawHeader(in pageSize: CGSize, margin: CGFloat, y: inout CGFloat) {
        let titleAttributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.boldSystemFont(ofSize: 18),
            .foregroundColor: UIColor.black
        ]
        let bodyAttributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 9),
            .foregroundColor: UIColor.darkGray
        ]

        options.companyName.draw(
            in: CGRect(x: margin, y: y, width: pageSize.width - margin * 2, height: 24),
            withAttributes: titleAttributes
        )
        y += 24

        let headerLines = [options.address, options.phone, options.licenseNumber]
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        for line in headerLines {
            line.draw(
                in: CGRect(x: margin, y: y, width: pageSize.width - margin * 2, height: 13),
                withAttributes: bodyAttributes
            )
            y += 13
        }

        UIColor.systemGray3.setStroke()
        UIBezierPath(rect: CGRect(x: margin, y: y + 4, width: pageSize.width - margin * 2, height: 1)).stroke()
        y += 12
    }

    private func drawPanelInfo(schedule: PanelSchedule, margin: CGFloat, y: inout CGFloat) {
        let titleAttributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.boldSystemFont(ofSize: 16),
            .foregroundColor: UIColor.black
        ]
        let metaAttributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 10),
            .foregroundColor: UIColor.darkGray
        ]

        "\(schedule.panelName) Panel Schedule".draw(
            in: CGRect(x: margin, y: y, width: 420, height: 22),
            withAttributes: titleAttributes
        )
        y += 24

        let main = schedule.mainBreakerAmps.map { "\($0)A Main" } ?? "MLO"
        let location = schedule.location?.isEmpty == false ? " | \(schedule.location ?? "")" : ""
        let metadata = "\(schedule.panelType.rawValue) | \(schedule.totalSpaces) Spaces | \(main) | \(schedule.voltage)V | \(schedule.phase) Phase\(location)"
        metadata.draw(in: CGRect(x: margin, y: y, width: 520, height: 16), withAttributes: metaAttributes)
        y += 18

        let prepared = options.preparedBy.trimmingCharacters(in: .whitespacesAndNewlines)
        if !prepared.isEmpty {
            "Prepared by: \(prepared)".draw(in: CGRect(x: margin, y: y, width: 420, height: 14), withAttributes: metaAttributes)
            y += 16
        }
    }

    private func drawScheduleTable(schedule: PanelSchedule, in pageSize: CGSize, margin: CGFloat, y: inout CGFloat) {
        let contentWidth = pageSize.width - margin * 2
        let rowHeight: CGFloat = 18
        let halfWidth = (contentWidth - 6) / 2
        let leftX = margin
        let rightX = margin + halfWidth + 6
        let headerAttributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.boldSystemFont(ofSize: 8),
            .foregroundColor: UIColor.black
        ]
        let cellAttributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 8),
            .foregroundColor: UIColor.darkGray
        ]

        func drawHalfHeader(x: CGFloat) {
            UIColor.systemGray5.setFill()
            UIBezierPath(rect: CGRect(x: x, y: y, width: halfWidth, height: rowHeight)).fill()
            drawRowText("#", x: x + 4, y: y + 4, width: 18, attributes: headerAttributes)
            drawRowText("A", x: x + 24, y: y + 4, width: 22, attributes: headerAttributes)
            drawRowText("Circuit", x: x + 48, y: y + 4, width: halfWidth - 52, attributes: headerAttributes)
        }

        drawHalfHeader(x: leftX)
        drawHalfHeader(x: rightX)
        y += rowHeight

        // max(..., 0) mirrors the same guard PanelScheduleBuilder's grid uses
        // (#1239) so a malformed non-positive totalSpaces can never produce a
        // negative range here either.
        for row in 0..<max(schedule.totalSpaces / 2, 0) {
            if y + rowHeight > pageSize.height - margin - 38 {
                break
            }

            let leftSpace = row * 2 + 1
            let rightSpace = row * 2 + 2
            drawCircuitRow(schedule: schedule, spaceNumber: leftSpace, x: leftX, width: halfWidth, y: y, attributes: cellAttributes)
            drawCircuitRow(schedule: schedule, spaceNumber: rightSpace, x: rightX, width: halfWidth, y: y, attributes: cellAttributes)
            y += rowHeight
        }
    }

    private func drawCircuitRow(
        schedule: PanelSchedule,
        spaceNumber: Int,
        x: CGFloat,
        width: CGFloat,
        y: CGFloat,
        attributes: [NSAttributedString.Key: Any]
    ) {
        let circuit = schedule.circuits.first { $0.spaceNumber == spaceNumber }
        UIColor.systemGray4.setStroke()
        UIBezierPath(rect: CGRect(x: x, y: y, width: width, height: 18)).stroke()

        drawRowText("\(spaceNumber)", x: x + 4, y: y + 4, width: 18, attributes: attributes)
        drawRowText(circuit?.breakerAmps.map { "\($0)" } ?? "-", x: x + 24, y: y + 4, width: 22, attributes: attributes)
        drawRowText(circuitDescription(circuit), x: x + 48, y: y + 4, width: width - 52, attributes: attributes)
    }

    private func circuitDescription(_ circuit: CircuitEntry?) -> String {
        guard let circuit else { return "SPARE" }
        if circuit.isSpare || circuit.circuitDescription.isEmpty {
            return "SPARE"
        }
        return circuit.circuitDescription
    }

    private func drawRowText(
        _ text: String,
        x: CGFloat,
        y: CGFloat,
        width: CGFloat,
        attributes: [NSAttributedString.Key: Any]
    ) {
        (text as NSString).draw(in: CGRect(x: x, y: y, width: width, height: 12), withAttributes: attributes)
    }

    private func drawFooter(in pageSize: CGSize, margin: CGFloat) {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 8),
            .foregroundColor: UIColor.gray
        ]
        let date = Date().formatted(.dateTime.month().day().year().hour().minute())
        let footer = options.footerNote.trimmingCharacters(in: .whitespacesAndNewlines)
        let left = footer.isEmpty ? "Generated \(date)" : "\(footer) | Generated \(date)"
        left.draw(
            in: CGRect(x: margin, y: pageSize.height - margin + 8, width: pageSize.width - margin * 2, height: 12),
            withAttributes: attributes
        )
    }
}

struct PanelScheduleHeaderSheet: View {
    @Binding var options: PanelScheduleExportOptions
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("Layout") {
                    Picker("Paper Size", selection: $options.paperSize) {
                        ForEach(PanelSchedulePaperSize.allCases) { size in
                            Text(size.rawValue).tag(size)
                        }
                    }
                }

                Section("Company Header") {
                    TextField("Company Name", text: $options.companyName)
                    TextField("Address", text: $options.address, axis: .vertical)
                    TextField("Phone", text: $options.phone)
                    TextField("License Number", text: $options.licenseNumber)
                }

                Section("Footer") {
                    TextField("Prepared By", text: $options.preparedBy)
                    TextField("Footer Note", text: $options.footerNote, axis: .vertical)
                }
            }
            .navigationTitle("Panel Header")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .fontWeight(.semibold)
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

struct PanelScheduleShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
