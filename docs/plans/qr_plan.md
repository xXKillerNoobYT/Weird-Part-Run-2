# QR Code Recognition & Auto-Fill Plan

> **Created:** 2026-03-15
> **Phase:** 12+ (AI Integration Extension)
> **Dependencies:** Phase 1 (Core Package), Phase 6 (Warehouse — existing QR infra)
> **Constraint:** Fully offline. Cross-platform parity. Bluetooth-only sync.

---

## Overview

Extend the existing QR code system from basic part/bin identification to a full auto-fill pipeline. QR codes scanned via device camera extract structured data (part numbers, job IDs, supplier IDs, bin locations) and auto-populate forms across every module. Cross-platform parity between macOS, iOS, and Windows.

---

## Current State

The existing QR system (`src/lib/qr-utils.ts`) encodes/decodes WiredPart-specific JSON payloads:

```json
{
  "app": "wiredpart",
  "part_id": 42,
  "code": "ELB-90-2IN-WHT",
  "version": 1
}
```

Libraries in use:
- `html5-qrcode` (browser/WebView scanning)
- `qrcode` (generation)
- `jsbarcode` (barcode generation)

The native SwiftUI migration needs to replace these with platform-native implementations.

---

## QR Payload Schema (Extended)

Extend the QR payload to support multiple entity types:

```json
{
  "app": "wiredpart",
  "version": 2,
  "type": "part | job | supplier | bin | vehicle | tool | employee | po",
  "id": 42,
  "code": "ELB-90-2IN-WHT",
  "meta": {
    "name": "2\" White 90° Elbow",
    "category": "Fittings"
  }
}
```

### Supported QR Types

| Type | Payload Fields | Auto-Fill Target |
|------|---------------|-----------------|
| `part` | id, code, name, category | Part selection in any form |
| `job` | id, code, name, customer | Job selection, clock-in, orders |
| `supplier` | id, code, name | Supplier selection in orders |
| `bin` | id, code, warehouse, aisle, shelf | Bin location in movements, receiving |
| `vehicle` | id, code, plate, type | Vehicle selection in fleet |
| `tool` | id, code, name, serial | Tool checkout/return |
| `employee` | id, code, name | Employee selection, labor entry |
| `po` | id, number, supplier | PO lookup in receiving |

---

## Technical Architecture

### Native QR Scanner (Apple)

```
Camera Feed
    │
    ▼
┌────────────────────────────┐
│ DataScannerViewController  │  ← iOS (VisionKit)
│ AVCaptureSession +         │  ← macOS (AVFoundation)
│ VNDetectBarcodesRequest    │
└──────────┬─────────────────┘
           │ [VNBarcodeObservation]
           ▼
┌────────────────────────────┐
│ QRDecoder (Core)           │
│ - Parse JSON payload       │
│ - Validate schema          │
│ - Resolve entity from DB   │
│ - Build auto-fill map      │
└──────────┬─────────────────┘
           │ QRScanResult
           ▼
┌────────────────────────────┐
│ Target Form / Action       │
│ - Auto-fill fields         │
│ - Navigate to entity       │
│ - Trigger action           │
└────────────────────────────┘
```

### Core Module: QRCodec

**Path:** `core/Sources/WiredPartCore/QR/QRCodec.swift`

```swift
struct QRCodec {
    /// Encode an entity into a QR JSON payload
    static func encode(_ entity: QREntity) throws -> String

    /// Decode a scanned string into a QR entity
    static func decode(_ payload: String) throws -> QREntity

    /// Validate a decoded entity against the local database
    func resolve(_ entity: QREntity) async throws -> QRResolvedEntity
}

enum QREntityType: String, Codable {
    case part, job, supplier, bin, vehicle, tool, employee, po
}

struct QREntity: Codable {
    let app: String             // "wiredpart"
    let version: Int            // 2
    let type: QREntityType
    let id: Int64
    let code: String
    let meta: [String: String]?
}

struct QRResolvedEntity {
    let entity: QREntity
    let resolved: Bool          // found in local DB
    let displayName: String
    let autoFillMap: [String: String]  // form field → value
}
```

