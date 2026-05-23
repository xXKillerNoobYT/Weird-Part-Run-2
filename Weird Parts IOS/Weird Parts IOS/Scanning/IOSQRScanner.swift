import Foundation
import WiredPartCore

#if os(iOS) && !targetEnvironment(macCatalyst)
import SwiftUI
import UIKit
import Vision
import VisionKit

@available(iOS 16.0, *)
private let iosQRScannerRecognizedTypes: Set<DataScannerViewController.RecognizedDataType> = [
    .barcode(symbologies: [.qr, .code128, .ean8, .ean13, .upce, .code39])
]

@available(iOS 16.0, *)
private func makeQRDataScannerViewController() -> DataScannerViewController {
    DataScannerViewController(
        recognizedDataTypes: iosQRScannerRecognizedTypes,
        qualityLevel: .accurate,
        recognizesMultipleItems: false,
        isHighFrameRateTrackingEnabled: true,
        isHighlightingEnabled: true
    )
}

/// Embedded SwiftUI live camera preview for pages that need the scanner inline.
///
/// `IOSQRScanner` remains available for modal/sheet scanning, but dashboard-style
/// experiences should use this representable so the user can see the live
/// `DataScannerViewController` viewfinder in the page instead of a black box.
@available(iOS 16.0, *)
struct IOSQRScannerView: UIViewControllerRepresentable {
    let isScanning: Bool
    let onEvent: (QRScanEvent) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onEvent: onEvent)
    }

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let scanner = makeQRDataScannerViewController()
        let scanDelegate = ScannerDelegate { event in
            switch event {
            case .error, .permissionDenied:
                context.coordinator.isScanning = false
            case .detected:
                break
            }
            context.coordinator.onEvent(event)
        }
        scanner.delegate = scanDelegate
        context.coordinator.delegate = scanDelegate
        context.coordinator.scanner = scanner
        if isScanning {
            startScanner(scanner, coordinator: context.coordinator)
        }
        return scanner
    }

    func updateUIViewController(_ scanner: DataScannerViewController, context: Context) {
        context.coordinator.onEvent = onEvent
        context.coordinator.scanner = scanner
        if isScanning {
            startScanner(scanner, coordinator: context.coordinator)
        } else if context.coordinator.isScanning {
            scanner.stopScanning()
            context.coordinator.isScanning = false
        }
    }

    static func dismantleUIViewController(_ scanner: DataScannerViewController, coordinator: Coordinator) {
        scanner.stopScanning()
        scanner.delegate = nil
        coordinator.isScanning = false
        coordinator.scanner = nil
        coordinator.delegate = nil
    }

    private func startScanner(_ scanner: DataScannerViewController, coordinator: Coordinator) {
        guard !coordinator.isScanning else { return }

        guard DataScannerViewController.isAvailable else {
            coordinator.isScanning = false
            onEvent(.permissionDenied)
            return
        }

        do {
            try scanner.startScanning()
            coordinator.isScanning = true
        } catch {
            coordinator.isScanning = false
            onEvent(.error(userFriendlyError(error, context: "scan item")))
        }
    }

    @MainActor
    final class Coordinator: NSObject {
        var onEvent: (QRScanEvent) -> Void
        weak var scanner: DataScannerViewController?
        fileprivate var delegate: ScannerDelegate?
        var isScanning = false

        init(onEvent: @escaping (QRScanEvent) -> Void) {
            self.onEvent = onEvent
        }
    }
}

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
        scannerVC?.delegate = nil
        scannerVC?.dismiss(animated: true)
        scannerVC = nil
        delegate = nil
        continuation?.finish()
        continuation = nil
    }

    // MARK: - Private

    private func presentScanner() {
        let scanner = makeQRDataScannerViewController()

        let scanDelegate = ScannerDelegate(continuation: continuation)
        scanner.delegate = scanDelegate
        self.delegate = scanDelegate
        self.scannerVC = scanner

        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let rootVC = windowScene.windows.first?.rootViewController else {
            finishScanningWithError("Unable to present scanner")
            return
        }

        rootVC.present(scanner, animated: true) { [weak self, weak scanner] in
            guard let self, let scanner else { return }

            do {
                try scanner.startScanning()
            } catch {
                self.finishScanningWithError(userFriendlyError(error, context: "scan item"))
            }
        }
    }

    private func finishScanningWithError(_ message: String) {
        continuation?.yield(.error(message))
        stopScanning()
    }
}

// MARK: - Scanner Delegate

@available(iOS 16.0, *)
@MainActor
fileprivate class ScannerDelegate: NSObject, DataScannerViewControllerDelegate {
    private let continuation: AsyncStream<QRScanEvent>.Continuation?
    private let onEvent: ((QRScanEvent) -> Void)?
    private var lastPayload: String?
    private var lastTime: Date = .distantPast

    init(continuation: AsyncStream<QRScanEvent>.Continuation?) {
        self.continuation = continuation
        self.onEvent = nil
    }

    init(onEvent: @escaping (QRScanEvent) -> Void) {
        self.continuation = nil
        self.onEvent = onEvent
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

                emit(.detected(
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
        emit(.error(userFriendlyError(error, context: "scan item")))
    }

    private func emit(_ event: QRScanEvent) {
        continuation?.yield(event)
        onEvent?(event)
    }
}
#else
// MARK: - Mac Catalyst Stub

/// Stub for Mac Catalyst where DataScannerViewController is unavailable.
@available(iOS 16.0, *)
@MainActor
final class IOSQRScanner: QRScannerAdapter {
    var isAvailable: Bool { false }

    func startScanning() async throws -> AsyncStream<QRScanEvent> {
        throw OCRError.scannerNotAvailable
    }

    func stopScanning() {}
}
#endif
