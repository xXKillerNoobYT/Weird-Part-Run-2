# Fix Prompt 12D: GPS Geofencing — Auto-Detect Job Transitions

> **BEFORE DOING ANYTHING:** Read `xcode-ai/xcode.md` and follow every instruction in it.
>
> **DEPENDS ON:** Prompt 12C must be completed first (inline clock with GPS).

---

## What the User Wants

When a worker is clocked into a job and their GPS shows they've left the 1-mile radius of that job site, the app notices and **locks the screen** — they can't do anything else until they answer "What happened?" This prevents data gaps where workers forget to clock out or switch jobs.

---

## New Files To Create

### 1. GeofenceManager.swift

**Create:** `Weird Parts IOS/App/GeofenceManager.swift`

This is a `CLLocationManager` wrapper that monitors a circular region around the clocked-in job.

```swift
import Foundation
import CoreLocation

@MainActor
final class GeofenceManager: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published var didExitJobRegion = false
    @Published var exitLocation: CLLocationCoordinate2D?
    @Published var exitTime: Date?

    private let locationManager = CLLocationManager()
    private var monitoredJobId: Int64?
    private var monitoredRegion: CLCircularRegion?

    static let jobRadiusMeters: Double = 1609.34 // 1 mile

    override init() {
        super.init()
        locationManager.delegate = self
        locationManager.allowsBackgroundLocationUpdates = false
        locationManager.desiredAccuracy = kCLLocationAccuracyHundredMeters
    }

    /// Start monitoring a 1-mile region around the given job coordinates.
    func startMonitoring(jobId: Int64, latitude: Double, longitude: Double) {
        stopMonitoring()

        let center = CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
        let region = CLCircularRegion(
            center: center,
            radius: Self.jobRadiusMeters,
            identifier: "job-\(jobId)"
        )
        region.notifyOnExit = true
        region.notifyOnEntry = false

        monitoredJobId = jobId
        monitoredRegion = region
        didExitJobRegion = false
        exitLocation = nil
        exitTime = nil

        locationManager.startMonitoring(for: region)
    }

    /// Stop all region monitoring.
    func stopMonitoring() {
        if let region = monitoredRegion {
            locationManager.stopMonitoring(for: region)
        }
        monitoredRegion = nil
        monitoredJobId = nil
        didExitJobRegion = false
        exitLocation = nil
        exitTime = nil
    }

    /// Reset the exit flag after the user handles the alert.
    func acknowledgeExit() {
        didExitJobRegion = false
        exitLocation = nil
        exitTime = nil
    }

    // MARK: - CLLocationManagerDelegate

    nonisolated func locationManager(_ manager: CLLocationManager, didExitRegion region: CLRegion) {
        Task { @MainActor in
            guard region.identifier == monitoredRegion?.identifier else { return }
            didExitJobRegion = true
            exitTime = Date()
            // Get current location for the exit event
            if let loc = manager.location?.coordinate {
                exitLocation = loc
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, monitoringDidFailFor region: CLRegion?, withError error: Error) {
        // Region monitoring failed — don't block the user, just log
        print("[GeofenceManager] Monitoring failed: \(error.localizedDescription)")
    }
}
```

### 2. GeofenceAlertView.swift

**Create:** `Weird Parts IOS/App/GeofenceAlertView.swift`

This is the full-screen lock modal that appears when the worker leaves the job zone.

