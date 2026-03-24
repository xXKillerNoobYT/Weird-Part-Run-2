# 54C — Device Pairing + Full Sync Infrastructure

> **Chain position:** 54A → 54B → **54C**
> **Prerequisite:** 54B (conflict UI)
> **Log file:** `xcode-ai/prompt-results-log.md`

## Instructions

This is the BACKBONE prompt. It makes the full sync pipeline work end-to-end: device pairing, initial data transfer, continuous background sync, change propagation, and offline resilience. Every other feature depends on this working correctly.

**Files to read first:**
- ALL files in `core/Sources/WiredPartCore/Sync/`
- ALL files in `Weird Parts IOS/Weird Parts IOS/Sync/`
- `Weird Parts IOS/Weird Parts IOS/Auth/DevicePairingView.swift`
- `Weird Parts IOS/Weird Parts IOS/Features/Settings/BluetoothPage.swift`
- `Weird Parts IOS/Weird Parts IOS/Features/Settings/SyncPage.swift`
- `Weird Parts IOS/Weird Parts IOS/App/AppCore.swift`

## Context

The sync system is the backbone of the entire program. Every device (shop computer, phones, tablets) must be able to:
1. Pair with the shop computer (anchor device)
2. Do an initial full data download
3. Continuously sync changes via Bluetooth/LAN
4. Work fully offline (changes queue up)
5. Resolve conflicts when reconnecting
6. Sync settings (company = all devices, personal = user's devices, device = never)

The shop computer is the ANCHOR — it holds the master database. All other devices sync TO and FROM the shop computer. Devices do NOT sync directly with each other (hub-and-spoke, not mesh).

## Task

### Step 1: Device Pairing Flow

Activate the DevicePairingView to actually pair devices:

```swift
// DevicePairingView — currently disabled
// Enable the pairing flow:

struct DevicePairingView: View {
    @EnvironmentObject var appCore: AppCore
    @State private var pairingCode = ""
    @State private var isPairing = false
    @State private var pairError: String?
    @State private var discoveredShop: ShopDevice?

    var body: some View {
        VStack(spacing: DS.Space.xl) {
            // Step 1: Discover shop computer via Bluetooth/LAN
            if discoveredShop == nil {
                discoverSection
            } else {
                // Step 2: Enter pairing code (shown on shop computer)
                pairingSection
            }
        }
        .task {
            // Start scanning for shop computer
            await scanForShopComputer()
        }
    }

    var discoverSection: some View {
        VStack(spacing: DS.Space.lg) {
            ProgressView()
            Text("Looking for shop computer...")
                .font(.headline)
            Text("Make sure the shop computer is running WiredPart and Bluetooth is enabled.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            // Manual entry fallback
            Section("Or enter shop address manually:") {
                TextField("192.168.1.100:8080", text: $manualAddress)
                Button("Connect") {
                    // Try LAN connection
                }
            }
        }
    }

    var pairingSection: some View {
        VStack(spacing: DS.Space.lg) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 48))
                .foregroundStyle(.green)
            Text("Shop Computer Found!")
                .font(.headline)
            Text(discoveredShop?.name ?? "WiredPart Shop")
                .foregroundStyle(.secondary)

            Text("Enter the pairing code shown on the shop computer:")
                .font(.subheadline)

            TextField("Pairing Code", text: $pairingCode)
                .textFieldStyle(.roundedBorder)
                .keyboardType(.numberPad)
                .frame(maxWidth: 200)
                .multilineTextAlignment(.center)
                .font(.title2.monospaced())

            Button {
                Task { await pairWithShop() }
            } label: {
                if isPairing {
                    ProgressView().controlSize(.small)
                } else {
                    Text("Pair This Device")
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(pairingCode.count < 4 || isPairing)

            if let error = pairError {
                Text(error)
                    .foregroundStyle(.red)
                    .font(.caption)
            }
        }
    }

    func pairWithShop() async {
        isPairing = true
        pairError = nil
        do {
            // 1. Send pairing request with code
            // 2. Shop verifies code → sends Ed25519 public key
            // 3. Device stores shop's public key
            // 4. Shop stores device's public key
            // 5. Initial data transfer begins

            guard let shop = discoveredShop else { return }
            let syncManager = appCore.syncManager

            try await syncManager.pairWithShop(
                shopAddress: shop.address,
                pairingCode: pairingCode
            )

            // 6. Full initial sync (download all data from shop)
            try await syncManager.performInitialSync()

            // 7. Save pairing info
            UserDefaults.standard.set(shop.address, forKey: "sync_server_address")
            UserDefaults.standard.set(true, forKey: "bluetooth_sync_enabled")
            UserDefaults.standard.set(true, forKey: "device_paired")

        } catch {
            pairError = error.localizedDescription
        }
        isPairing = false
    }
}
```

### Step 2: Initial Full Sync

After pairing, download ALL data from the shop computer:

```swift
extension IOSSyncManager {
    func performInitialSync() async throws {
        syncStatus = .syncing

        guard let db = appCore?.db else {
            throw SyncError.noDatabaseAvailable
        }

        // This is a full download — every table, every row
        // Uses the SyncEngine's bulk import capability

        let engine = SyncEngine(db: db)
        let tables = ConflictResolver.syncableTableNames // 140+ tables

        for table in tables {
            // Request all rows from shop for this table
            let rows = try await requestTableData(table: table)
            try engine.importBulkData(table: table, rows: rows)
        }

        // Mark all imported data as synced
        try ChangeTracker(db: db).markAllAsSynced()

        syncStatus = .synced(Date())
    }
}
```

### Step 3: Background Continuous Sync

```swift
extension IOSSyncManager {
    func startPeriodicSync(intervalMinutes: Int) {
        // Cancel existing timer
        syncTimer?.invalidate()

        // Create new periodic sync
        syncTimer = Timer.scheduledTimer(withTimeInterval: TimeInterval(intervalMinutes * 60), repeats: true) { [weak self] _ in
            Task { [weak self] in
                await self?.syncNow()
            }
        }
    }

    // Also sync when app comes to foreground
    func setupAppLifecycleSync() {
        NotificationCenter.default.addObserver(forName: UIApplication.willEnterForegroundNotification, object: nil, queue: .main) { [weak self] _ in
            Task { [weak self] in
                await self?.syncNow()
            }
        }
    }

    // Also sync when Bluetooth peer connects
    func setupPeerSync() {
        MultipeerManager.shared.onPeerConnected = { [weak self] peer in
            Task { [weak self] in
                await self?.syncNow()
            }
        }
    }
}
```

### Step 4: Offline Queue

```swift
extension IOSSyncManager {
    // Changes are ALWAYS saved locally first (via _change_log)
    // When sync runs, it sends queued changes
    // If sync fails, changes stay in queue for next attempt

    func getOfflineQueueSize() -> Int {
        guard let db = appCore?.db else { return 0 }
        let tracker = ChangeTracker(db: db)
        return (try? tracker.getPendingChanges().count) ?? 0
    }

    // Show queue size in sync status UI
    var syncStatusDescription: String {
        let queueSize = getOfflineQueueSize()
        switch syncStatus {
        case .idle:
            return queueSize > 0 ? "\(queueSize) changes waiting to sync" : "Ready"
        case .syncing:
            return "Syncing \(queueSize) changes..."
        case .synced(let date):
            return "Last sync: \(date.formatted(.relative(presentation: .numeric)))"
        case .error(let msg):
            return "Error: \(msg) (\(queueSize) changes queued)"
        }
    }
}
```

### Step 5: Settings Sync Scope

```swift
extension IOSSyncManager {
    // During sync, filter settings by scope
    func syncSettings() async throws {
        guard let db = appCore?.db else { return }

        // Get all settings changes
        let settingsChanges = try ChangeTracker(db: db)
            .getPendingChanges()
            .filter { $0.tableName == "settings" }

        for change in settingsChanges {
            let scope = getSettingSyncScope(key: change.recordKey)

            switch scope {
            case .company:
                // Sync to shop → shop distributes to all devices
                try await sendChange(change)
            case .personal:
                // Sync to shop → shop distributes to THIS USER's devices only
                try await sendChange(change, userScope: appCore?.currentUser?.id)
            case .device:
                // Never sync — skip
                continue
            }
        }
    }

    enum SettingSyncScope {
        case company    // 🌐 all devices
        case personal   // 👤 user's devices
        case device     // 📱 this device only
    }

    func getSettingSyncScope(key: String) -> SettingSyncScope {
        // Device-only settings
        let deviceKeys = ["device_name", "bluetooth_enabled", "sync_server_address",
                          "local_db_path", "device_id"]
        if deviceKeys.contains(key) { return .device }

        // Personal settings
        let personalKeys = ["theme_mode", "theme_color", "theme_font",
                           "notification_orders", "notification_certs",
                           "notification_vehicles", "notification_sync",
                           "notification_sound"]
        if personalKeys.contains(key) { return .personal }

        // Everything else is company-wide
        return .company
    }
}
```

### Step 6: Sync Status in UI

Update the Dashboard background tasks card and SyncPage to show real sync info:

```swift
// Dashboard card:
HStack {
    Image(systemName: syncManager.syncStatus.icon)
        .foregroundStyle(syncManager.syncStatus.color)
    VStack(alignment: .leading) {
        Text(syncManager.syncStatusDescription)
            .font(.caption)
        if syncManager.getOfflineQueueSize() > 0 {
            Text("\(syncManager.getOfflineQueueSize()) changes pending")
                .font(.caption2)
                .foregroundStyle(.orange)
        }
    }
}
```

## Important Notes

- Shop computer is the ANCHOR — hub-and-spoke topology, not mesh
- Devices sync TO/FROM the shop, never directly to each other
- All data is stored locally first — the app works 100% offline
- Sync is opportunistic — runs when connection is available
- Change tracking via `_change_log` is already recording all changes
- ConflictResolver handles LWW + field-level merge automatically
- Ed25519 signatures verify data integrity during transfer
- Initial sync can take several minutes for a large database
- Show progress during initial sync ("Downloading parts... 45%")

## Success Criteria

- [ ] Device pairing flow works (discover shop → enter code → pair)
- [ ] Initial full sync downloads all data from shop
- [ ] Periodic sync runs at configured interval
- [ ] App syncs on foreground return
- [ ] App syncs when Bluetooth peer connects
- [ ] Offline queue accumulates changes when no connection
- [ ] Settings respect sync scope (company/personal/device)
- [ ] Sync status shows in Dashboard + SyncPage
- [ ] Offline queue size visible
- [ ] Ed25519 signing active during sync
- [ ] Project builds with no errors

## Log Entry

```
## Prompt 54C Results (YYYY-MM-DD)
- Device pairing: discover + code + initial sync
- Continuous sync: periodic + foreground + peer connect
- Offline queue: changes accumulate, sync when available
- Settings scope: company/personal/device filtering
- Sync status UI: dashboard card + sync page
- Build: [PASS/FAIL]
```

**Bluetooth sync backbone is complete after this prompt.**
