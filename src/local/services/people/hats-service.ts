/**
 * People — Hats (Roles) & Permissions service.
 *
 * CRUD for hats, permission assignment, and the full permission matrix.
 * Source tables: hats, hat_permissions, user_hats (migration 001_foundation)
 */

import { getDb } from '../../db';
import { BaseRepo } from '../../repos/base-repo';

// ── Types ──────────────────────────────────────────────────────────

export interface HatDetail {
  id: number;
  name: string;
  description: string | null;
  level: number;
  is_builtin: boolean;
  permissions: string[];
  user_count: number;
  created_at: string | null;
}

export interface HatCreateData {
  name: string;
  description?: string | null;
  level?: number;
  permissions?: string[];
}

export interface HatUpdateData {
  name?: string | null;
  description?: string | null;
  level?: number | null;
}

export interface PermissionMatrixRow {
  permission_key: string;
  domain: string;
  hat_values: Record<number, boolean>;
}

export interface PermissionMatrixData {
  hats: Array<{ id: number; name: string; level: number }>;
  domains: Record<string, PermissionMatrixRow[]>;
}

// ── Repo ───────────────────────────────────────────────────────────

const hatRepo = new BaseRepo('hats');

// ── Known Permission Keys ──────────────────────────────────────────

/** Known permission keys grouped by domain */
const PERMISSION_DOMAINS: Record<string, string[]> = {
  parts: [
    'parts.view', 'parts.create', 'parts.edit', 'parts.delete',
    'parts.import', 'parts.export', 'parts.manage_categories',
  ],
  inventory: [
    'inventory.view', 'inventory.adjust', 'inventory.transfer',
    'inventory.count', 'inventory.audit',
  ],
  orders: [
    'orders.view', 'orders.create', 'orders.edit', 'orders.delete',
    'orders.approve', 'orders.receive', 'orders.return',
  ],
  jobs: [
    'jobs.view', 'jobs.create', 'jobs.edit', 'jobs.delete',
    'jobs.assign', 'jobs.close', 'jobs.manage_labor',
  ],
  labor: [
    'labor.view', 'labor.clock_in', 'labor.clock_out',
    'labor.edit_entries', 'labor.approve', 'labor.view_all',
  ],
  fleet: [
    'fleet.view', 'fleet.manage_vehicles', 'fleet.manage_assignments',
    'fleet.manage_maintenance', 'fleet.view_mileage',
  ],
  people: [
    'people.view', 'people.create', 'people.edit', 'people.delete',
    'people.manage_hats', 'people.manage_permissions',
    'people.view_wages', 'people.manage_wages',
    'people.view_notes', 'people.manage_notes',
  ],
  tools: [
    'tools.view', 'tools.manage', 'tools.checkout', 'tools.return',
    'tools.manage_kits', 'tools.manage_maintenance',
  ],
  warehouse: [
    'warehouse.view', 'warehouse.manage', 'warehouse.receive',
    'warehouse.ship', 'warehouse.audit',
  ],
  reports: [
    'reports.view', 'reports.create', 'reports.export',
    'reports.manage_periods', 'reports.billing',
  ],
  scheduling: [
    'scheduling.view', 'scheduling.manage', 'scheduling.dispatch',
    'scheduling.approve_pto',
  ],
  admin: [
    'admin.full_access', 'admin.manage_users', 'admin.manage_settings',
    'admin.manage_devices', 'admin.view_audit_log',
  ],
};

// ── Internal Helpers ───────────────────────────────────────────────

/** Build a HatDetail from a raw hats row */
async function enrichHat(hatRow: Record<string, any>): Promise<HatDetail> {
  const db = await getDb();

  const permResult = await db.query(
    'SELECT permission_key FROM hat_permissions WHERE hat_id = ? ORDER BY permission_key',
    [hatRow.id],
  );
  const userCountResult = await db.query(
    'SELECT COUNT(*) as cnt FROM user_hats WHERE hat_id = ? AND is_active = 1',
    [hatRow.id],
  );

  return {
    id: hatRow.id,
    name: hatRow.name,
    description: hatRow.description,
    level: hatRow.level ?? 0,
    is_builtin: !!hatRow.is_builtin,
    permissions: permResult.values.map((r: any) => r.permission_key),
    user_count: userCountResult.values[0]?.cnt ?? 0,
    created_at: hatRow.created_at,
  };
}

// ── Hat Functions ──────────────────────────────────────────────────

/** List all hats with permission counts and user counts */
export async function getHats(): Promise<HatDetail[]> {
  const db = await getDb();
  const result = await db.query(
    'SELECT * FROM hats ORDER BY level DESC, name ASC',
  );

  const hats: HatDetail[] = [];
  for (const row of result.values) {
    hats.push(await enrichHat(row));
  }
  return hats;
}

/** Get a single hat by ID */
export async function getHat(hatId: number): Promise<HatDetail | null> {
  const row = await hatRepo.getById(hatId);
  if (!row) return null;
  return enrichHat(row);
}

/** Create a new hat, optionally with initial permissions */
export async function createHat(data: HatCreateData): Promise<HatDetail> {
  const db = await getDb();

  const hatId = await hatRepo.insert({
    name: data.name,
    description: data.description ?? null,
    level: data.level ?? 0,
    is_builtin: 0,
    created_at: new Date().toISOString(),
  });

  // Insert permissions if provided
  if (data.permissions && data.permissions.length > 0) {
    for (const key of data.permissions) {
      await db.run(
        'INSERT OR IGNORE INTO hat_permissions (hat_id, permission_key) VALUES (?, ?)',
        [hatId, key],
      );
    }
  }

  return (await getHat(hatId))!;
}

