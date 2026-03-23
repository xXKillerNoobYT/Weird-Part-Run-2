import Foundation
import Vision
import WiredPartCore

import UIKit
import VisionKit

// MARK: - iOS OCR Scanner

/// iOS implementation of OCR scanning using VisionKit document camera
/// and Vision framework text recognition.
///
/// Uses `VNDocumentCameraViewController` for multi-page document capture
/// with real-time quality feedback, then `VNRecognizeTextRequest` (.accurate)
/// for text recognition.
final class IOSOCRScanner: OCRScannerAdapter {
    nonisolated var isAvailable: Bool {
        // VNDocumentCameraViewController.isSupported is a thread-safe class property
        true  // Always available on iOS devices with a camera
    }

    // MARK: - Scan Document

    @MainActor
    func scanDocument() async throws -> ScannedDocument {
        guard isAvailable else {
            throw OCRError.scannerNotAvailable
        }

        return try await withCheckedThrowingContinuation { continuation in
            let coordinator = DocumentScanCoordinator(continuation: continuation)
            let scannerVC = VNDocumentCameraViewController()
            scannerVC.delegate = coordinator

            // Present the scanner
            guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
                  let rootVC = windowScene.windows.first?.rootViewController else {
                continuation.resume(throwing: OCRError.scannerNotAvailable)
                return
            }

            // Keep coordinator alive while scanner is presented
            objc_setAssociatedObject(scannerVC, "coordinator", coordinator, .OBJC_ASSOCIATION_RETAIN)

            rootVC.present(scannerVC, animated: true)
        }
    }

    // MARK: - Recognize Text

    func recognizeText(in image: CGImage) async throws -> [RecognizedTextBlock] {
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

// MARK: - Document Scan Coordinator

/// Coordinator that bridges VNDocumentCameraViewController delegate
/// callbacks to an async continuation.
private class DocumentScanCoordinator: NSObject, VNDocumentCameraViewControllerDelegate {
    private var continuation: CheckedContinuation<ScannedDocument, Error>?

    init(continuation: CheckedContinuation<ScannedDocument, Error>) {
        self.continuation = continuation
    }

    func documentCameraViewController(
        _ controller: VNDocumentCameraViewController,
        didFinishWith scan: VNDocumentCameraScan
    ) {
        controller.dismiss(animated: true)

        var pages: [ScannedPage] = []
        for pageIndex in 0..<scan.pageCount {
            let image = scan.imageOfPage(at: pageIndex)
            if let data = image.jpegData(compressionQuality: 0.8) {
                pages.append(ScannedPage(
                    imageData: data,
                    pageIndex: pageIndex,
                    width: Int(image.size.width),
                    height: Int(image.size.height)
                ))
            }
        }

        continuation?.resume(returning: ScannedDocument(pages: pages))
        continuation = nil
    }

    func documentCameraViewControllerDidCancel(_ controller: VNDocumentCameraViewController) {
        controller.dismiss(animated: true)
        continuation?.resume(throwing: OCRError.scannerNotAvailable)
        continuation = nil
    }

    func documentCameraViewController(
        _ controller: VNDocumentCameraViewController,
        didFailWithError error: Error
    ) {
        controller.dismiss(animated: true)
        continuation?.resume(throwing: OCRError.recognitionFailed(error.localizedDescription))
        continuation = nil
    }
}

