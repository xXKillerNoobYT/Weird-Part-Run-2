import SwiftUI
import WiredPartCore
#if !targetEnvironment(macCatalyst)
import VisionKit
#endif

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

    @State private var isScanning = false
    @State private var scanError: String?
    @State private var resultTitle: String?
    @State private var resultIsFound = false
    @State private var resultEntityType: QREntityType?
    @State private var resultCode: String?
    @State private var typeMismatch = false
    @State private var isProcessing = false

    // Manual entry
    @State private var manualCode = ""

    @State private var scanner: IOSQRScanner?

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
        }
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

            if isProcessing {
                ProgressView()
                    .tint(.white)
                    .scaleEffect(1.5)
            }
        }
    }

    // MARK: - Bottom Section

    @ViewBuilder
    private var bottomSection: some View {
        VStack(spacing: 12) {
            // Result feedback
            if let error = scanError {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.subheadline)
                    .foregroundStyle(.red)
                    .padding(.horizontal)
                    .padding(.top, 12)
            } else if let title = resultTitle {
                HStack(spacing: 8) {
                    Image(systemName: resultIsFound ? "checkmark.circle.fill" : "questionmark.circle.fill")
                        .foregroundStyle(resultIsFound ? .green : .orange)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(resultIsFound ? "Found: \(title)" : "Not found: \(resultCode ?? "")")
                            .font(.subheadline)
                            .fontWeight(.medium)
                        if typeMismatch, let got = resultEntityType, let expected = expectedType {
                            Text("Expected \(expected.rawValue), got \(got.rawValue)")
                                .font(.caption)
                                .foregroundStyle(.orange)
                        }
                    }
                }
                .padding(.horizontal)
                .padding(.top, 12)
            } else {
                HStack(spacing: 8) {
                    Image(systemName: "viewfinder")
                        .foregroundStyle(.secondary)
                        .accessibilityHidden(true)
                    Text("Point camera at a QR code")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(.top, 12)
            }

            // Manual entry
            HStack(spacing: 8) {
                TextField("Type code manually...", text: $manualCode)
                    .textFieldStyle(.roundedBorder)
                    .submitLabel(.search)
                    .onSubmit { processManualEntry() }
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)

                Button("Look Up") { processManualEntry() }
                    .buttonStyle(.bordered)
                    .disabled(manualCode.trimmingCharacters(in: .whitespaces).isEmpty || isProcessing)
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

                Button("Look Up") { processManualEntry() }
                    .buttonStyle(.borderedProminent)
                    .disabled(manualCode.isEmpty || isProcessing)
            }
            .padding(.horizontal, 24)

            if let error = scanError {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.subheadline)
                    .foregroundStyle(.red)
            }

            if let title = resultTitle {
                HStack(spacing: 8) {
                    Image(systemName: resultIsFound ? "checkmark.circle.fill" : "questionmark.circle.fill")
                        .foregroundStyle(resultIsFound ? .green : .orange)
                        .accessibilityHidden(true)
                    Text(resultIsFound ? "Found: \(title)" : "Not found")
                        .font(.subheadline)
                }
            }

            Spacer()
        }
        .background(Color(.systemBackground))
    }

    // MARK: - Scanning

    private func startScanning() {
        let newScanner = IOSQRScanner()
        scanner = newScanner

        guard newScanner.isAvailable else {
            scanError = "Camera scanner not available."
            return
        }

        isScanning = true
        scanError = nil

        Task {
            do {
                let stream = try await newScanner.startScanning()
                for await event in stream {
                    switch event {
                    case .detected(let payload, _):
                        await processPayload(payload)
                    case .error(let msg):
                        scanError = msg
                    case .permissionDenied:
                        scanError = "Camera permission required. Enable in Settings."
                        isScanning = false
                        return
                    }
                }
            } catch {
                scanError = userFriendlyError(error, context: "scan item")
                isScanning = false
            }
        }
    }

    // MARK: - Processing

    private func processManualEntry() {
        let code = manualCode.trimmingCharacters(in: .whitespaces)
        guard !code.isEmpty else { return }
        Task {
            await processPayload(code)
            await MainActor.run { manualCode = "" }
        }
    }

    private func processPayload(_ payload: String) async {
        guard let db = appCore.db else {
            scanError = "Database not available"
            return
        }

        // Skip duplicate consecutive scans
        if let current = resultCode, current == payload, resultIsFound { return }

        await MainActor.run {
            isProcessing = true
            scanError = nil
            typeMismatch = false
        }

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

            let gotMismatch = expectedType != nil && result.entityType != expectedType

            await MainActor.run {
                resultTitle = title
                resultIsFound = result.isFound
                resultEntityType = result.entityType
                resultCode = result.code
                typeMismatch = gotMismatch
                isProcessing = false
            }

            // Auto-dismiss if we found a matching result
            if result.isFound {
                if let expected = expectedType {
                    if result.entityType == expected {
                        await MainActor.run { dismiss() }
                        onResult(result)
                    }
                    // Type mismatch → don't dismiss, show warning
                } else {
                    // Accept any type
                    await MainActor.run { dismiss() }
                    onResult(result)
                }
            }
        } catch {
            await MainActor.run {
                scanError = userFriendlyError(error, context: "scan item")
                isProcessing = false
            }
        }
    }
}
