# Fix Prompt 04: Fake Sync & Visible Placeholder Text

> **BEFORE DOING ANYTHING:** Read `xcode-ai/xcode.md` and follow every instruction in it.

---

## The Problem (User Perspective)

### Fake Sync
When a user chooses "Join Existing Business" during onboarding, they see a progress bar that goes from 0% to 100% with messages like "Syncing parts catalog..." — but **no actual data is transferred**. The user thinks they synced successfully, continues to login, and finds an empty user list. This is misleading and breaks trust.

### Placeholder Text
Several screens show text like "Charts will be available in Phase 15" or "Parts assigned to this job will be listed here" — these are developer notes visible to users.

---

## Fixes

### Fix 1: SyncWaitingView — Replace Fake Sync With Honest UI

**File:** `Auth/SyncWaitingView.swift`

Replace the `simulateSync()` method and `startSync()` with an honest "not yet available" message:

```swift
private func startSync() {
    // Sync infrastructure not yet implemented.
    // Show honest message instead of fake progress.
    errorMessage = nil
    statusMessage = "Sync requires a shop computer on your network."
    isSyncComplete = false
}
```

Replace the body's progress section with:
```swift
// Instead of fake progress bar, show info about what's needed
VStack(spacing: 16) {
    Image(systemName: "wifi.exclamationmark")
        .font(.system(size: 48))
        .foregroundStyle(.orange)

    Text("Sync Not Available Yet")
        .font(.title3)
        .fontWeight(.semibold)

    Text("To join an existing business, a shop computer with WiredPart must be running on your network. This feature is coming in a future update.")
        .font(.subheadline)
        .foregroundStyle(.secondary)
        .multilineTextAlignment(.center)
        .padding(.horizontal, 32)

    Button("Go Back") {
        // Navigate back to onboarding choice
    }
    .buttonStyle(.bordered)
}
```

Delete the `simulateSync()` function entirely.

### Fix 2: DevicePairingView — Be Upfront

**File:** `Auth/DevicePairingView.swift`

The QR scan button (line 47) shows an error AFTER the user taps it. Instead, disable the button and show a note:

```swift
Button {
    // Will use IOSQRScanner when sync is implemented
} label: {
    HStack(spacing: 12) {
        Image(systemName: "qrcode.viewfinder")
            .font(.title3)
        Text("Scan QR Code")
            .fontWeight(.medium)
    }
    .frame(maxWidth: 300)
}
.buttonStyle(.bordered)
.disabled(true) // Sync not yet available

Text("QR pairing requires a shop computer running WiredPart on your network.")
    .font(.caption)
    .foregroundStyle(.secondary)
    .padding(.horizontal, 40)
```

Also update `attemptPairing()` — replace the fake delay + error with immediate feedback:
```swift
private func attemptPairing() {
    errorMessage = "Device pairing requires sync infrastructure. Use \"Create New Business\" to get started, or wait for a future update."
}
```

### Fix 3: IOSSyncManager — Mark Methods As Stubs

**File:** `Sync/IOSSyncManager.swift`

Add a `isSyncAvailable` property and use it:
```swift
/// Whether real sync infrastructure is connected.
/// When false, sync operations show "not available" instead of faking it.
var isSyncAvailable: Bool { false }
```

Update `syncNow()`:
```swift
func syncNow() async {
    guard isSyncAvailable else {
        syncStatus = .idle
        errorMessage = "Sync not configured. Connect to a shop computer first."
        return
    }
    // Real sync will go here
}
```

### Fix 4: IOSSyncStatusView and IOSPeerBrowser — Share One Manager

**File:** `Sync/IOSSyncStatusView.swift` and `Sync/IOSPeerBrowser.swift`

Both create their own `IOSSyncManager()` instance. They should receive one from the environment:

```swift
// CURRENT (broken — isolated instance)
@State private var syncManager = IOSSyncManager()

// FIX — receive from parent or environment
@EnvironmentObject private var appCore: AppCore
// Access sync manager through appCore, or pass as binding
```

For now, since there's no real sync, the simplest fix is to show "Sync not configured" in both views instead of pretending to scan/sync.

### Fix 5: SyncPage "Sync Now" Button

**File:** `Features/Settings/SyncPage.swift`

The "Sync Now" button (around line 61) has an empty action. Replace with:
```swift
Button("Sync Now") {
    errorMessage = "Sync infrastructure not yet configured."
}
```

Also replace the hardcoded "Not yet synced" and "0" pending changes (around lines 43-45) with:
```swift
Text("Sync not configured")
    .foregroundStyle(.secondary)
```

### Fix 6: Remove Visible Placeholder Text

**`Features/Office/IOSSpendingDashboardPage.swift`** (line 53):
Replace `"Charts will be available in Phase 15"` with:
```swift
EmptyStateView(
    title: "No Spending Data",
    message: "Spending charts will appear once orders have cost data.",
    icon: "chart.bar"
)
```

**`Features/Jobs/IOSJobDetailTabView.swift`** — Team tab:
Replace `"Team member list will show assigned users with roles"` with:
```swift
EmptyStateView(
    title: "No Team Members",
    message: "Assign employees to this job to see them here.",
    icon: "person.2"
)
```

Parts tab — replace `"Parts assigned to this job will be listed here"` with:
```swift
EmptyStateView(
    title: "No Parts",
    message: "Parts used on this job will appear here.",
    icon: "wrench.and.screwdriver"
)
```

**`Features/Notebooks/IOSNotebookDetailPage.swift`** — Tasks tab:
Replace `"Tasks will be loaded from NotebooksService"` with:
```swift
EmptyStateView(
    title: "No Tasks",
    message: "Add tasks to this notebook to track work items.",
    icon: "checklist"
)
```

**`Features/People/IOSCustomerDetailPage.swift`** — Job History:
Replace `"Job history will be populated from JobsService"` with:
```swift
EmptyStateView(
    title: "No Job History",
    message: "Jobs linked to this customer will appear here.",
    icon: "clock"
)
```

**`Features/Reports/IOSPublicReportView.swift`** — `loadReport()`:
Replace the placeholder string with:
```swift
loadError = "Public report sharing is not yet available."
isLoading = false
```

**`Sync/IOSPeerBrowser.swift`** (line 134):
Replace `"Peer connection requires sync infrastructure (Phase 16)."` with:
`"Peer connection requires a shop computer running WiredPart on your network."`

---

## Testing Checklist

1. Start the onboarding flow → choose "Join Existing Business" → you should see an honest "not available yet" message, NOT a fake progress bar
2. Settings → Sync → "Sync Now" button should show a clear message, not do nothing
3. Open any job → Team tab → should say "No Team Members", not a developer placeholder
4. Spending Dashboard → should say "No Spending Data", not "Phase 15"
5. No user-visible text should reference "Phase" anything

---

## When Done

Start **prompt 05 (AppCore Safety)** next.
