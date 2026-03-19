# Platform Adapters

> Defines the adapter interfaces that allow the shared `WiredPartCore` to work across macOS, iOS, and Windows while keeping platform-specific code isolated.

---

## Adapter Architecture

```
┌─────────────────────────────────────────┐
│          Platform App (SwiftUI)          │
│  macOS: Sidebar, NSMenu, NSWindow       │
│  iOS: TabBar, UIKit bridges             │
│  Windows: WinUI 3 or Swift on Windows   │
├─────────────────────────────────────────┤
│        Platform Adapters Layer           │
│  Implements protocols from Core          │
│  using platform-specific APIs            │
├─────────────────────────────────────────┤
│          WiredPartCore Package           │
│  Pure Swift: Models, Services, Sync      │
│  No UIKit/SwiftUI/AppKit deps           │
└─────────────────────────────────────────┘
```

---

## 1. Sync Transport Adapter

The sync system has two transports. LAN HTTP works everywhere. Multipeer is Apple-only.

### Protocol (in Core)

```swift
// core/Sources/WiredPartCore/Sync/SyncTransport.swift

protocol SyncTransport: AnyObject {
    var isAvailable: Bool { get }
    var transportName: String { get }

    func start(config: SyncTransportConfig) async throws
    func stop() async
    func sendChanges(_ changes: [ChangeLogEntry], toPeer: PeerInfo) async throws -> SyncResponse
    func pullChanges(fromPeer: PeerInfo, sinceSequence: Int) async throws -> [ChangeLogEntry]
}

struct SyncTransportConfig {
    let deviceId: String
    let deviceName: String
    let companyId: String
    let syncPort: UInt16
}
```

### Implementations

| Platform | Transport | Implementation |
|----------|-----------|---------------|
| macOS | LAN HTTP | `LanSyncServer.swift` (Core — swift-nio) |
| macOS | Multipeer | `MultipeerManager.swift` (Core — MCSession) |
| iOS | LAN HTTP | Same as macOS |
| iOS | Multipeer | Same as macOS |
| Windows | LAN HTTP | Same (swift-nio compiles on Windows) |
| Windows | Multipeer | **Not available** — `isAvailable = false` |

### Compile-Time Gating

```swift
// In PeerManager.swift
#if canImport(MultipeerConnectivity)
    private let multipeerTransport = MultipeerManager()
#endif

// Always available on all platforms
private let lanTransport = LanSyncServer()
```

---

## 2. AI Service Adapter

AI features use platform-native models as primary, with llama.cpp as cross-platform fallback.

### Protocol (in Core)

```swift
// core/Sources/WiredPartCore/AI/AIServiceProtocol.swift

enum AIAvailability {
    case available
    case notEligible      // hardware doesn't support it
    case notEnabled       // user hasn't enabled it in OS
    case notReady         // model downloading
    case unavailable      // OS too old
    case notNative        // not running in native app
}

enum EnhanceMode: String, CaseIterable {
    case proofread, rewrite, summarize, expand, professional
}

protocol AIService: AnyObject {
    func checkAvailability() async -> AIAvailability
    func generateCompletion(partialText: String, fieldType: String?, context: [String: String]?) async throws -> String
    func enhanceText(_ text: String, mode: EnhanceMode) async throws -> String
    func generatePreFill(fieldType: String, contextData: [String: String]) async throws -> String
}
```

### Implementations

| Platform | Primary | Fallback |
|----------|---------|----------|
| macOS 26+ | `FoundationModelsService` (direct Swift) | `LlamaCppService` |
| macOS <26 | N/A | `LlamaCppService` |
| iOS 26+ | `FoundationModelsService` | `LlamaCppService` |
| iOS <26 | N/A | `LlamaCppService` |
| Windows | `CopilotRuntimeService` (Phase 13) | `LlamaCppService` |

### AI Service Factory

