import Foundation
import CoreGraphics

// MARK: - OCR Scanner Adapter Protocol

/// Platform-specific document scanning and text recognition interface.
///
/// Implementations:
/// - macOS: `VNRecognizeTextRequest` (.accurate) via Vision framework
/// - iOS: `VNDocumentCameraViewController` + `VNRecognizeTextRequest`
/// - Windows: `Windows.Media.Ocr.OcrEngine` (Phase 14)
public protocol OCRScannerAdapter: AnyObject, Sendable {
    /// Whether OCR/scanning hardware is available on this device.
    var isAvailable: Bool { get }

    /// Open a document scanner (camera or file picker).
    func scanDocument() async throws -> ScannedDocument

    /// Recognize text in a single image.
    func recognizeText(in image: CGImage) async throws -> [RecognizedTextBlock]
}

// MARK: - Scanned Document

/// Result of a document scan session (one or more pages).
public struct ScannedDocument: Sendable {
    public let pages: [ScannedPage]

    public init(pages: [ScannedPage]) {
        self.pages = pages
    }

    /// Total page count.
    public var pageCount: Int { pages.count }

    /// Whether this document is empty.
    public var isEmpty: Bool { pages.isEmpty }
}

// MARK: - Scanned Page

/// A single scanned page with its image data.
public struct ScannedPage: Sendable {
    public let imageData: Data
    public let pageIndex: Int
    public let width: Int
    public let height: Int

    public init(imageData: Data, pageIndex: Int, width: Int, height: Int) {
        self.imageData = imageData
        self.pageIndex = pageIndex
        self.width = width
        self.height = height
    }
}

// MARK: - Recognized Text Block

/// A block of text recognized by OCR with its position and confidence.
public struct RecognizedTextBlock: Sendable {
    public let text: String
    /// OCR confidence score from 0.0 (no confidence) to 1.0 (certain).
    public let confidence: Float
    /// Bounding box in normalized coordinates (0,0 = bottom-left, 1,1 = top-right).
    public let boundingBox: CGRect
    /// Whether the OCR engine detected this as handwriting.
    public let isHandwritten: Bool

    public init(
        text: String,
        confidence: Float,
        boundingBox: CGRect = .zero,
        isHandwritten: Bool = false
    ) {
        self.text = text
        self.confidence = confidence
        self.boundingBox = boundingBox
        self.isHandwritten = isHandwritten
    }
}

// MARK: - Confidence Thresholds

/// Confidence thresholds for OCR result display and auto-fill.
public enum OCRConfidence {
    /// Green: ≥ 0.90 — high confidence, safe to auto-fill
    public static let high: Float = 0.90
    /// Yellow: 0.70–0.89 — moderate confidence, show for review
    public static let medium: Float = 0.70
    /// Red: < 0.70 — low confidence, show as suggestion only
    /// Rescan prompt: < 0.50 — overall confidence too low
    public static let rescanThreshold: Float = 0.50

    /// Return a confidence tier for display.
    public static func tier(for confidence: Float) -> ConfidenceTier {
        if confidence >= high { return .high }
        if confidence >= medium { return .medium }
        return .low
    }
}

/// Visual confidence tier for UI display.
public enum ConfidenceTier: String, Sendable {
    case high   // Green indicator
    case medium // Yellow indicator
    case low    // Red indicator
}

// MARK: - OCR Errors

public enum OCRError: Error, LocalizedError, Sendable {
    case scannerNotAvailable
    case cameraPermissionDenied
    case recognitionFailed(String)
    case imageConversionFailed
    case noTextFound

    public var errorDescription: String? {
        switch self {
        case .scannerNotAvailable:
            return "Document scanner is not available on this device"
        case .cameraPermissionDenied:
            return "Camera permission is required for document scanning"
        case .recognitionFailed(let reason):
            return "Text recognition failed: \(reason)"
        case .imageConversionFailed:
            return "Failed to convert scanned image for processing"
        case .noTextFound:
            return "No text was found in the scanned document"
        }
    }
}
