/**
 * Local Auth Service — PIN authentication + first-run bootstrap.
 *
 * Every device authenticates against its own local SQLite DB.
 * User records come from either:
 *   1. seedFirstAdmin() — the very first device in a new company
 *   2. Sync from another device — all subsequent devices
 *
 * PIN verification uses SHA-256 hashes stored locally. Session tokens
 * are base64-encoded JSON payloads (24-hour expiry).
 */

import { getDb } from '../db';

// ── Types ──────────────────────────────────────────────────────────

export interface LocalUser {
  id: number;
  display_name: string;
  email: string | null;
  phone: string | null;
  avatar_url: string | null;
  certification: string | null;
  hire_date: string | null;
  is_active: number;
  default_truck_id: number | null;
  created_at: string;
  updated_at: string;
}

export interface AuthResult {
  success: boolean;
  user: LocalUser | null;
  token: string | null;
  message: string;
}

export interface UserPermission {
  permission_key: string;
}

// ── Service Functions ──────────────────────────────────────────────

/**
 * Authenticate a user by PIN against the local database.
 *
 * Since bcrypt isn't available natively in the browser/Tauri WebView,
 * we store a simple SHA-256 hash for offline verification. The real
 * bcrypt check happens on sync with the shop. For V1.0, we use a
 * PIN comparison approach: the shop syncs a device-specific auth
 * token that we validate locally.
 *
 * Flow:
 * 1. User enters PIN
 * 2. We look up the user and compare the PIN hash
 * 3. On match, we generate a local session token
 * 4. The token is stored in memory (Zustand) for the session
 */
export async function authenticateByPin(
  userId: number,
  pin: string,
): Promise<AuthResult> {
  const db = await getDb();

  const result = await db.query(
    'SELECT * FROM users WHERE id = ? AND is_active = 1',
    [userId],
  );

  const user = result.values[0] as LocalUser | undefined;
  if (!user) {
    return { success: false, user: null, token: null, message: 'User not found or inactive' };
  }

  // Verify PIN hash (synced from shop)
  const pinResult = await db.query(
    'SELECT pin_hash FROM users WHERE id = ?',
    [userId],
  );
  const pinHash = pinResult.values[0]?.pin_hash as string | undefined;

  if (!pinHash || pinHash === '__PLACEHOLDER_HASH__') {
    return { success: false, user: null, token: null, message: 'PIN not configured. Sync with shop first.' };
  }

  // Use the local PIN verification (SHA-256 for offline, synced from shop)
  const isValid = await verifyPinLocally(pin, pinHash);
  if (!isValid) {
    return { success: false, user: null, token: null, message: 'Invalid PIN' };
  }

  // Generate a local session token (simple UUID-based, not JWT)
  const token = generateLocalToken(userId);

  return {
    success: true,
    user,
    token,
    message: 'Authenticated',
  };
}

/** Get list of active users for the login screen */
export async function getActiveUsers(): Promise<LocalUser[]> {
  const db = await getDb();
  const result = await db.query(
    'SELECT id, display_name, email, phone, avatar_url, certification, hire_date, is_active, default_truck_id, created_at, updated_at FROM users WHERE is_active = 1 ORDER BY display_name ASC',
  );
  return result.values as LocalUser[];
}

/**
 * Bootstrap a brand-new company database on the very first device.
 *
 * Creates:
 *  - 7 built-in hats (Admin → Grunt) with permission keys
 *  - 1 admin user with the given display name and PIN
 *  - Assigns the Admin hat to that user
 *
 * This is the ONLY way to start from zero. All subsequent devices
 * receive data by syncing from this one (or any peer that already has it).
 *
 * Returns the new user's ID and a session token so the caller can
 * immediately log in without a second PIN prompt.
 */
