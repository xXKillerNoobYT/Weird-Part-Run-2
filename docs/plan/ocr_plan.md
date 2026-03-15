# Document Scanning & OCR Auto-Extraction Plan

> **Created:** 2026-03-15
> **Phase:** 12+ (AI Integration Extension)
> **Dependencies:** Phase 12 (AI — Apple), Core Package (Phase 1), Sync Engine (Phase 2)
> **Constraint:** Fully offline. No cloud OCR services. Bluetooth-only sync of extracted data.

---

## Overview

Add on-device OCR extraction capabilities to process scanned paper documents — purchase orders, delivery sheets, supplier invoices, and handwritten field notes. Extracted data auto-maps into the correct form fields with confidence scoring.

---

## Capabilities

### 1. OCR Text Extraction

| Feature | Description |
|---------|-------------|
| Printed text recognition | Extract typed text from scanned paper (POs, delivery sheets, invoices) |
| Handwritten number recognition | Extract handwritten quantities, dates, PO numbers |
| Signature/initial detection | Detect presence of signatures (not identity verification) |
| Multi-language | English primary. Number/date extraction is language-agnostic |

### 2. Auto-Detection of Document Fields

| Field Type | Detection Method | Target Forms |
|------------|-----------------|--------------|
| PO numbers | Regex pattern `PO-\d+`, `#\d{4,}` + positional heuristics | Orders, Receiving |
| Dates | Date format matching (MM/DD/YYYY, YYYY-MM-DD, written months) | All forms |
| Quantities | Numeric values adjacent to part descriptions or line items | Receiving, Orders |
| Supplier names | Match against known supplier database | Orders, POs |
| Part numbers | Match against parts catalog codes | Receiving, Warehouse |
| Delivery sheet fields | Structured extraction from known delivery form layouts | Warehouse Receiving |
| Handwritten numbers | VNRecognizeTextRequest with handwriting level | Quantity fields |
| Signatures/initials | Bounding box detection in expected signature regions | Delivery confirmation |

### 3. Auto-Mapping to Form Fields

Extracted fields are mapped to the target form with a confidence score:
- **High confidence (≥ 0.90):** Auto-filled, green indicator
- **Medium confidence (0.70–0.89):** Auto-filled with yellow warning, user review suggested
- **Low confidence (< 0.70):** Displayed as suggestion, not auto-filled

---

## Technical Architecture

### Apple Platforms (macOS / iOS)

```
Camera/Scanner Input
       │
       ▼
┌─────────────────────────┐
│  VisionKit              │
│  DataScannerViewController (iOS) │
│  VNDocumentCameraViewController  │
│  (iOS document scan mode)        │
└──────────┬──────────────┘
           │ CGImage
           ▼
┌─────────────────────────┐
│  Vision Framework       │
│  VNRecognizeTextRequest │
│  - .accurate level      │
│  - revision 3           │
│  - custom words list    │
│    (supplier names,     │
│     part codes)         │
└──────────┬──────────────┘
           │ [VNRecognizedText]
           ▼
┌─────────────────────────┐
│  OCRProcessor (Core)    │
│  - Field extraction     │
│  - Pattern matching     │
│  - Confidence scoring   │
│  - Form field mapping   │
└──────────┬──────────────┘
           │ OCRExtractionResult
           ▼
┌─────────────────────────┐
│  Target Form View       │
│  - Auto-fill fields     │
│  - Confidence indicators│
│  - User review/edit     │
└─────────────────────────┘
```

### Windows Platform

```
Camera/Scanner Input
       │
       ▼
┌─────────────────────────┐
│  Windows.Media.Ocr      │
│  OcrEngine              │
│  (UWP/WinRT)            │
└──────────┬──────────────┘
           │ OcrResult
           ▼
┌─────────────────────────┐
│  OCRProcessor (Core)    │
│  (same field extraction │
│   logic as Apple)       │
└─────────────────────────┘
```

---

## Core Module: OCRProcessor

**Path:** `core/Sources/WiredPartCore/AI/OCRProcessor.swift`