/** Update hat fields (name, description, level) */
export async function updateHat(hatId: number, data: HatUpdateData): Promise<HatDetail | null> {
  const updatePayload: Record<string, any> = {};
  if (data.name !== undefined) updatePayload.name = data.name;
  if (data.description !== undefined) updatePayload.description = data.description;
  if (data.level !== undefined) updatePayload.level = data.level;

  if (Object.keys(updatePayload).length === 0) {
    return getHat(hatId);
  }

  const updated = await hatRepo.update(hatId, updatePayload);
  if (!updated) return null;
  return getHat(hatId);
}

/** Soft-delete a hat (built-in hats with is_builtin=1 cannot be deleted) */
export async function deleteHat(hatId: number): Promise<boolean> {
  const hat = await hatRepo.getById(hatId);
  if (!hat || hat.is_builtin) return false;

  // Remove all permissions for this hat
  const db = await getDb();
  await db.run('DELETE FROM hat_permissions WHERE hat_id = ?', [hatId]);

  // Deactivate all user assignments
  await db.run(
    'UPDATE user_hats SET is_active = 0 WHERE hat_id = ?',
    [hatId],
  );

  // Delete the hat itself (hard delete — hats don't have deleted_at per migration 008)
  return hatRepo.delete(hatId);
}

/**
 * Replace all permissions for a hat.
 * Deletes existing permissions, then inserts the new set.
 */
export async function setHatPermissions(
  hatId: number,
  permissionKeys: string[],
): Promise<HatDetail | null> {
  const db = await getDb();

  // Verify hat exists
  const hat = await hatRepo.getById(hatId);
  if (!hat) return null;

  // Delete all existing permissions
  await db.run('DELETE FROM hat_permissions WHERE hat_id = ?', [hatId]);

  // Insert new permissions
  for (const key of permissionKeys) {
    await db.run(
      'INSERT OR IGNORE INTO hat_permissions (hat_id, permission_key) VALUES (?, ?)',
      [hatId, key],
    );
  }

  return getHat(hatId);
}

// ── Permission Matrix ──────────────────────────────────────────────

/**
 * Full permission matrix: all hats x all permissions, grouped by domain.
 * Includes both hardcoded known keys and any dynamically-assigned keys
 * found in the hat_permissions table.
 */
export async function getPermissionMatrix(): Promise<PermissionMatrixData> {
  const db = await getDb();

  // Get all hats
  const hatsResult = await db.query(
    'SELECT id, name, level FROM hats ORDER BY level DESC, name ASC',
  );
  const hats = hatsResult.values as Array<{ id: number; name: string; level: number }>;

  // Get all assigned permissions
  const permResult = await db.query(
    'SELECT hat_id, permission_key FROM hat_permissions ORDER BY permission_key',
  );

  // Build a set of assigned permissions per hat
  const hatPermMap = new Map<number, Set<string>>();
  for (const hat of hats) {
    hatPermMap.set(hat.id, new Set());
  }
  for (const row of permResult.values) {
    const set = hatPermMap.get(row.hat_id);
    if (set) set.add(row.permission_key);
  }

  // Collect any dynamically-assigned keys not in our known set
  const allKnownKeys = new Set<string>();
  for (const keys of Object.values(PERMISSION_DOMAINS)) {
    for (const k of keys) allKnownKeys.add(k);
  }

  const extraKeys: string[] = [];
  for (const row of permResult.values) {
    if (!allKnownKeys.has(row.permission_key)) {
      allKnownKeys.add(row.permission_key);
      extraKeys.push(row.permission_key);
    }
  }

  // Build the matrix grouped by domain
  const domains: Record<string, PermissionMatrixRow[]> = {};

  for (const [domain, keys] of Object.entries(PERMISSION_DOMAINS)) {
    domains[domain] = keys.map(key => ({
      permission_key: key,
      domain,
      hat_values: Object.fromEntries(
        hats.map(h => [h.id, hatPermMap.get(h.id)?.has(key) ?? false]),
      ),
    }));
  }

  // Add any extra keys under an "other" domain
  if (extraKeys.length > 0) {
    domains['other'] = extraKeys.sort().map(key => ({
      permission_key: key,
      domain: 'other',
      hat_values: Object.fromEntries(
        hats.map(h => [h.id, hatPermMap.get(h.id)?.has(key) ?? false]),
      ),
    }));
  }

  return { hats, domains };
}

/** Get all known permission keys (union of hardcoded + dynamically assigned) */
export async function getPermissionKeys(): Promise<string[]> {
  const db = await getDb();

  // Start with hardcoded keys
  const keys = new Set<string>();
  for (const domainKeys of Object.values(PERMISSION_DOMAINS)) {
    for (const k of domainKeys) keys.add(k);
  }

  // Add any additional keys from the database
  const result = await db.query(
    'SELECT DISTINCT permission_key FROM hat_permissions ORDER BY permission_key',
  );
  for (const row of result.values) {
    keys.add(row.permission_key);
  }

  return Array.from(keys).sort();
}
