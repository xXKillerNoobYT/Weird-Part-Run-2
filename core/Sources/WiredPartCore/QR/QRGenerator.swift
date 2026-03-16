import Foundation
import CoreImage

// MARK: - QR Generator

/// Generates QR code images from WiredPart payloads.
///
/// Uses CoreImage's `CIQRCodeGenerator` filter to produce QR images
/// at error correction level H (30% damage recovery) for field durability.
public enum QRGenerator {

    /// Error correction level for generated QR codes.
    /// Level H provides ~30% error recovery — best for field environments.
    public enum CorrectionLevel: String, Sendable {
        case low = "L"       // ~7%
        case medium = "M"    // ~15%
        case quartile = "Q"  // ~25%
        case high = "H"      // ~30%
    }

    // MARK: - Generate from Payload

    /// Generate a QR code image from a WiredPart entity.
    ///
    /// - Parameters:
    ///   - type: The entity type (part, job, bin, etc.)
    ///   - id: The entity's database ID.
    ///   - code: The entity's human-readable code or identifier.
    ///   - meta: Optional metadata to embed (e.g. name, location).
    ///   - size: Output image size in points. Default: 200×200.
    ///   - correction: Error correction level. Default: high (30%).
    /// - Returns: A `CGImage` containing the QR code, or nil on failure.
    public static func generate(
        type: QREntityType,
        id: Int64,
        code: String,
        meta: [String: String]? = nil,
        size: CGFloat = 200,
        correction: CorrectionLevel = .high
    ) -> CGImage? {
        let payload = QRPayload(type: type, id: id, code: code, meta: meta)
        guard let jsonString = try? QRCodec.encode(payload) else {
            return nil
        }
        return generateFromString(jsonString, size: size, correction: correction)
    }

    // MARK: - Generate from String

    /// Generate a QR code image from an arbitrary string.
    ///
    /// - Parameters:
    ///   - string: The text to encode.
    ///   - size: Output image size in points. Default: 200×200.
    ///   - correction: Error correction level.
    /// - Returns: A `CGImage` containing the QR code, or nil on failure.
    public static func generateFromString(
        _ string: String,
        size: CGFloat = 200,
        correction: CorrectionLevel = .high
    ) -> CGImage? {
        guard let data = string.data(using: .utf8) else { return nil }

        let filter = CIFilter(name: "CIQRCodeGenerator")
        filter?.setValue(data, forKey: "inputMessage")
        filter?.setValue(correction.rawValue, forKey: "inputCorrectionLevel")

        guard let ciImage = filter?.outputImage else { return nil }

        // Scale to desired size
        let scaleX = size / ciImage.extent.size.width
        let scaleY = size / ciImage.extent.size.height
        let scaled = ciImage.transformed(by: CGAffineTransform(scaleX: scaleX, y: scaleY))

        // Render to CGImage with sharp pixels (no interpolation)
        let context = CIContext(options: [.useSoftwareRenderer: false])
        return context.createCGImage(scaled, from: scaled.extent)
    }

    // MARK: - Generate Data

    /// Generate QR code as PNG data (for saving, sharing, or printing).
    ///
    /// - Parameters:
    ///   - type: The entity type.
    ///   - id: The entity ID.
    ///   - code: The entity code.
    ///   - meta: Optional metadata.
    ///   - size: Output size in points.
    /// - Returns: PNG data, or nil on failure.
    public static func generatePNGData(
        type: QREntityType,
        id: Int64,
        code: String,
        meta: [String: String]? = nil,
        size: CGFloat = 200
    ) -> Data? {
        guard let cgImage = generate(
            type: type, id: id, code: code, meta: meta, size: size
        ) else { return nil }

        #if canImport(AppKit) && !targetEnvironment(macCatalyst)
        let nsImage = NSImage(cgImage: cgImage, size: NSSize(width: size, height: size))
        guard let tiffData = nsImage.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData) else { return nil }
        return bitmap.representation(using: .png, properties: [:])
        #elseif canImport(UIKit)
        let uiImage = UIImage(cgImage: cgImage)
        return uiImage.pngData()
        #else
        return nil
        #endif
    }
}

#if canImport(AppKit) && !targetEnvironment(macCatalyst)
import AppKit
#elseif canImport(UIKit)
import UIKit
#endif
