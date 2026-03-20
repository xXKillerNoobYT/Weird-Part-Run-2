# 21B — QR Label Print UI: Size Picker, Layout Preview, Used Sticker Picker

> **Chain position:** 21A → **21B**
> **Prerequisite:** 21A complete (QRLabelPDFGenerator exists)
> **Log file:** `xcode-ai/prompt-results-log.md`

## Instructions

**IMPORTANT:** Before implementing, first plan your approach by reading all files mentioned below. Understand the current state, then implement the fixes. When done, wait for the user to confirm before proceeding to the next prompt.

## Context

The PDF label engine (21A) can generate label PDFs. Now we need the UI for users to:
1. Pick label size, layout, and paper type
2. Preview labels before printing
3. Select which positions on a sticker sheet are already used (partially-used sheet support)
4. Print via iOS built-in print system

This UI should be accessible from any page that shows entities with QR codes (Parts Catalog, Tool Registry, Warehouse bins, etc.).

**Files to create:**
- `Weird Parts IOS/Weird Parts IOS/Scanning/QRLabelPrintSheet.swift`

**Files to modify (add print button):**
- `Weird Parts IOS/Weird Parts IOS/Features/Parts/PartsCatalogPage.swift` — print labels for selected/filtered parts
- `Weird Parts IOS/Weird Parts IOS/Features/Tools/IOSToolRegistryPage.swift` — print labels for tools
- Other pages as appropriate

## Task

### Step 1: Create the used sticker position picker

```swift
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
                            } else {
                                Text("\(position + 1)")
                                    .font(.caption2)
                                    .foregroundStyle(.accentColor)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    .frame(minHeight: 30)
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
```

### Step 2: Create the label print sheet

```swift
/// Full-featured label printing sheet.
/// Shows size picker, layout picker, paper picker, used-sticker grid, preview, and print button.
struct QRLabelPrintSheet: View {
    let items: [QRLabelContent]       // Labels to print
    @Environment(\.dismiss) private var dismiss

    @State private var labelSize: QRLabelSize = .standard
    @State private var labelLayout: QRLabelLayout = .qrLeft
    @State private var paperSize: QRPaperSize = .letter
    @State private var usedPositions: Set<Int> = []
    @State private var previewPDF: Data?
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
                        // Group by category
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
                    let available = availablePositions
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
            .onChange(of: paperSize) { _, _ in
                usedPositions.removeAll() // Reset when paper type changes
            }
        }
    }

    // MARK: - Label Preview

    @ViewBuilder
    private var labelPreview: some View {
        if let first = items.first {
            // Simple visual preview showing QR position relative to text
            GeometryReader { geo in
                let size = CGSize(width: geo.size.width, height: geo.size.height)
                ZStack {
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(Color.secondary.opacity(0.3), lineWidth: 1)

                    HStack(spacing: 8) {
                        switch labelLayout {
                        case .qrLeft:
                            qrPlaceholder(size: min(size.height - 8, size.width * 0.3))
                            textPlaceholder(content: first)
                        case .qrRight:
                            textPlaceholder(content: first)
                            qrPlaceholder(size: min(size.height - 8, size.width * 0.3))
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

    @ViewBuilder
    private func qrPlaceholder(size: CGFloat) -> some View {
        Image(systemName: "qrcode")
            .resizable()
            .scaledToFit()
            .frame(width: size, height: size)
            .foregroundStyle(.accentColor)
    }

    @ViewBuilder
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
                    .font(.system(size: 8))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
        }
    }

    // MARK: - Helpers

    private var availablePositions: Int {
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

        // Use iOS print system
        let printController = UIPrintInteractionController.shared
        printController.printingItem = pdfData

        let printInfo = UIPrintInfo(dictionary: nil)
        printInfo.jobName = "WiredPart Labels"
        printInfo.outputType = .general
        printController.printInfo = printInfo

        printController.present(animated: true) { _, completed, error in
            isPrinting = false
            if let error = error {
                printError = error.localizedDescription
            } else if completed {
                dismiss()
            }
        }
    }
}
```

### Step 3: Add print button to Parts Catalog

In `PartsCatalogPage.swift`, add a print labels button. This could be:
- A toolbar button that prints labels for all currently filtered/visible parts
- A bulk action after selecting parts

```swift
// Add to toolbar or as a bulk action:
Button {
    // Build QRLabelContent from current filtered parts
    let labelItems = filteredParts.map { part in
        QRLabelContent(
            entityType: "part",
            entityId: part.id ?? 0,
            code: part.code ?? "",
            title: part.name,
            subtitle: part.categoryName,
            detail: part.binLocation
        )
    }
    printLabelItems = labelItems
    showPrintSheet = true
} label: {
    Image(systemName: "printer")
}

@State private var showPrintSheet = false
@State private var printLabelItems: [QRLabelContent] = []

// Add sheet (integrate into ActiveSheet enum if one exists):
.sheet(isPresented: $showPrintSheet) {
    QRLabelPrintSheet(items: printLabelItems)
}
```

### Step 4: Add print button to Tool Registry

Same pattern for tools:

```swift
Button {
    let labelItems = filteredTools.map { tool in
        QRLabelContent(
            entityType: "tool",
            entityId: tool.id,
            code: tool.serialNumber ?? tool.barcode ?? "",
            title: tool.name,
            subtitle: tool.categoryName,
            detail: tool.currentAssignee
        )
    }
    printLabelItems = labelItems
    showPrintSheet = true
} label: {
    Image(systemName: "printer")
}
```

## Important Notes

- `UIPrintInteractionController.present()` handles printer selection, copies, and paper size — it's the standard iOS print dialog.
- The used sticker picker resets when paper type changes (different paper = different positions).
- Preview shows a simplified visual representation — not pixel-perfect PDF preview. For PDF preview, you could use `PDFKit`'s `PDFView` but that's more complex.
- For very large print jobs (500+ labels), the PDF generation may take a moment. Consider running it on a background thread.
- The print button on catalog should work with the current filter state — print only what's visible, not all parts.
- Avery template numbers are well-known in the US market. Other countries may need different templates added later.
- If a page already uses `.sheet(item:)` with an `ActiveSheet` enum, add `.printLabels` case there.

## Success Criteria

- [ ] `UsedStickerPicker` shows visual grid for sticker sheets
- [ ] Tapping positions toggles used/available state
- [ ] "Clear All" and "Use All" buttons work
- [ ] `QRLabelPrintSheet` shows size, layout, paper pickers
- [ ] Layout preview updates when layout selection changes
- [ ] Used sticker picker appears only for sticker sheet paper types
- [ ] Page count estimate shows correct number
- [ ] Print button invokes iOS print dialog with generated PDF
- [ ] Print button added to Parts Catalog page
- [ ] Print button added to Tool Registry page
- [ ] Project builds with no errors

## Log Entry

```
## Prompt 21B Results (YYYY-MM-DD)
- Created QRLabelPrintSheet with size/layout/paper pickers
- UsedStickerPicker for partial sticker sheet support
- Layout preview with QR position visualization
- iOS UIPrintInteractionController integration
- Print buttons on Catalog + Tool Registry
- Build: [PASS/FAIL]
```

**QR label system complete. Continue with the next prompt chain.**
