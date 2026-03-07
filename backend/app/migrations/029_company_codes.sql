-- ═══════════════════════════════════════════════════════════════════════
-- Migration 029: Company Codes + PO Naming Support
--
-- Adds company_code column to customers table for use in PO naming
-- and report filenames. GCs already have gc_code from migration 025.
-- ═══════════════════════════════════════════════════════════════════════

-- Add company_code to customers (short code like "SMITH-RES", "CITY-GOV")
ALTER TABLE customers ADD COLUMN company_code TEXT;

CREATE UNIQUE INDEX IF NOT EXISTS idx_customers_code ON customers(company_code)
    WHERE company_code IS NOT NULL;
