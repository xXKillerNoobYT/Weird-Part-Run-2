# 61E — Fix 8 Empty-Closure Dead Buttons

> **Chain position:** **61E** (standalone)
> **Issue:** T2-07
> **Log file:** `xcode-ai/prompt-results-log.md`

## MANDATORY RULES
1. For each button, either IMPLEMENT the action or show a "Coming Soon" toast
2. DO NOT delete any buttons — they represent planned features
3. If implementing, use `appCore.xxxService` — never create services directly
4. If showing "Coming Soon", use a consistent toast/alert pattern
5. Project must build with zero errors when done

## Context

8 buttons in the app have empty closures `{ }` — they do absolutely nothing when tapped. This is a terrible user experience. Users tap them, nothing happens, and they think the app is broken.

## Files & Buttons to Fix

### 1. PartsForecastingPage — "Add to Wishlist" button
**File:** `Weird Parts IOS/Weird Parts IOS/Features/Parts/PartsForecastingPage.swift`

**Implement:** When tapped, call `appCore.ordersService.addToWishlist(partId:, quantity:, reason:)`. If the wishlist service/method doesn't exist, show a "Coming Soon" toast instead.

### 2. PartsForecastingPage — "View in Catalog" button
**File:** `Weird Parts IOS/Weird Parts IOS/Features/Parts/PartsForecastingPage.swift`

**Implement:** Navigate to `PartsCatalogPage` with the part pre-selected/filtered. Use a `@State private var navigateToPartId: Int64?` and a hidden `NavigationLink`.

### 3. IOSPartsOrderManagementPage — "Move to PO" button
**File:** `Weird Parts IOS/Weird Parts IOS/Features/Orders/IOSPartsOrderManagementPage.swift`

**Implement:** Move the selected JPO line item(s) to a purchase order. Call the appropriate service method to transition items from JPO to PO status. If the service method doesn't exist, show "Coming Soon" toast.

### 4. IOSPartsOrderManagementPage — "Change Qty" button
**File:** `Weird Parts IOS/Weird Parts IOS/Features/Orders/IOSPartsOrderManagementPage.swift`

**Implement:** Show an alert with a text field to change the quantity:
```swift
.alert("Change Quantity", isPresented: $showChangeQty) {
    TextField("New quantity", text: $newQtyText)
        .keyboardType(.numberPad)
    Button("Update") {
        if let qty = Int(newQtyText), qty > 0 {
            // Update the line item quantity via service
        }
    }
    Button("Cancel", role: .cancel) { }
}
```

### 5. IOSPartsOrderManagementPage — "Remove + Hold" button
**File:** `Weird Parts IOS/Weird Parts IOS/Features/Orders/IOSPartsOrderManagementPage.swift`

**Implement:** Remove item from current order and place on hold. Show confirmation first:
```swift
.confirmationDialog("Remove & Hold", isPresented: $showRemoveHold) {
    Button("Remove and place on hold", role: .destructive) {
        // Call service to remove from order and mark as held
    }
    Button("Cancel", role: .cancel) { }
}
```

### 6. IOSProcurementPage — "Save for Later" button
**File:** Find IOSProcurementPage in the project (likely in Features/Orders/).

**Implement:** Mark the procurement item as "saved for later" — a soft archive that removes it from the active list but keeps it accessible. If no such status exists, show "Coming Soon" toast.

### 7. IOSMessageThreadView — File Attachment button
**File:** `Weird Parts IOS/Weird Parts IOS/Features/Chat/IOSMessageThreadView.swift`

**Implement:** Show a document picker or photo picker:
```swift
.fileImporter(isPresented: $showFilePicker, allowedContentTypes: [.item]) { result in
    switch result {
    case .success(let url):
        // Attach file URL to the message
        attachmentURL = url
    case .failure(let error):
        loadError = error.localizedDescription
    }
}
```

If file handling infrastructure doesn't exist in the chat service, show "Coming Soon" toast with message "File attachments coming in a future update."

### 8. IOSShortTermPipelinePage — "AI Suggest" button
**File:** `Weird Parts IOS/Weird Parts IOS/Features/Scheduling/IOSShortTermPipelinePage.swift`

**Implement:** Call the AI dispatch service to get scheduling suggestions:
```swift
Button("AI Suggest") {
    Task {
        guard let aiService = appCore.aiDispatchService else {
            showComingSoon = true
            return
        }
        do {
            let suggestions = try await aiService.suggestSchedule(for: pipelineItems)
            aiSuggestions = suggestions
        } catch {
            loadError = error.localizedDescription
        }
    }
}
```

If AIDispatchService doesn't have a `suggestSchedule` method, show "Coming Soon" toast.

### "Coming Soon" Toast Pattern

For any button where the service method doesn't exist, use this consistent pattern:

```swift
@State private var showComingSoon = false

// On the button:
Button("Action Name") {
    showComingSoon = true
}

// On the view:
.overlay(alignment: .bottom) {
    if showComingSoon {
        Text("Coming in a future update")
            .font(.subheadline)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(.ultraThinMaterial)
            .cornerRadius(8)
            .padding(.bottom, 20)
            .onAppear {
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                    withAnimation { showComingSoon = false }
                }
            }
    }
}
```

## Success Criteria

- [ ] All 8 buttons either perform a real action OR show "Coming Soon" toast
- [ ] No empty closures `{ }` remain on any user-facing button
- [ ] Implemented actions use appCore services, not direct DB access
- [ ] "Coming Soon" toasts auto-dismiss after 2 seconds
- [ ] Project builds with zero errors
