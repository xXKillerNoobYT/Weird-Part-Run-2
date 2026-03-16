import Foundation
import AVFoundation
import Vision
import WiredPartCore

#if os(macOS)
import AppKit

// MARK: - macOS QR Scanner

/// macOS implementation of QR scanning using AVCaptureSession + Vision.
///
/// Uses the built-in webcam for live QR/barcode detection via
/// `VNDetectBarcodesRequest`.
@MainActor
final class MacQRScanner: QRScannerAdapter {
    var isAvailable: Bool {
        AVCaptureDevice.default(for: .video) != nil
    }

    private var captureSession: AVCaptureSession?
    private var continuation: AsyncStream<QRScanEvent>.Continuation?

    // MARK: - Start Scanning

    func startScanning() async throws -> AsyncStream<QRScanEvent> {
        guard isAvailable else {
            throw OCRError.scannerNotAvailable
        }

        // Check camera permission
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        switch status {
        case .notDetermined:
            let granted = await AVCaptureDevice.requestAccess(for: .video)
            if !granted {
                throw OCRError.cameraPermissionDenied
            }
        case .denied, .restricted:
            throw OCRError.cameraPermissionDenied
        case .authorized:
            break
        @unknown default:
            break
        }

        return AsyncStream { continuation in
            self.continuation = continuation

            continuation.onTermination = { @Sendable [weak self] _ in
                Task { @MainActor in
                    self?.stopScanning()
                }
            }

            self.startCapture()
        }
    }

    // MARK: - Stop Scanning

    func stopScanning() {
        captureSession?.stopRunning()
        captureSession = nil
        continuation?.finish()
        continuation = nil
    }

    // MARK: - Private Capture

    private func startCapture() {
        let session = AVCaptureSession()
        session.sessionPreset = .medium

        guard let device = AVCaptureDevice.default(for: .video),
              let input = try? AVCaptureDeviceInput(device: device) else {
            continuation?.yield(.error("Failed to access camera"))
            return
        }

        if session.canAddInput(input) {
            session.addInput(input)
        }

        let output = AVCaptureVideoDataOutput()
        output.setSampleBufferDelegate(
            QRSampleBufferDelegate(continuation: continuation),
            queue: DispatchQueue(label: "com.wiredpart.qr-scanner")
        )

        if session.canAddOutput(output) {
            session.addOutput(output)
        }

        captureSession = session
        session.startRunning()
    }
}

// MARK: - Sample Buffer Delegate

private class QRSampleBufferDelegate: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    private let continuation: AsyncStream<QRScanEvent>.Continuation?
    private var lastDetectedPayload: String?
    private var lastDetectionTime: Date = .distantPast

    init(continuation: AsyncStream<QRScanEvent>.Continuation?) {
        self.continuation = continuation
    }

    func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }

        let request = VNDetectBarcodesRequest { [weak self] request, error in
            guard let self, error == nil,
                  let results = request.results as? [VNBarcodeObservation] else { return }

            for barcode in results {
                guard let payload = barcode.payloadStringValue else { continue }

                // Debounce: don't emit the same code within 1 second
                let now = Date()
                if payload == self.lastDetectedPayload,
                   now.timeIntervalSince(self.lastDetectionTime) < 1.0 {
                    continue
                }

                self.lastDetectedPayload = payload
                self.lastDetectionTime = now
                self.continuation?.yield(.detected(
                    payload: payload,
                    bounds: barcode.boundingBox
                ))
            }
        }

        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, options: [:])
        try? handler.perform([request])
    }
}

#endif
