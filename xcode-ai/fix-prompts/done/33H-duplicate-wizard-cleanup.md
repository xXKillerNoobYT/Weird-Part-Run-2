# 33H — Delete Duplicate Movement Wizard

> **Chain position:** **33H** (standalone)
> **Log file:** `xcode-ai/prompt-results-log.md`

## Context

WarehouseMovementsPage.swift has an INLINE movement wizard (~600 lines) that duplicates the separate IOSMovementWizard.swift file. The plan says: delete the inline one, keep the separate file, make sure the separate file has all the rules.

## Task

1. Read BOTH: the inline wizard in WarehouseMovementsPage.swift AND IOSMovementWizard.swift
2. Compare — make sure IOSMovementWizard has everything the inline one has
3. If the inline one has features the separate file doesn't, MOVE those features to the separate file
4. Delete the inline wizard code from WarehouseMovementsPage.swift
5. Make WarehouseMovementsPage present IOSMovementWizard via ActiveSheet

## Success Criteria

- [ ] Only ONE movement wizard exists (IOSMovementWizard.swift)
- [ ] WarehouseMovementsPage uses the external wizard via sheet
- [ ] No feature regression — all wizard features preserved
- [ ] File size of WarehouseMovementsPage reduced significantly
- [ ] Project builds with no errors