```swift
// core/Sources/WiredPartCore/AI/AIServiceFactory.swift

class AIServiceFactory {
    static func createService(preference: AIPreference) -> AIService {
        switch preference {
        case .native:
            #if canImport(FoundationModels)
            if #available(macOS 26.0, iOS 26.0, *) {
                return FoundationModelsService()
            }
            #endif
            return LlamaCppService()

        case .localLLM:
            return LlamaCppService()

        case .auto:
            #if canImport(FoundationModels)
            if #available(macOS 26.0, iOS 26.0, *) {
                let fm = FoundationModelsService()
                if await fm.checkAvailability() == .available {
                    return fm
                }
            }
            #endif
            return LlamaCppService()
        }
    }
}
```

---

## 3. File System Adapter

Different platforms store data in different locations. The adapter resolves paths.

### Protocol (in Core)

```swift
// core/Sources/WiredPartCore/Database/StorageAdapter.swift

protocol StorageAdapter {
    /// App-private database path (default)
    var privateDatabasePath: String { get }

    /// Shared database path (shop computers only)
    var publicDatabasePath: String? { get }

    /// Path to store downloaded AI models
    var aiModelStoragePath: String { get }

    /// Path for temporary export files
    var tempExportPath: String { get }

    /// Create the public data directory if it doesn't exist
    func createPublicDataDir() throws
}
```

### Implementations

| Platform | Private DB | Public DB | AI Models |
|----------|-----------|-----------|-----------|
| macOS | `~/Library/Application Support/com.wiredpart.app/wiredpart.db` | `/Users/Shared/WiredPart/wiredpart.db` | `~/Library/Application Support/com.wiredpart.app/models/` |
| iOS | `Documents/wiredpart.db` (sandbox) | N/A (single user) | `Documents/models/` |
| Windows | `%LOCALAPPDATA%\WiredPart\wiredpart.db` | `C:\Users\Public\WiredPart\wiredpart.db` | `%LOCALAPPDATA%\WiredPart\models\` |

---

## 4. Notification Adapter

Platform-specific notification delivery.

### Protocol (in Core)

```swift
// core/Sources/WiredPartCore/Services/NotificationAdapter.swift

protocol NotificationAdapter {
    func requestPermission() async -> Bool
    func scheduleLocal(title: String, body: String, badge: Int?) async
    func clearBadge() async
}
```

### Implementations

| Platform | Implementation |
|----------|---------------|
| macOS | `UNUserNotificationCenter` |
| iOS | `UNUserNotificationCenter` |
| Windows | `ToastNotificationManager` (WinRT) |

---

## 5. Location Adapter (Jobs/Labor)

GPS capture for clock in/out.

### Protocol (in Core)

```swift
protocol LocationAdapter {
    func requestPermission() async -> Bool
    func getCurrentLocation() async throws -> (latitude: Double, longitude: Double, accuracy: Double)
}
```

### Implementations

| Platform | Implementation |
|----------|---------------|
| macOS | `CLLocationManager` (limited accuracy — Wi-Fi based) |
| iOS | `CLLocationManager` (full GPS) |
| Windows | `Windows.Devices.Geolocation.Geolocator` |

---

## 6. QR/Barcode Scanner Adapter (Enhanced — Phase 12+)

The QR scanner adapter is extended to support continuous scanning, multiple code types, and the new V2 QR payload schema with entity-type auto-fill.

### Protocol (in Core)

```swift
// core/Sources/WiredPartCore/QR/QRScannerAdapter.swift

protocol QRScannerAdapter {
    var isAvailable: Bool { get }
    func startScanning() async throws -> AsyncStream<QRScanEvent>
    func stopScanning()
}

enum QRScanEvent {
    case detected(payload: String, bounds: CGRect)
    case error(Error)
    case permissionDenied
}

// Legacy single-scan API (backward compat)
protocol ScannerAdapter {
    var isAvailable: Bool { get }
    func scan() async throws -> ScanResult
}

