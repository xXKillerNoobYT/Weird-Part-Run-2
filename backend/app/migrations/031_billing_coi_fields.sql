-- =============================================================
-- Migration 031: Customer billing + GC COI tracking fields
--
-- Adds billing-specific fields to customers and Certificate of
-- Insurance tracking fields to general_contractors.
-- =============================================================

-- Customer billing extensions
ALTER TABLE customers ADD COLUMN billing_address_line1 TEXT;
ALTER TABLE customers ADD COLUMN billing_address_line2 TEXT;
ALTER TABLE customers ADD COLUMN billing_city TEXT;
ALTER TABLE customers ADD COLUMN billing_state TEXT;
ALTER TABLE customers ADD COLUMN billing_zip TEXT;
ALTER TABLE customers ADD COLUMN payment_terms TEXT DEFAULT 'net_30'
    CHECK(payment_terms IN ('due_on_receipt', 'net_15', 'net_30', 'net_45', 'net_60', 'custom'));
ALTER TABLE customers ADD COLUMN tax_id TEXT;
ALTER TABLE customers ADD COLUMN billing_email TEXT;

-- GC Certificate of Insurance tracking
ALTER TABLE general_contractors ADD COLUMN coi_carrier TEXT;
ALTER TABLE general_contractors ADD COLUMN coi_policy_number TEXT;
ALTER TABLE general_contractors ADD COLUMN coi_expiry_date TEXT;
ALTER TABLE general_contractors ADD COLUMN coi_coverage_amount REAL;
ALTER TABLE general_contractors ADD COLUMN coi_on_file INTEGER DEFAULT 0;
ALTER TABLE general_contractors ADD COLUMN workers_comp_expiry TEXT;
ALTER TABLE general_contractors ADD COLUMN bonded INTEGER DEFAULT 0;
ALTER TABLE general_contractors ADD COLUMN bond_amount REAL;

-- Index for COI expiry monitoring
CREATE INDEX IF NOT EXISTS idx_gc_coi_expiry ON general_contractors(coi_expiry_date);
