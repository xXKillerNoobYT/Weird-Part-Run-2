# 54A — Bluetooth Sync Activation

> **Chain position:** **54A** → 54B → 54C
> **Prerequisite:** 53A (safe update system)
> **Log file:** `xcode-ai/prompt-results-log.md`

## Instructions

**IMPORTANT:** The core sync infrastructure already exists in `core/Sources/WiredPartCore/Sync/` — SyncEngine, ChangeTracker, ConflictResolver, PeerManager, MultipeerManager. The iOS sync manager (`IOSSyncManager.swift`) has `isSyncAvailable` hardcoded to `false`. This prompt wires it all together.

**Files to read first:**
- `core/Sources/WiredPartCore/Sync/SyncEngine.swift`
- `core/Sources/WiredPartCore/Sync/ChangeTracker.swift`
- `core/Sources/WiredPartCore/Sync/ConflictResolver.swift`
- `core/Sources/WiredPartCore/Sync/PeerManager.swift`
- `core/Sources/WiredPartCore/Sync/MultipeerManager.swift`
- `Weird Parts IOS/Weird Parts IOS/Sync/IOSSyncManager.swift`
- `Weird Parts IOS/Weird Parts IOS/Sync/IOSPeerBrowser.swift`
- `Weird Parts IOS/Weird Parts IOS/Features/Settings/SyncPage.swift`
- `Weird Parts IOS/Weird Parts IOS/Features/Settings/BluetoothPage.swift`

**Files to modify:**
- `Weird Parts IOS/Weird Parts IOS/Sync/IOSSyncManager.swift`
- `Weird Parts IOS/Weird Parts IOS/Features/Settings/SyncPage.swift`
- `Weird Parts IOS/Weird Parts IOS/Features/Settings/BluetoothPage.swift`
- `Weird Parts IOS/Weird Parts IOS/App/AppCore.swift`

## Task

### Step 1: Activate IOSSyncManager

Replace `isSyncAvailable` hardcoded false with actual availability check:

```swift
var isSyncAvailable: Bool {
    // Available if we have a configured server address OR Bluetooth is enabled
    let hasServer = UserDefaults.standard.string(forKey: "sync_server_address") != nil
    let btEnabled = UserDefaults.standard.bool(forKey: "bluetooth_sync_enabled")
    return hasServer || btEnabled
}
```

### Step 2: Wire syncNow() to SyncEngine

Replace the stub `syncNow()` with real sync logic:

```swift
func syncNow() async {
    guard isSyncAvailable else {
        syncStatus = .error("Sync not configured. Set up in Settings → Sync.")
        return
    }

    syncStatus = .syncing

    do {
        guard let db = appCore?.db else {
            syncStatus = .error("Database not available")
            return
        }

        // 1. Get pending changes from change log
        let changeTracker = ChangeTracker(db: db)
        let pendingChanges = try changeTracker.getPendingChanges()

        // 2. Attempt sync via configured method
        if let serverAddress = UserDefaults.standard.string(forKey: "sync_server_address") {
            // LAN HTTP sync
            try await syncViaHTTP(changes: pendingChanges, server: serverAddress)
        }

        if UserDefaults.standard.bool(forKey: "bluetooth_sync_enabled") {
            // Bluetooth/Multipeer sync
            try await syncViaBluetooth(changes: pendingChanges)
        }

        // 3. Mark changes as synced
        try changeTracker.markAsSynced(pendingChanges)

        syncStatus = .synced(Date())
        lastSyncDate = Date()
        UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: "last_sync_timestamp")
    } catch {
        syncStatus = .error(error.localizedDescription)
    }
}
```

### Step 3: Wire Bluetooth peer discovery

In `startPeerDiscovery()`, activate the MultipeerManager:

```swift
func startPeerDiscovery() {
    guard isSyncAvailable else { return }

    let multipeer = MultipeerManager.shared
    multipeer.startBrowsing()
    multipeer.startAdvertising()

    // Listen for discovered peers
    multipeer.onPeerFound = { [weak self] peer in
        self?.discoveredPeers.append(peer)
    }

    multipeer.onPeerLost = { [weak self] peer in
        self?.discoveredPeers.removeAll { $0.id == peer.id }
    }
}
```

### Step 4: Update SyncPage settings

Wire the "Sync Now" button to actually call `syncNow()`:

