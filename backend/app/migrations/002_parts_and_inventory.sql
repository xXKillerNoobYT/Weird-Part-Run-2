-- =============================================================
-- MIGRATION 002: Parts & Inventory (Hierarchical Variant System)
-- =============================================================
-- Parts follow a real-world electrical industry hierarchy:
--   Category → Style → Type → Color = one orderable variant
--
-- Key design decisions:
--   1. Lookup tables (categories, styles, types, colors) define the hierarchy
--   2. parts table = orderable variants (each row = one SKU)
--   3. General parts: no brand/code required, just hierarchy position
--   4. Branded parts: need part number per combo (may be "pending")
--   5. company_sell_price is a GENERATED column (auto-calculated)
--   6. stock uses location_type + location_id for polymorphic locations
--   7. stock_movements preserves the supplier chain on every move
--   8. brand_supplier_links tracks which suppliers carry which brands
-- =============================================================


-- ─── PART CATEGORIES ────────────────────────────────────────
-- Top-level grouping: Outlet, Switch, Wire, Breaker, etc.
-- Every part belongs to exactly one category.
CREATE TABLE IF NOT EXISTS part_categories (
    id          INTEGER PRIMARY KEY AUTOINCREMENT,
    name        TEXT    NOT NULL UNIQUE,
    description TEXT,
    sort_order  INTEGER DEFAULT 0,
    is_active   INTEGER DEFAULT 1,
    created_at  TEXT    DEFAULT (datetime('now')),
    updated_at  TEXT    DEFAULT (datetime('now'))
);

CREATE INDEX IF NOT EXISTS idx_categories_name ON part_categories(name);


-- ─── PART STYLES ────────────────────────────────────────────
-- Per-category visual/form-factor style: Decora, Traditional, etc.
-- Scoped to a specific category. Not every category has styles
-- (e.g., Wire may not need styles).
CREATE TABLE IF NOT EXISTS part_styles (
    id          INTEGER PRIMARY KEY AUTOINCREMENT,
    category_id INTEGER NOT NULL REFERENCES part_categories(id) ON DELETE CASCADE,
    name        TEXT    NOT NULL,
    description TEXT,
    sort_order  INTEGER DEFAULT 0,
    is_active   INTEGER DEFAULT 1,
    created_at  TEXT    DEFAULT (datetime('now')),
    updated_at  TEXT    DEFAULT (datetime('now')),
    UNIQUE(category_id, name)
);

CREATE INDEX IF NOT EXISTS idx_styles_category ON part_styles(category_id);


-- ─── PART TYPES ─────────────────────────────────────────────
-- Per-style functional variety: GFI, Tamper Resistant, Standard, etc.
-- Scoped to a specific style (which implicitly scopes to category).
CREATE TABLE IF NOT EXISTS part_types (
    id          INTEGER PRIMARY KEY AUTOINCREMENT,
    style_id    INTEGER NOT NULL REFERENCES part_styles(id) ON DELETE CASCADE,
    name        TEXT    NOT NULL,
    description TEXT,
    sort_order  INTEGER DEFAULT 0,
    is_active   INTEGER DEFAULT 1,
    created_at  TEXT    DEFAULT (datetime('now')),
    updated_at  TEXT    DEFAULT (datetime('now')),
    UNIQUE(style_id, name)
);

CREATE INDEX IF NOT EXISTS idx_types_style ON part_types(style_id);


-- ─── PART COLORS ────────────────────────────────────────────
-- Global color table (shared across all categories/styles/types).
-- Not every part needs a color (e.g., Wire, Conduit).
CREATE TABLE IF NOT EXISTS part_colors (
    id          INTEGER PRIMARY KEY AUTOINCREMENT,
    name        TEXT    NOT NULL UNIQUE,
    hex_code    TEXT,                              -- Optional: "#FFFFFF" for UI color swatches
    sort_order  INTEGER DEFAULT 0,
    is_active   INTEGER DEFAULT 1,
    created_at  TEXT    DEFAULT (datetime('now'))
);


