# 20A — QR Scanner Integration: Warehouse (Receiving + Movement)

> **Chain position:** **20A** → 20B → 20C → 20D
> **Prerequisite:** None (QR core infrastructure already exists)
> **Log file:** `xcode-ai/prompt-results-log.md`

## Instructions

**IMPORTANT:** Before implementing, first plan your approach by reading all files mentioned below. Understand the current state, then implement the fixes. When done, wait for the user to confirm before proceeding to the next prompt.

## Context

The QR scanning infrastructure is fully built:
- `IOSQRScanner` — VisionKit camera scanner with `AsyncStream<QRScanEvent>`
- `QRAutoFillService` — decodes payloads, looks up entities in DB, returns field mappings
- `IOSDashboardQRScannerPage` — demonstrates the full integration pattern

What's missing: wiring the scanner into specific module forms so users can scan QR codes to auto-fill fields instead of manually searching.

**Existing files to reference for the scanner pattern:**
- `Weird Parts IOS/Weird Parts IOS/Scanning/IOSQRScanner.swift` — scanner API
- `core/Sources/WiredPartCore/QR/QRScannerAdapter.swift` — `QRAutoFillService` and `QRAutoFillResult`
- `Weird Parts IOS/Weird Parts IOS/Features/Dashboard/IOSDashboardQRScannerPage.swift` — reference implementation

**Files to modify:**
- `Weird Parts IOS/Weird Parts IOS/Features/Orders/IOSReceiveShipmentPage.swift`
- `Weird Parts IOS/Weird Parts IOS/Features/Warehouse/IOSMovementWizard.swift` (if it exists; if not, check `IOSStagingPage.swift`)

## Task

### Step 1: Create a reusable QR scan sheet component

Create a lightweight QR scan sheet that can be used by any page. This wraps `IOSQRScanner` in a dismissible sheet that returns a result.

Create file `Weird Parts IOS/Weird Parts IOS/Scanning/QRScanSheet.swift`:

```swift
import SwiftUI
import WiredPartCore

/// Reusable QR scan sheet. Present as a .sheet, get a callback with the result.
/// Automatically dismisses after a successful scan.
struct QRScanSheet: View {
    let expectedType: QREntityType?   // nil = accept any type
    let onResult: (QRAutoFillResult) -> Void
    @EnvironmentObject private var appCore: AppCore
    @Environment(\.dismiss) private var dismiss

    @State private var scanResult: QRAutoFillResult?
    @State private var scanError: String?
    @State private var isScanning = true

    var body: some View {
        NavigationStack {
            ZStack {
                if isScanning {
                    IOSQRScannerView { event in
                        handleScanEvent(event)
                    }
                    .ignoresSafeArea()
                }

                VStack {
                    Spacer()

                    if let error = scanError {
                        Text(error)
                            .font(.subheadline)
                            .padding()
                            .background(.ultraThinMaterial)
                            .cornerRadius(10)
                            .padding()
                    }

                    if let result = scanResult {
                        VStack(spacing: 8) {
                            HStack {
                                Image(systemName: result.isFound ? "checkmark.circle.fill" : "questionmark.circle.fill")
                                    .foregroundStyle(result.isFound ? .green : .orange)
                                Text(result.isFound ? "Found: \(result.fields["_title"] ?? result.code)" : "Not found: \(result.code)")
                                    .fontWeight(.medium)
                            }
                            if let type = result.entityType, let expected = expectedType, type != expected {
                                Text("Expected \(expected.rawValue), got \(type.rawValue)")
                                    .font(.caption)
                                    .foregroundStyle(.orange)
                            }
                        }
                        .padding()
                        .background(.ultraThinMaterial)
                        .cornerRadius(10)
                        .padding()
                    }
                }
            }
            .navigationTitle("Scan QR Code")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    private func handleScanEvent(_ event: QRScanEvent) {
        switch event {
        case .detected(let payload, _):
            guard let db = appCore.db else { return }
            let service = QRAutoFillService(db: db)
            do {
                let result = try service.processQRScan(payload)
                scanResult = result

                // If we got what we expected (or accept anything), auto-dismiss
                if let expected = expectedType {
                    if result.entityType == expected && result.isFound {
                        onResult(result)
                        dismiss()
                    }
                } else if result.isFound {
                    onResult(result)
                    dismiss()
                }
            } catch {
                scanError = "Scan error: \(error.localizedDescription)"
            }
        case .error(let error):
            scanError = error.localizedDescription
        case .permissionDenied:
            scanError = "Camera permission required. Enable in Settings."
        }
    }
}

/// Wrapper that creates an IOSQRScanner and forwards events via callback.
/// Check how IOSDashboardQRScannerPage uses IOSQRScanner and match that pattern.
private struct IOSQRScannerView: UIViewControllerRepresentable {
    let onEvent: (QRScanEvent) -> Void

    // Implementation depends on how IOSQRScanner exposes its UIViewController.
    // If IOSQRScanner provides a DataScannerViewController wrapper, use that.
    // If it uses AsyncStream, create a hosting controller that starts scanning
    // and forwards events via the callback.
    //
    // Match the exact pattern used in IOSDashboardQRScannerPage.swift.
    // The key is: start scanning → receive .detected events → call onEvent.

    func makeUIViewController(context: Context) -> UIViewController {
        // Check IOSQRScanner's API and implement accordingly.
        // This is a placeholder — match the real scanner API.
        UIViewController()
    }

    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {}
}
```

