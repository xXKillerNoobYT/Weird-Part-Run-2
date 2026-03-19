# Fix Prompt Order — WiredPart iOS Audit Fixes

Run these prompts in order. Each one ends with "start prompt N next" so you can chain them.

| # | Area | What It Fixes (User Perspective) | Status |
|---|------|--------------------------------|--------|
| 01 | Sheet/Popup Dismissal | Popups don't close properly, stale data after closing forms | DONE |
| 02 | Error Visibility | User sees blank screens instead of error messages | NEXT |
| 03 | Infinite Spinners | Pages get stuck on loading spinner forever | |
| 04 | Stub Sync & Placeholders | Fake sync fools users, visible "Phase X" placeholder text | |
| 05 | AppCore Safety | App can crash on launch if database fails | |
| 06 | Missing CRUD — Jobs & People | Can't add/edit employees, customers; job tabs show placeholder text | |
| 07 | Missing CRUD — Orders & Warehouse | Can't add line items to orders, no receive workflow, no audit start | |
| 08 | Missing CRUD — Scheduling & Chat | Can't approve time-off, can't create chat channels | |
| 09 | Security Hardening | PIN hashing is weak, invalid tokens treated as valid | |
| 10 | Service Layer Bugs | Wrong table names, missing columns, broken counts | |
| 11A | Brand-Supplier Service | Add link/unlink methods to PartsService | |
| 11B | Brand Detail Sheet | Brand detail view with supplier list | |
| 11C | Brand Supplier Picker | Checkbox picker for managing brand-supplier links | |
| 12A | Dashboard Nav Changes | Add 4 Dashboard tabs, remove Clock from Jobs | |
| 12B | Clock Status Banner | Show clock-in status on Dashboard Overview | |
| 12C | Inline Clock + GPS Jobs | GPS-sorted job picker, shop/optional job link | |
| 12D | GPS Geofencing | Auto-detect job transitions, lock until answered | |
| 12E | Enhanced Daily Report | My hours, team status, fast actions | |
| 12F | Fast QR Scanner | Continuous camera scan with lock/auto-lock | |

## Prompt 01 Results (2026-03-18)

- 7 files fixed for multiple `.sheet` conflicts -> single `.sheet(item:)` enum pattern
- 3 files fixed for missing data reload on dismiss -> `.onChange` pattern
- 1 supporting change: TypeBrandColorSection binding -> closure for new enum pattern
- 6 files already had correct callbacks — no changes needed
- Build: SUCCESS