-- ─── BRANDS ─────────────────────────────────────────────────
-- Manufacturer brands. "Specific" (branded) parts link to a brand.
-- General/commodity parts have no brand.
CREATE TABLE IF NOT EXISTS brands (
    id          INTEGER PRIMARY KEY AUTOINCREMENT,
    name        TEXT    NOT NULL UNIQUE,
    website     TEXT,
    notes       TEXT,
    is_active   INTEGER DEFAULT 1,
    created_at  TEXT    DEFAULT (datetime('now')),
    updated_at  TEXT    DEFAULT (datetime('now'))
);

CREATE INDEX IF NOT EXISTS idx_brands_name ON brands(name);


-- ─── SUPPLIERS ──────────────────────────────────────────────
-- Companies we buy parts from. Three-tier contact hierarchy:
--   Business Contact → Sales Rep → Delivery Driver
-- Reliability scores are updated as POs are received (Phase 5).
CREATE TABLE IF NOT EXISTS suppliers (
    id                  INTEGER PRIMARY KEY AUTOINCREMENT,
    name                TEXT    NOT NULL,

    -- Business contact (main office / general inquiries / returns)
    contact_name        TEXT,
    email               TEXT,
    phone               TEXT,
    address             TEXT,
    website             TEXT,

    -- Sales rep contact (the person you call for orders and quotes)
    rep_name            TEXT,
    rep_email           TEXT,
    rep_phone           TEXT,

    notes               TEXT,

    -- Delivery logistics
    --   'standard_shipping'   = FedEx / UPS / USPS (carrier delivers)
    --   'scheduled_delivery'  = Supplier delivers on specific weekdays
    --   'in_store_pickup'     = No delivery — must go pick up in person
    delivery_method     TEXT    DEFAULT 'standard_shipping'
                                CHECK(delivery_method IN (
                                    'standard_shipping',
                                    'scheduled_delivery',
                                    'in_store_pickup'
                                )),
    delivery_days       TEXT,                            -- JSON: ["monday","wednesday","friday"]
    special_order_lead_days INTEGER,                     -- Extra days for items not in local warehouse
    delivery_notes      TEXT,                            -- Free text: "Delivers 7am-noon only", etc.

    -- Delivery driver contact (the person physically bringing parts)
    -- Only relevant when delivery_method = 'scheduled_delivery'
    driver_name         TEXT,
    driver_phone        TEXT,
    driver_email        TEXT,

    -- Reliability metrics (updated by PO receive flow)
    on_time_rate        REAL    DEFAULT 0.95,       -- 0.0–1.0
    quality_score       REAL    DEFAULT 0.90,        -- 0.0–1.0
    avg_lead_days       INTEGER DEFAULT 5,
    reliability_score   REAL    DEFAULT 0.85,        -- weighted composite
    is_active           INTEGER DEFAULT 1,
    created_at          TEXT    DEFAULT (datetime('now')),
    updated_at          TEXT    DEFAULT (datetime('now'))
);

CREATE INDEX IF NOT EXISTS idx_suppliers_name ON suppliers(name);


