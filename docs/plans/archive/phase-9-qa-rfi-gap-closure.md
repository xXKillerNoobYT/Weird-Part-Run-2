# Phase 9 Q&A/RFI Gap Closure

> **Date:** 2026-03-07
> **Status:** ✅ Complete
> **Scope:** Fully align Q&A Board + RFI bridge with concept doc `docs/plans/Q&A Part of the App`
> **Reason:** Phase 9 was marked complete, but 6 functional gaps remained in thread/RFI integration and office workflow UX.

---

## Context

The concept document requires:

1. One internal Q&A escalation chain (Worker → Lead → Foreman → Supervisor → Office)
2. Office decision node: **Send to GC**
3. External GC responses must be written back to the **same internal Q&A thread**
4. Q&A thread detail should show external RFI status/context

Audit found these gaps were not fully wired in the shipped UI/backend flow.

---

## Plan (What was closed)

### 1) Fix backend GC contact joins (critical)
- Replace invalid `contacts` references with `entity_contacts` + `general_contractors` joins in Q&A/RFI repository/service code.

### 2) Write external answers back into internal thread
- Enhance `QAService.update_rfi()` so `response_text` inserts a `qa_answer` message in original thread, adds system audit message, marks thread answered, and notifies original asker.

### 3) Include linked RFI in thread detail
- Extend `get_thread_detail()` to return linked RFI object.
- Extend API response models and frontend types accordingly.

### 4) Add missing Office “Send to GC” UX
- Add send mutation + button in QABoardPage.
- Add office-only inline picker flow: Job GC → GC Contact → method (SMS/Email) → send.

### 5) Fix status mapping mismatch
- Replace stale frontend status key `rfi_sent` with DB/API truth key `sent_to_gc`.

### 6) Add RFI status card in thread detail
- Show RFI metadata + status + channel + GC response directly in thread view.

---

## Implementation Summary

### Backend

- **`backend/app/repositories/qa_repo.py`**
  - Updated RFI detail joins to use:
    - `entity_contacts` for contact data
    - `general_contractors` for GC company name
  - Added:
    - `get_rfi_for_thread(qa_thread_id)`
    - `get_rfi_with_thread(rfi_id)`

- **`backend/app/services/qa_service.py`**
  - `send_to_gc()` now reads GC contact info via `entity_contacts`/`general_contractors`.
  - `update_rfi()` now:
    - updates RFI status
    - injects external response into original thread as `qa_answer`
    - adds audit/system message
    - marks thread `answered`
    - notifies asker
  - `get_thread_detail()` now includes `rfi` payload.

- **`backend/app/routers/chat.py`**
  - PATCH `/chat/rfis/{rfi_id}` now passes `updated_by=user["id"]` to service for attribution.

- **`backend/app/models/chat.py`**
  - `QAThreadDetailResponse` now includes optional `rfi: RFIResponse | None`.

### Frontend

- **`frontend/src/lib/types.ts`**
  - `QAThreadDetailResponse` now includes `rfi?: RFIResponse | null`.

- **`frontend/src/features/chat/pages/QABoardPage.tsx`**
  - Fixed status key to `sent_to_gc` (badge + filter option).
  - Added `sendToGC` mutation and office permission/path gating.
  - Added inline **Send to GC** flow:
    - fetch job-linked GCs
    - fetch selected GC contacts
    - choose SMS/Email channel
    - submit RFI
  - Added `RFIInfoCard` in thread detail showing:
    - RFI status badge
    - GC company/contact links
    - sent channel/timestamp
    - GC response text and response timestamp

---

## Verification

- Backend smoke validation executed:
  - `tests/test_base_repo.py` → **33 passed**
- Editor diagnostics:
  - Updated Q&A files → **0 TypeScript errors**
- Frontend build:
  - `npx vite build` run succeeded after JSX fix in QABoardPage

---

## Result

Q&A workflow now matches the concept doc end-to-end:

- Office has explicit send-to-GC decision point
- GC responses are written back into original internal thread
- Thread detail includes RFI state/response visibility
- Status keys are consistent across DB/API/UI (`sent_to_gc`)

This closes the known Phase 9 Q&A/RFI functional gaps for V1.
