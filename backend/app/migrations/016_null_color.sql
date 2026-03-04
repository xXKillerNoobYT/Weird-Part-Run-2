-- 016: Add [NULL] color for "color unknown or unimportant"
--
-- This is a system color that represents "no color" or "color doesn't matter".
-- sort_order = -1 ensures it appears first in ordered lists.
-- INSERT OR IGNORE is safe for re-runs (name has UNIQUE constraint).

INSERT OR IGNORE INTO part_colors (name, hex_code, sort_order, is_active)
VALUES ('[NULL]', '#000000', -1, 1);
