import SwiftUI
import WiredPartCore
#if canImport(UIKit)
import UIKit
#endif
#if !targetEnvironment(macCatalyst)
import VisionKit
#endif

struct QRScanDeliveryGate {
    private(set) var activePayload: String?
    private(set) var completedPayload: String?
    private(set) var lastFoundPayload: String?

    var isProcessing: Bool { activePayload != nil }

    mutating func claim(_ payload: String) -> Bool {
        guard activePayload == nil,
              completedPayload != payload,
              lastFoundPayload != payload else { return false }
        activePayload = payload
        lastFoundPayload = nil
        return true
    }

    mutating func finish(
        _ payload: String,
        isFound: Bool,
        shouldComplete: Bool
    ) -> Bool {
        guard activePayload == payload else { return false }
        activePayload = nil
        lastFoundPayload = isFound ? payload : nil
        guard shouldComplete, completedPayload != payload else { return false }
        completedPayload = payload
        return true
    }

    mutating func fail(_ payload: String) {
        if activePayload == payload {
            activePayload = nil
            lastFoundPayload = nil
        }
    }
}

enum QRScanManualSubmissionGate {
    static func code(from rawCode: String, isProcessing: Bool) -> String? {
        guard !isProcessing else { return nil }
        return rawCode.normalizedRequiredText
    }
}

@MainActor
enum QRScanCompletionDispatcher {
    static func deliver(dismiss: () -> Void, onResult: () -> Void) {
        dismiss()
        onResult()
    }
}

struct QRScanFeedback {
    let typeMismatch: Bool
    let message: String

    init(
        isFound: Bool,
        entityType: QREntityType?,
        expectedType: QREntityType?,
        title: String,
        code: String
    ) {
        if isFound, let entityType, let expectedType, entityType != expectedType {
            typeMismatch = true
            message = "Expected \(expectedType.rawValue), got \(entityType.rawValue)"
        } else {
            typeMismatch = false
            message = isFound ? "Found: \(title)" : "Not found: \(code)"
        }
    }
}

/// Reusable QR scan sheet. Present as a `.sheet`, get a callback with the result.
/// Automatically dismisses after a successful scan that matches the expected type.
///
/// Usage:
/// ```
/// .sheet(isPresented: $showScanner) {
///     QRScanSheet(expectedType: .po) { result in
///         selectedPOId = result.entityId
///     }
///     .environmentObject(appCore)
/// }
/// ```
struct QRScanSheet: View {
    let expectedType: QREntityType?   // nil = accept any type
    let onResult: (QRAutoFillResult) -> Void
    @EnvironmentObject private var appCore: AppCore
    @Environment(\.dismiss) private var dismiss

    @State private var scanError: String?
    @State private var resultTitle: String?
    @State private var resultIsFound = false
    @State private var resultEntityType: QREntityType?
    @State private var resultCode: String?
    @State private var deliveryGate = QRScanDeliveryGate()

    // Manual entry
    @State private var manualCode = ""

    @State private var scanner: IOSQRScanner?

    private var isProcessing: Bool { deliveryGate.isProcessing }

    private var resultFeedback: QRScanFeedback? {
        guard let resultTitle else { return nil }
        return QRScanFeedback(
            isFound: resultIsFound,
            entityType: resultEntityType,
            expectedType: expectedType,
            title: resultTitle,
            code: resultCode ?? ""
        )
    }

