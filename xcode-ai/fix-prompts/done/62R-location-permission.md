# 62R — Fix Location Permission to Check Status Before Requesting
> Chain position: Standalone

## Task

The app calls `requestWhenInUseAuthorization()` without checking the current authorization status first. If the user has already denied permission, calling this again does nothing (iOS ignores it), but it's wasteful and can cause unexpected behavior. Fix it to only request permission when status is `.notDetermined`.

### Current code in LocationManager.swift:

```swift
func requestPermission() {
    manager.requestWhenInUseAuthorization()
}
```

### Fix LocationManager.requestPermission():

**File:** `Weird Parts IOS/Weird Parts IOS/App/LocationManager.swift`

Replace the `requestPermission()` method:

```swift
/// Request "when in use" location permission.
/// Only requests if the user hasn't been asked yet (.notDetermined).
/// Returns the current authorization status for the caller to act on.
@discardableResult
func requestPermission() -> CLAuthorizationStatus {
    let status = manager.authorizationStatus
    switch status {
    case .notDetermined:
        manager.requestWhenInUseAuthorization()
    case .denied, .restricted:
        // Don't re-request — user already denied or device restricted
        // Caller should show an alert directing user to Settings
        break
    case .authorizedWhenInUse, .authorizedAlways:
        // Already authorized — nothing to do
        break
    @unknown default:
        break
    }
    return status
}
```

### Fix the caller in IOSClockPage.swift:

**File:** `Weird Parts IOS/Weird Parts IOS/Features/Jobs/IOSClockPage.swift`

Find line ~114 where `requestPermission()` is called:

```swift
locationManager.requestPermission()
```

Replace with a version that handles denied state:

```swift
let status = locationManager.requestPermission()
if status == .denied || status == .restricted {
    showLocationDeniedAlert = true
}
```

Add the alert state and view:

```swift
@State private var showLocationDeniedAlert = false

// Add this .alert modifier:
.alert("Location Access Denied", isPresented: $showLocationDeniedAlert) {
    Button("Open Settings") {
        if let url = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(url)
        }
    }
    Button("Skip", role: .cancel) {}
} message: {
    Text("Location is needed to record where you clock in/out. You can enable it in Settings > Privacy > Location Services.")
}
```

### Also check GeofenceManager.swift:

**File:** `Weird Parts IOS/Weird Parts IOS/App/GeofenceManager.swift`

If this file also calls `requestWhenInUseAuthorization()` or `requestAlwaysAuthorization()` directly, apply the same check:

```swift
let status = locationManager.authorizationStatus
guard status == .notDetermined else { return }
locationManager.requestWhenInUseAuthorization()
```

### Also update the CLLocationManagerDelegate:

Make sure the `locationManagerDidChangeAuthorization` delegate method updates the published status:

```swift
nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
    let status = manager.authorizationStatus
    Task { @MainActor in
        self.authorizationStatus = status
    }
}
```

This should already be present — verify it exists. If not, add it.

## Files to Modify

- `Weird Parts IOS/Weird Parts IOS/App/LocationManager.swift` — fix requestPermission(), ensure delegate method exists
- `Weird Parts IOS/Weird Parts IOS/Features/Jobs/IOSClockPage.swift` — handle denied state with alert
- `Weird Parts IOS/Weird Parts IOS/App/GeofenceManager.swift` — check status before requesting (if applicable)

## Success Criteria
- [ ] `requestPermission()` only calls `requestWhenInUseAuthorization()` when status is `.notDetermined`
- [ ] If user previously denied, app does NOT re-request (no repeated system dialogs)
- [ ] When permission is denied, user sees an alert with "Open Settings" button
- [ ] "Open Settings" button opens the iOS Settings app to the correct page
- [ ] `authorizationStatus` is updated via the delegate callback
- [ ] No compile errors
