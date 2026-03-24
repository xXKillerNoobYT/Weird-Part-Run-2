# 28C — Procurement: PO Preview + Generation

> **Chain position:** 28A → 28B → **28C** → 28D
> **Prerequisite:** 28B complete (supplier selection)
> **Plan:** `docs/plans/ios-procurement-page.md` — PO Preview + Partial Generation

## Instructions

Read 28B results and the plan. When done, wait for user confirmation.

## Task

Add a "Ready to Generate" section at the bottom of the procurement page that shows a preview of what POs will be created. Grouped by supplier, then by job within each supplier. Shows part count, total cost, and number of POs.

1. **Preview section** — appears when any parts have suppliers selected. Shows: "Will create X POs" with breakdown by supplier. Each supplier group shows jobs and parts.
2. **[Generate X POs]** button — creates draft POs grouped by supplier. Each PO gets line items from the selected parts. Links back to JPO line items via `po_line_id`. Updates JPO line status to `in_procurement`.
3. **[Save for Later]** button — keeps selections but doesn't generate. Items stay in procurement for next batch.
4. **Partial generation** — user can deselect some parts (via checkboxes) to exclude from this batch. Only parts with both supplier selected AND checkbox checked get generated.
5. **Add service method** `generatePOsFromProcurement(items: [(partId, supplierId, qty, jpoLineIds)])` that creates draft POs grouped by supplier.

## Success Criteria

- [ ] Preview section shows PO breakdown by supplier
- [ ] Generate button creates draft POs grouped by supplier
- [ ] JPO line items get `po_line_id` set and status → `in_procurement`
- [ ] Save for Later keeps state without generating
- [ ] Partial generation via checkboxes
- [ ] Project builds with no errors

**Wait for user confirmation before proceeding to prompt 28D.**
