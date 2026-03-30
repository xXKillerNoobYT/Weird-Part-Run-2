# 36A — Warehouse Floor Plan: Migration + Models

> **Chain position:** **36A** → 36B → 36C → 36D
> **Log file:** `xcode-ai/prompt-results-log.md`

## MANDATORY RULES
1. DO NOT use `import GRDB` in UI files
2. DO NOT use empty `catch { }` blocks
3. DO NOT use `#if os(iOS)` guards

## Context

The warehouse locations page needs a full floor plan system with storage hierarchy. This prompt creates the database tables and models. See `docs/plans/ios-warehouse-pages.md` (Locations section) and `docs/plans/warehouse-audit-intelligence.md` for full design.

## Task

### Migration: warehouse_floor_plans
```sql
CREATE TABLE warehouse_floor_plans (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    name TEXT NOT NULL,
    width_inches INTEGER NOT NULL,
    length_inches INTEGER NOT NULL,
    is_active INTEGER NOT NULL DEFAULT 1,
    created_at TEXT DEFAULT (datetime('now')),
    updated_at TEXT DEFAULT (datetime('now')),
    deleted_at TEXT
);
```

### Migration: warehouse_floor_features
Non-storage zones placed on the grid (doors, walkways, office, staging area, etc.)
```sql
CREATE TABLE warehouse_floor_features (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    floor_plan_id INTEGER NOT NULL REFERENCES warehouse_floor_plans(id) ON DELETE CASCADE,
    feature_type TEXT NOT NULL,  -- 'door', 'loading_dock', 'walkway', 'office', 'bathroom', 'electrical_panel', 'staging', 'incoming', 'returns', 'custom'
    label TEXT,
    grid_x INTEGER NOT NULL,
    grid_y INTEGER NOT NULL,
    grid_width INTEGER NOT NULL DEFAULT 1,
    grid_height INTEGER NOT NULL DEFAULT 1,
    rotation INTEGER NOT NULL DEFAULT 0,  -- 0, 90, 180, 270
    created_at TEXT DEFAULT (datetime('now')),
    deleted_at TEXT
);
```

### Migration: warehouse_storage_units
Physical storage devices placed on the floor plan.
```sql
CREATE TABLE warehouse_storage_units (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    floor_plan_id INTEGER NOT NULL REFERENCES warehouse_floor_plans(id) ON DELETE CASCADE,
    name TEXT NOT NULL,
    unit_type TEXT NOT NULL,  -- 'shelving', 'pipe_rack', 'gang_box', 'pallet_rack', 'wall_mount', 'cabinet', 'packout', 'tool_bag', 'parts_bin', 'crate', 'floor_area'
    row_number TEXT,  -- 'R01', 'R02', etc.
    unit_number TEXT, -- 'U01', 'U02', etc.
    width_inches INTEGER,
    depth_inches INTEGER,
    height_inches INTEGER,
    grid_x INTEGER,
    grid_y INTEGER,
    grid_width INTEGER DEFAULT 1,
    grid_height INTEGER DEFAULT 1,
    rotation INTEGER NOT NULL DEFAULT 0,
    front_face TEXT DEFAULT 'south',  -- which direction faces the walkway
    is_movable INTEGER NOT NULL DEFAULT 0,
    is_job_ready INTEGER NOT NULL DEFAULT 0,  -- packouts, kits = always job-ready
    home_area_id INTEGER,  -- for movable units with a home location
    current_location_type TEXT,  -- 'warehouse', 'truck', 'trailer', 'job'
    current_location_id INTEGER,
    assigned_to INTEGER REFERENCES users(id),
    is_configured INTEGER NOT NULL DEFAULT 0,  -- levels/areas set up?
    created_at TEXT DEFAULT (datetime('now')),
    updated_at TEXT DEFAULT (datetime('now')),
    deleted_at TEXT
);
```

