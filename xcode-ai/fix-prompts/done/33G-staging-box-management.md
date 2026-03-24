# 33G — Staging Box Management

> **Chain position:** **33G** (standalone)
> **Log file:** `xcode-ai/prompt-results-log.md`

## Context

Staging needs physical box management for job prepping. Boxes are PHYSICAL (real boxes with handwritten labels), not just digital grouping.

**Box system:**
- 3 sizes: Small, Normal, Large
- Label guidance: shows EXACTLY what to write (JobName short + box number)
- Box number auto-increments per job: 0412-01, 0412-02
- Mark box as Full → system auto-creates next box
- Visual: full boxes show ✅, open boxes show ◑
- Loose parts default to boxing (unless can't-box per-part/per-category flag)
- Parts that can't be grouped (size, storage setting) stay separate

**Box rules:**
- An area may have several jobs (try not to mix but sometimes necessary)
- A job may be in several areas
- No "clearing" — it's moving parts IN/OUT of staging

## Files to Modify

- `Weird Parts IOS/Weird Parts IOS/Features/Warehouse/IOSStagingPage.swift`
- `core/Sources/WiredPartCore/Services/WarehouseService.swift` (box CRUD)
- `core/Sources/WiredPartCore/Database/AppDatabase+Migrations.swift` (staging_boxes table)

## Task

### Migration: staging_boxes table
```sql
CREATE TABLE staging_boxes (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    job_id INTEGER NOT NULL REFERENCES jobs(id),
    box_number TEXT NOT NULL,        -- "0412-01"
    box_size TEXT NOT NULL DEFAULT 'normal',  -- small/normal/large
    label_text TEXT NOT NULL,         -- "SMITH RES 0412-01"
    is_full INTEGER NOT NULL DEFAULT 0,
    area_id INTEGER,                  -- optional staging area
    created_at TEXT DEFAULT (datetime('now')),
    deleted_at TEXT
);
```

### UI: Box management on staging page
- Create box: pick job, pick size, auto-generate label text + number
- View box contents (list of parts inside)
- Mark box as full/open toggle
- Move box out (to truck) → creates movement for all parts inside
- Add parts to box from receiving/shelf pull

## Success Criteria

- [ ] staging_boxes table created
- [ ] Box creation with size picker and auto-generated labels
- [ ] Label guidance showing exactly what to write on the physical box
- [ ] Full/Open toggle with visual indicators
- [ ] Box contents view
- [ ] Move box out creates movement for all contained parts
- [ ] Project builds with no errors