```swift
Button {
    Task {
        await syncManager.syncNow()
    }
} label: {
    HStack {
        if syncManager.syncStatus == .syncing {
            ProgressView().controlSize(.small)
        } else {
            Image(systemName: "arrow.triangle.2.circlepath")
        }
        Text("Sync Now")
    }
}
.disabled(syncManager.syncStatus == .syncing)
```

Show actual sync status:
```swift
Section("Status") {
    switch syncManager.syncStatus {
    case .idle:
        Label("Not synced yet", systemImage: "circle.dashed")
    case .syncing:
        Label("Syncing...", systemImage: "arrow.triangle.2.circlepath")
    case .synced(let date):
        Label("Last sync: \(date, format: .relative(presentation: .numeric))",
              systemImage: "checkmark.circle.fill")
            .foregroundStyle(.green)
    case .error(let msg):
        Label(msg, systemImage: "exclamationmark.triangle.fill")
            .foregroundStyle(.red)
    }
}
```

### Step 5: Update BluetoothPage

Wire the Bluetooth toggle to actually enable/disable Multipeer:

```swift
Toggle("Enable Bluetooth Sync", isOn: $bluetoothEnabled)
    .onChange(of: bluetoothEnabled) { newValue in
        UserDefaults.standard.set(newValue, forKey: "bluetooth_sync_enabled")
        if newValue {
            syncManager.startPeerDiscovery()
        } else {
            MultipeerManager.shared.stopBrowsing()
            MultipeerManager.shared.stopAdvertising()
        }
    }

// Show actual discovered peers instead of placeholder
Section("Nearby Devices") {
    if syncManager.discoveredPeers.isEmpty {
        Text("No nearby WiredPart devices found")
            .foregroundStyle(.secondary)
    } else {
        ForEach(syncManager.discoveredPeers) { peer in
            HStack {
                Image(systemName: "antenna.radiowaves.left.and.right")
                    .foregroundStyle(.blue)
                VStack(alignment: .leading) {
                    Text(peer.displayName).font(.subheadline)
                    Text(peer.deviceType).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                if peer.isConnected {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                } else {
                    Button("Connect") {
                        Task { await syncManager.connectToPeer(peer) }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }
        }
    }
}
```

### Step 6: Auto-sync on app launch

In AppCore, start sync automatically if configured:

```swift
// In setupServices() or after database is ready:
if syncManager.isSyncAvailable {
    Task {
        await syncManager.syncNow()
        syncManager.startPeerDiscovery()

        // Schedule periodic sync
        if let interval = settingsService?.getSetting("sync_interval") {
            syncManager.startPeriodicSync(intervalMinutes: Int(interval) ?? 15)
        }
    }
}
```

## Important Notes

- The core sync engine (SyncEngine, ChangeTracker, ConflictResolver) already exists and handles the heavy lifting — this prompt just WIRES it to the iOS UI
- LWW (Last Writer Wins) with field-level merge is already implemented in ConflictResolver
- Ed25519 signing is already in the core — just needs to be activated
- Change tracking via `_change_log` table is already recording changes
- This prompt makes sync FUNCTIONAL but not production-hardened — error recovery, retry logic, and conflict UI are in 54B and 54C
- Test with two simulators on the same network to verify LAN sync works

## Success Criteria

- [ ] `isSyncAvailable` returns true when server or Bluetooth is configured
- [ ] "Sync Now" button actually triggers sync
- [ ] Sync status shows real state (idle/syncing/synced/error)
- [ ] Bluetooth toggle enables/disables MultipeerManager
- [ ] Discovered peers show in BluetoothPage (not placeholder)
- [ ] Auto-sync on app launch if configured
- [ ] Periodic sync runs at configured interval
- [ ] Changes from `_change_log` are sent during sync
- [ ] Project builds with no errors

## Log Entry

```
## Prompt 54A Results (YYYY-MM-DD)
- IOSSyncManager activated (isSyncAvailable checks config)
- Sync Now wired to SyncEngine + ChangeTracker
- Bluetooth peer discovery wired to MultipeerManager
- SyncPage shows real status
- BluetoothPage shows real peers
- Auto-sync on launch + periodic sync
- Build: [PASS/FAIL]
```

**Wait for user confirmation before proceeding to prompt 54B.**
