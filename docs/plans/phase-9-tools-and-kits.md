# Phase 9: Tools & Kits — Implementation Plan

> **Date:** 2026-03-05
> **Status:** Complete
> **Scope:** Tool registry, kit verification checklists, checkout/return flow, maintenance tracking, cross-module visibility (warehouse, trucks, jobs)
> **Follows:** Phase 8 (People Full) — complete

See `.claude/plans/snappy-splashing-flute.md` for the full detailed plan.

## Summary

8 new database tables, ~25 API endpoints, 2 page rewrites + job integration + dashboard card update.

### Key Features
1. **Tool Registry** — individual tracked assets with categories, serial numbers, condition ratings
2. **Movement Tracking** — immutable audit log for every checkout/return/transfer
3. **Kit Verification** — checklist flow ensuring chargers, batteries, bits, etc. travel with the tool
4. **Maintenance Tracking** — calibration, blade replacement, safety inspection scheduling
5. **QR Code Scanning** — fast lookup, checkout, and return via QR labels
6. **Cross-Module Visibility** — tools show on warehouse dashboard, truck tools page, job detail

### New Files
- `backend/app/migrations/024_tools_and_kits.sql`
- `backend/app/models/tools.py`
- `backend/app/repositories/tools_repo.py`
- `backend/app/services/tools_service.py`
- `backend/app/routers/tools.py`
- `frontend/src/api/tools.ts`
- `frontend/src/features/tools/components/ToolScanRedirect.tsx`

### Modified Files
- `backend/app/main.py` — register tools router
- `frontend/src/lib/types.ts` — ~20 new interfaces
- `frontend/src/lib/navigation.ts` — add `view_tools` permission gates
- `frontend/src/App.tsx` — add QR scan route
- `frontend/src/features/warehouse/pages/ToolsPage.tsx` — full rewrite
- `frontend/src/features/trucks/pages/ToolsPage.tsx` — full rewrite
- `frontend/src/features/jobs/pages/JobDetailPage.tsx` — add tools sub-tab
- `frontend/src/features/warehouse/pages/WarehouseDashboardPage.tsx` — live summary card
