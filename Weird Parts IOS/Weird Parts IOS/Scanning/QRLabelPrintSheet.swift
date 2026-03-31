import SwiftUI
import WiredPartCore

/// Visual grid where users tap to mark which sticker positions are already used.
/// Tapped positions turn gray/crossed-out. Remaining positions get labels.
struct UsedStickerPicker: View {
    let grid: LabelGrid
    @Binding var usedPositions: Set<Int>

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Tap positions already used on your sheet:")
                .font(.caption)
                .foregroundStyle(.secondary)

            // Grid representation of the sticker sheet
            let columns = Array(repeating: GridItem(.flexible(), spacing: 4), count: grid.columns)
            LazyVGrid(columns: columns, spacing: 4) {
                ForEach(0..<grid.totalPositions, id: \.self) { position in
                    Button {
                        if usedPositions.contains(position) {
                            usedPositions.remove(position)
                        } else {
                            usedPositions.insert(position)
                        }
                    } label: {
                        ZStack {
                            RoundedRectangle(cornerRadius: 4)
                                .fill(usedPositions.contains(position)
                                      ? Color.gray.opacity(0.3)
                                      : Color.accentColor.opacity(0.1))
                                .aspectRatio(grid.labelWidth / grid.labelHeight, contentMode: .fit)

                            if usedPositions.contains(position) {
                                Image(systemName: "xmark")
                                    .font(.caption2)
                                    .foregroundStyle(.gray)
                                    .accessibilityHidden(true)
                            } else {
                                Text("\(position + 1)")
                                    .font(.caption2)
                                    .foregroundStyle(Color.accentColor)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    .frame(minHeight: 30)
                    .accessibilityLabel(usedPositions.contains(position) ? "Position \(position + 1): Used" : "Position \(position + 1): Available")
                }
            }

            HStack {
                Text("\(grid.totalPositions - usedPositions.count) labels will print")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Clear All") { usedPositions.removeAll() }
                    .font(.caption)
                Button("Use All") { usedPositions = Set(0..<grid.totalPositions) }
                    .font(.caption)
            }
        }
    }
}

// MARK: - Label Print Sheet

/// Full-featured label printing sheet.
/// Shows size picker, layout picker, paper picker, used-sticker grid, preview, and print button.
struct QRLabelPrintSheet: View {
    let items: [QRLabelContent]
    @Environment(\.dismiss) private var dismiss

    @State private var labelSize: QRLabelSize = .standard
    @State private var labelLayout: QRLabelLayout = .qrLeft
    @State private var paperSize: QRPaperSize = .letter
    @State private var usedPositions: Set<Int> = []
    @State private var isPrinting = false
    @State private var printError: String?