```swift
import SwiftUI
import WiredPartCore

/// Full-screen modal shown when worker leaves the 1-mile radius of their clocked-in job.
/// Blocks all other app interaction until the worker responds.
struct GeofenceAlertView: View {
    @EnvironmentObject private var appCore: AppCore
    @ObservedObject var geofenceManager: GeofenceManager

    let currentJobName: String
    let currentJobId: Int64
    let onResolved: () -> Void

    @State private var selectedReason: ExitReason?
    @State private var otherNotes = ""
    @State private var targetJobId: Int64?
    @State private var activeJobs: [JobOption] = []
    @State private var isProcessing = false

    enum ExitReason: String, CaseIterable {
        case supplyRun = "Supply Run"
        case anotherJob = "Going to Another Job"
        case lunch = "Lunch Break"
        case breakTime = "Break"
        case doneForDay = "Done for the Day"
        case other = "Other"
    }

    struct JobOption: Identifiable {
        let id: Int64
        let name: String
        let number: String
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    // Warning header
                    VStack(spacing: 12) {
                        Image(systemName: "location.slash.fill")
                            .font(.system(size: 48))
                            .foregroundStyle(.orange)

                        Text("You've Left the Job Area")
                            .font(.title2)
                            .fontWeight(.bold)

                        Text("You're clocked in to **\(currentJobName)** but you've moved outside the job site. What happened?")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 24)

                        if let exitTime = geofenceManager.exitTime {
                            Text("Detected at \(exitTime.formatted(date: .omitted, time: .shortened))")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .padding(.top, 32)

                    // Reason buttons
                    VStack(spacing: 12) {
                        ForEach(ExitReason.allCases, id: \.rawValue) { reason in
                            Button {
                                selectedReason = reason
                                if reason == .anotherJob { loadActiveJobs() }
                            } label: {
                                HStack(spacing: 16) {
                                    Image(systemName: iconFor(reason))
                                        .font(.title3)
                                        .frame(width: 28)
                                        .foregroundStyle(colorFor(reason))

                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(reason.rawValue)
                                            .font(.body)
                                            .fontWeight(.medium)
                                        Text(descriptionFor(reason))
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }

                                    Spacer()

                                    if selectedReason == reason {
                                        Image(systemName: "checkmark.circle.fill")
                                            .foregroundStyle(.blue)
                                    } else {
                                        Image(systemName: "circle")
                                            .foregroundStyle(.tertiary)
                                    }
                                }
                                .padding(16)
                                .background(
                                    RoundedRectangle(cornerRadius: 12)
                                        .fill(selectedReason == reason
                                            ? Color.blue.opacity(0.08)
                                            : Color(.secondarySystemGroupedBackground))
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12)
                                        .stroke(selectedReason == reason ? Color.blue.opacity(0.3) : .clear, lineWidth: 1)
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 20)

                    // Job picker (if "Another Job" selected)
                    if selectedReason == .anotherJob && !activeJobs.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Which job are you going to?")
                                .font(.subheadline)
                                .fontWeight(.medium)

                            ForEach(activeJobs) { job in
                                Button {
                                    targetJobId = job.id
                                } label: {
                                    HStack {
                                        Text(job.name)
                                            .font(.subheadline)
                                        if !job.number.isEmpty {
                                            Text("#\(job.number)")
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        }
                                        Spacer()
                                        if targetJobId == job.id {
                                            Image(systemName: "checkmark.circle.fill")
                                                .foregroundStyle(.blue)
                                        }
                                    }
                                    .padding(12)
                                    .background(
                                        RoundedRectangle(cornerRadius: 8)
                                            .fill(targetJobId == job.id
                                                ? Color.blue.opacity(0.06)
                                                : Color(.tertiarySystemGroupedBackground))
                                    )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal, 20)
                    }

                    // Notes (if "Other" selected)
                    if selectedReason == .other {
                        TextField("What happened?", text: $otherNotes, axis: .vertical)
                            .textFieldStyle(.roundedBorder)
                            .lineLimit(2...4)
                            .padding(.horizontal, 20)
                    }

                    // Confirm button
                    Button {
                        Task { await handleResponse() }
                    } label: {
                        if isProcessing {
                            ProgressView()
                                .frame(maxWidth: .infinity)
                        } else {
                            Text("Confirm")
                                .fontWeight(.semibold)
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(selectedReason == nil || isProcessing ||
                              (selectedReason == .anotherJob && targetJobId == nil) ||
                              (selectedReason == .other && otherNotes.trimmingCharacters(in: .whitespaces).isEmpty))
                    .padding(.horizontal, 20)
                    .padding(.bottom, 32)
                }
            }
            .interactiveDismissDisabled(true) // Cannot swipe to dismiss
            .navigationTitle("Location Alert")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    // MARK: - Handle Response

    private func handleResponse() async {
        guard let reason = selectedReason else { return }
        isProcessing = true

        guard let service = appCore.jobsService,
              let userId = appCore.currentUser?.id else {
            isProcessing = false
            return
        }

        let exitTimeStamp = geofenceManager.exitTime ?? Date()

        do {
            switch reason {
            case .supplyRun:
                // Stay clocked in, record supply run event
                // TODO: Record event in labor_entries notes or labor_events table
                break

            case .anotherJob:
                if let newJobId = targetJobId {
                    // Clock out of current job at exit time
                    try service.clockOut(userId: userId, latitude: geofenceManager.exitLocation?.latitude, longitude: geofenceManager.exitLocation?.longitude)
                    // Clock in to new job at current time
                    try service.clockIn(userId: userId, jobId: newJobId, latitude: geofenceManager.exitLocation?.latitude, longitude: geofenceManager.exitLocation?.longitude)
                }

            case .lunch:
                try service.clockOut(userId: userId, latitude: geofenceManager.exitLocation?.latitude, longitude: geofenceManager.exitLocation?.longitude)
                // TODO: Set a reminder to clock back in

            case .breakTime:
                try service.clockOut(userId: userId, latitude: geofenceManager.exitLocation?.latitude, longitude: geofenceManager.exitLocation?.longitude)

            case .doneForDay:
                try service.clockOut(userId: userId, latitude: geofenceManager.exitLocation?.latitude, longitude: geofenceManager.exitLocation?.longitude)

            case .other:
                // Stay clocked in, record the explanation
                // TODO: Record otherNotes in labor_entries
                break
            }

            await MainActor.run {
                geofenceManager.acknowledgeExit()
                isProcessing = false
                onResolved()
            }
        } catch {
            await MainActor.run {
                isProcessing = false
                // Show error but don't dismiss — they must still respond
            }
        }
    }

    // MARK: - Load Jobs

    private func loadActiveJobs() {
        guard let db = appCore.db else { return }
        do {
            let rows = try db.writer.read { conn in
                try Row.fetchAll(conn, sql: """
                    SELECT id, job_name, job_number FROM jobs
                    WHERE status IN ('active', 'in_progress') AND deleted_at IS NULL AND id != ?
                    ORDER BY job_name ASC
                    """, arguments: [currentJobId])
            }
            activeJobs = rows.map { row in
                JobOption(id: row["id"] ?? 0, name: row["job_name"] ?? "", number: row["job_number"] ?? "")
            }
        } catch {
            print("[GeofenceAlert] Load jobs error: \(error)")
        }
    }

    // MARK: - Helpers

    private func iconFor(_ reason: ExitReason) -> String {
        switch reason {
        case .supplyRun: return "truck.box.fill"
        case .anotherJob: return "arrow.right.circle.fill"
        case .lunch: return "fork.knife"
        case .breakTime: return "cup.and.saucer.fill"
        case .doneForDay: return "moon.fill"
        case .other: return "ellipsis.circle.fill"
        }
    }

    private func colorFor(_ reason: ExitReason) -> Color {
        switch reason {
        case .supplyRun: return .blue
        case .anotherJob: return .orange
        case .lunch: return .green
        case .breakTime: return .purple
        case .doneForDay: return .indigo
        case .other: return .gray
        }
    }

    private func descriptionFor(_ reason: ExitReason) -> String {
        switch reason {
        case .supplyRun: return "Getting supplies. Clock keeps running."
        case .anotherJob: return "Clock out here, clock in at the new job."
        case .lunch: return "Clock out for lunch."
        case .breakTime: return "Taking a break. Clock pauses."
        case .doneForDay: return "Clock out and done."
        case .other: return "Something else — explain below."
        }
    }
}
```

