# Fix Prompt 12C: Inline Clock with GPS-Sorted Jobs

> **BEFORE DOING ANYTHING:** Read `xcode-ai/xcode.md` and follow every instruction in it.
>
> **DEPENDS ON:** Prompts 12A and 12B must be completed first.

---

## What the User Wants

The Clock page currently shows a "Clock In" button that opens a sheet with a job picker. The user wants the job list **inline on the page** — always visible, no sheet. Jobs are sorted by distance from the user's GPS location so the nearest job site is always at the top. "Shop / Warehouse" is always pinned first.

When someone clocks into "Shop / Warehouse", they get an optional collapsible section to link time to a specific job (for office tasks like ordering parts, design work, phone calls related to a job). They can fast-switch this job link without clocking out/in.

---

## File To Edit

**`Weird Parts IOS/Features/Jobs/IOSClockPage.swift`**

### Step 1: Add Location + Distance State

Add these state variables:

```swift
@State private var userLocation: CLLocationCoordinate2D?
@State private var sortedJobs: [JobWithDistance] = []
@State private var isShopClockIn = false
@State private var linkedJobId: Int64?
@State private var linkedJobName: String?
@State private var showJobLinkPicker = false

struct JobWithDistance: Identifiable {
    let id: Int64
    let jobName: String
    let jobNumber: String
    let address: String?
    let latitude: Double?
    let longitude: Double?
    let distanceMiles: Double?
    let status: String

    var distanceText: String {
        guard let d = distanceMiles else { return "" }
        if d < 0.1 { return "Nearby" }
        return String(format: "%.1f mi", d)
    }
}
```

### Step 2: Fetch User Location and Sort Jobs

Replace the existing `loadData()` method. The new version:

1. Gets the user's current GPS coordinates
2. Fetches all active jobs with their lat/lng
3. Calculates distance and sorts by proximity
4. Loads current clock status (existing logic stays)

```swift
private func loadData() {
    isLoading = true
    errorMessage = nil

    // Get GPS first
    Task {
        userLocation = await locationManager.getCurrentLocation()
        await loadJobsAndClockStatus()
    }
}

private func loadJobsAndClockStatus() async {
    guard let db = appCore.db,
          let userId = appCore.currentUser?.id else {
        isLoading = false
        errorMessage = "Not logged in"
        return
    }

    do {
        // Load active clock entry
        let entry = try appCore.jobsService?.getActiveClockEntry(userId: userId)

        // Load active jobs
        let jobRows = try db.writer.read { conn -> [Row] in
            try Row.fetchAll(conn, sql: """
                SELECT id, job_name, job_number, address, latitude, longitude, status
                FROM jobs
                WHERE status IN ('active', 'in_progress') AND deleted_at IS NULL
                ORDER BY job_name ASC
                """)
        }

        // Calculate distances and sort
        let userLoc = userLocation
        var jobsWithDist: [JobWithDistance] = jobRows.map { row in
            let lat: Double? = row["latitude"]
            let lng: Double? = row["longitude"]
            var dist: Double? = nil

            if let userLoc, let lat, let lng,
               lat != 0, lng != 0 {
                let jobLoc = CLLocation(latitude: lat, longitude: lng)
                let userCLLoc = CLLocation(latitude: userLoc.latitude, longitude: userLoc.longitude)
                dist = userCLLoc.distance(from: jobLoc) / 1609.34
            }

            return JobWithDistance(
                id: row["id"] ?? 0,
                jobName: row["job_name"] ?? "",
                jobNumber: row["job_number"] ?? "",
                address: row["address"],
                latitude: lat,
                longitude: lng,
                distanceMiles: dist,
                status: row["status"] ?? ""
            )
        }

        // Sort: jobs with distance first (nearest first), then jobs without distance
        jobsWithDist.sort { a, b in
            switch (a.distanceMiles, b.distanceMiles) {
            case let (ad?, bd?): return ad < bd
            case (_?, nil): return true
            case (nil, _?): return false
            case (nil, nil): return a.jobName < b.jobName
            }
        }

        await MainActor.run {
            activeEntry = entry
            sortedJobs = jobsWithDist
            isLoading = false

            // Check if current clock-in is to shop
            if let entry, entry.jobName == "Shop / Warehouse" {
                isShopClockIn = true
            } else {
                isShopClockIn = false
            }
        }
    } catch {
        await MainActor.run {
            errorMessage = error.localizedDescription
            isLoading = false
        }
    }
}
```

### Step 3: Replace Clock-In Sheet with Inline Job List

Remove the `showClockInSheet` state and the `.sheet(isPresented: $showClockInSheet)` modifier.

Replace the "Clock In" button section with an inline job list. When the user is NOT clocked in, show:

