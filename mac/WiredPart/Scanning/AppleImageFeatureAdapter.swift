import Foundation
import Vision
import WiredPartCore

// MARK: - Apple Image Feature Adapter

/// Apple Vision framework implementation of image feature extraction.
///
/// Uses `VNGenerateImageFeaturePrintRequest` to extract 2048-dimension
/// feature vectors from images. These vectors enable cosine-similarity
/// based part matching.
///
/// Available on macOS 14+ and iOS 17+. No model download required —
/// the Vision framework includes the feature extraction model.
final class AppleImageFeatureAdapter: ImageFeatureAdapter {
    var isAvailable: Bool { true }
    var featureDimension: Int { 2048 }
    var adapterType: String { "apple_vision" }

    // MARK: - Extract Features

    func extractFeatures(from image: CGImage) async throws -> [Float] {
        guard image.width >= 64, image.height >= 64 else {
            throw ImageFeatureError.invalidImageSize
        }

        return try await withCheckedThrowingContinuation { continuation in
            let request = VNGenerateImageFeaturePrintRequest { request, error in
                if let error {
                    continuation.resume(
                        throwing: ImageFeatureError.extractionFailed(error.localizedDescription)
                    )
                    return
                }

                guard let observation = request.results?.first as? VNFeaturePrintObservation else {
                    continuation.resume(
                        throwing: ImageFeatureError.extractionFailed("No feature print generated")
                    )
                    return
                }

                // Extract raw float data from the feature print
                let data = observation.data
                let floatCount = data.count / MemoryLayout<Float>.size
                let vector = data.withUnsafeBytes { rawBuffer -> [Float] in
                    let floatBuffer = rawBuffer.bindMemory(to: Float.self)
                    return Array(floatBuffer.prefix(floatCount))
                }

                // Normalize the vector for cosine similarity
                let normalized = Self.normalizeVector(vector)
                continuation.resume(returning: normalized)
            }

            let handler = VNImageRequestHandler(cgImage: image, options: [:])
            do {
                try handler.perform([request])
            } catch {
                continuation.resume(
                    throwing: ImageFeatureError.extractionFailed(error.localizedDescription)
                )
            }
        }
    }

    // MARK: - Vector Normalization

    /// L2-normalize a vector so cosine similarity becomes a dot product.
    private static func normalizeVector(_ vector: [Float]) -> [Float] {
        let norm = sqrt(vector.map { $0 * $0 }.reduce(0, +))
        guard norm > 0 else { return vector }
        return vector.map { $0 / norm }
    }
}
