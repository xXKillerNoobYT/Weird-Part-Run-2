# Camera-Based Part Matching Plan

> **Created:** 2026-03-15
> **Phase:** 12+ (AI Integration Extension)
> **Dependencies:** Phase 5 (Parts & Inventory), Phase 12 (AI — Apple), Core Package (Phase 1)
> **Constraint:** Fully offline. No cloud image recognition. Bluetooth-only sync of captured images + match results.

---

## Overview

Enable field workers to photograph an unknown part and receive the top 3–5 closest matches from the local parts catalog. Uses on-device image feature extraction and similarity search — no internet required. Captured images and match results sync via Bluetooth to other devices.

---

## Use Cases

| Scenario | User Action | Expected Result |
|----------|------------|-----------------|
| Unknown part in the field | Photo the part | Top 5 matches from catalog with confidence % |
| Part identification at receiving | Photo incoming part without label | Match to expected PO line items |
| Bin verification | Photo parts in a bin | Confirm they match the bin's assigned parts |
| Damage documentation | Photo damaged part | Match to catalog + flag as damage report |
| Quick reorder | Photo depleted part | Match → navigate to order form pre-filled |

---

## Technical Architecture

### Image Matching Pipeline

```
Camera Capture
    │
    ▼
┌──────────────────────────────┐
│  Image Pre-Processing        │
│  - Crop to center region     │
│  - Normalize lighting        │
│  - Resize to 224×224         │
│  - Remove background (opt.)  │
└──────────┬───────────────────┘
           │ Processed Image
           ▼
┌──────────────────────────────┐
│  Feature Extraction          │
│  VNFeaturePrintObservation   │  ← Apple Vision (primary)
│  (VNGenerateImageFeature-    │
│   PrintRequest)              │
│  — OR —                      │
│  MobileNetV3 via Core ML     │  ← Fallback / Windows
└──────────┬───────────────────┘
           │ Float[2048] feature vector
           ▼
┌──────────────────────────────┐
│  Similarity Search           │
│  - Cosine similarity against │
│    catalog feature index     │
│  - Top-K nearest neighbors   │
│  - Confidence = similarity   │
│    score normalized to %     │
└──────────┬───────────────────┘
           │ [PartMatch]
           ▼
┌──────────────────────────────┐
│  Results Display             │
│  - Top 3–5 matches           │
│  - Confidence %              │
│  - Part photo + name + code  │
│  - Quick actions (order, move)│
└──────────────────────────────┘
```

### Feature Index (Catalog Embeddings)

Each part in the catalog with a reference photo gets a pre-computed feature vector. These vectors are stored in a local index for fast similarity search.

```
Parts Catalog
    │
    ▼ (background task, runs when catalog updates)
┌──────────────────────────────┐
│  Catalog Indexer              │
│  For each part with image:   │
│  1. Load reference image     │
│  2. Extract feature vector   │
│  3. Store in feature_index   │
│     table (part_id, vector)  │
└──────────────────────────────┘
```

---

## Core Module: ImageMatcher

**Path:** `core/Sources/WiredPartCore/AI/ImageMatcher.swift`

```swift
actor ImageMatcher {
    private var featureIndex: [Int64: [Float]]  // part_id → feature vector

    /// Load or rebuild the feature index from the database
    func loadIndex() async throws

    /// Match a captured image against the catalog
    func findMatches(for image: CGImage,
                     topK: Int = 5,
                     minimumConfidence: Float = 0.3) async throws -> [ImageMatchResult]

    /// Add/update a part's reference image in the index
    func indexPartImage(partId: Int64, image: CGImage) async throws

    /// Remove a part from the index
    func removeFromIndex(partId: Int64) async throws

    /// Get index statistics
    func indexStats() -> ImageIndexStats
}

struct ImageMatchResult {
    let part: Part
    let confidence: Float           // 0.0–1.0
    let referenceImagePath: String? // path to catalog reference image
    let matchRank: Int              // 1-based rank
}

struct ImageIndexStats {
    let totalIndexedParts: Int
    let totalPartsWithImages: Int
    let indexSizeBytes: Int
    let lastIndexUpdate: Date?
}
```

### Feature Extraction Adapter

