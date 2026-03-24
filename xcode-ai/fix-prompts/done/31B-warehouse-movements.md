# 31B — Warehouse Movements: Service Layer + ActiveSheet

> **Plan:** `docs/plans/ios-warehouse-pages.md`

## Instructions

Read the file first, then fix all issues. When done, wait for user confirmation.

## Context

The movements page imports GRDB and uses raw SQL. It uses `sheet(isPresented:)` instead of ActiveSheet pattern. Has platform guard.

**Files to modify:**
- `Weird Parts IOS/Weird Parts IOS/Features/Warehouse/WarehouseMovementsPage.swift`

## Task

1. **Remove `import GRDB`** — replace all raw SQL with WarehouseService method calls
2. **Replace `sheet(isPresented:)` + `fullScreenCover`** with single ActiveSheet enum:
   ```swift
   private enum ActiveSheet: Identifiable {
       case movementDetail(Int64)
       case newMovement
       case qrScanner
       var id: String { String(describing: self) }
   }
   ```
3. **Remove `#if os(iOS)` platform guard**
4. **Add smart card filters** — replace segmented filter (All/Transfers/Returns) with smart cards showing counts
5. **Deduplicate icon/color helpers** — if they duplicate Dashboard helpers, extract to a shared extension or keep as local but don't import from Dashboard

## Success Criteria

- [ ] `import GRDB` removed
- [ ] ActiveSheet pattern with single `.sheet(item:)`
- [ ] Platform guard removed
- [ ] Smart card filters replace segmented control
- [ ] Project builds with no errors

**Wait for user confirmation before proceeding to prompt 31C.**
