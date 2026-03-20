# 20C — QR Scanner Integration: Jobs Clock-In + Tools

> **Chain position:** 20A → 20B → **20C** → 20D
> **Prerequisite:** 20A complete (QRScanSheet reusable component exists)
> **Log file:** `xcode-ai/prompt-results-log.md`

## Instructions

**IMPORTANT:** Before implementing, first plan your approach by reading all files mentioned below. Understand the current state, then implement the fixes. When done, wait for the user to confirm before proceeding to the next prompt.

## Context

Wire QR scanning into the Jobs clock-in flow and the Tools checkout/return system. Workers in the field scan job QR codes to clock in quickly, and scan tool barcodes/QR codes to check out or return tools.

**Files to modify:**
- `Weird Parts IOS/Weird Parts IOS/Features/Jobs/IOSClockPage.swift`
- `Weird Parts IOS/Weird Parts IOS/Features/Tools/IOSToolCheckoutsPage.swift`
- `Weird Parts IOS/Weird Parts IOS/Features/Tools/IOSToolRegistryPage.swift`

**Reusable component from 20A:**
- `Weird Parts IOS/Weird Parts IOS/Scanning/QRScanSheet.swift`

## Task

### Step 1: Add QR scan to Clock-In page

The Clock page has an inline job picker sorted by GPS distance. Add a "Scan Job" button that scans a job QR code and immediately selects that job for clock-in.

```swift
// Add state:
@State private var showJobScanner = false

// Add scan button near the job picker. The exact placement depends on the current layout.
// Option A: If there's a toolbar, add there:
.toolbar {
    ToolbarItem(placement: .primaryAction) {
        Button {
            showJobScanner = true
        } label: {
            Label("Scan Job", systemImage: "qrcode.viewfinder")
        }
    }
}

// Option B: If the job picker is a list/section, add a scan row at the top:
Section {
    Button {
        showJobScanner = true
    } label: {
        Label("Scan Job QR Code", systemImage: "qrcode.viewfinder")
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(minHeight: 44)
    }
    // ... existing job list rows
}

// Add sheet:
.sheet(isPresented: $showJobScanner) {
    QRScanSheet(expectedType: .job) { result in
        if let jobId = result.entityId, result.isFound {
            // Select this job for clock-in
            selectedJobId = jobId
            // If the page auto-clocks-in on selection, trigger that
            // If not, just set the selected job and let user tap "Clock In"
        }
    }
    .environmentObject(appCore)
}
```

**Important:** If the clock page already has `.sheet` modifiers (e.g., for questionnaire from 19G), integrate QR into the existing sheet management to avoid conflicts.

### Step 2: Add QR scan to Tool Checkouts page

Add a "Scan Tool" button that scans a tool QR/barcode and initiates a checkout or return flow.

```swift
// In IOSToolCheckoutsPage, add state:
@State private var showToolScanner = false
@State private var scannedToolId: Int64?
@State private var scannedToolName: String?
@State private var showCheckoutConfirm = false

// Add toolbar button:
.toolbar {
    ToolbarItem(placement: .primaryAction) {
        Button {
            showToolScanner = true
        } label: {
            Image(systemName: "qrcode.viewfinder")
        }
    }
}

// Add scanner sheet:
.sheet(isPresented: $showToolScanner) {
    QRScanSheet(expectedType: .tool) { result in
        if let toolId = result.entityId, result.isFound {
            scannedToolId = toolId
            scannedToolName = result.fields["_title"] ?? result.code

            // Check if tool is currently checked out
            // If checked out → offer return flow
            // If available → offer checkout flow
            showCheckoutConfirm = true
        }
    }
    .environmentObject(appCore)
}

// Confirmation alert:
.alert("Tool Scanned", isPresented: $showCheckoutConfirm) {
    if let toolId = scannedToolId {
        Button("Check Out") {
            Task { await checkoutTool(toolId: toolId) }
        }
        Button("Return") {
            Task { await returnTool(toolId: toolId) }
        }
        Button("Cancel", role: .cancel) {}
    }
} message: {
    Text(scannedToolName ?? "Unknown tool")
}
```

### Step 3: Add QR scan to Tool Registry page

On the Tool Registry list page, add a scan button that finds a tool by QR/barcode and navigates to its detail.

```swift
// In IOSToolRegistryPage, add state:
@State private var showToolScanner = false

// Add toolbar button alongside existing buttons:
.toolbar {
    ToolbarItem(placement: .primaryAction) {
        HStack(spacing: 12) {
            Button {
                showToolScanner = true
            } label: {
                Image(systemName: "qrcode.viewfinder")
            }
            // ... existing add button if any
        }
    }
}

// Add scanner sheet:
.sheet(isPresented: $showToolScanner) {
    QRScanSheet(expectedType: .tool) { result in
        if let toolId = result.entityId, result.isFound {
            // Navigate to tool detail
            // Use whatever detail presentation the page uses (sheet, navigation, etc.)
            selectedToolId = toolId
        }
    }
    .environmentObject(appCore)
}
```

## Important Notes

- **Tool scanning is the highest-value QR integration** — field workers scan tool serial number barcodes constantly for checkout/return tracking.
- Tools may use standard barcodes (Code 128, Code 39) not just QR codes. The `IOSQRScanner` already supports these barcode formats — `QRAutoFillService` will try to match the scanned code against tools by serial number, barcode, or code field.
- The checkout/return flow after scanning should match whatever pattern the page already uses for manual checkout/return.
- If `IOSToolCheckoutsPage` doesn't have checkout/return actions yet, just navigate to the tool detail and let the user act from there.
- Clock page may have no toolbar currently — adding one is fine.

## Success Criteria

- [ ] Clock page has "Scan Job" button (toolbar or inline)
- [ ] Scanning a job QR selects that job for clock-in
- [ ] Tool Checkouts page has QR scan button
- [ ] Scanning a tool shows checkout/return options
- [ ] Tool Registry page has QR scan button for lookup
- [ ] Scanning a tool navigates to its detail
- [ ] Standard barcodes (Code 128) work for tool scanning
- [ ] No `.sheet` conflicts on any page
- [ ] Project builds with no errors

## Log Entry

```
## Prompt 20C Results (YYYY-MM-DD)
- Clock page: scan job QR to select for clock-in
- Tool Checkouts: scan tool for checkout/return flow
- Tool Registry: scan tool for detail lookup
- Build: [PASS/FAIL]
```

**Wait for user confirmation before proceeding to prompt 20D.**