**Path:** `core/Sources/WiredPartCore/AI/ImageFeatureAdapter.swift`

```swift
protocol ImageFeatureAdapter {
    var isAvailable: Bool { get }

    /// Extract a feature vector from an image
    func extractFeatures(from image: CGImage) async throws -> [Float]

    /// Feature vector dimension (e.g., 2048 for VNFeaturePrint)
    var featureDimension: Int { get }
}
```

### Apple Implementation

**Path:** `mac/WiredPart/Adapters/AppleImageFeatureAdapter.swift` (shared macOS/iOS)

```swift
/// Uses Vision framework VNGenerateImageFeaturePrintRequest
/// Available on macOS 10.15+ / iOS 13+
class AppleImageFeatureAdapter: ImageFeatureAdapter {
    var isAvailable: Bool { true }
    var featureDimension: Int { 2048 }  // VNFeaturePrintObservation

    func extractFeatures(from image: CGImage) async throws -> [Float] {
        let request = VNGenerateImageFeaturePrintRequest()
        let handler = VNImageRequestHandler(cgImage: image)
        try handler.perform([request])
        guard let observation = request.results?.first as? VNFeaturePrintObservation else {
            throw ImageMatchError.featureExtractionFailed
        }
        // Extract float array from observation.data
        ...
    }
}
```

### Windows / Fallback Implementation

**Path:** `windows/Adapters/CoreMLImageFeatureAdapter.swift`

- Uses a bundled MobileNetV3-Small Core ML model exported as ONNX
- Feature extraction from the penultimate layer (1024-dim vector)
- ONNX Runtime for inference on Windows

---

## Similarity Search Algorithm

### Cosine Similarity (In-Memory)

For catalogs up to ~10,000 parts with images, brute-force cosine similarity is fast enough:

```swift
func cosineSimilarity(_ a: [Float], _ b: [Float]) -> Float {
    let dot = zip(a, b).reduce(0.0) { $0 + $1.0 * $1.1 }
    let normA = sqrt(a.reduce(0.0) { $0 + $1 * $1 })
    let normB = sqrt(b.reduce(0.0) { $0 + $1 * $1 })
    guard normA > 0, normB > 0 else { return 0 }
    return dot / (normA * normB)
}
```

**Performance target:** < 100ms for 10,000-part index on M1 Mac / A16 iPhone.

### Optimizations for Larger Catalogs

If catalog exceeds 10,000 indexed parts:
1. **Quantize vectors** to `Int8` (256× storage reduction, ~1% accuracy loss)
2. **Category pre-filter** — if user selects a category first, only search within it
3. **Accelerate.framework** — use `vDSP` for vectorized dot products on Apple
4. Future: **Approximate Nearest Neighbors** (HNSW) if needed

---

## Database Schema

### Feature Index Table

```sql
CREATE TABLE part_image_features (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    part_id INTEGER NOT NULL REFERENCES parts(id) ON DELETE CASCADE,
    feature_vector BLOB NOT NULL,       -- Float32 array, packed binary
    vector_dimension INTEGER NOT NULL,   -- 2048 for Vision, 1024 for MobileNet
    adapter_type TEXT NOT NULL,          -- 'vision_featureprint' or 'mobilenet_v3'
    image_hash TEXT NOT NULL,            -- SHA256 of source image (cache invalidation)
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    updated_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    UNIQUE(part_id, adapter_type)
);
CREATE INDEX idx_pif_part_id ON part_image_features(part_id);
```

### Match History Table (Local-Only, Diagnostic)

```sql
CREATE TABLE image_match_history (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    captured_image_path TEXT,            -- local path to captured photo
    top_match_part_id INTEGER,
    top_match_confidence REAL,
    total_matches_returned INTEGER,
    user_selected_part_id INTEGER,       -- which match the user actually chose
    processing_time_ms INTEGER,
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP
);
```

---

## UI Components

### CameraMatchView (Shared Component)

```swift
struct CameraMatchView: View {
    @State private var capturedImage: CGImage?
    @State private var matches: [ImageMatchResult] = []
    @State private var isProcessing = false
    let onPartSelected: (Part) -> Void

    var body: some View {
        VStack {
            // Camera preview / captured image
            // "Take Photo" button
            // Results list:
            //   - Part thumbnail + name + code
            //   - Confidence bar (green/yellow/red)
            //   - "Select" button
            //   - "Not a match? Try again" option
        }
    }
}
```

