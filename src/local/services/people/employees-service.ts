/**
 * People — Employees service.
 *
 * CRUD on the `users` table: list, detail, create, update, toggle active,
 * avatar upload, and CSV import.
 *
 * Depends on: certifications, wages, notes, skills sub-services for
 * composing the full EmployeeDetail.
 */

import { getDb } from '../../db';
import { BaseRepo } from '../../repos/base-repo';
import { getUserCertifications, type Certification } from './certifications-service';
import { addWageEntry, getWageHistory, getCurrentPayRate, type WageHistoryEntry } from './wages-service';
import { getEmployeeNotes, type EmployeeNote } from './notes-service';
import { getUserSkills, type UserSkill } from './skills-service';

// ── Types ──────────────────────────────────────────────────────────

export interface EmployeeListParams {
  search?: string;
  is_active?: boolean;
  hat_id?: number;
  page?: number;
  page_size?: number;
}

export interface EmployeeListItem {
  id: number;
  display_name: string;
  email: string | null;
  phone: string | null;
  certification: string | null;
  hire_date: string | null;
  pay_rate: number | null;
  is_active: boolean;
  avatar_url: string | null;
  hat_names: string[];
  active_cert_count: number;
}

export interface EmployeeDetail {
  id: number;
  display_name: string;
  email: string | null;
  phone: string | null;
  certification: string | null;
  hire_date: string | null;
  pay_rate: number | null;
  is_active: boolean;
  avatar_url: string | null;
  emergency_contact_name: string | null;
  emergency_contact_phone: string | null;
  hats: Array<{ id: number; name: string; level: number }>;
  permissions: string[];
  certifications: Certification[];
  wage_history: WageHistoryEntry[];
  notes: EmployeeNote[];
  skills: UserSkill[];
  current_pay_rate: number | null;
  created_at: string | null;
  updated_at: string | null;
}

export interface EmployeeCreateData {
  display_name: string;
  pin: string;
  email?: string | null;
  phone?: string | null;
  certification?: string | null;
  hire_date?: string | null;
  pay_rate?: number | null;
  hat_ids?: number[] | null;
  emergency_contact_name?: string | null;
  emergency_contact_phone?: string | null;
}

export interface EmployeeUpdateData {
  display_name?: string | null;
  email?: string | null;
  phone?: string | null;
  certification?: string | null;
  hire_date?: string | null;
  pay_rate?: number | null;
  emergency_contact_name?: string | null;
  emergency_contact_phone?: string | null;
}

export interface PaginatedResult<T> {
  items: T[];
  total: number;
  page: number;
  page_size: number;
}

export interface CSVImportResult {
  created: number;
  skipped: number;
  errors: Array<{ row: number; error: string }>;
}

// ── Repo ───────────────────────────────────────────────────────────

const userRepo = new BaseRepo('users');

// ── Functions ──────────────────────────────────────────────────────

