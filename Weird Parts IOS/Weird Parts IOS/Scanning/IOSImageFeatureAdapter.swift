import Foundation
import Vision
import WiredPartCore

#if os(iOS)

// MARK: - iOS Image Feature Adapter

/// iOS implementation of image feature extraction using Vision framework.
///
/// Shares the same VNGenerateImageFeaturePrintRequest approach as macOS.
/// Feature vectors are 2048-dimensional and normalized for cosine similarity.
final class IOSImageFeatureAdapter: ImageFeatureAdapter {
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

                let data = observation.data
                let floatCount = data.count / MemoryLayout<Float>.size
                let vector = data.withUnsafeBytes { rawBuffer -> [Float] in
                    let floatBuffer = rawBuffer.bindMemory(to: Float.self)
                    return Array(floatBuffer.prefix(floatCount))
                }

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

    private static func normalizeVector(_ vector: [Float]) -> [Float] {
        let norm = sqrt(vector.map { $0 * $0 }.reduce(0, +))
        guard norm > 0 else { return vector }
        return vector.map { $0 / norm }
    }
}

#endif
