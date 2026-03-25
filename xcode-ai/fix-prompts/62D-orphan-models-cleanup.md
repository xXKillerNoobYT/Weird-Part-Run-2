# 62D — Review and Clean Up 9 Orphan Model Structs in CostsModels.swift
> Chain position: Standalone

## Task

`core/Sources/WiredPartCore/Models/Costs/CostsModels.swift` contains model structs that may not be used by any service method. Review each of the following 9 structs and determine whether any service actually queries/inserts/updates their table. If no service references the table, the struct is dead code — remove it. If the table is referenced in raw SQL but no typed model is used, leave the struct (it may be needed later).

### Structs to audit:

1. **`ReportAnnotation`** (table: `report_annotations`) — Check if `ReportsService` has methods that read/write report annotations.
2. **`ReportShareToken`** (table: `report_share_tokens`) — Check if any service generates or validates share tokens.
3. **`ReportTemplate`** (table: `report_templates`) — Check if `ReportsService` or `SettingsService` manages report templates.
4. **`PTOPolicy`** (table: `pto_policies`) — Check if `SchedulingService` or `PeopleService` manages PTO policies.
5. **`PTOBalance`** (table: `pto_balances`) — Check if any service tracks PTO balances.
6. **`SupplierPortalToken`** (table: `supplier_portal_tokens`) — Check if `OrdersService` or `PartsService` manages supplier portal tokens.
7. **`SupplierContactRating`** (table: `supplier_contact_ratings`) — Check if any service reads/writes supplier contact ratings.
8. **`POConversation`** (table: `po_conversations`) — Check if `OrdersService` manages PO conversation entries.
9. **`POGroup`** / **`POGroupMember`** (tables: `po_groups`, `po_group_members`) — Check if `OrdersService` has PO grouping methods.

### How to audit each struct:

1. Search ALL service files (`core/Sources/WiredPartCore/Services/*.swift`) for references to the table name (e.g., `"report_annotations"`, `"report_share_tokens"`).
2. Search for references to the struct type name (e.g., `ReportAnnotation`, `ReportShareToken`).
3. If NEITHER the table name NOR the struct type appears in any service: **remove the struct from CostsModels.swift**.
4. If the table name appears in raw SQL queries but the struct type is not used: **keep the struct** — add a comment `// Used by: [ServiceName].[methodName] (raw SQL)`.
5. If the struct type is used directly (e.g., `ReportTemplate.fetchAll()`): **keep it** — add a comment `// Used by: [ServiceName].[methodName]`.

### After the audit:

- Remove all confirmed dead-code structs.
- For surviving structs, add a `// Used by:` comment on the `MARK` line.
- If you remove 3+ structs, also check if any migration creates those tables — leave the migration alone (tables might be needed for future features), but note in a comment at the top of CostsModels.swift which structs were removed and why.

## Files to Modify

- `core/Sources/WiredPartCore/Models/Costs/CostsModels.swift` — remove dead structs, annotate surviving ones
- Search (read-only): all files in `core/Sources/WiredPartCore/Services/`

## Success Criteria
- [ ] Every struct in CostsModels.swift is either confirmed used (with a `// Used by:` comment) or removed
- [ ] No compile errors after removal
- [ ] No service method references a removed struct type
- [ ] Migrations are NOT modified (only model definitions)
