# File Staging List

> Every file to create, modify, or delete during the migration, with patch sketches and acceptance criteria.
> Organized by phase. Uses the File Staging Template from the planning prompt.

---

## Phase 1: Swift Core Package

### 1.1 Package.swift

```
Path: core/Package.swift
Action: create
Summary: Swift package manifest for WiredPartCore library.
Patch sketch:
    // swift-tools-version: 6.0
    import PackageDescription
    let package = Package(
        name: "WiredPartCore",
        platforms: [.macOS(.v14), .iOS(.v17)],
        products: [.library(name: "WiredPartCore", targets: ["WiredPartCore"])],
        dependencies: [
            .package(url: "https://github.com/groue/GRDB.swift", from: "7.0.0"),
            .package(url: "https://github.com/apple/swift-nio", from: "2.70.0"),
        ],
        targets: [
            .target(name: "WiredPartCore", dependencies: [
                .product(name: "GRDB", package: "GRDB.swift"),
                .product(name: "NIOCore", package: "swift-nio"),
                .product(name: "NIOHTTP1", package: "swift-nio"),
            ]),
            .testTarget(name: "WiredPartCoreTests", dependencies: ["WiredPartCore"]),
        ]
    )
Tests: N/A (build verification only)
Acceptance: `swift build` succeeds with zero errors.
```

### 1.2 AppDatabase.swift

```
Path: core/Sources/WiredPartCore/Database/AppDatabase.swift
Action: create
Summary: GRDB database connection singleton with migration runner.
Patch sketch:
    import GRDB

    final class AppDatabase: Sendable {
        let writer: DatabaseWriter

        init(_ writer: DatabaseWriter) throws {
            self.writer = writer
            var migrator = DatabaseMigrator()
            Self.registerMigrations(&migrator)
            try migrator.migrate(writer)
        }

        static func openDatabase(atPath path: String) throws -> AppDatabase {
            let writer = try DatabasePool(path: path)
            return try AppDatabase(writer)
        }

        static func openInMemoryDatabase() throws -> AppDatabase {
            let writer = try DatabaseQueue()
            return try AppDatabase(writer)
        }
    }
Tests: core/Tests/WiredPartCoreTests/DatabaseTests.swift
Acceptance: In-memory DB opens, all migrations run, tables exist.
```

### 1.3 AppDatabase+Migrations.swift

```
Path: core/Sources/WiredPartCore/Database/AppDatabase+Migrations.swift
Action: create
Summary: All 17 SQLite migrations ported from TypeScript to GRDB DatabaseMigrator.
Patch sketch:
    extension AppDatabase {
        static func registerMigrations(_ migrator: inout DatabaseMigrator) {
            migrator.registerMigration("001_foundation") { db in
                try db.create(table: "users") { t in
                    t.autoIncrementedPrimaryKey("id")
                    t.column("display_name", .text).notNull()
                    t.column("email", .text)
                    t.column("pin_hash", .text).notNull()
                    t.column("is_active", .boolean).notNull().defaults(to: true)
                    t.column("created_at", .datetime).notNull().defaults(sql: "CURRENT_TIMESTAMP")
                    t.column("updated_at", .datetime).notNull().defaults(sql: "CURRENT_TIMESTAMP")
                }
                // ... hats, hat_permissions, user_hats, devices, settings, notifications
            }
            // ... migrations 002 through 017
        }
    }
Tests: core/Tests/WiredPartCoreTests/DatabaseTests.swift — verify table/column existence
Acceptance: Schema matches TypeScript migration output exactly (automated comparison).
```

### 1.4 BaseRepository.swift

```
Path: core/Sources/WiredPartCore/Database/BaseRepository.swift
Action: create
Summary: Generic CRUD repository with automatic change tracking.
Patch sketch:
    protocol BaseRepository {
        associatedtype Model: FetchableRecord & MutablePersistableRecord & Identifiable
            where Model.ID == Int64?
        var db: AppDatabase { get }
    }

    extension BaseRepository {
        func insert(_ record: inout Model, deviceId: String) throws -> Model {
            try db.writer.write { database in
                try record.insert(database)
                try ChangeTracker.track(db: database, deviceId: deviceId,
                    table: Model.databaseTableName, recordId: record.id!,
                    operation: .insert, recordData: record)
            }
            return record
        }
        // update, delete, getById, findAll ...
    }
Tests: core/Tests/WiredPartCoreTests/BaseRepositoryTests.swift
Acceptance: Every write produces a _change_log entry.
```

