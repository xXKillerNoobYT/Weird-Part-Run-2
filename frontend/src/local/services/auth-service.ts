/**
 * Local Auth Service — PIN authentication for offline use.
 *
 * On mobile devices, users authenticate against the local SQLite DB.
 * User records are synced from the shop server. PIN verification uses
 * bcrypt hashes stored locally. JWT tokens are generated locally for
 * session management.
 *
 * Shop-only features (user CRUD, hat management) are NOT here.
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
 * Since bcrypt isn't available natively in the browser/Capacitor,
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
 * Capacitor equivalent of GET /auth/me.
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
