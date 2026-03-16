import SwiftUI
import WiredPartCore

#if os(macOS)

// MARK: - Document Scan View (macOS)

/// View for scanning documents and extracting fields via OCR on macOS.
///
/// Pipeline:
/// 1. User selects document images via file picker
/// 2. OCR processes each page
/// 3. OCRProcessor extracts structured fields
/// 4. AutoFillBanner shows results for user confirmation
struct DocumentScanView: View {
    @EnvironmentObject var appCore: AppCore
    @State private var scannedPages: [ScannedPage] = []
    @State private var extractedFields: [ExtractedField] = []
    @State private var rawText: String = ""
    @State private var isProcessing = false
    @State private var overallConfidence: Float = 0
    @State private var errorMessage: String?
    @State private var showResults = false

    let onFieldsAccepted: ([ExtractedField]) -> Void

    private let ocrScanner = MacOCRScanner()

    var body: some View {
        VStack(spacing: 16) {
            // Header
            HStack {
                Label("Document Scanner", systemImage: "doc.text.viewfinder")
                    .font(.title2)
                Spacer()

                if isProcessing {
                    ProgressView()
                        .scaleEffect(0.7)
                    Text("Processing...")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            // Scan button
            if !showResults {
                VStack(spacing: 12) {
                    Image(systemName: "doc.text.magnifyingglass")
                        .font(.system(size: 48))
                        .foregroundStyle(.tertiary)

                    Text("Select document images to scan and extract data")
                        .foregroundStyle(.secondary)

                    Button("Select Documents...") {
                        Task { await scanAndProcess() }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isProcessing)
                }
                .frame(maxWidth: .infinity, minHeight: 200)
                .background(Color.secondary.opacity(0.03))
                .clipShape(RoundedRectangle(cornerRadius: 10))
            }

            // Error
            if let error = errorMessage {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                    Text(error)
                        .font(.callout)
                }
                .padding()
                .background(Color.orange.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }

            // Rescan prompt
            if showResults && overallConfidence < OCRConfidence.rescanThreshold {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                    Text("Low confidence scan. Consider rescanning with better lighting.")
                        .font(.callout)
                    Spacer()
                    Button("Rescan") {
                        resetAndRescan()
                    }
                }
                .padding()
                .background(Color.red.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }

            // Results
            if showResults && !extractedFields.isEmpty {
                AutoFillBanner(
                    fields: extractedFields,
                    onAccept: { accepted in
                        onFieldsAccepted(accepted)
                        resetState()
                    },
                    onDismiss: {
                        resetState()
                    }
                )
            }

            // Raw text (collapsible)
            if showResults && !rawText.isEmpty {
                DisclosureGroup("Raw OCR Text") {
                    ScrollView {
                        Text(rawText)
                            .font(.system(.caption, design: .monospaced))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(maxHeight: 200)
                }
                .padding()
                .background(Color.secondary.opacity(0.03))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
        }
        .padding()
    }

    // MARK: - Actions

    private func scanAndProcess() async {
        isProcessing = true
        errorMessage = nil

        do {
            // Step 1: Scan document
            let document = try await ocrScanner.scanDocument()
            scannedPages = document.pages

            guard let db = appCore.db else {
                errorMessage = "Database not available"
                isProcessing = false
                return
            }

            // Step 2: OCR each page
            var allBlocks: [RecognizedTextBlock] = []
            for page in document.pages {
                guard let provider = CGDataProvider(data: page.imageData as CFData),
                      let cgImage = CGImage(
                          pngDataProviderSource: provider,
                          decode: nil,
                          shouldInterpolate: true,
                          intent: .defaultIntent
                      ) else { continue }

                let blocks = try await ocrScanner.recognizeText(in: cgImage)
                allBlocks.append(contentsOf: blocks)
            }

            guard !allBlocks.isEmpty else {
                errorMessage = "No text found in the scanned document"
                isProcessing = false
                return
            }

            // Step 3: Extract fields
            let processor = OCRProcessor(db: db)
            let result = try processor.extractFields(from: allBlocks)

            extractedFields = result.fields
            rawText = result.rawText
            overallConfidence = result.overallConfidence
            showResults = true

        } catch {
            errorMessage = error.localizedDescription
        }

        isProcessing = false
    }

    private func resetAndRescan() {
        resetState()
        Task { await scanAndProcess() }
    }

    private func resetState() {
        scannedPages = []
        extractedFields = []
        rawText = ""
        overallConfidence = 0
        showResults = false
        errorMessage = nil
    }
}

#endif