### 1.5 ChangeTracker.swift

```
Path: core/Sources/WiredPartCore/Sync/ChangeTracker.swift
Action: create
Summary: Tracks all DB writes to _change_log for sync.
Patch sketch:
    struct ChangeTracker {
        static func track(db: Database, deviceId: String, table: String,
                          recordId: Int64, operation: ChangeOperation,
                          changedFields: String? = nil, oldValues: String? = nil,
                          recordData: (any Encodable)? = nil) throws {
            var entry = ChangeLogEntry(deviceId: deviceId, tableName: table,
                recordId: String(recordId), operation: operation.rawValue,
                changedFields: changedFields, oldValues: oldValues,
                recordData: recordData.flatMap { try? JSONEncoder().encode($0) }.map { String(data: $0, encoding: .utf8) } ?? nil,
                timestamp: ISO8601DateFormatter().string(from: Date()))
            try entry.insert(db)
        }
    }
Tests: core/Tests/WiredPartCoreTests/ChangeTrackerTests.swift
Acceptance: INSERT/UPDATE/DELETE all produce correct log entries.
```

### 1.6 Model files (representative sample)

```
Path: core/Sources/WiredPartCore/Models/Foundation/User.swift
Action: create
Summary: User model matching the `users` table schema.
Patch sketch:
    struct User: Codable, FetchableRecord, MutablePersistableRecord, Identifiable {
        static let databaseTableName = "users"
        var id: Int64?
        var displayName: String
        var email: String?
        var pinHash: String
        var isActive: Bool
        var createdAt: Date
        var updatedAt: Date

        enum CodingKeys: String, CodingKey {
            case id, displayName = "display_name", email
            case pinHash = "pin_hash", isActive = "is_active"
            case createdAt = "created_at", updatedAt = "updated_at"
        }

        mutating func didInsert(_ inserted: InsertionSuccess) {
            id = inserted.rowID
        }
    }
Tests: core/Tests/WiredPartCoreTests/ModelTests.swift
Acceptance: Insert + fetch round-trip preserves all fields.
```

Additional model files (same template):
- `core/Sources/WiredPartCore/Models/Foundation/Hat.swift`
- `core/Sources/WiredPartCore/Models/Foundation/HatPermission.swift`
- `core/Sources/WiredPartCore/Models/Foundation/Setting.swift`
- `core/Sources/WiredPartCore/Models/Foundation/Device.swift`
- `core/Sources/WiredPartCore/Models/Parts/Part.swift`
- `core/Sources/WiredPartCore/Models/Parts/PartCategory.swift`
- `core/Sources/WiredPartCore/Models/Parts/Supplier.swift`
- `core/Sources/WiredPartCore/Models/Jobs/Job.swift`
- `core/Sources/WiredPartCore/Models/Jobs/LaborEntry.swift`
- `core/Sources/WiredPartCore/Models/Orders/PurchaseOrder.swift`
- `core/Sources/WiredPartCore/Models/Orders/JobPartsOrder.swift`
- `core/Sources/WiredPartCore/Models/Sync/ChangeLogEntry.swift`
- `core/Sources/WiredPartCore/Models/Sync/VectorClock.swift`
- ... (one per DB table, ~50+ files total)

### 1.7 AuthService.swift