-- ─── PARTS (Orderable Variants) ─────────────────────────────
-- Each row = one orderable part variant, defined by its position
-- in the Category→Style→Type→Color hierarchy plus optionally a brand.
--
-- Types:
--   'general'  = commodity item, no brand/code needed, order from anyone
--   'specific' = branded part, needs manufacturer_part_number (may be pending)
CREATE TABLE IF NOT EXISTS parts (
    id                          INTEGER PRIMARY KEY AUTOINCREMENT,

    -- ── Hierarchy position (defines WHAT this part IS) ──
    category_id                 INTEGER NOT NULL REFERENCES part_categories(id),
    style_id                    INTEGER REFERENCES part_styles(id),      -- NULL for "unstyled" categories (Wire, Conduit)
    type_id                     INTEGER REFERENCES part_types(id),       -- NULL for simple categories
    color_id                    INTEGER REFERENCES part_colors(id),      -- NULL = color not applicable

    -- ── General vs Branded ──
    part_type                   TEXT    NOT NULL DEFAULT 'general'
                                        CHECK(part_type IN ('general', 'specific')),

    -- ── Identification ──
    code                        TEXT    UNIQUE,                           -- Optional for general, used for branded
    name                        TEXT    NOT NULL,                         -- Human-readable (auto-gen or manual)
    description                 TEXT,

    -- ── Brand info (required for 'specific', NULL for 'general') ──
    brand_id                    INTEGER REFERENCES brands(id) ON DELETE SET NULL,
    manufacturer_part_number    TEXT,                                     -- Brand's SKU. NULL = "pending" for specific parts

    -- ── Physical attributes ──
    unit_of_measure             TEXT    DEFAULT 'each',                   -- each, ft, box, roll, etc.
    weight_lbs                  REAL,

    -- ── Pricing (internal use — bookkeeper handles customer billing) ──
    company_cost_price          REAL    NOT NULL DEFAULT 0.0,
    company_markup_percent      REAL    NOT NULL DEFAULT 0.0,
    company_sell_price          REAL    GENERATED ALWAYS AS (
                                    company_cost_price * (1.0 + company_markup_percent / 100.0)
                                ) STORED,

    -- ── Inventory levels (targets — actual qty is in `stock` table) ──
    min_stock_level             INTEGER DEFAULT 0,
    max_stock_level             INTEGER DEFAULT 0,
    target_stock_level          INTEGER DEFAULT 0,

    -- ── Forecasting fields (updated by forecast service) ──
    forecast_last_run           TEXT,
    forecast_adu_30             REAL    DEFAULT 0,
    forecast_adu_90             REAL    DEFAULT 0,
    forecast_reorder_point      INTEGER DEFAULT 0,
    forecast_target_qty         INTEGER DEFAULT 0,
    forecast_suggested_order    INTEGER DEFAULT 0,
    forecast_days_until_low     INTEGER DEFAULT 999,                     -- -1 = already below min

    -- ── Status & metadata ──
    is_deprecated               INTEGER DEFAULT 0,
    deprecation_reason          TEXT,
    is_qr_tagged                INTEGER DEFAULT 0,
    notes                       TEXT,
    image_url                   TEXT,
    pdf_url                     TEXT,

    created_at                  TEXT    DEFAULT (datetime('now')),
    updated_at                  TEXT    DEFAULT (datetime('now'))
);

-- Prevent duplicate variants: same hierarchy + brand combo can't appear twice.
-- COALESCE converts NULLs to 0 for uniqueness (SQLite treats NULLs as distinct).
CREATE UNIQUE INDEX IF NOT EXISTS idx_parts_variant_unique
    ON parts(category_id, COALESCE(style_id, 0), COALESCE(type_id, 0), COALESCE(color_id, 0), COALESCE(brand_id, 0));

-- Standard lookup indexes
CREATE INDEX IF NOT EXISTS idx_parts_category ON parts(category_id);
CREATE INDEX IF NOT EXISTS idx_parts_style ON parts(style_id);
CREATE INDEX IF NOT EXISTS idx_parts_type_id ON parts(type_id);
CREATE INDEX IF NOT EXISTS idx_parts_color ON parts(color_id);
CREATE INDEX IF NOT EXISTS idx_parts_brand ON parts(brand_id);
CREATE INDEX IF NOT EXISTS idx_parts_part_type ON parts(part_type);
CREATE INDEX IF NOT EXISTS idx_parts_code ON parts(code);
CREATE INDEX IF NOT EXISTS idx_parts_name ON parts(name);
CREATE INDEX IF NOT EXISTS idx_parts_deprecated ON parts(is_deprecated);

-- Fast lookup for "Pending Part Numbers" queue
CREATE INDEX IF NOT EXISTS idx_parts_pending_pn
    ON parts(part_type, manufacturer_part_number)
    WHERE part_type = 'specific' AND manufacturer_part_number IS NULL;


