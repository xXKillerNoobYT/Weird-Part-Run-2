import SwiftUI
import WiredPartCore

import UIKit

// MARK: - iOS Document Scan View

/// Document scanning and OCR field extraction view for iOS.
///
/// Uses VNDocumentCameraViewController for multi-page capture,
/// then processes with Vision framework OCR.
struct IOSDocumentScanView: View {
    @EnvironmentObject var appCore: AppCore
    @State private var extractedFields: [ExtractedField] = []
    @State private var rawText: String = ""
    @State private var isProcessing = false
    @State private var overallConfidence: Float = 0
    @State private var errorMessage: String?
    @State private var showResults = false

    let onFieldsAccepted: ([ExtractedField]) -> Void

    private let ocrScanner = IOSOCRScanner()

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                // Scan button
                if !showResults {
                    VStack(spacing: 16) {
                        Image(systemName: "doc.text.viewfinder")
                            .font(.system(size: 56))
                            .foregroundStyle(.blue.opacity(0.6))

                        Text("Scan a document to extract data")
                            .font(.body)
                            .foregroundStyle(.secondary)

                        Button {
                            Task { await scanAndProcess() }
                        } label: {
                            Label("Scan Document", systemImage: "camera.fill")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                        .disabled(isProcessing)
                    }
                    .padding(.vertical, 40)
                }

                if isProcessing {
                    ProgressView("Processing document...")
                        .padding()
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
                    .frame(maxWidth: .infinity)
                    .background(Color.orange.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                }

                // Rescan prompt
                if showResults && overallConfidence < OCRConfidence.rescanThreshold {
                    VStack(spacing: 8) {
                        HStack {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(.red)
                            Text("Low quality scan")
                                .font(.headline)
                        }
                        Text("Try rescanning with better lighting")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Button("Rescan") {
                            resetState()
                            Task { await scanAndProcess() }
                        }
                        .buttonStyle(.bordered)
                    }
                    .padding()
                    .frame(maxWidth: .infinity)
                    .background(Color.red.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                }

                // Results
                if showResults && !extractedFields.isEmpty {
                    IOSAutoFillBanner(
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

                // Raw text
                if showResults && !rawText.isEmpty {
                    DisclosureGroup("Raw Text") {
                        Text(rawText)
                            .font(.system(.caption, design: .monospaced))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.top, 4)
                    }
                    .padding()
                    .background(Color.secondary.opacity(0.05))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                }
            }
            .padding()
        }
        .navigationTitle("Document Scanner")
    }

    // MARK: - Actions

    private func scanAndProcess() async {
        isProcessing = true
        errorMessage = nil

        do {
            let document = try await ocrScanner.scanDocument()

            guard let db = appCore.db else {
                errorMessage = "Database not available"
                isProcessing = false
                return
            }

            var allBlocks: [RecognizedTextBlock] = []
            for page in document.pages {
                // Convert page data to CGImage for OCR
                guard let uiImage = UIImage(data: page.imageData),
                      let cgImage = uiImage.cgImage else { continue }

                let blocks = try await ocrScanner.recognizeText(in: cgImage)
                allBlocks.append(contentsOf: blocks)
            }

            guard !allBlocks.isEmpty else {
                errorMessage = "No text found in document"
                isProcessing = false
                return
            }

            let processor = OCRProcessor(db: db)
            let result = try processor.extractFields(from: allBlocks)

            extractedFields = result.fields
            rawText = result.rawText
            overallConfidence = result.overallConfidence
            showResults = true

        } catch {
            errorMessage = userFriendlyError(error, context: "scan document")
        }

        isProcessing = false
    }

    private func resetState() {
        extractedFields = []
        rawText = ""
        overallConfidence = 0
        showResults = false
        errorMessage = nil
    }
}