```
Path: core/Sources/WiredPartCore/Services/AuthService.swift
Action: create
Summary: Authentication service ported from auth-service.ts.
Patch sketch:
    import CryptoKit

    final class AuthService {
        private let db: AppDatabase

        func authenticateByPin(userId: Int64, pin: String) async throws -> AuthResult {
            let user = try db.writer.read { db in try User.fetchOne(db, id: userId) }
            guard let user, user.isActive else { throw AuthError.userNotFound }
            let inputHash = sha256Hash(pin)
            guard inputHash == user.pinHash else { throw AuthError.invalidPin }
            return AuthResult(user: user, permissions: try getUserPermissions(userId: userId))
        }

        func seedFirstAdmin(displayName: String, pin: String) async throws -> AuthResult { ... }
        func getUserPermissions(userId: Int64) async throws -> [String] { ... }

        private func sha256Hash(_ input: String) -> String {
            let data = Data(input.utf8)
            let hash = SHA256.hash(data: data)
            return hash.map { String(format: "%02x", $0) }.joined()
        }
    }
Tests: core/Tests/WiredPartCoreTests/AuthServiceTests.swift
Acceptance: Seed admin → authenticate → verify permissions chain works.
```

### 1.8 SettingsService.swift

```
Path: core/Sources/WiredPartCore/Services/SettingsService.swift
Action: create
Summary: Settings CRUD service.
Patch sketch:
    final class SettingsService {
        private let db: AppDatabase
        func getSetting(key: String) async throws -> String? { ... }
        func updateSetting(key: String, value: String, category: String) async throws { ... }
        func getTheme() async throws -> ThemeSettings { ... }
        func getCompanyProfile() async throws -> CompanyProfile? { ... }
    }
Tests: core/Tests/WiredPartCoreTests/SettingsServiceTests.swift
Acceptance: Get/set round-trip for all setting categories.
```

---

## Phase 2: Sync Engine (key files only)

### 2.1 ConflictResolver.swift
```
Path: core/Sources/WiredPartCore/Sync/ConflictResolver.swift
Action: create
Summary: Field-level merge with LWW conflict resolution. Direct port of conflict-resolver.ts.
Patch sketch:
    struct ConflictResolver {
        func resolveAndApply(_ incomingChanges: [ChangeLogEntry],
                             localDB: DatabaseWriter,
                             localDeviceId: String) throws -> MergeResult {
            // For each incoming change:
            // 1. Check if local has a newer change for same record+field
            // 2. If no conflict: apply incoming
            // 3. If conflict: compare timestamps, later wins (LWW)
            // 4. Log to _conflict_log
            // 5. Return MergeResult with applied/rejected counts
        }
    }
Tests: core/Tests/WiredPartCoreTests/ConflictResolverTests.swift
Acceptance: LWW winner matches TypeScript resolver for identical inputs.
```

### 2.2 LanSyncServer.swift
```
Path: core/Sources/WiredPartCore/Sync/LanSyncServer.swift
Action: create
Summary: HTTP sync server using swift-nio. Replaces src-tauri/src/sync_server.rs.
Patch sketch:
    import NIOCore
    import NIOHTTP1

    actor LanSyncServer {
        private(set) var port: Int = 0

        func start() async throws {
            // Bind to 0.0.0.0:0 (ephemeral)
            // Routes: POST /sync/push, POST /sync/pull, GET /sync/status
            // Same JSON format as Rust axum server
        }
        func stop() async { ... }
    }
Tests: core/Tests/WiredPartCoreTests/LanSyncServerTests.swift
Acceptance: Push/pull round-trip on loopback; JSON backward-compatible with TypeScript.
```

### 2.3 PeerDiscovery.swift
```
Path: core/Sources/WiredPartCore/Sync/PeerDiscovery.swift
Action: create
Summary: mDNS peer discovery via Network.framework. Replaces discovery.rs.
Patch sketch:
    import Network

    @Observable
    final class PeerDiscovery {
        private(set) var discoveredPeers: [DiscoveredPeer] = []
        func startAdvertising(port: UInt16, config: SyncTransportConfig) { ... }
        func startBrowsing(myConfig: SyncTransportConfig) { ... }
        func stop() { ... }
    }
Tests: core/Tests/WiredPartCoreTests/PeerDiscoveryTests.swift
Acceptance: Two instances discover each other on loopback.
```