-- ─── BRAND ↔ SUPPLIER LINKS ────────────────────────────────
-- Many-to-many: which suppliers carry which brands.
-- Not every supplier carries every brand. This is used for:
--   1. Knowing where to order branded parts from
--   2. Storing our account # per supplier/brand relationship
--   3. Future AI email scanning (matching supplier quotes to brands)
CREATE TABLE IF NOT EXISTS brand_supplier_links (
    id              INTEGER PRIMARY KEY AUTOINCREMENT,
    brand_id        INTEGER NOT NULL REFERENCES brands(id) ON DELETE CASCADE,
    supplier_id     INTEGER NOT NULL REFERENCES suppliers(id) ON DELETE CASCADE,
    account_number  TEXT,                                      -- Our account # with this supplier for this brand
    notes           TEXT,
    is_active       INTEGER DEFAULT 1,
    created_at      TEXT    DEFAULT (datetime('now')),
    UNIQUE(brand_id, supplier_id)
);

CREATE INDEX IF NOT EXISTS idx_bsl_brand ON brand_supplier_links(brand_id);
CREATE INDEX IF NOT EXISTS idx_bsl_supplier ON brand_supplier_links(supplier_id);


-- ─── PART ↔ SUPPLIER LINKS ─────────────────────────────────
-- Many-to-many: a part can come from multiple suppliers, and
-- a supplier can provide multiple parts. Each link stores
-- the supplier's own part number, MOQ, and volume discounts.
-- This is where supplier-specific pricing lives.
CREATE TABLE IF NOT EXISTS part_supplier_links (
    id                  INTEGER PRIMARY KEY AUTOINCREMENT,
    part_id             INTEGER NOT NULL REFERENCES parts(id) ON DELETE CASCADE,
    supplier_id         INTEGER NOT NULL REFERENCES suppliers(id) ON DELETE CASCADE,
    supplier_part_number TEXT,                                        -- Supplier's catalog #
    supplier_cost_price REAL,                                        -- Override price from this supplier
    moq                 INTEGER DEFAULT 1,                           -- Minimum order quantity
    discount_brackets   TEXT,                                        -- JSON: [{"qty":50,"price":4.75}, ...]
    last_price_date     TEXT,                                        -- When we last verified the price
    is_preferred        INTEGER DEFAULT 0,                           -- 1 = default supplier for this part
    created_at          TEXT    DEFAULT (datetime('now')),
    UNIQUE(part_id, supplier_id)
);

CREATE INDEX IF NOT EXISTS idx_psl_part ON part_supplier_links(part_id);
CREATE INDEX IF NOT EXISTS idx_psl_supplier ON part_supplier_links(supplier_id);


-- ─── STOCK ──────────────────────────────────────────────────
-- Current inventory levels at every location in the system.
-- Uses a polymorphic pattern: location_type + location_id together
-- identify WHERE the stock is.
--
-- location_type values:
--   'warehouse'  — main warehouse (location_id = 1 for default)
--   'pulled'     — staging area (location_id = warehouse_id)
--   'truck'      — on a truck (location_id = truck.id)
--   'job'        — consumed/allocated to a job (location_id = job.id)
--
-- supplier_id is carried forward on every move to enable returns.
CREATE TABLE IF NOT EXISTS stock (
    id              INTEGER PRIMARY KEY AUTOINCREMENT,
    part_id         INTEGER NOT NULL REFERENCES parts(id) ON DELETE CASCADE,
    location_type   TEXT    NOT NULL CHECK(location_type IN ('warehouse','pulled','truck','job')),
    location_id     INTEGER NOT NULL DEFAULT 1,
    qty             INTEGER NOT NULL DEFAULT 0 CHECK(qty >= 0),
    supplier_id     INTEGER REFERENCES suppliers(id),
    last_counted    TEXT,
    updated_at      TEXT    DEFAULT (datetime('now')),
    UNIQUE(part_id, location_type, location_id, supplier_id)
);

CREATE INDEX IF NOT EXISTS idx_stock_part ON stock(part_id);
CREATE INDEX IF NOT EXISTS idx_stock_location ON stock(location_type, location_id);
CREATE INDEX IF NOT EXISTS idx_stock_supplier ON stock(supplier_id);


