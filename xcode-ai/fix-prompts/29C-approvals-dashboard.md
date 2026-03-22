# 29C — Approvals: Quick Dashboard + Reject Reason + Smart Cards

> **Chain position:** Independent fix
> **Plan:** `docs/plans/ios-procurement-page.md` — Section 3, IOSApprovalsPage
> **Log file:** `xcode-ai/prompt-results-log.md`

## Instructions

**IMPORTANT:** Read the file first, then fix all issues. When done, wait for user confirmation.

## Context

The approvals page shows pending JPOs for approval. It needs to become a "quick approval dashboard" for managers — showing what needs attention across ALL approval types (JPOs, scheduled deletions, time-off requests, etc.). Currently, `actionError` is never displayed, reject doesn't require a reason, and it uses a platform guard.

**Files to read first:**
- `Weird Parts IOS/Weird Parts IOS/Features/Orders/IOSApprovalsPage.swift` (191 lines)

**Files to modify:**
- `Weird Parts IOS/Weird Parts IOS/Features/Orders/IOSApprovalsPage.swift`

## Task

### Step 1: Fix actionError display

The page has `actionError` state but errors are only printed to console. Add an `.alert`:

```swift
.alert("Error", isPresented: .constant(actionError != nil)) {
    Button("OK") { actionError = nil }
} message: {
    Text(actionError ?? "")
}
```

Replace all `print(...)` error statements with `actionError = error.localizedDescription`.

### Step 2: Require reject reason

Add a reason requirement for rejection:

```swift
@State private var rejectReason = ""
@State private var showRejectAlert = false
@State private var rejectingJPOId: Int64?

// Reject button triggers alert instead of immediate action:
Button {
    rejectingJPOId = jpo.id
    showRejectAlert = true
} label: {
    Label("Reject", systemImage: "xmark.circle.fill")
}
.tint(.red)

// Alert with reason field:
.alert("Reject JPO?", isPresented: $showRejectAlert) {
    TextField("Reason (required)", text: $rejectReason)
    Button("Cancel", role: .cancel) { rejectReason = "" }
    Button("Reject", role: .destructive) {
        guard !rejectReason.trimmingCharacters(in: .whitespaces).isEmpty else {
            actionError = "Rejection reason is required."
            return
        }
        if let id = rejectingJPOId {
            rejectJPO(id, reason: rejectReason)
        }
        rejectReason = ""
    }
} message: {
    Text("A reason is required. The requester will be notified.")
}
```

### Step 3: Add smart card filters

Replace any capsule chips with smart card filters showing approval type counts:

```swift
// Smart cards for approval categories:
// JPO Approvals (X) | Deletions (X) | Time-Off (X) | All (X)
```

Each card is tappable to filter. Tap again to deselect (show all). Cards always show global counts.

### Step 4: Remove platform guard

Remove `#if os(iOS)` around `.listStyle(.insetGrouped)`.

### Step 5: Add loading state for approve/deny

Show a ProgressView overlay or disable buttons while processing:

```swift
@State private var processingId: Int64?

// On button:
.disabled(processingId != nil)
.overlay {
    if processingId == jpo.id {
        ProgressView()
    }
}
```

## Success Criteria

- [ ] actionError displayed via `.alert` — no console-only errors
- [ ] Reject requires reason (alert with TextField)
- [ ] Smart card filters for approval types
- [ ] Platform guard removed
- [ ] Loading state during approve/deny
- [ ] Project builds with no errors

## Log Entry

```
## Prompt 29C Results (YYYY-MM-DD)
- actionError → alert display
- Reject reason required
- Smart card filters
- Loading state on actions
- Build: [PASS/FAIL]
```

**Wait for user confirmation before proceeding.**