### QR Generation

**Path:** `core/Sources/WiredPartCore/QR/QRGenerator.swift`

```swift
struct QRGenerator {
    /// Generate a QR code image from an entity
    static func generate(_ entity: QREntity, size: CGSize) throws -> CGImage

    /// Generate a printable label with QR code + text
    static func generateLabel(_ entity: QREntity,
                              includeText: Bool,
                              size: CGSize) throws -> CGImage
}
```

Uses `CIFilter.qrCodeGenerator()` (Core Image) — available on all Apple platforms.

---

## Platform Adapter: QR Scanner

**Path:** `core/Sources/WiredPartCore/QR/QRScannerAdapter.swift`

```swift
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
```

### Apple Implementation (iOS)

**Path:** `ios-app/WiredPartIOS/Adapters/IOSQRScanner.swift`

- `DataScannerViewController` for live camera scanning
- Supports QR codes + Code 128 barcodes
- Real-time overlay showing detected codes
- Haptic feedback on successful scan

### Apple Implementation (macOS)

**Path:** `mac/WiredPart/Adapters/MacQRScanner.swift`

- `AVCaptureSession` with built-in/external webcam
- `VNDetectBarcodesRequest` for QR detection
- Preview in a floating panel or sheet
- Also supports file-based QR reading (drag image onto reader)

### Windows Implementation

**Path:** `windows/Adapters/WindowsQRScanner.swift`

- `Windows.Devices.PointOfService.BarcodeScanner` for USB scanners
- Camera-based fallback via `MediaCapture` + `BarcodeDecoder`
- USB barcode scanners appear as keyboard input (auto-detect prefix/suffix)

---

## Auto-Fill Integration Points

### Per-Module QR Actions

| Module | Scan Trigger | QR Type(s) | Auto-Fill Action |
|--------|-------------|------------|-----------------|
| **Warehouse Receiving** | "Scan" button on receiving session | `po`, `part`, `bin` | Fill PO reference, add line item, set destination bin |
| **Warehouse Movement** | "Scan" button on movement wizard | `part`, `bin` | Select part to move, set source/destination bin |
| **Orders — New JPO** | "Scan Part" in line item entry | `part`, `supplier` | Add part to order, pre-select supplier |
| **Orders — Receiving** | "Scan PO" at start of session | `po` | Load PO details and expected line items |
| **Jobs — Clock In** | "Scan Job" on clock-in screen | `job` | Select job to clock into |
| **Tools — Checkout** | "Scan Tool" on checkout form | `tool` | Select tool for checkout/return |
| **Tools — Kit Verify** | "Scan Items" during verification | `tool` | Check off tool from kit manifest |
| **Fleet — Inspection** | "Scan Vehicle" on inspection form | `vehicle` | Load vehicle details for inspection |
| **Parts — Catalog** | "Scan" on catalog search | `part` | Navigate to part detail |
| **People — Directory** | "Scan Badge" on directory | `employee` | Navigate to employee detail |

### Universal QR Action

A global "Scan QR" action (accessible from toolbar or keyboard shortcut) that:
1. Scans any WiredPart QR code
2. Determines the entity type
3. Navigates to the relevant detail page
4. If in a form context, auto-fills the matching field instead

---

## Backward Compatibility

| Scenario | Handling |
|----------|---------|
| V1 QR codes (no `type` field) | Treated as `type: "part"` for backward compat |
| Non-WiredPart QR codes | Display raw text, offer to search parts catalog by code |
| Damaged/partial QR | Show "Couldn't read QR code" with retry option |
| QR from different company | Show entity info but flag as "external" |

---

## QR Label Printing

Integrate with the existing label generation system:

| Label Type | Contents | Print Target |
|-----------|----------|-------------|
| Part label | QR + part code + description + bin | Thermal printer (2"×1") |
| Bin label | QR + bin code + warehouse + aisle/shelf | Thermal printer (2"×1") |
| Tool label | QR + tool name + serial + owner | Thermal printer (2"×1") |
| Vehicle placard | QR + plate + vehicle name | Standard printer (4"×3") |

