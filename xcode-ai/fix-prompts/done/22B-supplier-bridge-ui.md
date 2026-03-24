# 22B — Supplier Communication Bridge: Channel UI + PO Thread Links

> **Chain position:** 22A → **22B** → 22C
> **Prerequisite:** 22A complete (bridge tables + service methods exist)
> **Log file:** `xcode-ai/prompt-results-log.md`

## Instructions

**IMPORTANT:** Before implementing, first plan your approach by reading all files mentioned below. Understand the current state, then implement the fixes. When done, wait for the user to confirm before proceeding to the next prompt.

## Context

The bridge tables and service methods exist (22A). Now we need UI for:
1. Creating supplier channels from the supplier detail page
2. Viewing supplier channels in the channels list with a distinct badge
3. Sending messages with direction tracking (to/from supplier)
4. Linking PO references to messages
5. Accessing supplier channels from the supplier detail page

**Files to modify:**
- `Weird Parts IOS/Weird Parts IOS/Features/Chat/IOSChannelsPage.swift` — show supplier channels with badge
- `Weird Parts IOS/Weird Parts IOS/Features/Parts/PartsSuppliersPage.swift` — add "Message" button on supplier detail
- `Weird Parts IOS/Weird Parts IOS/Features/Chat/CreateChannelSheet.swift` — add supplier channel creation option

