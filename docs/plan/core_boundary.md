# Core Boundary — WiredPartCore Swift Package

> Lists every module, class, and key function that belongs in the shared `WiredPartCore` package.
> This package has **no UI dependencies** — only Foundation, GRDB.swift, CryptoKit, Network.

---

## Package Dependencies

| Dependency | Version | Purpose |
|-----------|---------|---------|
| `groue/GRDB.swift` | 7.x | Type-safe SQLite ORM, migrations, observation |
| `apple/swift-nio` | 2.x | HTTP server for LAN sync (Phase 2) |
| `apple/swift-nio-http2` | — | Not needed (HTTP/1.1 only) |
| CryptoKit | built-in | Ed25519 signing/verification |
| Network | built-in | NWBrowser, NWListener for mDNS |
| MultipeerConnectivity | built-in | BT/Wi-Fi P2P sync (Apple only) |
| Foundation | built-in | Base types, JSON, dates |

---

## Module: Database

**Path:** `Sources/WiredPartCore/Database/`

### AppDatabase.swift
- `class AppDatabase` — Singleton GRDB database connection manager
  - `static func openDatabase(atPath: String) throws -> DatabaseWriter`
  - `static func openInMemoryDatabase() throws -> DatabaseWriter` (testing)
  - `func runMigrations() throws`
  - `var reader: DatabaseReader { get }`
  - `var writer: DatabaseWriter { get }`

### AppDatabase+Migrations.swift
- `extension AppDatabase`
  - `static func registerMigrations(_ migrator: inout DatabaseMigrator)`
  - 17 registered migrations matching `src/local/migrations/001–017`
  - Each migration creates tables, indexes, triggers matching TypeScript SQL exactly

### BaseRepository.swift
- `protocol BaseRepository`
  - `associatedtype Model: FetchableRecord & PersistableRecord & Identifiable`
  - `func insert(_ record: inout Model) throws -> Model`
  - `func update(_ record: Model) throws`
  - `func delete(id: Int64) throws`
  - `func getById(_ id: Int64) throws -> Model?`
  - `func findAll(filter: SQLSpecificExpressible?, orderBy: SQLOrderingTerm?, limit: Int?) throws -> [Model]`
  - `func count(filter: SQLSpecificExpressible?) throws -> Int`
- `class ConcreteRepository<M>: BaseRepository` — Generic implementation
  - All writes automatically call `ChangeTracker.track()` — non-bypassable

### DatabaseConfig.swift
- `struct DatabaseConfig`
  - `enum StorageMode { case privateApp, publicShared }`
  - `static func resolveDBPath(mode: StorageMode) -> String`
  - macOS public: `/Users/Shared/WiredPart/wiredpart.db`
  - macOS private: `~/Library/Application Support/com.wiredpart.app/wiredpart.db`
  - iOS: always private (sandbox)

---

## Module: Models

**Path:** `Sources/WiredPartCore/Models/`

### Foundation/
| Struct | Table | Key Fields |
|--------|-------|------------|
| `User` | `users` | id, displayName, email, pinHash, isActive, createdAt |
| `Hat` | `hats` | id, name, level, description, isActive |
| `HatPermission` | `hat_permissions` | id, hatId, permissionKey |
| `UserHat` | `user_hats` | id, userId, hatId, isPrimary |
| `Device` | `devices` | id, deviceId, deviceName, platform, lastSeen |
| `Setting` | `settings` | id, key, value, category |
| `Notification` | `notifications` | id, userId, type, title, message, isRead, createdAt |
| `CompanyProfile` | `company_profiles` | id, companyName, address, phone, email |

### Parts/
| Struct | Table |
|--------|-------|
| `PartCategory` | `part_categories` |
| `PartType` | `part_types` |
| `PartStyle` | `part_styles` |
| `PartColor` | `part_colors` |
| `Brand` | `brands` |
| `Supplier` | `suppliers` |
| `SupplierContact` | `supplier_contacts` |
| `Part` | `parts` |
| `Stock` | `stock` |
| `StockMovement` | `stock_movements` |
| `CompanionRule` | `companion_rules` |
| `AlternativePart` | `alternative_parts` |
| `CategorySupplierPreference` | `category_supplier_preferences` |

### Jobs/
| Struct | Table |
|--------|-------|
| `Job` | `jobs` |
| `JobPart` | `job_parts` |
| `LaborEntry` | `labor_entries` |
| `DailyReport` | `daily_reports` |
| `JobQuestionnaire` | `job_questionnaires` |

### Orders/
| Struct | Table |
|--------|-------|
| `JobPartsOrder` | `job_parts_orders` |
| `JPOLineItem` | `jpo_line_items` |
| `PurchaseOrder` | `purchase_orders` |
| `POLineItem` | `po_line_items` |
| `Return` | `returns` |
| `ReturnItem` | `return_items` |
| `SpecialItem` | `special_items` |