    private var isScannerSupported: Bool {
        #if targetEnvironment(macCatalyst)
        return false
        #else
        return DataScannerViewController.isSupported
        #endif
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if isScannerSupported {
                    cameraSection
                        .frame(maxHeight: .infinity)

                    bottomSection
                } else {
                    manualOnlyView
                }
            }
            .background(Color.black)
            .navigationTitle(scanTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .onAppear {
                if isScannerSupported {
                    startScanning()
                }
            }
            .onDisappear {
                scanner?.stopScanning()
            }
            .onChange(of: statusAccessibilityLabel) { _, status in
                announceStatus(status)
            }
        }
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
    }

    private var scanTitle: String {
        if let type = expectedType {
            return "Scan \(type.rawValue.capitalized)"
        }
        return "Scan QR Code"
    }

    // MARK: - Camera Section

    @ViewBuilder
    private var cameraSection: some View {
        ZStack {
            Rectangle()
                .fill(Color.black)

            // Scanning frame overlay
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.white.opacity(0.5), lineWidth: 2)
                .frame(width: 250, height: 250)

        }
    }

    // MARK: - Bottom Section

    @ViewBuilder
    private var bottomSection: some View {
        VStack(spacing: 12) {
            feedbackStatusView
                .padding(.horizontal)
                .padding(.top, 12)

            // Manual entry
            HStack(spacing: 8) {
                TextField("Type code manually...", text: $manualCode)
                    .textFieldStyle(.roundedBorder)
                    .submitLabel(.search)
                    .onSubmit { processManualEntry() }
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .accessibilityLabel("QR code")
                    .accessibilityIdentifier("qrScanManualCodeField")

                Button("Look Up") { processManualEntry() }
                    .buttonStyle(.bordered)
                    .disabled(manualCode.isBlankRequiredText || isProcessing)
                    .accessibilityIdentifier("qrScanLookUpButton")
            }
            .padding(.horizontal)
            .padding(.bottom, 12)
        }
        .background(Color(.systemBackground))
    }

    // MARK: - Manual Only Fallback

    private var manualOnlyView: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "camera.badge.ellipsis")
                .decorativeIconFont(48)
                .foregroundStyle(.tertiary)

            Text("Camera not available")
                .font(.title3)
                .fontWeight(.medium)
                .foregroundStyle(.primary)

            HStack(spacing: 8) {
                TextField("Type or paste code...", text: $manualCode)
                    .textFieldStyle(.roundedBorder)
                    .submitLabel(.search)
                    .onSubmit { processManualEntry() }
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .accessibilityLabel("QR code")
                    .accessibilityIdentifier("qrScanManualCodeField")

                Button("Look Up") { processManualEntry() }
                    .buttonStyle(.borderedProminent)
                    .disabled(manualCode.isBlankRequiredText || isProcessing)
                    .accessibilityIdentifier("qrScanLookUpButton")
            }
            .padding(.horizontal, 24)

            feedbackStatusView
                .padding(.horizontal, 24)

            Spacer()
        }
        .background(Color(.systemBackground))
    }

    @ViewBuilder
    private var feedbackStatusView: some View {
        HStack(spacing: 8) {
            if isProcessing {
                ProgressView()
                    .controlSize(.small)
                    .accessibilityHidden(true)
                Text("Looking up…")
                    .fontWeight(.medium)
            } else if let error = scanError {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
                    .accessibilityHidden(true)
                Text(error)
                    .fontWeight(.medium)
                    .foregroundStyle(.red)
            } else if let feedback = resultFeedback, feedback.typeMismatch {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .accessibilityHidden(true)
                Text(feedback.message)
                    .fontWeight(.medium)
                    .foregroundStyle(.orange)
            } else if let feedback = resultFeedback {
                Image(systemName: resultIsFound ? "checkmark.circle.fill" : "questionmark.circle.fill")
                    .foregroundStyle(resultIsFound ? .green : .orange)
                    .accessibilityHidden(true)
                Text(feedback.message)
                    .fontWeight(.medium)
                    .foregroundStyle(resultIsFound ? .green : .orange)
            } else {
                Image(systemName: "viewfinder")
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
                Text(isScannerSupported ? "Point camera at a QR code" : "Enter a QR code to look it up")
                    .foregroundStyle(.secondary)
            }
        }
        .font(.subheadline)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("qrScanStatus")
        .accessibilityLabel(statusAccessibilityLabel)
        .accessibilityAddTraits(.updatesFrequently)
    }

    private var statusAccessibilityLabel: String {
        if isProcessing {
            return "Looking up…"
        }
        if let error = scanError {
            return error
        }
        if let resultFeedback {
            return resultFeedback.message
        }
        return isScannerSupported ? "Point camera at a QR code" : "Enter a QR code to look it up"
    }

    private func announceStatus(_ status: String) {
        #if canImport(UIKit)
        UIAccessibility.post(notification: .announcement, argument: status)
        #endif
    }

    // MARK: - Scanning

    private func startScanning() {
        let newScanner = IOSQRScanner()
        scanner = newScanner

        guard newScanner.isAvailable else {
            scanError = "Camera scanner not available."
            return
        }

        scanError = nil

        Task {
            do {
                let stream = try await newScanner.startScanning()
                for await event in stream {
                    switch event {
                    case .detected(let payload, _):
                        await processPayload(payload)
                    case .error(let msg):
                        // SwiftUI @State must be mutated on the main actor (GH #711).
                        await MainActor.run { scanError = msg }
                    case .permissionDenied:
                        await MainActor.run {
                            scanError = "Camera permission required. Enable in Settings."
                        }
                        return
                    }
                }
            } catch {
                await MainActor.run {
                    scanError = userFriendlyError(error, context: "scan item")
                }
            }
        }
    }

    // MARK: - Processing
    private func processManualEntry() {
        guard let code = QRScanManualSubmissionGate.code(
            from: manualCode,
            isProcessing: isProcessing
        ) else { return }
        Task {
            await processPayload(code)
            await MainActor.run { manualCode = "" }
        }
    }

    private func processPayload(_ payload: String) async {
        guard let db = appCore.db else {
            await MainActor.run { scanError = "Database not available" }
            return
        }

        // Claim the processing slot atomically on MainActor. Camera streams can
        // deliver the same payload again while the first database lookup awaits.
        let shouldSkip = await MainActor.run {
            guard deliveryGate.claim(payload) else { return true }

            scanError = nil
            resultTitle = nil
            resultIsFound = false
            resultEntityType = nil
            resultCode = nil
            return false
        }
        if shouldSkip { return }

        // Let SwiftUI render and announce the loading state before the local
        // synchronous lookup begins, even when the database responds quickly.
        await Task.yield()

        do {
            let service = QRAutoFillService(db: db)
            let result = try service.processQRScan(payload)

            let title = result.fields["name"]
                ?? result.fields["po_number"]
                ?? result.fields["job_name"]
                ?? result.fields["tool_name"]
                ?? result.fields["label"]
                ?? result.fields["display_name"]
                ?? result.fields["code"]
                ?? result.code

            let shouldAutoComplete = result.isFound
                && (expectedType == nil || result.entityType == expectedType)

            await MainActor.run {
                let shouldComplete = deliveryGate.finish(
                    payload,
                    isFound: result.isFound,
                    shouldComplete: shouldAutoComplete
                )
                resultTitle = title
                resultIsFound = result.isFound
                resultEntityType = result.entityType
                resultCode = result.code

                // Every result callback mutates parent SwiftUI state. Keep the
                // callback and dismissal in one MainActor transaction.
                if shouldComplete {
                    QRScanCompletionDispatcher.deliver(
                        dismiss: { dismiss() },
                        onResult: { onResult(result) }
                    )
                }
            }
        } catch {
            await MainActor.run {
                deliveryGate.fail(payload)
                scanError = userFriendlyError(error, context: "scan item")
            }
        }
    }
}