    var body: some View {
        NavigationStack {
            Form {
                // Summary
                Section {
                    LabeledContent("Labels to Print", value: "\(items.count)")
                }

                // Label size
                Section("Label Size") {
                    Picker("Size", selection: $labelSize) {
                        ForEach(QRLabelSize.allCases, id: \.self) { size in
                            Text(size.displayName).tag(size)
                        }
                    }
                    .pickerStyle(.menu)
                }

                // Layout
                Section("Layout") {
                    Picker("Layout", selection: $labelLayout) {
                        ForEach(QRLabelLayout.allCases, id: \.self) { layout in
                            Text(layout.displayName).tag(layout)
                        }
                    }
                    .pickerStyle(.menu)

                    // Preview of single label
                    labelPreview
                        .frame(height: 80)
                        .padding(.vertical, 4)
                }

                // Paper type
                Section("Paper") {
                    Picker("Paper Type", selection: $paperSize) {
                        Section("Standard Paper") {
                            Text(QRPaperSize.letter.displayName).tag(QRPaperSize.letter)
                            Text(QRPaperSize.legal.displayName).tag(QRPaperSize.legal)
                            Text(QRPaperSize.a4.displayName).tag(QRPaperSize.a4)
                        }
                        Section("Sticker Sheets") {
                            Text(QRPaperSize.avery5160.displayName).tag(QRPaperSize.avery5160)
                            Text(QRPaperSize.avery5163.displayName).tag(QRPaperSize.avery5163)
                            Text(QRPaperSize.avery5164.displayName).tag(QRPaperSize.avery5164)
                            Text(QRPaperSize.avery5167.displayName).tag(QRPaperSize.avery5167)
                            Text(QRPaperSize.avery8160.displayName).tag(QRPaperSize.avery8160)
                            Text(QRPaperSize.avery5165.displayName).tag(QRPaperSize.avery5165)
                        }
                        Section("Thermal Labels") {
                            Text(QRPaperSize.thermal2x1.displayName).tag(QRPaperSize.thermal2x1)
                            Text(QRPaperSize.thermal4x6.displayName).tag(QRPaperSize.thermal4x6)
                        }
                    }
                    .pickerStyle(.menu)
                }

                // Used sticker picker (only for sticker sheet paper types)
                if let grid = paperSize.labelGrid {
                    Section("Used Positions") {
                        UsedStickerPicker(grid: grid, usedPositions: $usedPositions)
                    }
                }

                // Page count estimate
                Section {
                    let available = availablePositionsPerPage
                    let pages = available > 0 ? Int(ceil(Double(items.count) / Double(available))) : 1
                    LabeledContent("Pages to Print", value: "\(pages)")
                }

                // Error
                if let error = printError {
                    Section {
                        Label(error, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("Print Labels")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        printLabels()
                    } label: {
                        if isPrinting {
                            ProgressView()
                        } else {
                            Label("Print", systemImage: "printer")
                        }
                    }
                    .disabled(items.isEmpty || isPrinting)
                }
            }
            .onChange(of: paperSize) {
                usedPositions.removeAll()
            }
        }
    }

    // MARK: - Label Preview

    @ViewBuilder
    private var labelPreview: some View {
        if let first = items.first {
            GeometryReader { geo in
                let size = CGSize(width: geo.size.width, height: geo.size.height)
                ZStack {
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(Color.secondary.opacity(0.3), lineWidth: 1)

                    Group {
                        switch labelLayout {
                        case .qrLeft:
                            HStack(spacing: 8) {
                                qrPlaceholder(size: min(size.height - 8, size.width * 0.3))
                                textPlaceholder(content: first)
                            }
                        case .qrRight:
                            HStack(spacing: 8) {
                                textPlaceholder(content: first)
                                qrPlaceholder(size: min(size.height - 8, size.width * 0.3))
                            }
                        case .qrTop:
                            VStack(spacing: 4) {
                                qrPlaceholder(size: size.height * 0.5)
                                textPlaceholder(content: first)
                            }
                        case .qrBottom:
                            VStack(spacing: 4) {
                                textPlaceholder(content: first)
                                qrPlaceholder(size: size.height * 0.5)
                            }
                        case .qrCenter:
                            qrPlaceholder(size: size.height * 0.6)
                        case .codeOnly:
                            qrPlaceholder(size: size.height - 8)
                        }
                    }
                    .padding(8)
                }
            }
        }
    }

    private func qrPlaceholder(size: CGFloat) -> some View {
        Image(systemName: "qrcode")
            .resizable()
            .scaledToFit()
            .frame(width: size, height: size)
            .foregroundStyle(Color.accentColor)
            .accessibilityHidden(true)
    }

    private func textPlaceholder(content: QRLabelContent) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(content.title)
                .font(.caption2)
                .fontWeight(.bold)
                .lineLimit(1)
            Text(content.code)
                .font(.caption2)
                .monospaced()
                .foregroundStyle(.secondary)
                .lineLimit(1)
            if let sub = content.subtitle {
                Text(sub)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
        }
    }

    // MARK: - Helpers

    private var availablePositionsPerPage: Int {
        if let grid = paperSize.labelGrid {
            return grid.totalPositions - usedPositions.count
        }
        // Plain paper: auto-calculate
        let pageSize = paperSize.pageSizePoints
        let labelDim = labelSize.sizePoints
        let cols = max(1, Int((pageSize.width - 72) / (labelDim.width + 8)))
        let rows = max(1, Int((pageSize.height - 72) / (labelDim.height + 8)))
        return cols * rows
    }

    private func printLabels() {
        isPrinting = true
        printError = nil

        guard let pdfData = QRLabelPDFGenerator.generatePDF(
            items: items,
            labelSize: labelSize,
            layout: labelLayout,
            paperSize: paperSize,
            usedPositions: usedPositions
        ) else {
            printError = "Failed to generate PDF."
            isPrinting = false
            return
        }

        let printController = UIPrintInteractionController.shared
        printController.printingItem = pdfData

        let printInfo = UIPrintInfo(dictionary: nil)
        printInfo.jobName = "WiredPart Labels"
        printInfo.outputType = .general
        printController.printInfo = printInfo

        printController.present(animated: true) { _, completed, error in
            isPrinting = false
            if let error = error {
                printError = userFriendlyError(error, context: "print labels")
            } else if completed {
                dismiss()
            }
        }
    }
}