-- ─── STOCK MOVEMENTS ────────────────────────────────────────
-- Immutable log of every stock movement. This is the audit trail.
-- Every move has a human user (never automated), from/to locations,
-- and preserves the supplier chain.
CREATE TABLE IF NOT EXISTS stock_movements (
    id                  INTEGER PRIMARY KEY AUTOINCREMENT,
    part_id             INTEGER NOT NULL REFERENCES parts(id),
    qty                 INTEGER NOT NULL CHECK(qty > 0),

    -- From location (NULL = new stock from PO receive)
    from_location_type  TEXT    CHECK(from_location_type IN ('warehouse','pulled','truck','job') OR from_location_type IS NULL),
    from_location_id    INTEGER,

    -- To location (NULL = stock removed / written off)
    to_location_type    TEXT    CHECK(to_location_type IN ('warehouse','pulled','truck','job') OR to_location_type IS NULL),
    to_location_id      INTEGER,

    -- Supplier chain tracking
    supplier_id         INTEGER REFERENCES suppliers(id),

    -- Movement metadata
    movement_type       TEXT    NOT NULL DEFAULT 'transfer'
                                CHECK(movement_type IN (
                                    'receive', 'transfer', 'consume',
                                    'return', 'adjust', 'write_off'
                                )),
    reason              TEXT,
    job_id              INTEGER,

    -- Human accountability
    performed_by        INTEGER NOT NULL REFERENCES users(id),
    verified_by         INTEGER REFERENCES users(id),
    photo_path          TEXT,
    scan_confirmed      INTEGER DEFAULT 0,
    gps_lat             REAL,
    gps_lng             REAL,

    -- Cost snapshot (for reporting)
    unit_cost_at_move   REAL,
    unit_sell_at_move   REAL,

    created_at          TEXT    DEFAULT (datetime('now'))
);

CREATE INDEX IF NOT EXISTS idx_movements_part ON stock_movements(part_id);
CREATE INDEX IF NOT EXISTS idx_movements_type ON stock_movements(movement_type);
CREATE INDEX IF NOT EXISTS idx_movements_from ON stock_movements(from_location_type, from_location_id);
CREATE INDEX IF NOT EXISTS idx_movements_to ON stock_movements(to_location_type, to_location_id);
CREATE INDEX IF NOT EXISTS idx_movements_job ON stock_movements(job_id);
CREATE INDEX IF NOT EXISTS idx_movements_user ON stock_movements(performed_by);
CREATE INDEX IF NOT EXISTS idx_movements_date ON stock_movements(created_at);


-- ─── FORECAST HISTORY ───────────────────────────────────────
-- Tracks how forecasts change over time for trend analysis.
CREATE TABLE IF NOT EXISTS part_forecast_history (
    id                  INTEGER PRIMARY KEY AUTOINCREMENT,
    part_id             INTEGER NOT NULL REFERENCES parts(id) ON DELETE CASCADE,
    forecast_date       TEXT    NOT NULL,
    adu_30              REAL,
    adu_90              REAL,
    reorder_point       INTEGER,
    target_qty          INTEGER,
    suggested_order     INTEGER,
    total_stock         INTEGER,
    created_at          TEXT    DEFAULT (datetime('now'))
);

CREATE INDEX IF NOT EXISTS idx_forecast_hist_part ON part_forecast_history(part_id, forecast_date);


-- =============================================================
-- SEED DATA
-- =============================================================

-- ─── Seed: Part Categories ──────────────────────────────────
INSERT OR IGNORE INTO part_categories (name, description, sort_order) VALUES
    ('Outlet',         'Receptacles and power outlets',                 10),
    ('Switch',         'Light switches, dimmers, and controls',         20),
    ('Cover Plate',    'Wall plates and cover plates',                  30),
    ('Wire',           'Conductors, cables, and wiring',                40),
    ('Breaker',        'Circuit breakers and GFCI breakers',            50),
    ('Panel',          'Electrical panels and load centers',            60),
    ('Junction Box',   'Boxes, rings, and brackets',                    70),
    ('Conduit',        'Conduit, raceway, and tubing',                  80),
    ('Fitting',        'Connectors, couplings, and fittings',           90),
    ('Connector',      'Wire nuts, lugs, and terminals',               100),
    ('Light Fixture',  'Indoor and outdoor lighting',                  110),
    ('Misc',           'Uncategorized and specialty items',             999);


