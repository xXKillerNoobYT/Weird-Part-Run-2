-- =================================================================
-- Migration 008: Add bin_location to parts
--
-- Separate from shelf_location for more granular warehouse placement.
-- shelf_location = general area (Row A, Shelf 3)
-- bin_location   = specific bin within that area (Bin 12)
-- Both are optional — not all items use bins.
-- =================================================================

ALTER TABLE parts ADD COLUMN bin_location TEXT;