```swift
/// Platform-agnostic OCR result processing.
/// Receives raw recognized text blocks from platform adapters,
/// applies field extraction, pattern matching, and confidence scoring.

struct OCRProcessor {
    let partsLookup: PartsLookupProvider
    let suppliersLookup: SuppliersLookupProvider

    func extractFields(from recognizedBlocks: [RecognizedTextBlock],
                       documentType: DocumentType) -> OCRExtractionResult

    func matchSupplier(name: String) -> SupplierMatch?
    func matchPartCode(code: String) -> PartMatch?
    func parseDate(text: String) -> DateParseResult?
    func parseQuantity(text: String) -> Int?
    func parsePONumber(text: String) -> String?
}
```

### Data Types

```swift
enum DocumentType {
    case purchaseOrder
    case deliverySheet
    case supplierInvoice
    case handwrittenNote
    case unknown
}

struct RecognizedTextBlock {
    let text: String
    let confidence: Float           // 0.0–1.0
    let boundingBox: CGRect         // normalized coordinates
    let isHandwritten: Bool
}

struct OCRExtractionResult {
    let documentType: DocumentType
    let extractedFields: [ExtractedField]
    let rawText: String
    let overallConfidence: Float
    let processingTimeMs: Int
}

struct ExtractedField {
    let fieldType: FormFieldType
    let value: String
    let confidence: Float
    let sourceRegion: CGRect        // where on the document
    let alternatives: [String]      // other possible values
}

enum FormFieldType {
    case poNumber
    case date
    case quantity
    case supplierName
    case partNumber
    case partDescription
    case unitPrice
    case totalAmount
    case deliveryAddress
    case signaturePresent
    case notes
}

struct SupplierMatch {
    let supplier: Supplier
    let confidence: Float
    let matchMethod: MatchMethod    // exact, fuzzy, alias
}

struct PartMatch {
    let part: Part
    let confidence: Float
    let matchMethod: MatchMethod
}

enum MatchMethod {
    case exact
    case fuzzy(distance: Int)
    case alias
    case partialCode
}
```

---

## Platform Adapter: OCR Scanner

**Path:** `core/Sources/WiredPartCore/AI/OCRScannerAdapter.swift`

```swift
protocol OCRScannerAdapter {
    var isAvailable: Bool { get }
    func scanDocument() async throws -> ScannedDocument
    func recognizeText(in image: CGImage) async throws -> [RecognizedTextBlock]
}

struct ScannedDocument {
    let pages: [ScannedPage]
}

struct ScannedPage {
    let image: CGImage
    let pageIndex: Int
}
```

### Apple Implementation

**Path:** `mac/WiredPart/Adapters/AppleOCRScanner.swift` (macOS)
**Path:** `ios-app/WiredPartIOS/Adapters/AppleOCRScanner.swift` (iOS)

- Uses `VNRecognizeTextRequest` with `.accurate` recognition level
- Custom words list populated from parts catalog codes and supplier names
- Handwriting detection via `VNRecognizeTextRequest` with `usesLanguageCorrection = true`
- Document camera via `VNDocumentCameraViewController` (iOS) or file picker (macOS)

### Windows Implementation

**Path:** `windows/Adapters/WindowsOCRScanner.swift`

- Uses `Windows.Media.Ocr.OcrEngine`
- Falls back to Tesseract via C library binding if WinRT OCR unavailable

---

## Integration Points

### 1. Warehouse Receiving Session

**Trigger:** User taps "Scan Document" in receiving session
**Flow:**
1. Camera opens in document scan mode
2. User captures delivery sheet / packing slip
3. OCR extracts: PO number, quantities, part numbers, dates
4. Extracted fields pre-fill the receiving form
5. User reviews, corrects, and confirms

### 2. Purchase Order Import

**Trigger:** User taps "Scan PO" in Orders module
**Flow:**
1. Camera/file picker provides document image
2. OCR extracts: supplier name, PO number, line items (part + qty + price)
3. Supplier auto-matched from database
4. Line items mapped to parts catalog
5. New PO created with extracted data for review

