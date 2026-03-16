import Foundation
import Vision
import WiredPartCore

#if os(macOS)
import AppKit

// MARK: - macOS OCR Scanner

/// macOS implementation of OCR scanning using Vision framework.
///
/// Uses `VNRecognizeTextRequest` with `.accurate` recognition level
/// for best quality text recognition. Supports file picker for
/// existing documents (no document camera on macOS).
final class MacOCRScanner: OCRScannerAdapter {
    var isAvailable: Bool { true }

    // MARK: - Scan Document

    /// Opens a file picker to select document images for OCR.
    @MainActor func scanDocument() async throws -> ScannedDocument {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowedContentTypes = [.image, .pdf]
        panel.message = "Select document images to scan"

        let response = panel.runModal()
        guard response == .OK, !panel.urls.isEmpty else {
            throw OCRError.scannerNotAvailable
        }

        var pages: [ScannedPage] = []
        for (index, url) in panel.urls.enumerated() {
            guard let imageData = try? Data(contentsOf: url) else { continue }
            guard let nsImage = NSImage(data: imageData),
                  let cgImage = nsImage.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
                continue
            }
            pages.append(ScannedPage(
                imageData: imageData,
                pageIndex: index,
                width: cgImage.width,
                height: cgImage.height
            ))
        }

        guard !pages.isEmpty else {
            throw OCRError.noTextFound
        }

        return ScannedDocument(pages: pages)
    }

    // MARK: - Recognize Text

    /// Recognize text in a single image using Vision framework.
    nonisolated func recognizeText(in image: CGImage) async throws -> [RecognizedTextBlock] {
        try await withCheckedThrowingContinuation { continuation in
            let request = VNRecognizeTextRequest { request, error in
                if let error {
                    continuation.resume(throwing: OCRError.recognitionFailed(error.localizedDescription))
                    return
                }

                guard let observations = request.results as? [VNRecognizedTextObservation] else {
                    continuation.resume(returning: [])
                    return
                }

                let blocks = observations.compactMap { observation -> RecognizedTextBlock? in
                    guard let candidate = observation.topCandidates(1).first else { return nil }
                    return RecognizedTextBlock(
                        text: candidate.string,
                        confidence: candidate.confidence,
                        boundingBox: observation.boundingBox,
                        isHandwritten: false
                    )
                }

                continuation.resume(returning: blocks)
            }

            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true

            // Add custom vocabulary from domain
            request.customWords = [
                "WiredPart", "PO", "SKU", "EMT", "MC",
                "Romex", "NM-B", "THHN", "XHHW", "UF-B",
            ]

            let handler = VNImageRequestHandler(cgImage: image, options: [:])
            do {
                try handler.perform([request])
            } catch {
                continuation.resume(throwing: OCRError.recognitionFailed(error.localizedDescription))
            }
        }
    }
}

#endif
