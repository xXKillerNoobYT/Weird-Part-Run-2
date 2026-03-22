# 31F — Warehouse Audit: Fix Setup Stub + Finalize/Adjust Actions

> **Plan:** `docs/plans/ios-warehouse-pages.md`

## Instructions

Read all 3 audit files first (IOSAuditPage, IOSAuditSetupView, IOSAuditSummaryView), then fix all issues. When done, wait for user confirmation.

## Context

The audit system has 3 files. The setup view's `startAudit()` is a stub that just dismisses. The summary view is read-only with no finalize or adjust actions. Setup has no ErrorStateView.

**Files to modify:**
- `Weird Parts IOS/Weird Parts IOS/Features/Warehouse/IOSAuditSetupView.swift` (176 lines)
- `Weird Parts IOS/Weird Parts IOS/Features/Warehouse/IOSAuditSummaryView.swift` (166 lines)
- `Weird Parts IOS/Weird Parts IOS/Features/Warehouse/IOSAuditPage.swift` (201 lines)
- `core/Sources/WiredPartCore/Services/WarehouseService.swift` — add audit session methods if missing

## Task

### IOSAuditSetupView — Fix startAudit() stub

1. **Replace stub with real audit session creation:**
   ```swift
   private func startAudit() {
       guard let service = appCore.warehouseService else {
           errorMessage = "Warehouse service not available"
           return
       }
       isSaving = true
       do {
           let sessionId = try service.createAuditSession(
               scope: selectedScope,
               zone: zoneName.isEmpty ? nil : zoneName,
               sampleSize: selectedScope == "spot_check" ? sampleSize : nil,
               includeZeroStock: includeZeroStock,
               notes: notes.isEmpty ? nil : notes
           )
           // Pass sessionId back to parent and dismiss
           onAuditCreated?(sessionId)
           dismiss()
       } catch {
           errorMessage = error.localizedDescription
       }
       isSaving = false
   }
   ```

2. **Add callback to pass session ID to parent:**
   ```swift
   var onAuditCreated: ((Int64) -> Void)?
   ```

3. **Add ErrorStateView** or inline error display

4. **Add `isSaving` state with ProgressView** on the Start button

5. **Remove platform guard**

6. **Check/add `createAuditSession` to WarehouseService** if it doesn't exist

### IOSAuditSummaryView — Add Finalize + Adjust

1. **Add [Finalize Audit] button** — closes the audit session:
   ```swift
   Button {
       finalizeAudit()
   } label: {
       Label("Finalize Audit", systemImage: "checkmark.seal")
           .frame(maxWidth: .infinity)
   }
   .buttonStyle(.borderedProminent)
   ```

2. **Add [Adjust] action on discrepancy rows** — tap a discrepancy to adjust the system count:
   ```swift
   // On each discrepancy row, add tap action:
   Button { selectedDiscrepancy = discrepancy } label: {
       discrepancyRow(discrepancy)
   }

   // Sheet for adjusting:
   .sheet(item: $selectedDiscrepancy) { disc in
       AdjustDiscrepancySheet(discrepancy: disc, onAdjust: { loadData() })
   }
   ```

3. **Move accuracy calculation to service layer** — don't compute inline in the view

4. **Remove platform guard**

### IOSAuditPage — Minor fixes

1. **Add [Recount] action** on discrepancy rows (swipe or button)
2. **Add audit→forecasting certainty note** as a TODO comment:
   ```swift
   // TODO: When certainty drops below 80% for a part, auto-add to audit queue
   // This ties into the forecasting system (see docs/plans/ios-warehouse-pages.md)
   ```
3. **Remove platform guard**

## Success Criteria

- [ ] startAudit() creates a real audit session (not a stub)
- [ ] Session ID passed back to parent view
- [ ] ErrorStateView/error display in setup
- [ ] [Finalize Audit] button on summary
- [ ] [Adjust] action on discrepancy rows
- [ ] [Recount] action on audit page discrepancies
- [ ] Accuracy calculation moved to service layer
- [ ] Platform guards removed (all 3 files)
- [ ] Certainty tie-in noted as TODO
- [ ] Project builds with no errors

**Wait for user confirmation before proceeding to prompt 31G.**