export async function seedFirstAdmin(
  displayName: string,
  pin: string,
): Promise<AuthResult> {
  const db = await getDb();

  // Guard: don't re-seed if users already exist
  const existing = await db.query('SELECT COUNT(*) AS cnt FROM users');
  if ((existing.values[0]?.cnt as number) > 0) {
    return { success: false, user: null, token: null, message: 'Users already exist. Seed aborted.' };
  }

  const now = new Date().toISOString().replace('T', ' ').slice(0, 19);
  const pinHash = await hashPin(pin);

  // ── 1. Create built-in hats ──────────────────────────────────────
  const hats = [
    { name: 'Admin',      level: 100, description: 'Full system access' },
    { name: 'Manager',    level: 80,  description: 'Most permissions except system settings' },
    { name: 'Office',     level: 60,  description: 'Ordering, reports, scheduling' },
    { name: 'Lead',       level: 50,  description: 'Field lead with scoped job management' },
    { name: 'Worker',     level: 30,  description: 'Basic field access' },
    { name: 'Apprentice', level: 20,  description: 'Restricted field access' },
    { name: 'Grunt',      level: 10,  description: 'Minimal access' },
  ];

  for (const hat of hats) {
    await db.query(
      `INSERT OR IGNORE INTO hats (name, description, level, is_builtin, created_at)
       VALUES (?, ?, ?, 1, ?)`,
      [hat.name, hat.description, hat.level, now],
    );
  }

  // ── 2. Assign permission keys to each hat ────────────────────────
  const permissionMap: Record<string, string[]> = {
    Admin: [
      'view_parts_catalog', 'edit_parts_catalog', 'edit_pricing', 'show_dollar_values',
      'manage_deprecation', 'view_warehouse', 'manage_warehouse', 'move_stock_warehouse',
      'view_trucks', 'manage_trucks', 'move_stock_truck', 'view_jobs', 'manage_jobs',
      'clock_in_out', 'consume_parts_any_job', 'view_labor', 'manage_labor',
      'view_orders', 'manage_orders', 'approve_returns', 'view_people', 'manage_people',
      'view_reports', 'export_reports', 'manage_settings', 'manage_devices',
      'manage_templates', 'manage_notebooks', 'perform_audit', 'manager_override', 'view_activity_log',
      'view_fleet', 'manage_fleet', 'view_tools', 'manage_tools',
      'view_scheduling', 'manage_scheduling', 'manage_dispatch',
      'view_schedule', 'manage_schedule', 'dispatch_employees',
      'manage_time_off', 'manage_subcontractors',
      'view_chat', 'manage_chat', 'moderate_chat',
    ],
    Manager: [
      'view_parts_catalog', 'edit_parts_catalog', 'edit_pricing', 'show_dollar_values',
      'manage_deprecation', 'view_warehouse', 'manage_warehouse', 'move_stock_warehouse',
      'view_trucks', 'manage_trucks', 'move_stock_truck', 'view_jobs', 'manage_jobs',
      'clock_in_out', 'consume_parts_any_job', 'view_labor', 'manage_labor',
      'view_orders', 'manage_orders', 'approve_returns', 'view_people', 'manage_people',
      'view_reports', 'export_reports', 'manage_templates', 'manage_notebooks', 'perform_audit',
      'manager_override', 'view_activity_log',
      'view_fleet', 'manage_fleet', 'view_tools', 'manage_tools',
      'view_scheduling', 'manage_scheduling', 'manage_dispatch',
      'view_schedule', 'manage_schedule', 'dispatch_employees',
    ],
    Office: [
      'view_parts_catalog', 'edit_parts_catalog', 'show_dollar_values',
      'view_warehouse', 'view_trucks', 'view_jobs', 'manage_jobs',
      'view_labor', 'manage_labor', 'view_orders', 'manage_orders',
      'view_people', 'view_reports', 'export_reports',
      'view_scheduling', 'manage_scheduling', 'view_schedule', 'dispatch_employees',
    ],
    Lead: [
      'view_parts_catalog', 'view_warehouse', 'view_trucks', 'move_stock_truck',
      'view_jobs', 'manage_jobs', 'clock_in_out', 'consume_parts_any_job',
      'view_labor', 'view_orders', 'view_reports',
      'view_fleet', 'view_tools', 'view_scheduling', 'view_schedule',
    ],
    Worker: [
      'view_parts_catalog', 'view_warehouse', 'view_trucks', 'move_stock_truck',
      'view_jobs', 'clock_in_out', 'view_labor', 'view_orders',
      'view_fleet', 'view_tools', 'view_schedule',
    ],
    Apprentice: [
      'view_parts_catalog', 'view_trucks', 'view_jobs', 'clock_in_out', 'view_labor',
    ],
    Grunt: [
      'view_parts_catalog', 'view_trucks', 'view_jobs', 'clock_in_out',
    ],
  };

  for (const [hatName, perms] of Object.entries(permissionMap)) {
    for (const perm of perms) {
      await db.query(
        `INSERT OR IGNORE INTO hat_permissions (hat_id, permission_key)
         SELECT id, ? FROM hats WHERE name = ?`,
        [perm, hatName],
      );
    }
  }

  // ── 3. Create the first admin user ───────────────────────────────
  await db.query(
    `INSERT INTO users (display_name, pin_hash, is_active, created_at, updated_at)
     VALUES (?, ?, 1, ?, ?)`,
    [displayName, pinHash, now, now],
  );

  // Get the new user's ID
  const userResult = await db.query(
    'SELECT id FROM users WHERE display_name = ? ORDER BY id DESC LIMIT 1',
    [displayName],
  );
  const userId = userResult.values[0]?.id as number;

  // ── 4. Assign Admin hat ──────────────────────────────────────────
  await db.query(
    `INSERT INTO user_hats (user_id, hat_id, is_active)
     SELECT ?, id, 1 FROM hats WHERE name = 'Admin'`,
    [userId],
  );

  // ── 5. Seed default settings ─────────────────────────────────────
  const defaultSettings = [
    ['company_name', displayName + "'s Company", 'general'],
    ['auto_lock_minutes', '15', 'security'],
    ['stale_data_hours', '4', 'sync'],
    ['archive_completed_days', '90', 'data'],
  ];
  for (const [key, value, category] of defaultSettings) {
    await db.query(
      `INSERT OR IGNORE INTO settings (key, value, category, updated_at)
       VALUES (?, ?, ?, ?)`,
      [key, value, category, now],
    );
  }

  // Log to activity log
  await db.query(
    `INSERT INTO activity_log (user_id, action, entity_type, entity_id, details, timestamp)
     VALUES (?, 'first_admin_setup', 'user', ?, 'First device bootstrap', ?)`,
    [userId, userId, now],
  );

  // Return a session token so the caller can log in immediately
  const user = await getUser(userId);
  const token = generateLocalToken(userId);

  return {
    success: true,
    user,
    token,
    message: 'Company database initialized. Welcome!',
  };
}

