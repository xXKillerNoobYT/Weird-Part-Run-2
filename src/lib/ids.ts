/**
 * ID Generation Utilities
 *
 * All new records created in the local data layer use UUID v4 primary keys
 * to prevent collisions when multiple devices create records independently.
 *
 * Existing records migrated from the shop may still have integer IDs —
 * SQLite is flexible about column types, so UUID strings and integers
 * coexist without issue in the same column.
 *
 * Usage:
 *   import { generateId } from '../lib/ids';
 *   const id = generateId(); // e.g. "a1b2c3d4-e5f6-4789-abcd-ef1234567890"
 */

/**
 * Generate a UUID v4 string for use as a primary key.
 * Uses the Web Crypto API (available in all modern browsers + WebViews).
 */
export function generateId(): string {
  return crypto.randomUUID();
}

/**
 * Check if a value looks like a UUID (vs an integer ID from legacy data).
 * Useful for sync logic that needs to distinguish local vs migrated records.
 */
export function isUuid(value: string | number): boolean {
  if (typeof value === 'number') return false;
  return /^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(value);
}
