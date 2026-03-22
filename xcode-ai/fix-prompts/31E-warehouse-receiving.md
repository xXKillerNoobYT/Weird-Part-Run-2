# 31E — Warehouse Receiving: Start/Continue Session Actions

> **Plan:** `docs/plans/ios-warehouse-pages.md`

## Instructions

Read the file first, then fix all issues. When done, wait for user confirmation.

## Context

The receiving page is display-only — it lists sessions but has no way to start a new session or continue an existing one. Needs action buttons and navigation to `IOSReceiveShipmentPage`.

**Files to modify:**
- `Weird Parts IOS/Weird Parts IOS/Features/Warehouse/IOSReceivingPage.swift`

## Task

1. **Add [Start New Session] toolbar button** — opens a sheet to select a PO for receiving:
   ```swift
   @State private var activeSheet: ActiveSheet?

   private enum ActiveSheet: Identifiable {
       case selectPO
       case continueSession(Int64)
       var id: String { String(describing: self) }
   }

   // Toolbar:
   ToolbarItem(placement: .primaryAction) {
       Button { activeSheet = .selectPO } label: {
           Image(systemName: "plus")
       }
   }
   ```

2. **Make session rows tappable** — tap an active session to continue it:
   ```swift
   // For active sessions:
   Button { activeSheet = .continueSession(session.id) } label: {
       sessionRow(session)
   }
   ```

3. **Wire sheets to IOSReceiveShipmentPage**:
   ```swift
   .sheet(item: $activeSheet) { sheet in
       switch sheet {
       case .selectPO:
           // Show PO picker → navigate to IOSReceiveShipmentPage
           NavigationStack {
               IOSReceiveShipmentPage()
                   .environmentObject(appCore)
           }
       case .continueSession(let sessionId):
           NavigationStack {
               IOSReceiveShipmentPage(sessionId: sessionId)
                   .environmentObject(appCore)
           }
       }
   }
   ```
   **Note:** Check if `IOSReceiveShipmentPage` accepts a `sessionId` parameter. If not, it may need a minor update to support resuming sessions.

4. **Remove `#if os(iOS)` platform guard**

5. **Replace status filter capsule chips with smart card filters**

## Success Criteria

- [ ] [Start New Session] button in toolbar
- [ ] Active sessions tappable to continue
- [ ] Sheets wire to IOSReceiveShipmentPage
- [ ] Platform guard removed
- [ ] Smart card filters
- [ ] Project builds with no errors

**Wait for user confirmation before proceeding to prompt 31F.**