```swift
@ViewBuilder
private var jobPickerSection: some View {
    Section {
        // Shop / Warehouse — always first, pinned
        Button {
            clockIn(jobId: nil, isShop: true)
        } label: {
            HStack(spacing: DS.Space.md) {
                Image(systemName: "building.fill")
                    .font(.title3)
                    .foregroundStyle(.blue)
                    .frame(width: 40, height: 40)
                    .background(Color.blue.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 8))

                VStack(alignment: .leading, spacing: 2) {
                    Text("Shop / Warehouse")
                        .font(.body)
                        .fontWeight(.semibold)
                    Text("Office, ordering, design work")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Image(systemName: "clock.badge.checkmark.fill")
                    .foregroundStyle(.green)
            }
            .frame(minHeight: 56)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    } header: {
        Text("Clock In To")
    }

    // Active Jobs sorted by distance
    if !sortedJobs.isEmpty {
        Section {
            ForEach(sortedJobs) { job in
                Button {
                    clockIn(jobId: job.id, isShop: false)
                } label: {
                    HStack(spacing: DS.Space.md) {
                        Image(systemName: "mappin.circle.fill")
                            .font(.title3)
                            .foregroundStyle(.orange)
                            .frame(width: 40, height: 40)
                            .background(Color.orange.opacity(0.1))
                            .clipShape(RoundedRectangle(cornerRadius: 8))

                        VStack(alignment: .leading, spacing: 2) {
                            Text(job.jobName)
                                .font(.body)
                                .fontWeight(.medium)
                            HStack(spacing: 8) {
                                if !job.jobNumber.isEmpty {
                                    Text("#\(job.jobNumber)")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                if let addr = job.address, !addr.isEmpty {
                                    Text(addr)
                                        .font(.caption)
                                        .foregroundStyle(.tertiary)
                                        .lineLimit(1)
                                }
                            }
                        }

                        Spacer()

                        if !job.distanceText.isEmpty {
                            Text(job.distanceText)
                                .font(.caption)
                                .fontWeight(.medium)
                                .foregroundStyle(
                                    (job.distanceMiles ?? 999) < 1 ? .green : .secondary
                                )
                        }

                        Image(systemName: "clock.badge.checkmark.fill")
                            .foregroundStyle(.green)
                    }
                    .frame(minHeight: 56)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        } header: {
            HStack {
                Text("Job Sites")
                Spacer()
                if userLocation != nil {
                    Label("Sorted by distance", systemImage: "location.fill")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}
```

### Step 4: Shop Mode — Optional Job Link

When clocked into Shop, show a collapsible section to link time to a job:

```swift
@ViewBuilder
private var shopJobLinkSection: some View {
    if isShopClockIn {
        Section {
            DisclosureGroup("Link time to a job (optional)") {
                if let linkedName = linkedJobName {
                    // Currently linked
                    HStack {
                        Image(systemName: "link.circle.fill")
                            .foregroundStyle(.blue)
                        Text("Linked to: \(linkedName)")
                            .font(.subheadline)
                        Spacer()
                        Button("End Link") {
                            endJobLink()
                        }
                        .font(.caption)
                        .buttonStyle(.bordered)
                        .tint(.red)
                    }
                    .padding(.vertical, 4)

                    Button("Change Job") {
                        showJobLinkPicker = true
                    }
                    .font(.caption)
                } else {
                    // Not linked — show job list
                    ForEach(sortedJobs) { job in
                        Button {
                            startJobLink(jobId: job.id, jobName: job.jobName)
                        } label: {
                            HStack {
                                Text(job.jobName)
                                    .font(.subheadline)
                                if !job.distanceText.isEmpty {
                                    Spacer()
                                    Text(job.distanceText)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .frame(minHeight: 40)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        } header: {
            Text("Job Link")
        }
    }
}
```

Add the link/unlink methods:

```swift
private func startJobLink(jobId: Int64, jobName: String) {
    linkedJobId = jobId
    linkedJobName = jobName
    // TODO: Record the job link start time in labor_entries notes or a new field
    // For now, store locally. Geofencing (12D) will formalize this.
}

private func endJobLink() {
    // TODO: Record the end time of the job link
    linkedJobId = nil
    linkedJobName = nil
}
```

### Step 5: Update the Clock-In Method

```swift
private func clockIn(jobId: Int64?, isShop: Bool) {
    guard let service = appCore.jobsService,
          let userId = appCore.currentUser?.id else {
        errorMessage = "Not logged in"
        return
    }

    do {
        let coords = userLocation
        let lat = coords?.latitude
        let lng = coords?.longitude

        if isShop {
            // Clock in to Shop/Warehouse (jobId = 0 or a special "shop" job)
            // Use the first job or create a special shop entry
            try service.clockIn(userId: userId, jobId: jobId ?? 0, latitude: lat, longitude: lng)
            isShopClockIn = true
        } else if let jid = jobId {
            try service.clockIn(userId: userId, jobId: jid, latitude: lat, longitude: lng)
            isShopClockIn = false
        }
        loadData()
    } catch {
        errorMessage = error.localizedDescription
    }
}
```

### Step 6: Update the Body

Replace the `clockContent` body to show either the clocked-in status (existing) OR the inline job picker (new):

```swift
@ViewBuilder
private var clockContent: some View {
    if isLoading {
        ProgressView("Loading clock status...")
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    } else {
        List {
            // Error banner
            if let errorMessage {
                Section {
                    Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                        .font(.caption)
                }
            }

            if let entry = activeEntry {
                // CLOCKED IN — show status + clock out button
                clockedInSection(entry)
                shopJobLinkSection
                todayHoursSection
            } else {
                // NOT CLOCKED IN — show inline job picker
                jobPickerSection
                todayHoursSection
            }
        }
        #if os(iOS)
        .listStyle(.insetGrouped)
        #endif
    }
}
```

---

## Success Criteria

1. When NOT clocked in: page shows "Shop / Warehouse" at top, then all active jobs sorted by GPS distance
2. Nearest job shows green distance text (e.g., "0.3 mi")
3. Tapping a job clocks in immediately — no sheet popup
4. After clocking into Shop: collapsible "Link time to a job" section appears
5. Can link to a job, see the link, change the link, or end the link
6. "Shop / Warehouse" is always the first option, never sorted by distance
7. If GPS is unavailable, jobs sort alphabetically with no distance shown

---

## When Done

Read and implement **prompt 12D-gps-geofencing.md** next.
