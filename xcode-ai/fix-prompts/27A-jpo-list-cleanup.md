# 27A — JPO List: Cleanup + Create JPO + QR

> **Chain position:** **27A** → 27B → 27C → 27D → 27E
> **Prerequisite:** None
> **Plan:** `docs/plans/ios-jpo-page.md`
> **Log file:** `xcode-ai/prompt-results-log.md`

## Instructions

**IMPORTANT:** Before implementing, first plan your approach by reading all files mentioned below. Understand the current state, then implement. When done, wait for user confirmation before proceeding to the next prompt.

## Context

The JPO list page has 11 issues: no Create JPO button, no ActiveSheet pattern, no QR scan, platform guards, no count badges, silent guard failures, and no link to the PO generated from each JPO. This prompt fixes the structural issues and adds the Create JPO flow with auto-fill from the user's current clock-in.

**Files to read first:**
- `Weird Parts IOS/Weird Parts IOS/Features/Orders/IOSJPOsPage.swift` — current list page (177 lines)
- `Weird Parts IOS/Weird Parts IOS/Features/Orders/IOSJPODetailPage.swift` — current detail page (331 lines)
- `core/Sources/WiredPartCore/Services/OrdersService.swift` — search for JPO methods: `listJPOs`, `createJPO`
- `core/Sources/WiredPartCore/Services/JobsService.swift` — search for clock-in / active labor entry methods

**Files to modify:**
- `Weird Parts IOS/Weird Parts IOS/Features/Orders/IOSJPOsPage.swift`

## Task

### Step 1: Add ActiveSheet pattern

Replace any `@State private var showX = false` booleans with a single ActiveSheet enum:

```swift
@State private var activeSheet: ActiveSheet?

private enum ActiveSheet: Identifiable {
    case createJPO
    case qrScanner
    case scannedJPODetail(Int64)

    var id: String {
        switch self {
        case .createJPO: "createJPO"
        case .qrScanner: "qrScanner"
        case .scannedJPODetail(let id): "scannedJPO-\(id)"
        }
    }
}
```

### Step 2: Add toolbar buttons

```swift
.toolbar {
    ToolbarItemGroup(placement: .primaryAction) {
        Button { activeSheet = .qrScanner } label: {
            Image(systemName: "qrcode.viewfinder")
        }
        Button { activeSheet = .createJPO } label: {
            Image(systemName: "plus")
        }
    }
}
```

### Step 3: Add sheet routing

```swift
.sheet(item: $activeSheet) { sheet in
    switch sheet {
    case .createJPO:
        CreateJPOSheet(onSave: { loadData() })
            .environmentObject(appCore)
    case .qrScanner:
        QRScanSheet(expectedType: .jpo) { result in
            if let jpoId = result.entityId, result.isFound {
                activeSheet = .scannedJPODetail(jpoId)
            }
        }
        .environmentObject(appCore)
    case .scannedJPODetail(let jpoId):
        NavigationStack {
            IOSJPODetailPage(jpoId: jpoId)
                .environmentObject(appCore)
        }
    }
}
```

### Step 4: Create the CreateJPOSheet

Create a new `CreateJPOSheet` struct inside the file (or as a separate file if preferred). It auto-fills the job from the user's current clock-in:

```swift
private struct CreateJPOSheet: View {
    @EnvironmentObject private var appCore: AppCore
    @Environment(\.dismiss) private var dismiss
    let onSave: () -> Void

    @State private var selectedJobId: Int64?
    @State private var selectedJobName = ""
    @State private var priority = "normal"
    @State private var deliveryOption = "partial" // "partial" or "full"
    @State private var notes = ""
    @State private var jobs: [JobsService.JobListItem] = []
    @State private var errorMessage: String?
    @State private var showJobVerification = false
    @State private var clockedInJobId: Int64?
    @State private var clockedInJobName: String?

    var body: some View {
        NavigationStack {
            Form {
                // Job selection
                Section("Job") {
                    if let clockedJob = clockedInJobName {
                        HStack {
                            VStack(alignment: .leading) {
                                Text(clockedJob)
                                    .fontWeight(.medium)
                                Text("Clocked in")
                                    .font(.caption)
                                    .foregroundStyle(.green)
                            }
                            Spacer()
                            Button("Change") {
                                selectedJobId = nil
                                selectedJobName = ""
                            }
                            .font(.caption)
                        }
                    } else {
                        Picker("Select Job", selection: $selectedJobId) {
                            Text("Select a job...").tag(nil as Int64?)
                            ForEach(jobs, id: \.id) { job in
                                Text(job.jobName).tag(job.id as Int64?)
                            }
                        }
                    }
                }

                Section("Priority") {
                    Picker("Priority", selection: $priority) {
                        Text("Normal").tag("normal")
                        Text("High").tag("high")
                        Text("Urgent").tag("urgent")
                    }
                    .pickerStyle(.segmented)
                }

                Section("Delivery") {
                    Picker("Delivery Option", selection: $deliveryOption) {
                        Text("Deliver as parts arrive").tag("partial")
                        Text("Wait for complete order").tag("full")
                    }
                }

                Section("Notes") {
                    TextField("Optional notes...", text: $notes, axis: .vertical)
                        .lineLimit(3...6)
                }

                if let error = errorMessage {
                    Section {
                        Text(error)
                            .foregroundStyle(.red)
                            .font(.caption)
                    }
                }
            }
            .navigationTitle("New JPO")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") { createJPO() }
                        .disabled(selectedJobId == nil && clockedInJobId == nil)
                }
            }
            .task { await loadJobContext() }
        }
    }

    private func loadJobContext() async {
        guard let jobsService = appCore.jobsService else { return }
        // Load active jobs
        do {
            jobs = try jobsService.listJobs(status: "active", limit: 100)
        } catch { }

        // Check if user is clocked in
        guard let authService = appCore.authService,
              let userId = authService.currentUserId else { return }
        do {
            if let activeEntry = try jobsService.getActiveClockEntry(userId: userId) {
                clockedInJobId = activeEntry.jobId
                clockedInJobName = activeEntry.jobName
                selectedJobId = activeEntry.jobId
            }
        } catch { }
    }

    private func createJPO() {
        guard let service = appCore.ordersService else {
            errorMessage = "Orders service not available"
            return
        }
        let jobId = selectedJobId ?? clockedInJobId
        guard let jobId else {
            errorMessage = "Please select a job"
            return
        }
        do {
            _ = try service.createJPO(
                jobId: jobId,
                priority: priority,
                notes: notes.isEmpty ? nil : notes
            )
            onSave()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
```

**Note:** Check the actual method signatures for `getActiveClockEntry`, `listJobs`, and `createJPO`. The `createJPO` method may need a `deliveryOption` parameter added — if so, add it to the service method. Also check if `JobsService.JobListItem` has `jobName` or `name` as the property.

### Step 5: Add count badges to status chips

Load all JPOs for counting, then filter for display:

```swift
@State private var allJPOs: [OrdersService.JPOListItem] = []

private func countForStatus(_ status: String) -> Int {
    if status == "all" { return allJPOs.count }
    return allJPOs.filter { $0.status == status }.count
}
```

Update the chip label to include the count:

```swift
Text("\(status == "all" ? "All" : status.capitalized) (\(countForStatus(status)))")
```

### Step 6: Fix guard failures

```swift
// In loadData():
guard let service = appCore.ordersService else {
    loadError = "Orders service not available"
    isLoading = false
    return
}
```

### Step 7: Remove platform guards

Remove all `#if os(iOS)` / `#endif` blocks. Keep the iOS code.

### Step 8: Add KPI summary line

```swift
private var pendingCount: Int {
    allJPOs.filter { $0.status == "pending" }.count
}

// Between status picker and list:
if pendingCount > 0 {
    HStack {
        Label("\(pendingCount) pending approval", systemImage: "clock.badge.exclamationmark")
            .font(.caption)
            .foregroundStyle(.secondary)
        Spacer()
    }
    .padding(.horizontal)
    .padding(.vertical, 4)
}
```

## Success Criteria

- [ ] ActiveSheet enum with single `.sheet(item:)`
- [ ] [+] Create JPO button in toolbar
- [ ] QR scan button in toolbar
- [ ] CreateJPOSheet auto-fills job from clock-in
- [ ] Count badges on all status chips
- [ ] Platform guards removed
- [ ] Guard failures set loadError
- [ ] Pending count KPI line
- [ ] Project builds with no errors

## Log Entry

```
## Prompt 27A Results (YYYY-MM-DD)
- ActiveSheet + QR scan + Create JPO sheet with clock auto-fill
- Count badges, platform guards removed, loadError guards
- Build: [PASS/FAIL]
```

**Wait for user confirmation before proceeding to prompt 27B.**