struct ScanResult {
    let value: String
    let format: ScanFormat  // qr, barcode, code128, etc.
}
```

### Implementations

| Platform | Implementation | Features |
|----------|---------------|----------|
| macOS | `AVCaptureSession` + `VNDetectBarcodesRequest` | Webcam QR/barcode, file-based QR reading |
| iOS | `DataScannerViewController` (VisionKit) | Live camera, haptic feedback, torch control |
| Windows | `Windows.Devices.PointOfService.BarcodeScanner` + `MediaCapture` fallback | USB scanner, camera fallback |

---

## 7. OCR Scanner Adapter (Phase 12+)

Document scanning and text recognition for paper POs, delivery sheets, and handwritten notes.

### Protocol (in Core)

```swift
// core/Sources/WiredPartCore/AI/OCRScannerAdapter.swift

protocol OCRScannerAdapter {
    var isAvailable: Bool { get }

    /// Open document scanner (camera or file picker)
    func scanDocument() async throws -> ScannedDocument

    /// Recognize text in a single image
    func recognizeText(in image: CGImage) async throws -> [RecognizedTextBlock]
}

struct ScannedDocument {
    let pages: [ScannedPage]
}

struct ScannedPage {
    let image: CGImage
    let pageIndex: Int
}

struct RecognizedTextBlock {
    let text: String
    let confidence: Float           // 0.0–1.0
    let boundingBox: CGRect         // normalized coordinates
    let isHandwritten: Bool
}
```

### Implementations

| Platform | Implementation |
|----------|---------------|
| macOS | `VNRecognizeTextRequest` (.accurate level) via Vision framework. File picker for existing documents. Custom word list from parts/suppliers DB. |
| iOS | `VNDocumentCameraViewController` for multi-page document capture + `VNRecognizeTextRequest`. Real-time quality feedback. |
| Windows | `Windows.Media.Ocr.OcrEngine` (WinRT). Fallback: Tesseract C library binding. |

---

## 8. Image Feature Extraction Adapter (Phase 12+)

Extracts feature vectors from images for camera-based part matching.

### Protocol (in Core)

```swift
// core/Sources/WiredPartCore/AI/ImageFeatureAdapter.swift

protocol ImageFeatureAdapter {
    var isAvailable: Bool { get }

    /// Extract a feature vector from an image
    func extractFeatures(from image: CGImage) async throws -> [Float]

    /// Feature vector dimension (e.g., 2048 for VNFeaturePrint)
    var featureDimension: Int { get }
}
```

### Implementations

| Platform | Implementation | Vector Dimension |
|----------|---------------|:----------------:|
| macOS/iOS | `VNGenerateImageFeaturePrintRequest` (Vision framework) | 2048 |
| Windows | MobileNetV3-Small via ONNX Runtime (penultimate layer) | 1024 |

### Notes
- Apple Vision feature print is built-in — no model download needed
- Windows requires a bundled ONNX model (~15MB)
- Feature vectors from different adapters are NOT interchangeable — the `adapter_type` column in `part_image_features` ensures vectors are only compared against same-adapter vectors
- If a device rebuilds its index with a different adapter, all vectors are recomputed

---

## 9. PDF Generation Adapter

### Protocol (in Core)

```swift
protocol PDFGenerator {
    func generatePurchaseOrderPDF(po: PurchaseOrder, lineItems: [POLineItem], company: CompanyProfile) throws -> Data
    func generateReportPDF(report: ReportData) throws -> Data
}
```

### Implementations

| Platform | Implementation |
|----------|---------------|
| macOS/iOS | `PDFKit.PDFDocument` + custom `PDFPage` rendering |
| Windows | TBD (Phase 14) |

---

## Ad-Hoc Network Sync (Mac ↔ Windows)

When Mac and Windows devices are not on a shared LAN, the user can initiate a direct sync:

1. **Windows creates a Wi-Fi hotspot** (Settings > Network > Mobile Hotspot)
2. **Mac joins the hotspot** (Wi-Fi menu > select Windows hotspot)
3. **Both devices are now on the same LAN** (the hotspot's local network)
4. **Standard LAN HTTP sync runs** — no protocol changes needed
5. **User triggers sync** from Settings > Sync > "Sync Now"

This requires no code changes to the sync engine — it's purely a network configuration step. The Settings UI on both platforms should include:
- Instructions for creating/joining the hotspot
- A "Scan for peers" button that re-runs mDNS discovery
- Status indicator showing when the other device is found