/** Get a single user by ID */
export async function getUser(userId: number): Promise<LocalUser | null> {
  const db = await getDb();
  const result = await db.query(
    'SELECT id, display_name, email, phone, avatar_url, certification, hire_date, is_active, default_truck_id, created_at, updated_at FROM users WHERE id = ?',
    [userId],
  );
  return (result.values[0] as LocalUser) ?? null;
}

/** Get permissions for a user (from user_hats + hat_permissions) */
export async function getUserPermissions(userId: number): Promise<string[]> {
  const db = await getDb();
  const result = await db.query(
    `SELECT DISTINCT hp.permission_key
     FROM user_hats uh
     JOIN hat_permissions hp ON hp.hat_id = uh.hat_id
     WHERE uh.user_id = ? AND uh.is_active = 1`,
    [userId],
  );
  return result.values.map((r) => r.permission_key as string);
}

/** Check if user has a specific permission */
export async function hasPermission(userId: number, permissionKey: string): Promise<boolean> {
  const db = await getDb();
  const result = await db.query(
    `SELECT 1 FROM user_hats uh
     JOIN hat_permissions hp ON hp.hat_id = uh.hat_id
     WHERE uh.user_id = ? AND uh.is_active = 1 AND hp.permission_key = ?
     LIMIT 1`,
    [userId, permissionKey],
  );
  return result.values.length > 0;
}

/** Get hat names for a user (for UserPicker display) */
export async function getUserHatNames(userId: number): Promise<string[]> {
  const db = await getDb();
  const result = await db.query(
    `SELECT h.name FROM user_hats uh
     JOIN hats h ON h.id = uh.hat_id
     WHERE uh.user_id = ? AND uh.is_active = 1
     ORDER BY h.level DESC`,
    [userId],
  );
  return result.values.map((r) => r.name as string);
}

/** Get hat summaries for a user (for UserProfile) */
export async function getUserHats(userId: number): Promise<{ id: number; name: string; level: number }[]> {
  const db = await getDb();
  const result = await db.query(
    `SELECT h.id, h.name, h.level FROM user_hats uh
     JOIN hats h ON h.id = uh.hat_id
     WHERE uh.user_id = ? AND uh.is_active = 1
     ORDER BY h.level DESC`,
    [userId],
  );
  return result.values as { id: number; name: string; level: number }[];
}

/**
 * Build a full UserProfile from a local token.
 *
 * Decodes the base64 token to extract the user ID, then queries the
 * local database for user details, hats, and permissions. This is the
 * Tauri equivalent of GET /auth/me.
 *
 * Throws if the token is expired or user not found.
 */