/** Paginated employee list with search/filters */
export async function getEmployees(
  params: EmployeeListParams = {},
): Promise<PaginatedResult<EmployeeListItem>> {
  const db = await getDb();
  const page = params.page ?? 1;
  const pageSize = params.page_size ?? 50;
  const offset = (page - 1) * pageSize;

  const conditions: string[] = ['u.deleted_at IS NULL'];
  const queryParams: any[] = [];

  if (params.search) {
    conditions.push(
      "(u.display_name LIKE ? OR u.email LIKE ? OR u.phone LIKE ?)",
    );
    const term = `%${params.search}%`;
    queryParams.push(term, term, term);
  }

  if (params.is_active !== undefined) {
    conditions.push('u.is_active = ?');
    queryParams.push(params.is_active ? 1 : 0);
  }

  // If filtering by hat, join user_hats
  let hatJoin = '';
  if (params.hat_id) {
    hatJoin = 'JOIN user_hats uh ON uh.user_id = u.id AND uh.is_active = 1';
    conditions.push('uh.hat_id = ?');
    queryParams.push(params.hat_id);
  }

  const whereClause = conditions.join(' AND ');

  // Count total
  const countResult = await db.query(
    `SELECT COUNT(DISTINCT u.id) as cnt FROM users u ${hatJoin} WHERE ${whereClause}`,
    queryParams,
  );
  const total = countResult.values[0]?.cnt ?? 0;

  // Fetch page
  const rows = await db.query(
    `SELECT DISTINCT u.id, u.display_name, u.email, u.phone, u.certification,
            u.hire_date, u.pay_rate, u.is_active, u.avatar_url
     FROM users u ${hatJoin}
     WHERE ${whereClause}
     ORDER BY u.display_name ASC
     LIMIT ? OFFSET ?`,
    [...queryParams, pageSize, offset],
  );

  // Enrich with hat names and cert counts
  const items: EmployeeListItem[] = [];
  for (const row of rows.values) {
    const hatsResult = await db.query(
      `SELECT h.name FROM hats h
       JOIN user_hats uh ON uh.hat_id = h.id
       WHERE uh.user_id = ? AND uh.is_active = 1`,
      [row.id],
    );
    const certCountResult = await db.query(
      `SELECT COUNT(*) as cnt FROM certifications
       WHERE user_id = ? AND deleted_at IS NULL AND is_active = 1`,
      [row.id],
    );

    items.push({
      id: row.id,
      display_name: row.display_name,
      email: row.email,
      phone: row.phone,
      certification: row.certification,
      hire_date: row.hire_date,
      pay_rate: row.pay_rate,
      is_active: !!row.is_active,
      avatar_url: row.avatar_url,
      hat_names: hatsResult.values.map((h: any) => h.name),
      active_cert_count: certCountResult.values[0]?.cnt ?? 0,
    });
  }

  return { items, total, page, page_size: pageSize };
}

/** Full employee detail with all related data */
export async function getEmployee(userId: number): Promise<EmployeeDetail | null> {
  const db = await getDb();

  const userResult = await db.query(
    'SELECT * FROM users WHERE id = ? AND deleted_at IS NULL',
    [userId],
  );
  const user = userResult.values[0];
  if (!user) return null;

  // Hats
  const hatsResult = await db.query(
    `SELECT h.id, h.name, h.level FROM hats h
     JOIN user_hats uh ON uh.hat_id = h.id
     WHERE uh.user_id = ? AND uh.is_active = 1`,
    [userId],
  );

  // Permissions (aggregate from all active hats)
  const permResult = await db.query(
    `SELECT DISTINCT hp.permission_key FROM hat_permissions hp
     JOIN user_hats uh ON uh.hat_id = hp.hat_id
     WHERE uh.user_id = ? AND uh.is_active = 1
     ORDER BY hp.permission_key`,
    [userId],
  );

  // Related collections
  const certifications = await getUserCertifications(userId, {
    include_inactive: true,
    include_expired: true,
  });
  const wageHistory = await getWageHistory(userId);
  const notes = await getEmployeeNotes(userId, { include_private: true });
  const skills = await getUserSkills(userId);
  const currentPayRate = await getCurrentPayRate(userId);

  return {
    id: user.id,
    display_name: user.display_name,
    email: user.email,
    phone: user.phone,
    certification: user.certification,
    hire_date: user.hire_date,
    pay_rate: user.pay_rate,
    is_active: !!user.is_active,
    avatar_url: user.avatar_url,
    emergency_contact_name: user.emergency_contact_name,
    emergency_contact_phone: user.emergency_contact_phone,
    hats: hatsResult.values as any[],
    permissions: permResult.values.map((r: any) => r.permission_key),
    certifications,
    wage_history: wageHistory,
    notes,
    skills,
    current_pay_rate: currentPayRate,
    created_at: user.created_at,
    updated_at: user.updated_at,
  };
}

/**
 * Create a new employee — inserts user, assigns hats, and optionally
 * creates the first wage history entry.
 *
 * PIN is hashed using SHA-256 for offline verification. The real bcrypt
 * hash is created on sync with the shop server.
 */
