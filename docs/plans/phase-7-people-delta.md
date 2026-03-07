# Phase 7: People (Full) — Delta Addendum

> **Date:** 2026-03-07
> **Status:** ✅ Complete
> **Context:** Phase 7 (People Full) is built and functional. This addendum adds two naming convention features that weren't in the original scope but are needed before V1.0.
> **Estimated work:** < 1 day
> **Previous plans:** `phase-8-people-full.md`, `phase-10-people-contacts-scheduling.md`

---

## 1. PO Naming Convention — GC-Aware Format

### Problem

Current PO numbers are simple sequential: `PO-0001`, `PO-0002`, etc. (see `orders_repo.py` line 236–242).

When a General Contractor (GC) hires us, POs should carry the GC's code and the job ID so they're instantly identifiable on both sides. The convention is:

```
PO=[GC_CODE]+[Job ID]+[Order Number]
```

**Example:** `PO=TURNER+J-042+003` → Turner Construction, Job J-042, 3rd PO for that job.

### When It Applies

- **GC-attached jobs only** — where the job has a `gc_contact_id` and the contact's relationship is `they_are_gc` (they hired us, we're the sub)
- **Non-GC jobs** — keep existing `PO-NNNN` format unchanged
- **Warehouse restocks** — keep existing `PO-NNNN` format unchanged

### Backend Changes

#### `backend/app/repositories/orders_repo.py` — `get_next_po_number()`

```python
async def get_next_po_number(self, job_id: int | None = None) -> str:
    """Generate the next PO number.
    
    GC-attached jobs: 'PO=<GC_CODE>+<JOB_NUMBER>+<SEQ>'
    Other jobs/warehouse: 'PO-NNNN' (global sequential)
    """
    if job_id:
        # Check if job has a GC contact
        gc = await self.db.execute_fetchone("""
            SELECT c.company_name, c.company_code, j.job_number
            FROM jobs j
            JOIN contacts c ON c.id = j.gc_contact_id
            WHERE j.id = ? AND j.gc_contact_id IS NOT NULL
              AND c.relationship = 'they_are_gc'
        """, (job_id,))
        
        if gc:
            gc_code = (gc["company_code"] or gc["company_name"][:8]).upper().replace(" ", "")
            job_num = gc["job_number"]
            # Count existing POs for this job
            seq = await self.db.execute_fetchone(
                "SELECT COUNT(*) as cnt FROM purchase_orders WHERE job_id = ?",
                (job_id,)
            )
            return f"PO={gc_code}+{job_num}+{(seq['cnt'] or 0) + 1:03d}"
    
    # Fallback: global sequential for non-GC or warehouse
    seq = await self.db.execute_fetchone(
        "SELECT COUNT(*) as cnt FROM purchase_orders WHERE job_id IS NULL OR job_id NOT IN (SELECT id FROM jobs WHERE gc_contact_id IS NOT NULL)"
    )
    return f"PO-{(seq['cnt'] or 0) + 1:04d}"
```

#### Contacts Table — Add `company_code` Column

If not already present, add a short code field for GC identification:

```sql
-- Migration 028 or inline
ALTER TABLE contacts ADD COLUMN company_code TEXT;
-- e.g. 'TURNER', 'MCCARTHY', 'SKANSKA'
```

The `company_code` is a short identifier (3–10 chars) set when creating a GC contact. Falls back to first 8 chars of `company_name` if not set.

### Frontend Changes

- **Contact form:** Add optional "Company Code" field (shown when relationship = `they_are_gc`), with placeholder "e.g. TURNER"
- **PO display:** No changes needed — PO numbers already displayed as strings everywhere
- **JPO → PO conversion:** When the office creates a PO from a JPO for a GC job, the auto-generated number follows the new format

### Validation

- GC code: uppercase alphanumeric, 2–10 chars
- The full PO number must be unique (already enforced by UNIQUE constraint)
- If a GC contact is removed from a job, existing POs keep their numbers

---

## 2. Time Report Naming Convention

### Problem

Time reports / timesheets need consistent naming for file exports and display. Currently, there's no naming convention — exports just get generic filenames.

### Convention

```
Timesheet-[Employee Name]-[Period Start]-[Period End].[ext]
```

**Examples:**
- `Timesheet-Roy-2026-02-24-2026-03-01.csv`
- `Timesheet-Roy-2026-02-24-2026-03-01.pdf`
- `Timesheet-AllEmployees-2026-02-01-2026-02-28.csv`

For Pre-Billing reports:
```
PreBilling-[Job Number]-[Period Start]-[Period End].[ext]
```

**Examples:**
- `PreBilling-J-001-2026-02-01-2026-02-28.pdf`
- `PreBilling-AllJobs-2026-02-01-2026-02-28.csv`

For Labor Overview:
```
LaborOverview-[Period Start]-[Period End].[ext]
```

For Profitability:
```
Profitability-[Period Start]-[Period End].[ext]
```

For Bookkeeper Exports:
```
Bookkeeper-[Format]-[Period Start]-[Period End].[ext]
```
**Examples:**
- `Bookkeeper-QuickBooks-2026-02-01-2026-02-28.iif`
- `Bookkeeper-GeneralLedger-2026-02-01-2026-02-28.csv`
- `Bookkeeper-Payroll-2026-02-24-2026-03-01.csv`

### Backend Changes

Add a utility function in `report_service.py`:

```python
def generate_report_filename(
    report_type: str,       # "timesheet", "pre-billing", "labor-overview", "profitability", "bookkeeper"
    period_start: str,
    period_end: str,
    format: str,            # "csv", "pdf", "iif"
    subject: str = None,    # Employee name, job number, or format name
) -> str:
    """Generate a standardized report filename."""
    type_map = {
        "timesheet": "Timesheet",
        "pre-billing": "PreBilling",
        "labor-overview": "LaborOverview",
        "profitability": "Profitability",
        "bookkeeper": "Bookkeeper",
    }
    prefix = type_map.get(report_type, report_type)
    subject_part = f"-{subject}" if subject else ""
    return f"{prefix}{subject_part}-{period_start}-{period_end}.{format}"
```

The export endpoints should use this function for the `Content-Disposition` header filename.

### Frontend Changes

- Export buttons should show the generated filename as a preview before download
- "Recent Exports" list on ExportsPage should show these formatted names

---

## Success Criteria

- [x] GC-attached job POs generate as `{GC_CODE}-{JOB_ID}-{SEQ}` (e.g. `SMITH-42-001`)
- [x] Non-GC job POs continue to generate as `PO-NNNN`
- [x] GC form has `gc_code` field (ContractorsPage create + ContractorDetailPage edit)
- [x] All report exports use standardized naming convention via `format_report_filename()`
- [x] Export filenames include employee/job name, date range, and format extension
- [x] Existing PO numbers are not retroactively changed

---

## Execution Order

1. Add `company_code` column to contacts table (migration)
2. Update `get_next_po_number()` in `orders_repo.py` with GC-aware logic
3. Add `generate_report_filename()` utility to `report_service.py`
4. Update export endpoints to use filename utility in Content-Disposition headers
5. Update Contact form UI to show Company Code field for GC contacts
6. Test PO generation for GC vs non-GC jobs
7. Test export filenames across all report types