### Fleet/
| Struct | Table |
|--------|-------|
| `Vehicle` | `vehicles` |
| `VehicleAssignment` | `vehicle_assignments` |
| `FuelEntry` | `fuel_entries` |
| `Inspection` | `inspections` |
| `MileageTrip` | `mileage_trips` |
| `Delivery` | `deliveries` |
| `Trailer` | `trailers` |

### People/
| Struct | Table |
|--------|-------|
| `Certification` | `certifications` |
| `EmployeeCertification` | `employee_certifications` |
| `Wage` | `wages` |
| `Skill` | `skills` |
| `EmployeeSkill` | `employee_skills` |
| `EmployeeNote` | `employee_notes` |
| `Team` | `teams` |
| `TeamMember` | `team_members` |

### Scheduling/
| Struct | Table |
|--------|-------|
| `JobDispatch` | `job_dispatches` |
| `ScheduleTemplate` | `schedule_templates` |
| `ScheduleConfig` | `schedule_configs` |
| `TimeOffRequest` | `time_off_requests` |
| `WeeklyAvailability` | `weekly_availability` |

### Chat/
| Struct | Table |
|--------|-------|
| `ChatChannel` | `chat_channels` |
| `ChatMessage` | `chat_messages` |
| `QAThread` | `qa_threads` |
| `QAMessage` | `qa_messages` |

### Sync/
| Struct | Table |
|--------|-------|
| `ChangeLogEntry` | `_change_log` |
| `ConflictLogEntry` | `_conflict_log` |
| `VectorClock` | `_vector_clock` |
| `DeviceRegistry` | `_device_registry` |
| `SyncBatch` | `_sync_batches` |

---

## Module: Services

**Path:** `Sources/WiredPartCore/Services/`

### AuthService.swift
- `func authenticateByPin(userId: Int64, pin: String) async throws -> AuthResult`
- `func getActiveUsers() async throws -> [User]`
- `func seedFirstAdmin(displayName: String, pin: String) async throws -> AuthResult`
- `func getUserPermissions(userId: Int64) async throws -> [String]`
- `func hasPermission(userId: Int64, permissionKey: String) async throws -> Bool`
- `func getUserHats(userId: Int64) async throws -> [Hat]`
- `func updateProfile(userId: Int64, displayName: String, email: String?) async throws`
- `func changePin(userId: Int64, oldPin: String, newPin: String) async throws`

### SettingsService.swift
- `func getSetting(key: String) async throws -> String?`
- `func updateSetting(key: String, value: String, category: String) async throws`
- `func getTheme() async throws -> ThemeSettings`
- `func updateTheme(_ theme: ThemeSettings) async throws`
- `func getCompanyProfile() async throws -> CompanyProfile?`
- `func updateCompanyProfile(_ profile: CompanyProfile) async throws`

### DashboardService.swift
- `func getDashboardSummary() async throws -> DashboardSummary`
- `func getRecentActivity(limit: Int) async throws -> [ActivityEntry]`
- `func getPendingNotifications() async throws -> [Notification]`
- `func getStockAlerts() async throws -> [StockAlert]`

### Parts/ (sub-services)
- `PartsService` — CRUD for parts, catalog queries, search
- `HierarchyService` — category/type/style/color tree management
- `PricingService` — cost layers, markup, sell price calculations
- `StockService` — stock levels, movements, forecasting queries
- `SuppliersService` — supplier CRUD, contacts, delivery methods
- `CompanionsService` — companion rules, alternatives
- `ForecastingService` — usage prediction, reorder suggestions
- `ImportExportService` — CSV/JSON import/export

### JobService.swift
- Job CRUD, status transitions, assignment, consumption tracking

### LaborService.swift
- Clock in/out, GPS capture, drive time, overtime, daily totals

### OrderService.swift
- JPO lifecycle, PO creation, line items, status transitions, approvals

### WarehouseService.swift
- Bin locations, inventory queries, audit trail

### MovementService.swift
- Stock movements, staging, receiving sessions

### FleetService.swift
- Vehicle CRUD, assignments, fuel, inspections, mileage, deliveries

### ToolService.swift
- Tool registry, kits, checkout/return, maintenance schedules

### ChatService.swift
- Channels, messages, Q&A threads, RFI objects

### NotebookService.swift
- Templates, notebooks, sections, entries, permissions

### SchedulingService.swift
- Dispatch, calendar, templates, config

### PTOService.swift
- Time-off requests, approval, availability

### ContactsService.swift
- Entity contacts, contact directory, search

### People/ (sub-services)
- `EmployeeService` — employee CRUD, certifications, wages, skills
- `CustomerService` — customer CRUD, job history
- `ContractorService` — contractor CRUD, work history