**Files to create (if chat detail doesn't exist):**
- May need a simple message view or integration with existing chat detail

## Task

### Step 1: Update IOSChannelsPage to show supplier channels

In `IOSChannelsPage.swift`, the channel list already shows type badges. Add handling for the "supplier" type:

```swift
// In the channel type badge/color logic, add:
case "supplier":
    // Orange badge to distinguish from internal channels
    Text("Supplier")
        .font(.caption2)
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(Color.orange.opacity(0.15))
        .foregroundStyle(.orange)
        .clipShape(Capsule())
```

If the channels page has a filter/picker (e.g., filter by "All", "Jobs", "Groups", "DMs"), add "Supplier" as a filter option:

```swift
// Add to the filter options:
Text("Supplier").tag("supplier")
```

### Step 2: Add "Message Supplier" button to SupplierDetailSheet

In `PartsSuppliersPage.swift`, on the `SupplierDetailSheet`, add a button to open or create a supplier channel:

```swift
// Add state:
@State private var supplierChannelId: Int64?

// Add section before Notes, or in the Contact section:
Section("Communication") {
    if let channelId = supplierChannelId {
        // Channel exists — open it
        Button {
            // Navigate to the channel
            // Option: post a notification to navigate to chat
            NotificationCenter.default.post(
                name: .init("navigateToChannel"),
                object: nil,
                userInfo: ["channelId": channelId]
            )
            dismiss()
        } label: {
            Label("Open Supplier Channel", systemImage: "bubble.left.and.bubble.right")
                .frame(maxWidth: .infinity, alignment: .leading)
                .frame(minHeight: 44)
        }
    } else {
        // No channel yet — create one
        Button {
            createSupplierChannel()
        } label: {
            Label("Start Conversation", systemImage: "plus.bubble")
                .frame(maxWidth: .infinity, alignment: .leading)
                .frame(minHeight: 44)
        }
    }
}
```

Add the creation logic:

```swift
private func createSupplierChannel() {
    guard let chatService = appCore.chatService,
          let userId = appCore.currentUserId else { return }

    do {
        let displayName = supplier.contactName ?? supplier.name
        let channelId = try chatService.createSupplierChannel(
            name: "Channel: \(supplier.name)",
            supplierId: supplier.id,
            supplierDisplayName: displayName,
            contactId: nil,  // general supplier channel
            role: nil,
            createdBy: userId
        )
        supplierChannelId = channelId
    } catch {
        // Show error
        print("[SupplierDetail] Create channel error: \(error)")
    }
}
```

In `loadAllDetails()`, check if a supplier channel already exists:

```swift
// Check for existing supplier channel
if let chatService = appCore.chatService, let userId = appCore.currentUserId {
    let channels = try chatService.listSupplierChannels(userId: userId)
    supplierChannelId = channels.first(where: { $0.supplierId == supplier.id })?.channelId
}
```

### Step 3: Add supplier channel creation to CreateChannelSheet

In `CreateChannelSheet.swift`, add "supplier" as a channel type option. This requires a supplier picker.

```swift
// Add to channel type options:
Picker("Type", selection: $channelType) {
    Text("Group").tag("group")
    Text("DM").tag("dm")
    Text("Supplier").tag("supplier")
}

// When "supplier" is selected, show supplier picker:
if channelType == "supplier" {
    Section("Supplier") {
        Picker("Select Supplier", selection: $selectedSupplierId) {
            Text("Choose...").tag(Int64(0))
            ForEach(suppliers, id: \.id) { supplier in
                Text(supplier.name).tag(supplier.id ?? Int64(0))
            }
        }
    }
}

@State private var selectedSupplierId: Int64 = 0
@State private var suppliers: [SupplierListRow] = []

// Load suppliers on appear:
.task {
    if let service = appCore.partsService {
        suppliers = (try? service.listSuppliers()) ?? []
    }
}
```

Update the save action to handle supplier channels:

```swift
// In the save action:
if channelType == "supplier" {
    guard selectedSupplierId != 0 else { return }
    let supplier = suppliers.first(where: { ($0.id ?? 0) == selectedSupplierId })
    channelId = try chatService.createSupplierChannel(
        name: channelName.isEmpty ? "Channel: \(supplier?.name ?? "Supplier")" : channelName,
        supplierId: selectedSupplierId,
        supplierDisplayName: supplier?.contactName ?? supplier?.name ?? "Supplier",
        contactId: nil,
        role: nil,
        createdBy: userId
    )
} else {
    channelId = try chatService.createChannel(
        name: channelName,
        channelType: channelType,
        jobId: nil,
        createdBy: userId
    )
}
```

### Step 4: Add direction indicator to messages in supplier channels

When viewing messages in a supplier channel, show direction badges so users know which messages are to/from the supplier:

```swift
// In the message row view (wherever chat messages are displayed):
// Check if this channel has a supplier bridge, then show direction:

// For outbound messages (to supplier):
HStack(spacing: 4) {
    Image(systemName: "arrow.up.right")
        .font(.caption2)
        .foregroundStyle(.blue)
    Text("To \(supplierName)")
        .font(.caption2)
        .foregroundStyle(.blue)
}

// For inbound messages (from supplier):
HStack(spacing: 4) {
    Image(systemName: "arrow.down.left")
        .font(.caption2)
        .foregroundStyle(.orange)
    Text("From \(supplierName)")
        .font(.caption2)
        .foregroundStyle(.orange)
}
```

This depends on how the chat message detail view is structured. Read the existing chat message view and add direction indicators where appropriate.

### Step 5: Add PO reference attachment support

When sending a message in a supplier channel, allow attaching a PO reference:

```swift
// In the message compose area for supplier channels:
if isSupplierChannel {
    HStack {
        // Quick-attach PO reference
        Menu {
            ForEach(recentPOs, id: \.poId) { po in
                Button("\(po.poNumber) — \(po.status)") {
                    attachPOReference(po)
                }
            }
        } label: {
            Image(systemName: "doc.text")
                .frame(width: 44, height: 44)
        }
    }
}

private func attachPOReference(_ po: RecentPO) {
    // Send message with PO context
    let content = "📋 PO Reference: \(po.poNumber)"
    try? chatService.sendSupplierMessage(
        channelId: channelId,
        senderId: userId,
        content: content,
        direction: "outbound",
        attachmentType: "po_reference",
        attachmentRef: po.poNumber
    )
}
```

Load recent POs for the supplier:

```swift
// In the channel detail, if supplier channel:
if let bridge = try? chatService.getSupplierBridge(channelId: channelId),
   let service = appCore.partsService {
    recentPOs = try service.getSupplierRecentPOs(supplierId: bridge.supplierId)
}
```

## Important Notes

- **Bridge approach means internal users act as intermediaries.** Messages are sent by internal users but tagged with direction (to/from supplier). In the future, suppliers could have direct access via the `invite_token`.
- The "supplier" channel type uses orange badge to visually distinguish from green "group" channels.
- Creating a supplier channel from the detail page is the primary entry point. The CreateChannelSheet option is secondary.
- PO reference attachment is a convenience — it links conversations to specific orders.
- If the app doesn't have a full chat message detail view yet (just the channel list), this prompt adds the supplier-specific features. The general chat detail view is assumed to exist or be created separately.
- Check `appCore.chatService` availability — it may need to be initialized in AppCore if not already.

## Success Criteria

- [ ] Supplier channels show orange "Supplier" badge in channels list
- [ ] "Supplier" filter option in channels page (if filter exists)
- [ ] "Start Conversation" button on supplier detail creates channel + bridge
- [ ] "Open Supplier Channel" button appears when channel exists
- [ ] CreateChannelSheet has "Supplier" type with supplier picker
- [ ] Direction indicators (to/from supplier) on messages
- [ ] PO reference attachment in supplier channels
- [ ] No `.sheet` conflicts
- [ ] Project builds with no errors

## Log Entry

```
## Prompt 22B Results (YYYY-MM-DD)
- Supplier channels: orange badge, filter option
- Supplier detail: start/open conversation button
- CreateChannelSheet: supplier type + picker
- Direction indicators + PO reference attachment
- Build: [PASS/FAIL]
```

**Wait for user confirmation before proceeding to prompt 22C.**