-- ─── Seed: Part Styles ──────────────────────────────────────
-- Outlet styles
INSERT OR IGNORE INTO part_styles (category_id, name, sort_order)
    SELECT id, 'Decora', 10 FROM part_categories WHERE name = 'Outlet';
INSERT OR IGNORE INTO part_styles (category_id, name, sort_order)
    SELECT id, 'Traditional', 20 FROM part_categories WHERE name = 'Outlet';

-- Switch styles
INSERT OR IGNORE INTO part_styles (category_id, name, sort_order)
    SELECT id, 'Decora', 10 FROM part_categories WHERE name = 'Switch';
INSERT OR IGNORE INTO part_styles (category_id, name, sort_order)
    SELECT id, 'Traditional', 20 FROM part_categories WHERE name = 'Switch';

-- Cover Plate styles
INSERT OR IGNORE INTO part_styles (category_id, name, sort_order)
    SELECT id, 'Decora', 10 FROM part_categories WHERE name = 'Cover Plate';
INSERT OR IGNORE INTO part_styles (category_id, name, sort_order)
    SELECT id, 'Traditional', 20 FROM part_categories WHERE name = 'Cover Plate';


-- ─── Seed: Part Types (per style) ───────────────────────────
-- Outlet > Decora types
INSERT OR IGNORE INTO part_types (style_id, name, sort_order)
    SELECT ps.id, 'Standard', 10
    FROM part_styles ps JOIN part_categories pc ON pc.id = ps.category_id
    WHERE pc.name = 'Outlet' AND ps.name = 'Decora';
INSERT OR IGNORE INTO part_types (style_id, name, sort_order)
    SELECT ps.id, 'GFI', 20
    FROM part_styles ps JOIN part_categories pc ON pc.id = ps.category_id
    WHERE pc.name = 'Outlet' AND ps.name = 'Decora';
INSERT OR IGNORE INTO part_types (style_id, name, sort_order)
    SELECT ps.id, 'Tamper Resistant', 30
    FROM part_styles ps JOIN part_categories pc ON pc.id = ps.category_id
    WHERE pc.name = 'Outlet' AND ps.name = 'Decora';
INSERT OR IGNORE INTO part_types (style_id, name, sort_order)
    SELECT ps.id, 'Weather Resistant', 40
    FROM part_styles ps JOIN part_categories pc ON pc.id = ps.category_id
    WHERE pc.name = 'Outlet' AND ps.name = 'Decora';
INSERT OR IGNORE INTO part_types (style_id, name, sort_order)
    SELECT ps.id, 'USB', 50
    FROM part_styles ps JOIN part_categories pc ON pc.id = ps.category_id
    WHERE pc.name = 'Outlet' AND ps.name = 'Decora';

-- Outlet > Traditional types
INSERT OR IGNORE INTO part_types (style_id, name, sort_order)
    SELECT ps.id, 'Standard', 10
    FROM part_styles ps JOIN part_categories pc ON pc.id = ps.category_id
    WHERE pc.name = 'Outlet' AND ps.name = 'Traditional';
INSERT OR IGNORE INTO part_types (style_id, name, sort_order)
    SELECT ps.id, 'GFI', 20
    FROM part_styles ps JOIN part_categories pc ON pc.id = ps.category_id
    WHERE pc.name = 'Outlet' AND ps.name = 'Traditional';
INSERT OR IGNORE INTO part_types (style_id, name, sort_order)
    SELECT ps.id, 'Tamper Resistant', 30
    FROM part_styles ps JOIN part_categories pc ON pc.id = ps.category_id
    WHERE pc.name = 'Outlet' AND ps.name = 'Traditional';