### 2.4 MultipeerManager.swift
```
Path: core/Sources/WiredPartCore/Sync/MultipeerManager.swift
Action: create
Summary: Native Swift Multipeer Connectivity. Replaces MultipeerBridge.m + multipeer.rs.
Patch sketch:
    #if canImport(MultipeerConnectivity)
    import MultipeerConnectivity

    @Observable
    final class MultipeerManager: NSObject, MCSessionDelegate,
        MCNearbyServiceBrowserDelegate, MCNearbyServiceAdvertiserDelegate {
        private(set) var connectedPeers: [PeerInfo] = []
        func start(config: SyncTransportConfig) { ... }
        func stop() { ... }
        func send(to peerId: String, data: Data) throws { ... }
        func popReceived() -> ReceivedMessage? { ... }
    }
    #endif
Tests: Integration test with two simulators.
Acceptance: Peer discovery + data round-trip between two instances.
```

### 2.5 SyncCrypto.swift
```
Path: core/Sources/WiredPartCore/Crypto/SyncCrypto.swift
Action: create
Summary: Ed25519 signing/verification via CryptoKit. Replaces crypto.rs.
Patch sketch:
    import CryptoKit

    struct SyncCrypto {
        static func verifyCertificate(certDataB64: String, signatureB64: String,
                                       companyPublicKeyB64: String) throws -> CertificatePayload {
            let pubKeyData = Data(base64Encoded: companyPublicKeyB64)!
            let publicKey = try Curve25519.Signing.PublicKey(rawRepresentation: pubKeyData)
            let certData = Data(base64Encoded: certDataB64)!
            let signature = Data(base64Encoded: signatureB64)!
            guard publicKey.isValidSignature(signature, for: certData) else {
                throw SyncCryptoError.invalidSignature
            }
            return try JSONDecoder().decode(CertificatePayload.self, from: certData)
        }
    }
Tests: core/Tests/WiredPartCoreTests/CryptoTests.swift
Acceptance: Verify valid cert, reject invalid sig, reject expired cert.
```

---

## Phase 3: macOS App Shell (key files)

### 3.1 WiredPartMacApp.swift
```
Path: mac/WiredPartMac/App/WiredPartMacApp.swift
Action: create
Summary: SwiftUI macOS app entry point.
Patch sketch:
    @main
    struct WiredPartMacApp: App {
        @State private var appCore = AppCore()
        var body: some Scene {
            WindowGroup {
                ContentView()
                    .environment(appCore)
                    .task { await appCore.initialize() }
            }
        }
    }
Tests: mac/WiredPartMacTests/ — app launches without crash.
Acceptance: Window opens, sidebar visible, auth flow completes.
```

### 3.2 SidebarView.swift
```
Path: mac/WiredPartMac/Navigation/SidebarView.swift
Action: create
Summary: macOS sidebar navigation with 14 module entries.
Patch sketch:
    struct SidebarView: View {
        @Binding var selection: AppDestination?
        var body: some View {
            List(selection: $selection) {
                Section("Main") {
                    Label("Dashboard", systemImage: "gauge")
                        .tag(AppDestination.dashboard)
                    Label("Parts", systemImage: "shippingbox")
                        .tag(AppDestination.partsCatalog)
                    // ... 12 more modules
                }
                Section("System") {
                    Label("Settings", systemImage: "gear")
                        .tag(AppDestination.settings(.general))
                }
            }
        }
    }
Tests: mac/WiredPartMacTests/ — all 14 modules appear in sidebar.
Acceptance: Every module clickable, routes to correct content.
```

### 3.3 WebFallbackView.swift
```
Path: mac/WiredPartMac/WebFallback/WebFallbackView.swift
Action: create
Summary: WKWebView that loads React dist for unported pages.
Patch sketch:
    import WebKit

    struct WebFallbackView: NSViewRepresentable {
        let route: String
        func makeNSView(context: Context) -> WKWebView {
            let webView = WKWebView()
            let distURL = Bundle.main.url(forResource: "index", withExtension: "html", subdirectory: "dist")!
            webView.loadFileURL(distURL, allowingReadAccessTo: distURL.deletingLastPathComponent())
            return webView
        }
        func updateNSView(_ webView: WKWebView, context: Context) {
            webView.evaluateJavaScript("window.location.hash = '\(route)'")
        }
    }
Tests: mac/WiredPartMacTests/ — WebFallback loads and renders React page.
Acceptance: React dist renders in WebView, auth token bridged.
```

---

## Phases 4–15: Service + View files follow the same template.

