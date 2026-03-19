# Legacy Cleanup Plan this is the final cleanup phase to remove dead code and label future-phase placeholders after the Phase 7A-7E orders redesign.

> **Date:** 2026-03-06
> **Status:** ✅ Complete (4 legacy files need manual deletion — OneDrive lock)
> **Estimated work:** 0.5 day
> **Dependencies:** None (can be done anytime)

---

## Context

The Orders module was redesigned in Phases 7A-7E. Several old pages were superseded but left in the codebase. Additionally, some Settings tabs are placeholders for future phases (Sync, AI, Devices) and some pages are stubs that should be clearly labeled.

**Goal:** Remove dead code, clean up routes, label future-phase placeholders so the codebase is clean for V1.0 deployment.

---

## Pages to Delete

These pages were superseded by the Phase 7A-7E orders redesign and are no longer reachable through normal navigation:

| Page | File | Superseded By | Action |
|------|------|--------------|--------|
| `NewPartsRequestPage` | `frontend/src/features/orders/pages/NewPartsRequestPage.tsx` | `UnifiedOrderPage.tsx` (Phase 7A) | Delete file |
| `DraftOrdersPage` | `frontend/src/features/orders/pages/DraftOrdersPage.tsx` | `PartsRequestsPage.tsx` filters | Delete file |
| `ActiveOrdersPage` | `frontend/src/features/orders/pages/ActiveOrdersPage.tsx` | `PurchaseOrdersPage.tsx` | Delete file |
| `IncomingOrdersPage` | `frontend/src/features/orders/pages/IncomingOrdersPage.tsx` | `ReceivingPage.tsx` (Phase 7C) | Delete file |

## Routes to Clean Up

In `frontend/src/App.tsx`:

| Route | Action |
|-------|--------|
| `/orders/purchase-orders-legacy` | Remove route (was the old PO page) |
| Legacy redirects block (line ~230) | Remove entire block |
| Any routes pointing to deleted pages | Remove |

## Pages to Label as Future-Phase Placeholders

These Settings stubs aren't broken — they're intentionally empty because they depend on future phases. Update their `<EmptyState>` descriptions to be clear:

| Page | Current Message | Updated Message |
|------|----------------|-----------------|
| `SyncSettingsPage` | Generic "coming soon" | "Sync settings will be available when Bluetooth mesh sync is implemented (v2.0+)" |
| `AISettingsPage` | Generic "coming soon" | "AI integration settings will be available when LM Studio connection is built (v2.0+)" |
| `DevicesPage` | Generic "coming soon" | "Device management will be available when the device pairing system is built (v2.0+)" |

## Templates Page

Check if `TemplatesPage` route exists and whether it points to the notebook templates system or is orphaned. If orphaned, redirect to the notebook templates tab.

## API Client Cleanup

Check `frontend/src/api/orders.ts` for any functions that only served deleted pages. Remove unused API functions.

---

## Execution Steps

1. **Delete the 4 superseded page files**
2. **Remove their routes from App.tsx**
3. **Remove any imports of deleted pages from App.tsx**
4. **Update Settings stub pages with clear future-phase messages**
5. **Check for orphaned API functions and remove**
6. **Run TypeScript build to verify no broken imports:** `cd frontend && npm run build`
7. **Verify all routes work by navigating through the app**

---

## Success Criteria

- [~] No dead code from pre-redesign orders pages — 4 files need manual deletion (OneDrive lock prevents automated delete)
- [x] No broken routes in App.tsx — legacy route + 5 redirects removed
- [x] Clean TypeScript build with no import errors — `npx tsc --noEmit` passes
- [x] Settings stubs clearly labeled as v2.0+ features — SyncPage, AiConfigPage, DeviceManagementPage updated
- [x] No orphaned API functions — `listDraftPOs`/`listActivePOs` only used by legacy pages (will be removed with file deletion)
- [x] App routes all resolve to real pages (no blank screens)