### 3. Delivery Sheet Confirmation

**Trigger:** User taps "Scan Delivery" in Fleet/Deliveries
**Flow:**
1. Camera captures signed delivery sheet
2. OCR detects: delivery date, recipient signature presence, notes
3. Delivery record updated with confirmation data

### 4. Handwritten Field Notes

**Trigger:** User taps "Scan Notes" in Job Detail or Notebook
**Flow:**
1. Camera captures handwritten notes
2. OCR extracts text with handwriting recognition
3. Extracted text added to notebook entry or job notes
4. Original image stored as attachment

---

## Bluetooth Sync of Extracted Data

Extracted OCR data syncs via the existing `_change_log` mechanism:

| Data | Sync Behavior |
|------|---------------|
| Extracted text fields | Normal record sync (receiving session, PO, notes) |
| Scanned page images | Stored as binary blobs, synced as attachment records |
| Confidence metadata | Stored in `extraction_metadata` JSON column, synced with record |
| OCR processing log | Local-only, not synced (diagnostic data) |

Image attachments follow a chunked sync strategy for Bluetooth:
- Images compressed to JPEG 80% quality before storage
- Maximum 2MB per scanned page
- Chunked into 16KB Bluetooth MTU frames
- Reassembled on receiving device
- Hash verification after reassembly

---

## Error Detection & Recovery

| Error Scenario | Detection | Recovery |
|---------------|-----------|----------|
| Blurry/unreadable scan | Overall confidence < 0.50 | Prompt user to rescan with better lighting |
| Partial extraction | Some fields extracted, others empty | Show extracted fields, highlight missing ones |
| Wrong document type | Extracted fields don't match expected | Suggest correct document type or manual entry |
| Supplier not found | No match in database | Show "New supplier?" option or manual selection |
| Part code not found | No match in catalog | Show closest matches or allow manual entry |
| Handwriting unreadable | Per-block confidence < 0.40 | Show original image alongside best-guess text |

---

## Acceptance Criteria

| Criterion | Target | Measurement |
|-----------|--------|-------------|
| Printed text OCR accuracy | ≥ 95% character accuracy | 50-document test corpus |
| Handwritten number recognition | ≥ 85% accuracy | 30-sample handwritten number set |
| PO number extraction | ≥ 90% correct extraction | 40 PO documents |
| Supplier name matching | ≥ 85% correct match (from known suppliers) | 30 supplier documents |
| Part code extraction | ≥ 80% correct extraction | 40 documents with part codes |
| Date extraction | ≥ 95% correct parsing | 50 documents with various date formats |
| Processing time (single page) | < 3 seconds on iPhone 15+ | Measured on-device |
| Processing time (single page) | < 5 seconds on Mac (M1+) | Measured on-device |
| Signature detection | ≥ 90% detection rate | 20 signed delivery sheets |
| Image sync via Bluetooth | Complete transfer < 30s per page | 2MB JPEG over BT |

---

## Dependencies

| Dependency | Required For | Platform |
|-----------|-------------|----------|
| Vision framework | Text recognition | macOS/iOS |
| VisionKit | Document camera | iOS |
| `Windows.Media.Ocr` | Text recognition | Windows |
| GRDB | Storing extraction results | All |
| Existing parts catalog data | Part code matching | All |
| Existing supplier data | Supplier name matching | All |

---

## Risks

| Risk | Likelihood | Impact | Mitigation |
|------|-----------|--------|------------|
| Poor scan quality in field conditions | High | Medium | Provide real-time quality feedback before processing; auto-enhance contrast |
| Handwriting recognition failures | Medium | Medium | Always show original image; allow manual override |
| Vision framework accuracy variations across OS versions | Low | Medium | Pin minimum OS version; test on oldest supported version |
| Large image files slow Bluetooth sync | Medium | Medium | Compress images; chunk transfers; prioritize text data over images |
| False positive supplier/part matches | Medium | High | Require user confirmation for all matches; never auto-submit |
