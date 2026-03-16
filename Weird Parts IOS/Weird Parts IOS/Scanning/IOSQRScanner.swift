import Foundation
import WiredPartCore

#if os(iOS)
import UIKit
import Vision
import VisionKit

// MARK: - iOS QR Scanner

/// iOS implementation of QR scanning using DataScannerViewController.
///
/// Provides live camera QR/barcode detection with haptic feedback
/// and torch control. Uses VisionKit's DataScanner API for
/// optimized real-time recognition.
@available(iOS 16.0, *)
@MainActor
final class IOSQRScanner: QRScannerAdapter {
    var isAvailable: Bool {
        DataScannerViewController.isSupported && DataScannerViewController.isAvailable
    }

    private var continuation: AsyncStream<QRScanEvent>.Continuation?
    private var scannerVC: DataScannerViewController?
    private var delegate: ScannerDelegate?

    // MARK: - Start Scanning

    func startScanning() async throws -> AsyncStream<QRScanEvent> {
        guard isAvailable else {
            throw OCRError.scannerNotAvailable
        }

        return AsyncStream { continuation in
            self.continuation = continuation

            continuation.onTermination = { @Sendable [weak self] _ in
                Task { @MainActor in
                    self?.stopScanning()
                }
            }

            self.presentScanner()
        }
    }

    // MARK: - Stop Scanning

    func stopScanning() {
        scannerVC?.stopScanning()
        scannerVC?.dismiss(animated: true)
        scannerVC = nil
        delegate = nil
        continuation?.finish()
        continuation = nil
    }

    // MARK: - Private

    private func presentScanner() {
        let recognizedTypes: Set<DataScannerViewController.RecognizedDataType> = [
            .barcode(symbologies: [.qr, .code128, .ean8, .ean13, .upce, .code39])
        ]

        let scanner = DataScannerViewController(
            recognizedDataTypes: recognizedTypes,
            qualityLevel: .accurate,
            recognizesMultipleItems: false,
            isHighFrameRateTrackingEnabled: true,
            isHighlightingEnabled: true
        )

        let scanDelegate = ScannerDelegate(continuation: continuation)
        scanner.delegate = scanDelegate
        self.delegate = scanDelegate
        self.scannerVC = scanner

        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let rootVC = windowScene.windows.first?.rootViewController else {
            continuation?.yield(.error("Unable to present scanner"))
            return
        }

        rootVC.present(scanner, animated: true) {
            try? scanner.startScanning()
        }
    }
}

// MARK: - Scanner Delegate

@available(iOS 16.0, *)
private class ScannerDelegate: NSObject, DataScannerViewControllerDelegate {
    private let continuation: AsyncStream<QRScanEvent>.Continuation?
    private var lastPayload: String?
    private var lastTime: Date = .distantPast

    init(continuation: AsyncStream<QRScanEvent>.Continuation?) {
        self.continuation = continuation
    }

    func dataScanner(
        _ dataScanner: DataScannerViewController,
        didAdd addedItems: [RecognizedItem],
        allItems: [RecognizedItem]
    ) {
        for item in addedItems {
            if case .barcode(let barcode) = item {
                guard let payload = barcode.payloadStringValue else { continue }

                // Debounce: don't emit the same code within 1 second
                let now = Date()
                if payload == lastPayload,
                   now.timeIntervalSince(lastTime) < 1.0 {
                    continue
                }

                lastPayload = payload
                lastTime = now

                // Haptic feedback
                let generator = UIImpactFeedbackGenerator(style: .medium)
                generator.impactOccurred()

                let b = barcode.bounds
                let xs = [b.topLeft.x, b.topRight.x, b.bottomLeft.x, b.bottomRight.x]
                let ys = [b.topLeft.y, b.topRight.y, b.bottomLeft.y, b.bottomRight.y]
                let rect = CGRect(
                    x: xs.min() ?? 0,
                    y: ys.min() ?? 0,
                    width: (xs.max() ?? 0) - (xs.min() ?? 0),
                    height: (ys.max() ?? 0) - (ys.min() ?? 0)
                )

                continuation?.yield(.detected(
                    payload: payload,
                    bounds: rect
                ))
            }
        }
    }

    func dataScanner(
        _ dataScanner: DataScannerViewController,
        becameUnavailableWithError error: DataScannerViewController.ScanningUnavailable
    ) {
        continuation?.yield(.error("Scanner became unavailable: \(error.localizedDescription)"))
    }
}

#endif