export async function createEmployee(data: EmployeeCreateData): Promise<EmployeeDetail> {
  const db = await getDb();
  const now = new Date().toISOString();

  // Hash the PIN for local storage (simple SHA-256 for offline use)
  let pinHash: string;
  try {
    const encoder = new TextEncoder();
    const hashBuffer = await crypto.subtle.digest('SHA-256', encoder.encode(data.pin));
    const hashArray = Array.from(new Uint8Array(hashBuffer));
    pinHash = 'sha256:' + hashArray.map(b => b.toString(16).padStart(2, '0')).join('');
  } catch {
    // Fallback: store a placeholder that forces shop sync for real auth
    pinHash = '__PLACEHOLDER_HASH__';
  }

  const userId = await userRepo.insert({
    display_name: data.display_name,
    pin_hash: pinHash,
    email: data.email ?? null,
    phone: data.phone ?? null,
    certification: data.certification ?? null,
    hire_date: data.hire_date ?? null,
    pay_rate: data.pay_rate ?? null,
    emergency_contact_name: data.emergency_contact_name ?? null,
    emergency_contact_phone: data.emergency_contact_phone ?? null,
    is_active: 1,
    avatar_url: null,
    created_at: now,
    updated_at: now,
  });

  // Assign hats
  if (data.hat_ids && data.hat_ids.length > 0) {
    for (const hatId of data.hat_ids) {
      await db.run(
        'INSERT OR IGNORE INTO user_hats (user_id, hat_id, is_active) VALUES (?, ?, 1)',
        [userId, hatId],
      );
    }
  }

  // Create initial wage entry if pay_rate provided
  if (data.pay_rate != null) {
    await addWageEntry({
      user_id: userId,
      pay_rate: data.pay_rate,
      effective_date: data.hire_date ?? now.split('T')[0],
      reason: 'hire',
    });
  }

  return (await getEmployee(userId))!;
}

/** Update employee fields on the users table */
export async function updateEmployee(
  userId: number,
  data: EmployeeUpdateData,
): Promise<EmployeeDetail | null> {
  // Build update payload, stripping undefined values
  const updatePayload: Record<string, any> = { updated_at: new Date().toISOString() };
  if (data.display_name !== undefined) updatePayload.display_name = data.display_name;
  if (data.email !== undefined) updatePayload.email = data.email;
  if (data.phone !== undefined) updatePayload.phone = data.phone;
  if (data.certification !== undefined) updatePayload.certification = data.certification;
  if (data.hire_date !== undefined) updatePayload.hire_date = data.hire_date;
  if (data.emergency_contact_name !== undefined) updatePayload.emergency_contact_name = data.emergency_contact_name;
  if (data.emergency_contact_phone !== undefined) updatePayload.emergency_contact_phone = data.emergency_contact_phone;

  // If pay_rate changes, also create a wage history entry
  if (data.pay_rate !== undefined) {
    updatePayload.pay_rate = data.pay_rate;
    if (data.pay_rate != null) {
      await addWageEntry({
        user_id: userId,
        pay_rate: data.pay_rate,
        effective_date: new Date().toISOString().split('T')[0],
        reason: 'adjustment',
      });
    }
  }

  const updated = await userRepo.update(userId, updatePayload);
  if (!updated) return null;
  return getEmployee(userId);
}

/** Activate or deactivate an employee */
export async function toggleEmployeeActive(
  userId: number,
  isActive: boolean,
): Promise<{ user_id: number; is_active: boolean }> {
  await userRepo.update(userId, {
    is_active: isActive ? 1 : 0,
    updated_at: new Date().toISOString(),
  });
  return { user_id: userId, is_active: isActive };
}

/**
 * Store an avatar file path for an employee.
 * In local mode we don't upload to a server — we just record the path.
 */
export async function uploadEmployeeAvatar(
  employeeId: number,
  filePath: string,
): Promise<{ avatar_url: string }> {
  await userRepo.update(employeeId, {
    avatar_url: filePath,
    updated_at: new Date().toISOString(),
  });
  return { avatar_url: filePath };
}

/**
 * Import employees from CSV text.
 *
 * Expected CSV columns (header row required):
 *   display_name, pin, email, phone, certification, hire_date, pay_rate, hat_id
 *
 * - display_name and pin are required; others are optional.
 * - hat_id can be comma-separated for multiple hats (e.g. "1,3").
 * - Rows with missing display_name or pin are skipped with an error.
 * - Duplicate display_names are skipped.
 */