Each feature module creates:
1. `core/Sources/WiredPartCore/Services/<Module>Service.swift` — ported from `src/local/services/<module>-service.ts`
2. `mac/WiredPartMac/Features/<Module>/<Page>View.swift` — one per React page
3. `core/Tests/WiredPartCoreTests/<Module>ServiceTests.swift` — unit tests
4. `mac/WiredPartMacTests/<Module>Tests.swift` — UI tests

Total new files across all phases: ~250–300 Swift files.

---

## Phase 12+: AI-Assisted Capabilities (OCR, QR, Image Match, Text Predict, Binary Sync)

> New files for intelligent text, document scanning, QR recognition, camera part matching, and expanded sync.
> See individual plan docs: `ocr_plan.md`, `qr_plan.md`, `image_match_plan.md`, `text_predict_plan.md`, `bluetooth_sync_expanded.md`

### 12+.1 OCRProcessor.swift
```
Path: core/Sources/WiredPartCore/AI/OCRProcessor.swift
Action: create
Summary: Platform-agnostic OCR result processing — field extraction, pattern matching, confidence scoring.
Patch sketch:
    struct OCRProcessor {
        let partsLookup: PartsLookupProvider
        let suppliersLookup: SuppliersLookupProvider
        func extractFields(from: [RecognizedTextBlock], documentType: DocumentType) -> OCRExtractionResult
        func matchSupplier(name: String) -> SupplierMatch?
        func matchPartCode(code: String) -> PartMatch?
        func parseDate(text: String) -> DateParseResult?
        func parseQuantity(text: String) -> Int?
        func parsePONumber(text: String) -> String?
    }
Tests: core/Tests/WiredPartCoreTests/OCRProcessorTests.swift
Acceptance: Field extraction from 50-doc corpus with ≥ 95% char accuracy (printed), ≥ 85% (handwritten numbers).
```

### 12+.2 OCRScannerAdapter.swift
```
Path: core/Sources/WiredPartCore/AI/OCRScannerAdapter.swift
Action: create
Summary: Protocol for platform-specific OCR scanner implementations.
Patch sketch:
    protocol OCRScannerAdapter {
        var isAvailable: Bool { get }
        func scanDocument() async throws -> ScannedDocument
        func recognizeText(in image: CGImage) async throws -> [RecognizedTextBlock]
    }
Tests: Platform adapter tests in mac/ios test targets.
Acceptance: Protocol compiles; adapters conform.
```

### 12+.3 AppleOCRScanner.swift (macOS)
```
Path: mac/WiredPart/Adapters/AppleOCRScanner.swift
Action: create
Summary: macOS OCR scanner using Vision framework VNRecognizeTextRequest.
Tests: mac/WiredPartTests/AppleOCRScannerTests.swift
Acceptance: Text extraction from test image matches expected output.
```

### 12+.4 AppleOCRScanner.swift (iOS)
```
Path: ios-app/WiredPartIOS/Adapters/AppleOCRScanner.swift
Action: create
Summary: iOS OCR scanner using Vision + VisionKit document camera.
Tests: ios-app/WiredPartIOSTests/AppleOCRScannerTests.swift
Acceptance: Document camera launches, text extracted from test image.
```

### 12+.5 QRCodec.swift
```
Path: core/Sources/WiredPartCore/QR/QRCodec.swift
Action: create
Summary: Encode/decode WiredPart QR payloads (V2 schema with entity types).
Patch sketch:
    struct QRCodec {
        static func encode(_ entity: QREntity) throws -> String
        static func decode(_ payload: String) throws -> QREntity
        func resolve(_ entity: QREntity) async throws -> QRResolvedEntity
    }
Tests: core/Tests/WiredPartCoreTests/QRCodecTests.swift
Acceptance: Round-trip encode/decode for all 8 entity types; V1 backward compat.
```

### 12+.6 QRGenerator.swift
```
Path: core/Sources/WiredPartCore/QR/QRGenerator.swift
Action: create
Summary: QR code image generation using CIFilter.
Patch sketch:
    struct QRGenerator {
        static func generate(_ entity: QREntity, size: CGSize) throws -> CGImage
        static func generateLabel(_ entity: QREntity, includeText: Bool, size: CGSize) throws -> CGImage
    }
Tests: core/Tests/WiredPartCoreTests/QRGeneratorTests.swift
Acceptance: Generated QR code is scannable and decodes to original entity.
```