**Important:** The exact `IOSQRScannerView` implementation depends on how `IOSQRScanner` exposes its view controller. Read `IOSQRScanner.swift` and `IOSDashboardQRScannerPage.swift` to understand the real API, then implement `IOSQRScannerView` to match. The scanner may already have a SwiftUI-compatible view — if so, use it directly instead of wrapping.

### Step 2: Add QR scan to IOSReceiveShipmentPage

Add a "Scan PO" button to the receiving page. When scanned, it auto-selects the matching PO for receiving.

```swift
// Add state:
@State private var showQRScanner = false

// Add toolbar button:
.toolbar {
    ToolbarItem(placement: .primaryAction) {
        Button {
            showQRScanner = true
        } label: {
            Image(systemName: "qrcode.viewfinder")
        }
    }
}

// Add sheet:
.sheet(isPresented: $showQRScanner) {
    QRScanSheet(expectedType: .po) { result in
        // Auto-select the PO that was scanned
        if let poId = result.entityId {
            // Navigate to or select this PO for receiving
            // Match whatever selection/navigation pattern the page uses
            selectedPOId = poId
        }
    }
    .environmentObject(appCore)
}
```

If the page already has a `.sheet`, integrate QR into the existing `ActiveSheet` enum:
```swift
case qrScanner
```

### Step 3: Add QR scan to Movement Wizard

If `IOSMovementWizard.swift` exists with a multi-step flow, add QR scanning to the part selection step.

```swift
// In the part selection step, add a scan button:
HStack {
    Text("Select Parts")
        .font(.headline)
    Spacer()
    Button {
        showPartScanner = true
    } label: {
        Label("Scan", systemImage: "qrcode.viewfinder")
            .font(.subheadline)
    }
}

@State private var showPartScanner = false

// Sheet for part scanning:
.sheet(isPresented: $showPartScanner) {
    QRScanSheet(expectedType: .part) { result in
        if let partId = result.entityId, result.isFound {
            // Add this part to the movement list
            // Use the fields from result.fields for name, code, etc.
            let partName = result.fields["_title"] ?? result.code
            addPartToMovement(partId: partId, name: partName)
        }
    }
    .environmentObject(appCore)
}
```

Also add bin scanning for source/destination selection:
```swift
// In the bin selection step:
Button {
    showBinScanner = true
} label: {
    Label("Scan Bin", systemImage: "qrcode.viewfinder")
        .font(.subheadline)
}

.sheet(isPresented: $showBinScanner) {
    QRScanSheet(expectedType: .bin) { result in
        if let binId = result.entityId, result.isFound {
            selectedBinId = binId
            selectedBinName = result.fields["_title"] ?? result.code
        }
    }
    .environmentObject(appCore)
}
```

If no movement wizard exists, add part/bin scan buttons to `IOSStagingPage.swift` instead.

## Important Notes

- The `QRScanSheet` is a reusable component — all subsequent prompts (20B-20D) will use it.
- `expectedType` filters what QR type is accepted. Pass `nil` to accept any type.
- The scanner should auto-dismiss on a successful, type-matching scan.
- If the scanned type doesn't match expected, show a warning but don't dismiss.
- Read `IOSDashboardQRScannerPage.swift` carefully to understand the exact scanner API before implementing `IOSQRScannerView`.

## Success Criteria

- [ ] `QRScanSheet.swift` created as reusable component
- [ ] Receiving page has QR scan button in toolbar
- [ ] Scanning a PO QR code auto-selects that PO for receiving
- [ ] Movement wizard has scan buttons for parts and bins
- [ ] Scanning a part adds it to the movement list
- [ ] Scanning a bin selects it as source/destination
- [ ] Wrong QR type shows warning, doesn't auto-dismiss
- [ ] Project builds with no errors

## Log Entry

```
## Prompt 20A Results (YYYY-MM-DD)
- Created QRScanSheet reusable component
- Added QR scan to IOSReceiveShipmentPage (PO scan)
- Added QR scan to movement wizard (part + bin scan)
- Build: [PASS/FAIL]
```

**Wait for user confirmation before proceeding to prompt 20B.**
