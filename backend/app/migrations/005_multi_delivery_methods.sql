-- Migration 005: Multi-select delivery methods for suppliers
--
-- Previously, suppliers had a single delivery_method column (one of:
-- standard_shipping, scheduled_delivery, in_store_pickup).
--
-- Now suppliers can offer MULTIPLE delivery methods with one marked
-- as the primary/default method.
--
-- New column: delivery_methods  TEXT (JSON array, e.g. '["scheduled_delivery","in_store_pickup"]')
-- Rename:     delivery_method → primary_delivery_method (the default method for this supplier)

-- Step 1: Add the new delivery_methods column (JSON array of all offered methods)
ALTER TABLE suppliers ADD COLUMN delivery_methods TEXT;

-- Step 2: Populate delivery_methods from the existing single delivery_method
-- Each existing supplier gets a one-element array from their current delivery_method
UPDATE suppliers
SET delivery_methods = '["' || delivery_method || '"]'
WHERE delivery_methods IS NULL;

-- NOTE: SQLite doesn't support ALTER COLUMN RENAME, so delivery_method remains as-is
-- and is treated as "primary_delivery_method" by the application layer.
-- The backend models will map:
--   DB column `delivery_method`  → API field `primary_delivery_method`
--   DB column `delivery_methods` → API field `delivery_methods`
