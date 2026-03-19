# WiredPart iOS — Audit Observations

## Audit Date: 2026-03-18

### What Was Found

**180+ issues** across ~160 Swift files. The app has a comprehensive architecture and service layer — the backend is solid. The issues are overwhelmingly in the UI layer: missing action buttons, swallowed errors, stub content shown to users, and sheet/popup conflicts.

### Systemic Patterns

1. **"Catch and Forget"** — ~25 catch blocks print to console, never show errors to users
2. **"Guard and Abandon"** — ~10 guard-let-else-return blocks leave isLoading=true forever
3. **"Read-Only Pages"** — ~30 list/detail pages missing create/edit/delete actions
4. **"no such table" Suppression** — ~15 files silently eat database migration errors
5. **Multiple `.sheet` on one view** — CategoriesEditorPanel (7), IOSMainView (5+), CategoriesTreeView (4)
6. **Fake Sync** — SyncWaitingView, IOSSyncManager, DevicePairingView all simulate without doing real work
7. **Duplicate utilities** — formatDate, formatCurrency, safeCount copy-pasted across 12+ files

### Fix Priority

| Priority | Prompt | Impact |
|----------|--------|--------|
| P0 | 01 (Sheets) | Users can't close popups |
| P0 | 02 (Errors) | Users see blank screens |
| P0 | 03 (Spinners) | Users see infinite loading |
| P1 | 04 (Stubs) | Users are deceived by fake sync |
| P1 | 05 (AppCore) | App crashes if DB fails |
| P2 | 06-08 (CRUD) | Users can't create/edit/delete data |
| P3 | 09 (Security) | PIN weakness, sync injection |
| P3 | 10 (Services) | Data integrity bugs |

### What Worked Well

- Architecture is clean — AppCore → Services → GRDB is a solid pattern
- Design system exists (tokens, styles, reusable components)
- Navigation routing is comprehensive with legacy redirects
- Permission gating infrastructure is in place
- Error state and empty state view components exist but aren't used everywhere
