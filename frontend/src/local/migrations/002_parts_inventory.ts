/**
 * Migration 002: Parts & Inventory
 *
 * Parts hierarchy, brands, suppliers, stock, movements.
 * Consolidated from: backend migrations 002, 003, 004, 005, 006, 008, 016
 */

export const migration = {
  name: '002_parts_inventory',
  sql: `
-- ─── PART CATEGORIES ────────────────────────────────────────
CREATE TABLE IF NOT EXISTS part_categories (
    id          INTEGER PRIMARY KEY AUTOINCREMENT,
    name        TEXT    NOT NULL UNIQUE,
    description TEXT,
    sort_order  INTEGER DEFAULT 0,
    is_active   INTEGER DEFAULT 1,
    created_at  TEXT    DEFAULT (datetime('now')),
    updated_at  TEXT    DEFAULT (datetime('now'))
);

-- ─── PART STYLES ────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS part_styles (
    id          INTEGER PRIMARY KEY AUTOINCREMENT,
    category_id INTEGER NOT NULL REFERENCES part_categories(id) ON DELETE CASCADE,
    name        TEXT    NOT NULL,
    description TEXT,
    image_url   TEXT,
    sort_order  INTEGER DEFAULT 0,
    is_active   INTEGER DEFAULT 1,
    created_at  TEXT    DEFAULT (datetime('now')),
    updated_at  TEXT    DEFAULT (datetime('now')),
    UNIQUE(category_id, name)
);
CREATE INDEX IF NOT EXISTS idx_styles_category ON part_styles(category_id);

-- ─── PART TYPES ─────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS part_types (
    id          INTEGER PRIMARY KEY AUTOINCREMENT,
    style_id    INTEGER NOT NULL REFERENCES part_styles(id) ON DELETE CASCADE,
    name        TEXT    NOT NULL,
    description TEXT,
    color       TEXT,
    image_url   TEXT,
    sort_order  INTEGER DEFAULT 0,
    is_active   INTEGER DEFAULT 1,
    created_at  TEXT    DEFAULT (datetime('now')),
    updated_at  TEXT    DEFAULT (datetime('now')),
    UNIQUE(style_id, name)
);
CREATE INDEX IF NOT EXISTS idx_types_style ON part_types(style_id);

-- ─── PART COLORS ────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS part_colors (
    id          INTEGER PRIMARY KEY AUTOINCREMENT,
    name        TEXT    NOT NULL UNIQUE,
    hex_code    TEXT,
    sort_order  INTEGER DEFAULT 0,
    is_active   INTEGER DEFAULT 1,
    created_at  TEXT    DEFAULT (datetime('now'))
);

-- ─── BRANDS ─────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS brands (
    id          INTEGER PRIMARY KEY AUTOINCREMENT,
    name        TEXT    NOT NULL UNIQUE,
    website     TEXT,
    notes       TEXT,
    is_active   INTEGER DEFAULT 1,
    created_at  TEXT    DEFAULT (datetime('now')),
    updated_at  TEXT    DEFAULT (datetime('now'))
);

-- ─── SUPPLIERS ──────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS suppliers (
    id                      INTEGER PRIMARY KEY AUTOINCREMENT,
    name                    TEXT    NOT NULL,
    contact_name            TEXT,
    email                   TEXT,
    phone                   TEXT,
    address                 TEXT,
    website                 TEXT,
    rep_name                TEXT,
    rep_email               TEXT,
    rep_phone               TEXT,
    notes                   TEXT,
    delivery_method         TEXT    DEFAULT 'standard_shipping',
    delivery_days           TEXT,
    special_order_lead_days INTEGER,
    delivery_notes          TEXT,
    driver_name             TEXT,
    driver_phone            TEXT,
    driver_email            TEXT,
    on_time_rate            REAL    DEFAULT 0.95,
    quality_score           REAL    DEFAULT 0.90,
    avg_lead_days           INTEGER DEFAULT 5,
    reliability_score       REAL    DEFAULT 0.85,
    communication_score     REAL    DEFAULT 0.85,
    is_active               INTEGER DEFAULT 1,
    created_at              TEXT    DEFAULT (datetime('now')),
    updated_at              TEXT    DEFAULT (datetime('now'))
);

-- ─── PARTS (Orderable Variants) ────────────────────────────
CREATE TABLE IF NOT EXISTS parts (
    id                          INTEGER PRIMARY KEY AUTOINCREMENT,
    category_id                 INTEGER NOT NULL REFERENCES part_categories(id),
    style_id                    INTEGER REFERENCES part_styles(id),
    type_id                     INTEGER REFERENCES part_types(id),
    color_id                    INTEGER REFERENCES part_colors(id),
    part_type                   TEXT    NOT NULL DEFAULT 'general'
                                        CHECK(part_type IN ('general', 'specific')),
    code                        TEXT    UNIQUE,
    name                        TEXT    NOT NULL,
    description                 TEXT,
    brand_id                    INTEGER REFERENCES brands(id) ON DELETE SET NULL,
    manufacturer_part_number    TEXT,
    unit_of_measure             TEXT    DEFAULT 'each',
    weight_lbs                  REAL,
    company_cost_price          REAL    NOT NULL DEFAULT 0.0,
    company_markup_percent      REAL    NOT NULL DEFAULT 0.0,
    company_sell_price          REAL    GENERATED ALWAYS AS (
                                    company_cost_price * (1.0 + company_markup_percent / 100.0)
                                ) STORED,
    min_stock_level             INTEGER DEFAULT 0,
    max_stock_level             INTEGER DEFAULT 0,
    target_stock_level          INTEGER DEFAULT 0,
    reorder_point               INTEGER DEFAULT 0,
    forecast_last_run           TEXT,
    forecast_adu_30             REAL    DEFAULT 0,
    forecast_adu_90             REAL    DEFAULT 0,
    forecast_reorder_point      INTEGER DEFAULT 0,
    forecast_target_qty         INTEGER DEFAULT 0,
    forecast_suggested_order    INTEGER DEFAULT 0,
    forecast_days_until_low     INTEGER DEFAULT 999,
    is_deprecated               INTEGER DEFAULT 0,
    deprecation_reason          TEXT,
    is_qr_tagged                INTEGER DEFAULT 0,
    notes                       TEXT,
    image_url                   TEXT,
    pdf_url                     TEXT,
    shelf_location              TEXT,
    bin_location                TEXT,
    is_active                   INTEGER DEFAULT 1,
    created_at                  TEXT    DEFAULT (datetime('now')),
    updated_at                  TEXT    DEFAULT (datetime('now'))
);

CREATE UNIQUE INDEX IF NOT EXISTS idx_parts_variant_unique
    ON parts(category_id, COALESCE(style_id, 0), COALESCE(type_id, 0), COALESCE(color_id, 0), COALESCE(brand_id, 0));
CREATE INDEX IF NOT EXISTS idx_parts_category ON parts(category_id);
CREATE INDEX IF NOT EXISTS idx_parts_brand ON parts(brand_id);
CREATE INDEX IF NOT EXISTS idx_parts_name ON parts(name);
CREATE INDEX IF NOT EXISTS idx_parts_code ON parts(code);

-- ─── BRAND ↔ SUPPLIER LINKS ────────────────────────────────
CREATE TABLE IF NOT EXISTS brand_supplier_links (
    id              INTEGER PRIMARY KEY AUTOINCREMENT,
    brand_id        INTEGER NOT NULL REFERENCES brands(id) ON DELETE CASCADE,
    supplier_id     INTEGER NOT NULL REFERENCES suppliers(id) ON DELETE CASCADE,
    account_number  TEXT,
    notes           TEXT,
    is_active       INTEGER DEFAULT 1,
    created_at      TEXT    DEFAULT (datetime('now')),
    UNIQUE(brand_id, supplier_id)
);

-- ─── PART ↔ SUPPLIER LINKS ─────────────────────────────────
CREATE TABLE IF NOT EXISTS part_supplier_links (
    id                   INTEGER PRIMARY KEY AUTOINCREMENT,
    part_id              INTEGER NOT NULL REFERENCES parts(id) ON DELETE CASCADE,
    supplier_id          INTEGER NOT NULL REFERENCES suppliers(id) ON DELETE CASCADE,
    supplier_part_number TEXT,
    supplier_cost_price  REAL,
    moq                  INTEGER DEFAULT 1,
    discount_brackets    TEXT,
    last_price_date      TEXT,
    is_preferred         INTEGER DEFAULT 0,
    created_at           TEXT    DEFAULT (datetime('now')),
    UNIQUE(part_id, supplier_id)
);

-- ─── STOCK ──────────────────────────────────────────────────
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

-- ─── STOCK MOVEMENTS ────────────────────────────────────────
CREATE TABLE IF NOT EXISTS stock_movements (
    id                  INTEGER PRIMARY KEY AUTOINCREMENT,
    part_id             INTEGER NOT NULL REFERENCES parts(id),
    qty                 INTEGER NOT NULL CHECK(qty > 0),
    from_location_type  TEXT,
    from_location_id    INTEGER,
    to_location_type    TEXT,
    to_location_id      INTEGER,
    supplier_id         INTEGER REFERENCES suppliers(id),
    movement_type       TEXT    NOT NULL DEFAULT 'transfer'
                                CHECK(movement_type IN (
                                    'receive', 'transfer', 'consume',
                                    'return', 'adjust', 'write_off'
                                )),
    reason              TEXT,
    reference_number    TEXT,
    notes               TEXT,
    job_id              INTEGER,
    performed_by        INTEGER NOT NULL REFERENCES users(id),
    verified_by         INTEGER REFERENCES users(id),
    photo_path          TEXT,
    scan_confirmed      INTEGER DEFAULT 0,
    gps_lat             REAL,
    gps_lng             REAL,
    unit_cost_at_move   REAL,
    unit_sell_at_move   REAL,
    created_at          TEXT    DEFAULT (datetime('now'))
);
CREATE INDEX IF NOT EXISTS idx_movements_part ON stock_movements(part_id);
CREATE INDEX IF NOT EXISTS idx_movements_job ON stock_movements(job_id);
CREATE INDEX IF NOT EXISTS idx_movements_date ON stock_movements(created_at);

-- ─── PULLED STAGING TAGS ────────────────────────────────────
CREATE TABLE IF NOT EXISTS pulled_staging_tags (
    id               INTEGER PRIMARY KEY AUTOINCREMENT,
    stock_id         INTEGER NOT NULL REFERENCES stock(id) ON DELETE CASCADE,
    destination_type TEXT,
    destination_id   INTEGER,
    destination_label TEXT,
    tagged_by        INTEGER REFERENCES users(id),
    tagged_at        TEXT    DEFAULT (datetime('now')),
    UNIQUE(stock_id)
);
  `,
};
