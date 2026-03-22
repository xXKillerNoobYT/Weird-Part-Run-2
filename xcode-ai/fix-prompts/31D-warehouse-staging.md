# 31D — Warehouse Staging: Swipe Confirmation + Batch Clear

> **Plan:** `docs/plans/ios-warehouse-pages.md`

## Instructions

Read the file first, then fix all issues. When done, wait for user confirmation.

## Context

The staging page has a swipe-to-clear action with no confirmation — a destructive action that should require user confirmation. No batch clearing option exists.

**Files to modify:**
- `Weird Parts IOS/Weird Parts IOS/Features/Warehouse/IOSStagingPage.swift`

## Task

1. **Add confirmation on swipe-to-clear** — when user swipes "Loaded", show alert:
   ```swift
   @State private var itemToLoad: StagedItem?
   @State private var showLoadConfirm = false

   .swipeActions {
       Button {
           itemToLoad = item
           showLoadConfirm = true
       } label: {
           Label("Loaded", systemImage: "checkmark.circle")
       }
       .tint(.green)
   }

   .alert("Mark as Loaded?", isPresented: $showLoadConfirm) {
       Button("Cancel", role: .cancel) { }
       Button("Confirm Loaded") {
           if let item = itemToLoad {
               clearStaging(item)
           }
       }
   } message: {
       Text("This will clear \(itemToLoad?.partName ?? "this item") from staging. It will be marked as loaded onto the truck/vehicle.")
   }
   ```

2. **Add batch clear option** — toolbar button to select multiple items and clear all at once:
   ```swift
   @State private var selectedItems: Set<Int64> = []
   @State private var isSelecting = false

   // Toolbar toggle for selection mode
   // When in selection mode, show checkboxes + [Clear Selected] button
   ```

3. **Remove `#if os(iOS)` platform guard**

4. **Add smart card filters** — filter by destination or status

## Success Criteria

- [ ] Swipe-to-clear requires confirmation alert
- [ ] Batch selection mode with [Clear Selected] button
- [ ] Platform guard removed
- [ ] Smart card filters
- [ ] Project builds with no errors

**Wait for user confirmation before proceeding to prompt 31E.**