export async function getLocalUserProfile(token: string): Promise<{
  id: number;
  display_name: string;
  email: string | null;
  phone: string | null;
  avatar_url: string | null;
  certification: string | null;
  hire_date: string | null;
  is_active: boolean;
  hats: { id: number; name: string; level: number }[];
  permissions: string[];
  created_at: string | null;
}> {
  const payload = parseLocalToken(token);
  if (!payload) throw new Error('Invalid local token');

  if (payload.exp < Date.now()) {
    throw new Error('Token expired');
  }

  const userId = payload.sub;
  const user = await getUser(userId);
  if (!user) throw new Error('User not found');

  const hats = await getUserHats(userId);
  const permissions = await getUserPermissions(userId);

  return {
    id: user.id,
    display_name: user.display_name,
    email: user.email,
    phone: user.phone,
    avatar_url: user.avatar_url,
    certification: user.certification,
    hire_date: user.hire_date,
    is_active: !!user.is_active,
    hats,
    permissions,
    created_at: user.created_at,
  };
}

// ── Internal Helpers ───────────────────────────────────────────────

/**
 * Verify a PIN against a stored hash.
 *
 * For offline mode, the shop syncs a simplified hash that can be
 * verified without bcrypt. This is a SHA-256 of the PIN + a
 * device-specific salt. The real bcrypt verification happens
 * server-side during sync.
 */
async function verifyPinLocally(pin: string, storedHash: string): Promise<boolean> {
  // If the hash starts with '$2b$' it's bcrypt — we can't verify offline
  // without a bcrypt library. For V1.0, the sync engine provides a
  // device-verifiable hash alongside the bcrypt hash.
  if (storedHash.startsWith('$2b$') || storedHash.startsWith('$2a$')) {
    // Fallback: use the offline_pin_hash field if available
    // This is set by the sync engine specifically for offline verification
    // For now, we'll need the bcrypt-compatible library
    try {
      const { compare } = await import('bcryptjs');
      return await compare(pin, storedHash);
    } catch {
      // bcryptjs not available — PIN verification requires shop sync
      console.warn('bcryptjs not available for offline PIN verification');
      return false;
    }
  }

  // Simple hash comparison (SHA-256 based, set by sync engine)
  const encoder = new TextEncoder();
  const data = encoder.encode(pin + ':wiredpart');
  const hashBuffer = await crypto.subtle.digest('SHA-256', data);
  const hashArray = Array.from(new Uint8Array(hashBuffer));
  const hashHex = hashArray.map((b) => b.toString(16).padStart(2, '0')).join('');
  return hashHex === storedHash;
}

/**
 * Hash a PIN for local storage (SHA-256 with fixed salt).
 *
 * This produces the same hash format that verifyPinLocally() checks against.
 * Used by seedFirstAdmin() to set the initial admin PIN.
 */
async function hashPin(pin: string): Promise<string> {
  const encoder = new TextEncoder();
  const data = encoder.encode(pin + ':wiredpart');
  const hashBuffer = await crypto.subtle.digest('SHA-256', data);
  const hashArray = Array.from(new Uint8Array(hashBuffer));
  return hashArray.map((b) => b.toString(16).padStart(2, '0')).join('');
}

/**
 * DEV ONLY: Auto-login without PIN verification.
 * Used for iOS Simulator testing where keyboard input is broken.
 * Skips PIN hash check — just verifies user exists and generates token.
 *
 * If userId is 0 or not found, falls back to the first active user.
 */
export async function devAutoLogin(userId: number): Promise<AuthResult> {
  const db = await getDb();

  // Try specific user first, then fall back to first active user
  let result = await db.query(
    'SELECT * FROM users WHERE id = ? AND is_active = 1',
    [userId],
  );
  let user = result.values?.[0] as LocalUser | undefined;

  if (!user) {
    // Fallback: first active user in the DB
    result = await db.query(
      'SELECT * FROM users WHERE is_active = 1 ORDER BY id ASC LIMIT 1',
    );
    user = result.values?.[0] as LocalUser | undefined;
  }

  if (!user) {
    return { success: false, user: null, token: null, message: 'No active users in local DB' };
  }

  const token = generateLocalToken(user.id);
  return { success: true, user, token, message: `DEV auto-login as ${user.display_name} (id=${user.id})` };
}

/** Generate a simple local session token */
function generateLocalToken(userId: number): string {
  const payload = {
    sub: userId,
    iat: Date.now(),
    exp: Date.now() + 24 * 60 * 60 * 1000, // 24 hours
    type: 'local',
  };
  return btoa(JSON.stringify(payload));
}

/** Parse a local token (base64-encoded JSON). Returns null if invalid. */
function parseLocalToken(token: string): { sub: number; iat: number; exp: number; type: string } | null {
  try {
    const json = atob(token);
    const payload = JSON.parse(json);
    if (payload.type !== 'local' || typeof payload.sub !== 'number') return null;
    return payload;
  } catch {
    return null;
  }
}