### 12+.7 QRScannerAdapter.swift
```
Path: core/Sources/WiredPartCore/QR/QRScannerAdapter.swift
Action: create
Summary: Protocol for platform-specific QR/barcode scanning.
Patch sketch:
    protocol QRScannerAdapter {
        var isAvailable: Bool { get }
        func startScanning() async throws -> AsyncStream<QRScanEvent>
        func stopScanning()
    }
Tests: Platform adapter tests.
Acceptance: Protocol compiles; adapters conform.
```

### 12+.8 IOSQRScanner.swift
```
Path: ios-app/WiredPartIOS/Adapters/IOSQRScanner.swift
Action: create
Summary: iOS QR scanner using DataScannerViewController.
Tests: ios-app/WiredPartIOSTests/IOSQRScannerTests.swift
Acceptance: QR codes detected in camera feed, haptic on success.
```

### 12+.9 MacQRScanner.swift
```
Path: mac/WiredPart/Adapters/MacQRScanner.swift
Action: create
Summary: macOS QR scanner using AVCaptureSession + VNDetectBarcodesRequest.
Tests: mac/WiredPartTests/MacQRScannerTests.swift
Acceptance: QR codes detected from webcam; file-based QR reading works.
```

### 12+.10 ImageMatcher.swift
```
Path: core/Sources/WiredPartCore/AI/ImageMatcher.swift
Action: create
Summary: Camera-based part matching — feature index, cosine similarity, top-K search.
Patch sketch:
    actor ImageMatcher {
        func loadIndex() async throws
        func findMatches(for: CGImage, topK: Int, minimumConfidence: Float) async throws -> [ImageMatchResult]
        func indexPartImage(partId: Int64, image: CGImage) async throws
        func removeFromIndex(partId: Int64) async throws
        func indexStats() -> ImageIndexStats
    }
Tests: core/Tests/WiredPartCoreTests/ImageMatcherTests.swift
Acceptance: Top-3 accuracy ≥ 80% on 100-part test set; index build < 60s for 1000 parts.
```

### 12+.11 ImageFeatureAdapter.swift
```
Path: core/Sources/WiredPartCore/AI/ImageFeatureAdapter.swift
Action: create
Summary: Protocol for platform-specific image feature extraction.
Patch sketch:
    protocol ImageFeatureAdapter {
        var isAvailable: Bool { get }
        func extractFeatures(from: CGImage) async throws -> [Float]
        var featureDimension: Int { get }
    }
Tests: Platform adapter tests.
Acceptance: Feature vector extracted, correct dimension.
```

### 12+.12 AppleImageFeatureAdapter.swift
```
Path: mac/WiredPart/Adapters/AppleImageFeatureAdapter.swift
Action: create (shared macOS/iOS via SPM or duplicate)
Summary: Vision framework VNGenerateImageFeaturePrintRequest for feature extraction.
Tests: mac/WiredPartTests/AppleImageFeatureAdapterTests.swift
Acceptance: 2048-dim feature vector extracted from test image.
```

### 12+.13 TextPredictor.swift
```
Path: core/Sources/WiredPartCore/AI/TextPredictor.swift
Action: create
Summary: Context-aware text prediction — entity lookup, phrase history, template expansion, LLM generation.
Patch sketch:
    actor TextPredictor {
        func predict(context: PredictionContext) async -> [TextSuggestion]
        func recordEntry(fieldType: String, text: String, entityContext: [String: String]?) async
        func generatePreFill(formType: FormType, context: PreFillContext) async -> [PreFilledField]
        func clearHistory(fieldType: String?) async
    }
Tests: core/Tests/WiredPartCoreTests/TextPredictorTests.swift
Acceptance: Entity lookup < 10ms; phrase completion < 20ms; no cross-user text history leak.
```