### Migration: warehouse_storage_levels
Levels within a storage unit (shelves, trays, tiers, drawers).
```sql
CREATE TABLE warehouse_storage_levels (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    unit_id INTEGER NOT NULL REFERENCES warehouse_storage_units(id) ON DELETE CASCADE,
    level_code TEXT NOT NULL,  -- 'G0', 'S01', 'S02', 'ST', 'T1', 'D1', 'M1'
    level_name TEXT,  -- 'Ground Zero', 'Shelf 1', 'Top', 'Tray 1', 'Drawer 1', 'Module 1'
    level_order INTEGER NOT NULL DEFAULT 0,  -- sort order bottom to top
    height_inches INTEGER,
    area_count INTEGER NOT NULL DEFAULT 1,
    created_at TEXT DEFAULT (datetime('now')),
    deleted_at TEXT
);
```

### Migration: warehouse_storage_areas
Individual areas within a level. This is where parts actually live.
```sql
CREATE TABLE warehouse_storage_areas (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    level_id INTEGER NOT NULL REFERENCES warehouse_storage_levels(id) ON DELETE CASCADE,
    area_code TEXT NOT NULL,  -- 'A01', 'A02', 'B01' (for bins in gang box trays)
    area_number INTEGER NOT NULL,
    width_inches INTEGER,
    has_qr_code INTEGER NOT NULL DEFAULT 0,
    has_sticker INTEGER NOT NULL DEFAULT 0,
    full_location_code TEXT,  -- auto-generated: 'R01-U01-S02-A04'
    created_at TEXT DEFAULT (datetime('now')),
    deleted_at TEXT
);
```

### Migration: warehouse_bins
Optional bins within areas. One part type per bin.
```sql
CREATE TABLE warehouse_bins (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    area_id INTEGER NOT NULL REFERENCES warehouse_storage_areas(id) ON DELETE CASCADE,
    bin_code TEXT NOT NULL,  -- 'B01', 'B02'
    bin_number INTEGER NOT NULL,
    is_fixed INTEGER NOT NULL DEFAULT 0,  -- fixed bins can't be moved
    assigned_part_id INTEGER REFERENCES parts(id),
    created_at TEXT DEFAULT (datetime('now')),
    deleted_at TEXT
);
```

### Migration: warehouse_part_assignments
Links parts to their home area (not bin — bins are optional subdivision).
```sql
CREATE TABLE warehouse_part_assignments (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    part_id INTEGER NOT NULL REFERENCES parts(id) ON DELETE CASCADE,
    area_id INTEGER NOT NULL REFERENCES warehouse_storage_areas(id) ON DELETE CASCADE,
    is_home INTEGER NOT NULL DEFAULT 0,  -- this is the part's HOME area
    created_at TEXT DEFAULT (datetime('now')),
    deleted_at TEXT,
    UNIQUE(part_id, area_id)
);
```

### Models

Create Swift model structs for each table with proper CodingKeys, Sendable, FetchableRecord, MutablePersistableRecord.

### Service Methods

Add to WarehouseService:
- `createFloorPlan(name:widthInches:lengthInches:)` → FloorPlan
- `getFloorPlan(id:)` → FloorPlan?
- `listFloorPlans()` → [FloorPlan]
- `addFloorFeature(...)` → FloorFeature
- `addStorageUnit(...)` → StorageUnit
- `updateStorageUnit(id:...)` → updates
- `deleteStorageUnit(id:)` → soft delete
- `addStorageLevel(unitId:levelCode:levelName:order:areaCount:)` → Level
- `listLevelsForUnit(unitId:)` → [Level]
- `addStorageArea(levelId:areaNumber:widthInches:)` → Area
- `listAreasForLevel(levelId:)` → [Area]
- `addBin(areaId:binNumber:isFixed:)` → Bin
- `assignPartToArea(partId:areaId:isHome:)` → Assignment
- `getPartAssignments(partId:)` → [Assignment with area info]
- `getAreaContents(areaId:)` → parts + bins + checked-out items
- `generateFullLocationCode(areaId:)` → String (R01-U01-S02-A04)

### ConflictResolver
Add all new tables to the whitelist.

## Success Criteria
- [ ] 7 new tables created in migration
- [ ] 7 model structs with proper CodingKeys
- [ ] 15+ service methods for CRUD
- [ ] ConflictResolver updated
- [ ] Project builds with no errors