### ReportService.swift
- Report templates, data aggregation, period locking, export

### CostsService.swift
- FIFO/LIFO cost layers, margin calculations, budget tracking

### SecurityService.swift
- Device certificates, company key management, trust chain

---

## Module: Sync

**Path:** `Sources/WiredPartCore/Sync/`

### ChangeTracker.swift
- `static func track(db:, deviceId:, table:, recordId:, operation:, changedFields:, oldValues:) throws`
- `func getPendingChanges() async throws -> [ChangeLogEntry]`
- `func getPendingChangeCount() async throws -> Int`
- `func markSynced(ids: [Int64], batchId: String) async throws`
- `func pruneOldChanges() async throws -> Int`
- `func getVectorClock() async throws -> VectorClock`
- `func updateVectorClock(peerId: String, lastSequence: Int) async throws`
- `func getChangesSince(sinceSequence: Int) async throws -> [ChangeLogEntry]`

### ConflictResolver.swift
- `func resolveAndApplyChanges(_ changes: [IncomingChange], db: DatabaseWriter) async throws -> MergeResult`
- Field-level merge with LWW per-field
- `_conflict_log` writes for every overwrite

### SyncEngine.swift (actor)
- `func runSync(deviceId:, shopURL:, authToken:) async -> Bool`
- `func runInitialSync(deviceId:, shopURL:) async -> Bool`
- `func startPeriodicSync(deviceId:, shopURL:)`
- `func stopPeriodicSync()`
- `NWPathMonitor` for connectivity changes

### PeerManager.swift
- Coordinates PeerDiscovery + MultipeerManager + SyncEngine
- `func initSync(deviceId:) async`
- `func getActivePeers() -> [Peer]`
- `func syncWithPeer(_ peer: Peer) async throws`

### PeerDiscovery.swift
- `func startAdvertising(port:, deviceId:, deviceName:, companyId:)`
- `func startBrowsing(myDeviceId:, myCompanyId:)`
- `@Published var discoveredPeers: [DiscoveredPeer]`
- NWBrowser/NWListener for `_wiredpart._tcp`

### MultipeerManager.swift
- `func start(deviceId:, deviceName:, companyId:)`
- `func stop()`
- `func send(toPeerId:, data:) throws`
- `func popReceived() -> ReceivedMessage?`
- `@Published var connectedPeers: [MCPeerID]`

### LanSyncServer.swift
- swift-nio HTTP server on ephemeral port
- `POST /sync/push` — accept changes
- `POST /sync/pull` — return changes since vector clock
- `GET /sync/status` — health check

---

## Module: Crypto

**Path:** `Sources/WiredPartCore/Crypto/`

### SyncCrypto.swift
- `func verifySyncAuth(auth:, expectedCompanyId:, companyPublicKeyB64:) -> AuthResult`
- `func generateKeyPair() -> (publicKey: Data, privateKey: Data)`
- `func signCertificate(payload:, privateKey:) -> String`
- Uses CryptoKit `Curve25519.Signing`

---

## Module: AI

**Path:** `Sources/WiredPartCore/AI/`

### AIServiceProtocol.swift
- `protocol AIService`
  - `func checkAvailability() async -> AIAvailability`
  - `func generateCompletion(prompt:, instructions:) async throws -> String`
  - `func enhanceText(_:, mode:) async throws -> String`
  - `func generatePreFill(fieldType:, contextData:) async throws -> String`

### FoundationModelsService.swift (Phase 12)
- `@available(macOS 26.0, iOS 26.0, *) actor FoundationModelsService: AIService`
- Direct `LanguageModelSession` — no FFI bridge

### LlamaCppService.swift (Phase 12)
- `class LlamaCppService: AIService`
- GGUF model loading, inference via llama.cpp C++ bridge
- Fallback when Foundation Models unavailable

### OCRProcessor.swift (Phase 12+)
- `struct OCRProcessor`
  - `func extractFields(from: [RecognizedTextBlock], documentType: DocumentType) -> OCRExtractionResult`
  - `func matchSupplier(name: String) -> SupplierMatch?`
  - `func matchPartCode(code: String) -> PartMatch?`
  - `func parseDate(text: String) -> DateParseResult?`
  - `func parseQuantity(text: String) -> Int?`
  - `func parsePONumber(text: String) -> String?`
- Platform-agnostic field extraction, pattern matching, confidence scoring
- Works with any recognized text input — no UI or Vision framework dependency

### OCRScannerAdapter.swift (Phase 12+)
- `protocol OCRScannerAdapter`
  - `var isAvailable: Bool { get }`
  - `func scanDocument() async throws -> ScannedDocument`
  - `func recognizeText(in image: CGImage) async throws -> [RecognizedTextBlock]`