-- Switch > Decora types
INSERT OR IGNORE INTO part_types (style_id, name, sort_order)
    SELECT ps.id, 'Single Pole', 10
    FROM part_styles ps JOIN part_categories pc ON pc.id = ps.category_id
    WHERE pc.name = 'Switch' AND ps.name = 'Decora';
INSERT OR IGNORE INTO part_types (style_id, name, sort_order)
    SELECT ps.id, '3-Way', 20
    FROM part_styles ps JOIN part_categories pc ON pc.id = ps.category_id
    WHERE pc.name = 'Switch' AND ps.name = 'Decora';
INSERT OR IGNORE INTO part_types (style_id, name, sort_order)
    SELECT ps.id, '4-Way', 30
    FROM part_styles ps JOIN part_categories pc ON pc.id = ps.category_id
    WHERE pc.name = 'Switch' AND ps.name = 'Decora';
INSERT OR IGNORE INTO part_types (style_id, name, sort_order)
    SELECT ps.id, 'Dimmer', 40
    FROM part_styles ps JOIN part_categories pc ON pc.id = ps.category_id
    WHERE pc.name = 'Switch' AND ps.name = 'Decora';
INSERT OR IGNORE INTO part_types (style_id, name, sort_order)
    SELECT ps.id, '0-10V Dimmer', 50
    FROM part_styles ps JOIN part_categories pc ON pc.id = ps.category_id
    WHERE pc.name = 'Switch' AND ps.name = 'Decora';

-- Switch > Traditional types
INSERT OR IGNORE INTO part_types (style_id, name, sort_order)
    SELECT ps.id, 'Single Pole', 10
    FROM part_styles ps JOIN part_categories pc ON pc.id = ps.category_id
    WHERE pc.name = 'Switch' AND ps.name = 'Traditional';
INSERT OR IGNORE INTO part_types (style_id, name, sort_order)
    SELECT ps.id, '3-Way', 20
    FROM part_styles ps JOIN part_categories pc ON pc.id = ps.category_id
    WHERE pc.name = 'Switch' AND ps.name = 'Traditional';
INSERT OR IGNORE INTO part_types (style_id, name, sort_order)
    SELECT ps.id, '4-Way', 30
    FROM part_styles ps JOIN part_categories pc ON pc.id = ps.category_id
    WHERE pc.name = 'Switch' AND ps.name = 'Traditional';


-- ─── Seed: Common Colors ────────────────────────────────────
INSERT OR IGNORE INTO part_colors (name, hex_code, sort_order) VALUES
    ('White',          '#FFFFFF',  10),
    ('Black',          '#000000',  20),
    ('Light Almond',   '#E8D5B7',  30),
    ('Gray',           '#808080',  40),
    ('Ivory',          '#FFFFF0',  50),
    ('Brown',          '#8B4513',  60),
    ('Red',            '#FF0000',  70),
    ('Blue',           '#0000FF',  80),
    ('Orange',         '#FFA500',  90),
    ('Tan',            '#D2B48C', 100);


-- ─── Seed: Brands ───────────────────────────────────────────
INSERT OR IGNORE INTO brands (name, website, notes) VALUES
    ('Southwire',     'https://www.southwire.com',      'Wire and cable manufacturer'),
    ('Leviton',       'https://www.leviton.com',        'Electrical devices and wiring'),
    ('Square D',      'https://www.se.com',             'Breakers and panels (Schneider Electric)'),
    ('Eaton',         'https://www.eaton.com',           'Breakers, panels, and industrial'),
    ('Arlington',     'https://www.aifittings.com',      'Fittings, boxes, and conduit accessories'),
    ('Klein Tools',   'https://www.kleintools.com',      'Hand tools and test equipment'),
    ('Milwaukee',     'https://www.milwaukeetool.com',   'Power tools and accessories'),
    ('Ideal',         'https://www.idealind.com',        'Wire connectors and tools'),
    ('Greenlee',      'https://www.greenlee.com',        'Cable pullers and bending equipment'),
    ('Carlon',        'https://www.tnb.com',             'PVC conduit and fittings');
