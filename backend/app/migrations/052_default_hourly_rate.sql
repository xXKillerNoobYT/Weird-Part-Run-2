-- ═══════════════════════════════════════════════════════════════════════
-- Migration 052: Default Hourly Rate Setting
--
-- Adds a company-wide default hourly rate for labor cost rollups.
-- The billing_rate column was dropped from jobs in migration 011
-- (replaced by bill_rate_type_id classification). This setting provides
-- a numeric rate for cost estimation until per-type rates are added.
-- ═══════════════════════════════════════════════════════════════════════

INSERT OR IGNORE INTO company_cost_settings (setting_key, setting_value)
VALUES ('default_hourly_rate', '0');