- Platform adapters in `mac/` and `ios-app/` directories

### ImageMatcher.swift (Phase 12+)
- `actor ImageMatcher`
  - `func loadIndex() async throws`
  - `func findMatches(for: CGImage, topK: Int, minimumConfidence: Float) async throws -> [ImageMatchResult]`
  - `func indexPartImage(partId: Int64, image: CGImage) async throws`
  - `func removeFromIndex(partId: Int64) async throws`
  - `func indexStats() -> ImageIndexStats`
- Cosine similarity search against feature index
- In-memory index for fast search (< 100ms for 10,000 parts)

### ImageFeatureAdapter.swift (Phase 12+)
- `protocol ImageFeatureAdapter`
  - `var isAvailable: Bool { get }`
  - `func extractFeatures(from: CGImage) async throws -> [Float]`
  - `var featureDimension: Int { get }`
- Apple implementation: `VNGenerateImageFeaturePrintRequest` (2048-dim)
- Windows fallback: MobileNetV3 ONNX (1024-dim)

### TextPredictor.swift (Phase 12+)
- `actor TextPredictor`
  - `func predict(context: PredictionContext) async -> [TextSuggestion]`
  - `func recordEntry(fieldType: String, text: String, entityContext: [String: String]?) async`
  - `func generatePreFill(formType: FormType, context: PreFillContext) async -> [PreFilledField]`
  - `func clearHistory(fieldType: String?) async`
- Priority chain: entity lookup (< 10ms) → phrase history (< 20ms) → template (< 5ms) → LLM (< 2s)
- `_text_history` table for phrase completion (local-only, not synced)

---

## Module: QR

**Path:** `Sources/WiredPartCore/QR/`

### QRCodec.swift (Phase 12+)
- `struct QRCodec`
  - `static func encode(_ entity: QREntity) throws -> String`
  - `static func decode(_ payload: String) throws -> QREntity`
  - `func resolve(_ entity: QREntity) async throws -> QRResolvedEntity`
- V2 schema with entity types: part, job, supplier, bin, vehicle, tool, employee, po
- V1 backward compatibility (payloads without `type` field treated as `part`)

### QRGenerator.swift (Phase 12+)
- `struct QRGenerator`
  - `static func generate(_ entity: QREntity, size: CGSize) throws -> CGImage`
  - `static func generateLabel(_ entity: QREntity, includeText: Bool, size: CGSize) throws -> CGImage`
- Uses `CIFilter.qrCodeGenerator()` (Core Image)
- Error correction level H (30% damage recovery)

### QRScannerAdapter.swift (Phase 12+)
- `protocol QRScannerAdapter`
  - `var isAvailable: Bool { get }`
  - `func startScanning() async throws -> AsyncStream<QRScanEvent>`
  - `func stopScanning()`
- Platform adapters: `DataScannerViewController` (iOS), `AVCaptureSession` (macOS), `BarcodeScanner` (Windows)

---

## Module: Sync (Extended — Phase 12+)

### BinarySyncManager.swift
- `actor BinarySyncManager`
  - `func enqueue(_ attachment: BinaryAttachment, priority: Priority)`
  - `func processQueue(transport: SyncTransport) async`
  - `func handleManifest(_ manifest: BinaryManifest, fromPeer: PeerInfo) async -> BinaryRequest`
  - `func resumeTransfer(_ transferId: UUID) async throws`
- Chunked binary transfer (16KB frames) for images and scanned documents
- SHA-256 deduplication, CRC32 per-chunk verification

### SyncPriorityQueue.swift
- `actor SyncPriorityQueue`
  - `func enqueue(_ task: SyncTask, priority: Priority)`
  - `func dequeueNext() -> SyncTask?`
  - `func pendingBinaryTransferCount() -> Int`
  - `func cancel(forRecordId: String, table: String)`
- Priority levels: critical (0) → high (1) → medium (3) → low (4) → background (5)
- Records always priority 1; images priority 3–5

---

## What Does NOT Go in Core

| Item | Reason | Where It Lives |
|------|--------|---------------|
| SwiftUI views | UI dependency | `mac/` or `ios/` |
| UIKit/AppKit types | Platform-specific | `mac/` or `ios/` |
| Navigation/routing | UI concern | `mac/WiredPartMac/Navigation/` |
| Theme colors/fonts | UI concern | `mac/WiredPartMac/Theme/` |
| WKWebView fallback | UI concern | `mac/WiredPartMac/WebFallback/` |
| App entry point | Platform-specific | `mac/WiredPartMac/App/` |
| Xcode project files | Build system | `mac/`, `ios/` |
| React/TypeScript code | Legacy | `src/` (retired Phase 15) |
| Rust code | Legacy | `src-tauri/` (retired Phase 15) |