### 3. Wire GeofenceManager Into IOSClockPage

**Edit:** `Weird Parts IOS/Features/Jobs/IOSClockPage.swift`

Add `GeofenceManager` as a `@StateObject`:

```swift
@StateObject private var geofenceManager = GeofenceManager()
```

When the user clocks in to a job with lat/lng, start monitoring:

```swift
// In clockIn() after successful clock-in:
if !isShop, let job = sortedJobs.first(where: { $0.id == jobId }),
   let lat = job.latitude, let lng = job.longitude,
   lat != 0, lng != 0 {
    geofenceManager.startMonitoring(jobId: job.id, latitude: lat, longitude: lng)
}
```

When clocking out, stop monitoring:

```swift
// In clockOut():
geofenceManager.stopMonitoring()
```

### 4. Show the Lock Modal

**Edit:** `Weird Parts IOS/Navigation/IOSMainView.swift` (or wherever the root NavigationStack lives)

Add the geofence alert as a `.fullScreenCover` that blocks all interaction:

```swift
@StateObject private var geofenceManager = GeofenceManager()

// In body:
.fullScreenCover(isPresented: $geofenceManager.didExitJobRegion) {
    GeofenceAlertView(
        geofenceManager: geofenceManager,
        currentJobName: currentClockedJobName,
        currentJobId: currentClockedJobId,
        onResolved: { /* reload clock data */ }
    )
    .environmentObject(appCore)
    .interactiveDismissDisabled(true)
}
```

**Note:** The `GeofenceManager` needs to be shared between the Clock page (which starts monitoring) and the main view (which shows the alert). Consider injecting it as an `@EnvironmentObject` on `AppCore`, or use a shared `@StateObject` at the root level that both views can observe.

---

## Success Criteria

1. Clock into a job with GPS coordinates → geofence starts monitoring (verify in Xcode console)
2. Leave the 1-mile radius → full-screen modal appears, cannot dismiss by swiping
3. Select "Supply Run" → modal closes, still clocked in, clock keeps running
4. Select "Another Job" → pick a different job → clocks out of old, clocks in to new
5. Select "Lunch" / "Done for Day" → clocks out
6. Cannot navigate to any other page while the modal is showing
7. Clock out manually → geofence monitoring stops

---

## When Done

Read and implement **prompt 12E-enhanced-daily-report.md** next.
