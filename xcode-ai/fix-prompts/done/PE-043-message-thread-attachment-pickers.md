# PE-043 — Message Thread: Wire Photo & Reference Pickers

**File:** `Weird Parts IOS/Weird Parts IOS/Features/Chat/IOSMessageThreadView.swift`
**GitHub Issue:** #152
**Severity:** P2 — Dead buttons (photo attach + reference pick do nothing)

---

## Problem

`IOSMessageThreadView` has two attachment buttons that set state variables but no sheets consume those variables:

1. **Photo button** sets `showPhotoPicker = true` — no `PhotosPicker` or sheet uses this.
2. **Reference button** (Part/PO/Job menu) sets `showReferencePicker = true` and `selectedReferenceType` — no sheet uses these.

Both buttons appear functional but tap silently with no result. The `pendingAttachments` array is already built correctly — the pickers just need to populate it.

---

## What to Build

### 1. Photo Picker (PhotosUI)

Replace the bare `showPhotoPicker = true` button with a proper `PhotosPicker`:

```swift
import PhotosUI

// Add @State:
@State private var selectedPhotoItems: [PhotosPickerItem] = []

// Replace the Photo button in attachmentBar with:
PhotosPicker(selection: $selectedPhotoItems, maxSelectionCount: 5, matching: .images) {
    Image(systemName: "photo")
        .foregroundStyle(.blue)
}
.accessibilityLabel("Attach photo")
.onChange(of: selectedPhotoItems) {
    Task {
        for item in selectedPhotoItems {
            if let data = try? await item.loadTransferable(type: Data.self) {
                // Save to temp file
                let tmpURL = FileManager.default.temporaryDirectory
                    .appendingPathComponent(UUID().uuidString + ".jpg")
                try? data.write(to: tmpURL)
                let att = ChatService.PendingAttachment(
                    type: "photo",
                    filePath: tmpURL.path,
                    fileName: tmpURL.lastPathComponent,
                    referenceId: nil,
                    referenceLabel: nil
                )
                await MainActor.run { pendingAttachments.append(att) }
            }
        }
        await MainActor.run { selectedPhotoItems = [] }
    }
}
```

### 2. Reference Picker Sheet

Add a `referencePickerSheet` case to `ActiveSheet` enum, then when the reference menu items are tapped, show the picker sheet:

```swift
// In ActiveSheet enum add:
case referencePicker(ReferenceType)
// id: "refpicker-\(type.rawValue)"

// In attachmentBar, change menu items to:
Button {
    activeSheet = .referencePicker(.part)
} label: { Label("Part Reference", systemImage: "shippingbox") }

Button {
    activeSheet = .referencePicker(.po)
} label: { Label("PO Reference", systemImage: "doc.text") }

Button {
    activeSheet = .referencePicker(.job)
} label: { Label("Job Reference", systemImage: "wrench.and.screwdriver") }
```

For the reference picker sheet content — simple list sheets loading from service:

- **Part picker**: `appCore.partsService?.listAllParts()` → list with search → tap adds `PendingAttachment(type: "part_ref", referenceId: part.id, referenceLabel: part.name)`
- **PO picker**: `appCore.ordersService?.listPurchaseOrders()` → tap adds `PendingAttachment(type: "po_ref", referenceId: po.id, referenceLabel: po.poNumber)`
- **Job picker**: `appCore.jobsService?.listActiveJobs()` → tap adds `PendingAttachment(type: "job_ref", referenceId: job.id, referenceLabel: job.name)`

Each picker sheet: NavigationStack with searchable list, Cancel toolbar button, tap to select and dismiss.

### 3. Remove dead state vars

Remove `showPhotoPicker: Bool` and `showReferencePicker: Bool` and `selectedReferenceType` since they're replaced by the above.

---

## Key Patterns

- Single `.sheet(item: $activeSheet)` — already in place, just add `referencePicker` case
- `PhotosPicker` from `PhotosUI` — no separate sheet needed
- Each picker sheet uses `@Environment(\.dismiss)` + `Cancel` toolbar item
- `pendingAttachments.append(att)` on MainActor after loading photo data

---

## Acceptance Criteria

- [ ] Tapping photo button opens system photo picker
- [ ] Selected photos appear as blue chips in `pendingAttachmentsBar`
- [ ] Tapping "Part Reference" opens searchable part list
- [ ] Tapping a part adds a chip labeled with part name
- [ ] Same for PO and Job references
- [ ] Sending a message with attachments clears all chips
- [ ] No `showPhotoPicker` or `showReferencePicker` state vars remain