---

## Bluetooth Sync Considerations

QR-related data syncs normally — the QR system itself doesn't generate new sync data beyond what already exists for the entities it references. However:

- Newly generated QR label images are stored locally (not synced — regenerated per device)
- QR scan history (for audit) is logged locally with timestamps
- If a scanned QR references an entity not yet synced to this device, show "Entity not found locally — sync first"

---

## Cross-Platform Parity Matrix

| Feature | macOS | iOS | Windows |
|---------|:-----:|:---:|:-------:|
| Camera QR scanning | AVFoundation | DataScanner | MediaCapture |
| File-based QR reading | Core Image | Core Image | Windows.Media.Ocr |
| USB barcode scanner | N/A | N/A | PointOfService API |
| QR generation | CIFilter | CIFilter | QRCoder library |
| Label printing | PDFKit | PDFKit | TBD |
| Auto-fill pipeline | Shared Core | Shared Core | Shared Core |
| Haptic on scan | N/A | UIImpactFeedback | N/A |

---

## Implementation Status

### Core Infrastructure (COMPLETE)
- ✅ `QRCodec.swift` — V2 payload encode/decode, V1 backward compat, 8 entity types, 14 tests passing
- ✅ `QRGenerator.swift` — CIFilter-based QR image generation, PNG export
- ✅ `IOSQRScanner.swift` — VisionKit DataScannerViewController, QR + barcode support, haptic feedback
- ✅ `QRScannerAdapter.swift` / `QRAutoFillService` — DB lookup for all entity types, field mappings
- ✅ `IOSDashboardQRScannerPage.swift` — Continuous scan with lock/unlock, entity detail, quick actions
- ✅ `IOSOCRScanner.swift` — VisionKit document camera, text extraction
- ✅ `IOSAutoFillBanner.swift` — Touch-optimized auto-fill banners for QR and OCR

### Per-Module Integration (Prompts 20A-20D)
- ⬜ 20A: Reusable `QRScanSheet` component + Warehouse (Receiving PO scan, Movement part/bin scan)
- ⬜ 20B: Orders (PO creation part/supplier scan, PO list lookup, Procurement JPO scan)
- ⬜ 20C: Jobs clock-in scan, Tool checkout/return/registry scan
- ⬜ 20D: Catalog part/barcode scan, Employee badge scan

### Deferred (v2.0+)
- macOS AVCaptureSession scanner
- Windows MediaCapture + USB barcode scanner
- QR label thermal printing integration
- File-based QR reading (drag image)

---

## Acceptance Criteria

| Criterion | Target | Measurement |
|-----------|--------|-------------|
| QR recognition accuracy | ≥ 99% for clean QR codes | 100 test QR codes at various sizes |
| QR recognition at distance | Readable at 30cm+ on iPhone | Physical test with printed labels |
| QR recognition in low light | ≥ 90% accuracy with flash/torch | 20 scans in dim lighting |
| Damaged QR tolerance | ≥ 80% at 15% damage level | 20 partially obscured codes |
| Scan-to-fill latency | < 500ms from detection to field fill | Measured on iPhone 15 |
| V1 backward compatibility | 100% of existing QR codes work | Test with 20 V1 format codes |
| Cross-platform parity | All auto-fill actions work on all platforms | Manual test on each platform |
| Barcode support (Code 128) | ≥ 95% accuracy | 30 barcode scans |

---

## Risks

| Risk | Likelihood | Impact | Mitigation |
|------|-----------|--------|------------|
| Camera permission denied | Medium | High | Clear permission prompt; fallback to manual entry |
| QR too small to scan | Low | Medium | Document minimum print size (15mm × 15mm) |
| Bright sunlight glare | Medium | Medium | Recommend matte label stock; provide scan angle tips |
| Multiple QR codes in frame | Low | Low | Highlight closest/largest; let user tap to select |
| USB scanner encoding issues | Medium | Medium (Windows) | Support common encoding prefixes; configurable in settings |