### 12+.14 BinarySyncManager.swift
```
Path: core/Sources/WiredPartCore/Sync/BinarySyncManager.swift
Action: create
Summary: Chunked binary transfer for images — priority queue, resume, dedup.
Patch sketch:
    actor BinarySyncManager {
        func enqueue(_ attachment: BinaryAttachment, priority: Priority)
        func processQueue(transport: SyncTransport) async
        func handleManifest(_ manifest: BinaryManifest, fromPeer: PeerInfo) async -> BinaryRequest
        func resumeTransfer(_ transferId: UUID) async throws
    }
Tests: core/Tests/WiredPartCoreTests/BinarySyncTests.swift
Acceptance: 1MB transfer over BT < 90s; resume within 10s; records unblocked during image sync.
```

### 12+.15 SyncPriorityQueue.swift
```
Path: core/Sources/WiredPartCore/Sync/SyncPriorityQueue.swift
Action: create
Summary: Priority-ordered sync task queue.
Patch sketch:
    actor SyncPriorityQueue {
        func enqueue(_ task: SyncTask, priority: Priority)
        func dequeueNext() -> SyncTask?
        func pendingBinaryTransferCount() -> Int
        func cancel(forRecordId: String, table: String)
    }
Tests: core/Tests/WiredPartCoreTests/SyncPriorityQueueTests.swift
Acceptance: Tasks dequeued in priority order; cancel removes correct tasks.
```

### 12+.16 CameraMatchView.swift (macOS)
```
Path: mac/WiredPart/Features/Parts/CameraMatchView.swift
Action: create
Summary: SwiftUI view for camera capture + part match results display.
Tests: mac/WiredPartTests/CameraMatchViewTests.swift
Acceptance: Camera opens, photo taken, results shown with confidence bars.
```

### 12+.17 CameraMatchView.swift (iOS)
```
Path: ios-app/WiredPartIOS/Features/Parts/CameraMatchView.swift
Action: create
Summary: iOS version of camera match view.
Tests: ios-app/WiredPartIOSTests/CameraMatchViewTests.swift
Acceptance: Same as macOS.
```

### 12+.18 DocumentScanView.swift (macOS)
```
Path: mac/WiredPart/Features/Shared/DocumentScanView.swift
Action: create
Summary: Document scan UI — file picker / camera, OCR progress, extracted fields review.
Tests: mac/WiredPartTests/DocumentScanViewTests.swift
Acceptance: Document loaded, OCR runs, fields displayed with confidence indicators.
```

### 12+.19 DocumentScanView.swift (iOS)
```
Path: ios-app/WiredPartIOS/Features/Shared/DocumentScanView.swift
Action: create
Summary: iOS document scan UI using VNDocumentCameraViewController.
Tests: ios-app/WiredPartIOSTests/DocumentScanViewTests.swift
Acceptance: Document camera launches, pages captured, OCR fields shown.
```

### 12+.20 AutoFillBanner.swift
```
Path: mac/WiredPart/Features/Shared/AutoFillBanner.swift (shared component)
Action: create
Summary: Banner shown when smart autofill pre-populates form fields.
Tests: UI test for banner visibility.
Acceptance: Banner appears with field count, Accept All / Clear buttons work.
```

### Test Files (Phase 12+)
```
core/Tests/WiredPartCoreTests/OCRProcessorTests.swift
core/Tests/WiredPartCoreTests/QRCodecTests.swift
core/Tests/WiredPartCoreTests/QRGeneratorTests.swift
core/Tests/WiredPartCoreTests/ImageMatcherTests.swift
core/Tests/WiredPartCoreTests/TextPredictorTests.swift
core/Tests/WiredPartCoreTests/BinarySyncTests.swift
core/Tests/WiredPartCoreTests/SyncPriorityQueueTests.swift
```

Total new files for Phase 12+: ~30 Swift files (core + platform adapters + views + tests).

---

## Files to Modify (existing)

| File | Phase | Change |
|------|-------|--------|
| `CLAUDE.md` | 15 | Update architecture section for native Swift |
| `MEMORY.md` | 15 | Update architecture summary, add migration history |
| `.gitignore` | 1 | Add `core/.build/`, `mac/build/`, `ios/build/` |

## Files to Delete (Phase 15)

All files listed in `repo_map.md` "Files to Remove" section.