### Integration in Existing Views

| View | Trigger | Placement |
|------|---------|-----------|
| Catalog search | "Match by Photo" button next to search bar | Floating action or toolbar item |
| Receiving session | "Identify Part" button per line item | Inline button |
| Movement wizard | "Scan Part" camera option | Step 1 part selection |
| New JPO line item | "Photo Match" in part picker | Part picker toolbar |
| Part Detail | "Update Reference Photo" | Edit mode action |

---

## Catalog Image Management

### Reference Images

Each part can have reference images for matching:

| Source | Priority | Notes |
|--------|----------|-------|
| Manufacturer product photo | 1 (best) | Clean, white background, consistent |
| User-uploaded photo | 2 | May vary in quality |
| Auto-captured during receiving | 3 | Prompted: "Save as reference?" after first scan |

### Image Storage

- Reference images stored in app's documents directory
- Path: `{app_data}/part_images/{part_id}/ref_{index}.jpg`
- Compressed JPEG, max 1024×1024 pixels
- Multiple reference images per part improve matching accuracy
- When multiple references exist, feature vector is the average of all reference vectors

---

## Bluetooth Sync of Images & Match Results

| Data Type | Syncs? | Method |
|-----------|--------|--------|
| Part reference images | Yes | Binary blob sync, chunked (16KB frames) |
| Feature vectors | No | Recomputed locally from synced images |
| Match history | No | Local diagnostic only |
| User's "selected match" actions | Yes | Normal record sync (if it triggers a form action) |

### Image Sync Strategy

1. Reference images are stored as records in `part_attachments` table
2. Binary data synced via existing blob sync mechanism
3. On receiving a new reference image, the local device recomputes the feature vector
4. Feature index rebuilt incrementally (only new/changed parts)

---

## Offline-Only Constraint Compliance

| Requirement | How Met |
|-------------|---------|
| No internet for matching | Vision framework runs 100% on-device |
| No cloud model downloads | Feature extraction uses built-in Vision APIs (no model download) |
| No external API calls | All similarity search is local in-memory |
| Works in airplane mode | Fully functional — camera + local index only |
| Works underground (no signal) | Same — no network dependency at all |

---

## Acceptance Criteria

| Criterion | Target | Measurement |
|-----------|--------|-------------|
| Top-1 accuracy (correct part is #1) | ≥ 60% | 100-part test set with reference images |
| Top-3 accuracy (correct part in top 3) | ≥ 80% | Same test set |
| Top-5 accuracy (correct part in top 5) | ≥ 90% | Same test set |
| Processing time (capture → results) | < 2 seconds on iPhone 15+ | On-device measurement |
| Processing time (capture → results) | < 3 seconds on Mac M1+ | On-device measurement |
| Index build time (1,000 parts) | < 60 seconds | Background task measurement |
| Index memory footprint (1,000 parts) | < 10MB | 2048 floats × 4 bytes × 1000 ≈ 8MB |
| False positive rate | < 10% at confidence ≥ 0.7 threshold | 50 "unknown" parts not in catalog |
| Graceful handling (no reference images) | Shows "No catalog images available" | Edge case test |

---

## Risks

| Risk | Likelihood | Impact | Mitigation |
|------|-----------|--------|------------|
| Parts look too similar (e.g., same fitting in 3 sizes) | High | Medium | Show all similar parts; user differentiates by size/description; add size estimation in future |
| Poor lighting in field/warehouse | High | Medium | Auto-flash; image enhancement before feature extraction; suggest better conditions |
| No reference images for most parts | High at launch | High | Prompt users to save reference photos during receiving; batch import from manufacturer catalogs |
| Vision framework feature print changes across OS versions | Low | High | Pin adapter type in feature index; rebuild index on OS upgrade |
| Large catalog (10K+ parts) slows search | Low | Medium | Quantized vectors + Accelerate.framework + category pre-filter |
| MobileNet accuracy lower than Vision | Medium | Low | Only used on Windows; document accuracy differences |