export async function importEmployeesCSV(csvText: string): Promise<CSVImportResult> {
  const lines = csvText.trim().split('\n');
  if (lines.length < 2) {
    return { created: 0, skipped: 0, errors: [{ row: 0, error: 'No data rows found' }] };
  }

  // Parse header
  const header = lines[0].split(',').map(h => h.trim().toLowerCase().replace(/['"]/g, ''));
  const colIndex = (name: string) => header.indexOf(name);

  const nameIdx = colIndex('display_name');
  const pinIdx = colIndex('pin');
  const emailIdx = colIndex('email');
  const phoneIdx = colIndex('phone');
  const certIdx = colIndex('certification');
  const hireDateIdx = colIndex('hire_date');
  const payRateIdx = colIndex('pay_rate');
  const hatIdIdx = colIndex('hat_id');

  if (nameIdx === -1) {
    return { created: 0, skipped: 0, errors: [{ row: 0, error: 'Missing required column: display_name' }] };
  }
  if (pinIdx === -1) {
    return { created: 0, skipped: 0, errors: [{ row: 0, error: 'Missing required column: pin' }] };
  }

  const result: CSVImportResult = { created: 0, skipped: 0, errors: [] };

  // Track existing names to detect duplicates
  const db = await getDb();
  const existingResult = await db.query(
    'SELECT display_name FROM users WHERE deleted_at IS NULL',
  );
  const existingNames = new Set(
    existingResult.values.map((r: any) => r.display_name?.toLowerCase()),
  );

  for (let i = 1; i < lines.length; i++) {
    const line = lines[i].trim();
    if (!line) continue;

    // Simple CSV parse (handles basic quoting)
    const cols = parseCSVLine(line);

    const displayName = cols[nameIdx]?.trim();
    const pin = cols[pinIdx]?.trim();

    if (!displayName) {
      result.errors.push({ row: i + 1, error: 'Missing display_name' });
      result.skipped++;
      continue;
    }
    if (!pin) {
      result.errors.push({ row: i + 1, error: 'Missing pin' });
      result.skipped++;
      continue;
    }
    if (existingNames.has(displayName.toLowerCase())) {
      result.errors.push({ row: i + 1, error: `Duplicate: "${displayName}" already exists` });
      result.skipped++;
      continue;
    }

    try {
      const hatIds = hatIdIdx >= 0 && cols[hatIdIdx]
        ? cols[hatIdIdx].split(',').map(id => parseInt(id.trim(), 10)).filter(n => !isNaN(n))
        : undefined;

      const payRate = payRateIdx >= 0 && cols[payRateIdx]
        ? parseFloat(cols[payRateIdx])
        : undefined;

      await createEmployee({
        display_name: displayName,
        pin,
        email: emailIdx >= 0 ? cols[emailIdx]?.trim() || null : null,
        phone: phoneIdx >= 0 ? cols[phoneIdx]?.trim() || null : null,
        certification: certIdx >= 0 ? cols[certIdx]?.trim() || null : null,
        hire_date: hireDateIdx >= 0 ? cols[hireDateIdx]?.trim() || null : null,
        pay_rate: payRate != null && !isNaN(payRate) ? payRate : null,
        hat_ids: hatIds && hatIds.length > 0 ? hatIds : null,
      });

      existingNames.add(displayName.toLowerCase());
      result.created++;
    } catch (err: any) {
      result.errors.push({ row: i + 1, error: err.message || 'Unknown error' });
      result.skipped++;
    }
  }

  return result;
}

/** Simple CSV line parser that handles basic double-quote escaping */
function parseCSVLine(line: string): string[] {
  const result: string[] = [];
  let current = '';
  let inQuotes = false;

  for (let i = 0; i < line.length; i++) {
    const ch = line[i];
    if (inQuotes) {
      if (ch === '"') {
        if (i + 1 < line.length && line[i + 1] === '"') {
          current += '"';
          i++; // skip escaped quote
        } else {
          inQuotes = false;
        }
      } else {
        current += ch;
      }
    } else if (ch === '"') {
      inQuotes = true;
    } else if (ch === ',') {
      result.push(current.trim());
      current = '';
    } else {
      current += ch;
    }
  }
  result.push(current.trim());
  return result;
}
