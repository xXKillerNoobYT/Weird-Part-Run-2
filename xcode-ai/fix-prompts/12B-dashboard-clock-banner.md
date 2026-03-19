# Fix Prompt 12B: Clock Status Banner on Dashboard Overview

> **BEFORE DOING ANYTHING:** Read `xcode-ai/xcode.md` and follow every instruction in it.
>
> **DEPENDS ON:** Prompt 12A must be completed first (Dashboard nav changes).

---

## What the User Wants

When a worker opens the Dashboard, they should immediately see whether they're clocked in or not — right at the top of the page, below the greeting. This is the most important piece of info for a field worker starting their day.

**When clocked in:** Green banner showing job name, job number, and a live duration counter (e.g., "3h 22m"). Tapping it navigates to Dashboard > Clock page.

**When not clocked in:** Gray banner with "Not clocked in" and a "Clock In" button that navigates to Dashboard > Clock page.

---

## File To Edit

**`Weird Parts IOS/Features/Dashboard/DashboardView.swift`**

### Step 1: Add Clock Status State

Add these state variables near the top of `DashboardView` (after the existing `@State` declarations):

```swift
// Clock status
@State private var isCurrentlyClockedIn = false
@State private var clockedInJobName: String?
@State private var clockedInJobNumber: String?
@State private var clockInTime: Date?
@State private var clockDurationText: String = "0m"
```

Add a timer for live duration updates (separate from the existing 60s refresh timer):

```swift
private let clockTimer = Timer.publish(every: 30, on: .main, in: .common).autoconnect()
```

### Step 2: Add the Banner View

Create a new computed property for the banner. Insert it in the `body` VStack, right after the `greeting` and before `kpiSection`:

```swift
// In body, after greeting and before the isLoading check:
// greeting
//     .padding(.horizontal, DS.Space.lg)
//
// clockStatusBanner    <--- ADD THIS
//     .padding(.horizontal, DS.Space.lg)
//
// if isLoading { ...

@ViewBuilder
private var clockStatusBanner: some View {
    NavigationLink(value: DashboardDestination.clock) {
        HStack(spacing: DS.Space.md) {
            // Status dot
            Circle()
                .fill(isCurrentlyClockedIn ? Color.green : Color.gray)
                .frame(width: 10, height: 10)

            if isCurrentlyClockedIn {
                VStack(alignment: .leading, spacing: DS.Space.xxxs) {
                    Text("Clocked In")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundStyle(.green)

                    if let jobName = clockedInJobName {
                        Text(jobName)
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                    }
                }

                Spacer()

                // Live duration
                Text(clockDurationText)
                    .font(.title3)
                    .fontWeight(.bold)
                    .monospacedDigit()
                    .foregroundStyle(.green)

                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            } else {
                Text("Not clocked in")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Spacer()

                Text("Clock In")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundStyle(Color.accentColor)

                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(DS.Space.md)
        .background(
            RoundedRectangle(cornerRadius: DS.Radius.md)
                .fill(isCurrentlyClockedIn
                    ? Color.green.opacity(0.08)
                    : Color(.secondarySystemGroupedBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: DS.Radius.md)
                .stroke(isCurrentlyClockedIn ? Color.green.opacity(0.2) : Color.clear, lineWidth: 1)
        )
    }
    .buttonStyle(.plain)
}
```

### Step 3: Load Clock Status in loadData()

Inside the existing `loadData()` method, add a clock status query to the `db.writer.read` closure. After the existing KPI queries (around where `newStats` is built), add:

```swift
// Clock status for current user
var clockedIn = false
var clockJobName: String?
var clockJobNumber: String?
var clockInTimestamp: String?

if let userId = await appCore.currentUser?.id {
    if let clockRow = try Row.fetchOne(dbConnection, sql: """
        SELECT le.clock_in, j.job_name, j.job_number
        FROM labor_entries le
        LEFT JOIN jobs j ON j.id = le.job_id
        WHERE le.user_id = ? AND le.clock_out IS NULL AND le.deleted_at IS NULL
        ORDER BY le.clock_in DESC LIMIT 1
        """, arguments: [userId]) {
        clockedIn = true
        clockJobName = clockRow["job_name"] as String?
        clockJobNumber = clockRow["job_number"] as String?
        clockInTimestamp = clockRow["clock_in"] as String?
    }
}
```

**Note:** The `appCore.currentUser?.id` access needs to happen outside the database read closure since it's `@MainActor`. Capture the userId before entering the closure:

```swift
let currentUserId = appCore.currentUser?.id
// Then inside the closure use currentUserId instead of appCore.currentUser?.id
```

Add clock fields to the `DashboardLoadResult` struct:

```swift
private struct DashboardLoadResult: Sendable {
    let stats: DashboardStats
    let certAlerts: [CertAlert]
    let vehicleAlerts: [VehicleAlert]
    // ADD:
    let isClockedIn: Bool
    let clockJobName: String?
    let clockJobNumber: String?
    let clockInTime: String?
}
```

In the `MainActor.run` block where results are applied:

```swift
isCurrentlyClockedIn = result.isClockedIn
clockedInJobName = result.clockJobName
clockedInJobNumber = result.clockJobNumber
if let timeStr = result.clockInTime {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    clockInTime = formatter.date(from: timeStr)
        ?? ISO8601DateFormatter().date(from: timeStr)
    updateClockDuration()
}
```

### Step 4: Live Duration Updates

Add the duration update method and timer handler:

```swift
private func updateClockDuration() {
    guard let startTime = clockInTime else {
        clockDurationText = "0m"
        return
    }
    let elapsed = Date().timeIntervalSince(startTime)
    let hours = Int(elapsed) / 3600
    let minutes = (Int(elapsed) % 3600) / 60
    if hours > 0 {
        clockDurationText = "\(hours)h \(minutes)m"
    } else {
        clockDurationText = "\(minutes)m"
    }
}
```

Add an `.onReceive` for the clock timer in the body:

```swift
.onReceive(clockTimer) { _ in
    updateClockDuration()
}
```

### Step 5: Place the Banner in the Body

The banner should show OUTSIDE the `isLoading` check — clock status should always be visible, even while KPIs are loading. Place it right after the greeting:

```swift
VStack(alignment: .leading, spacing: DS.Space.xl) {
    greeting
        .padding(.horizontal, DS.Space.lg)

    clockStatusBanner                        // <-- ADD HERE
        .padding(.horizontal, DS.Space.lg)

    if isLoading {
        DSLoadingState()
    } else if let error = loadError {
        // ...
    } else {
        kpiSection
        // ...
    }
}
```

---

## Success Criteria

1. Dashboard Overview shows a green banner when clocked in with job name and live duration
2. Dashboard Overview shows a gray "Not clocked in" banner when not clocked in
3. Duration updates every 30 seconds without a full page reload
4. Tapping the banner navigates to Dashboard > Clock page
5. Banner is visible even while KPIs are loading

---

## When Done

Read and implement **prompt 12C-inline-clock-gps.md** next.
