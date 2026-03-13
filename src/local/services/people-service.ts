/**
 * Local People Service — employee companion data (certifications, wages, notes, skills, teams).
 *
 * Mirrors the companion portions of backend people services for offline use.
 * Supports: certifications, wage history, employee notes, skills, teams.
 * NOT ported: cost-layer analysis, payroll integration (shop-only).
 *
 * Source tables: migration 009_people_full
 */

import { getDb } from '../db';
import { BaseRepo } from '../repos/base-repo';

// ── Types ──────────────────────────────────────────────────────────

// --- Certifications ---

export interface CertificationCreate {
  user_id: number;
  cert_type: string;
  cert_name: string;
  issuing_authority?: string;
  cert_number?: string;
  issued_date?: string;
  expiry_date?: string;
  notes?: string;
  document_path?: string;
}

export interface CertificationUpdate {
  cert_name?: string;
  issuing_authority?: string;
  cert_number?: string;
  issued_date?: string;
  expiry_date?: string;
  is_active?: number;
  notes?: string;
  document_path?: string;
}

export interface Certification {
  id: number;
  user_id: number;
  cert_type: string;
  cert_name: string;
  issuing_authority: string | null;
  cert_number: string | null;
  issued_date: string | null;
  expiry_date: string | null;
  is_active: number;
  notes: string | null;
  document_path: string | null;
  deleted_at: string | null;
  created_at: string;
  updated_at: string;
}

// --- Wage History ---

export interface WageHistoryCreate {
  user_id: number;
  pay_rate: number;
  effective_date: string;
  reason?: string;
  changed_by?: number;
}

export interface WageHistoryEntry {
  id: number;
  user_id: number;
  pay_rate: number;
  effective_date: string;
  reason: string | null;
  changed_by: number | null;
  created_at: string;
}

// --- Employee Notes ---

export interface EmployeeNoteCreate {
  user_id: number;
  note_type?: string;
  title: string;
  body: string;
  is_private?: number;
  created_by: number;
}

export interface EmployeeNoteUpdate {
  title?: string;
  body?: string;
  note_type?: string;
  is_private?: number;
}

export interface EmployeeNote {
  id: number;
  user_id: number;
  note_type: string;
  title: string;
  body: string;
  is_private: number;
  created_by: number | null;
  deleted_at: string | null;
  created_at: string;
  updated_at: string;
}

// --- User Skills ---

export interface UserSkillCreate {
  user_id: number;
  skill_name: string;
  proficiency?: string;
  years_experience?: number;
  verified_by?: number;
}

export interface UserSkillUpdate {
  proficiency?: string;
  years_experience?: number;
  verified_by?: number;
  verified_at?: string;
}

export interface UserSkill {
  id: number;
  user_id: number;
  skill_name: string;
  proficiency: string;
  years_experience: number | null;
  verified_by: number | null;
  verified_at: string | null;
  deleted_at: string | null;
  created_at: string;
}

// --- Teams ---

export interface TeamCreate {
  name: string;
  description?: string;
  lead_user_id?: number;
}

export interface TeamUpdate {
  name?: string;
  description?: string;
  lead_user_id?: number;
  is_active?: number;
}

export interface Team {
  id: number;
  name: string;
  description: string | null;
  lead_user_id: number | null;
  is_active: number;
  deleted_at: string | null;
  created_at: string;
  updated_at: string;
  member_count?: number;
  lead_name?: string;
}

export interface TeamMember {
  id: number;
  team_id: number;
  user_id: number;
  role: string;
  joined_at: string;
  deleted_at: string | null;
  display_name?: string;
}

// ── Repos ──────────────────────────────────────────────────────────

const certRepo = new BaseRepo('certifications');
const wageRepo = new BaseRepo('wage_history');
const noteRepo = new BaseRepo('employee_notes');
const skillRepo = new BaseRepo('user_skills');
const teamRepo = new BaseRepo('employee_teams');
const memberRepo = new BaseRepo('employee_team_members');

// ═══════════════════════════════════════════════════════════════════
// CERTIFICATIONS
// ═══════════════════════════════════════════════════════════════════

/** Create a certification record */
export async function createCertification(data: CertificationCreate): Promise<Certification> {
  const now = new Date().toISOString();
  const id = await certRepo.insert({
    user_id: data.user_id,
    cert_type: data.cert_type,
    cert_name: data.cert_name,
    issuing_authority: data.issuing_authority ?? null,
    cert_number: data.cert_number ?? null,
    issued_date: data.issued_date ?? null,
    expiry_date: data.expiry_date ?? null,
    notes: data.notes ?? null,
    document_path: data.document_path ?? null,
    is_active: 1,
    created_at: now,
    updated_at: now,
  });
  return (await getCertification(id))!;
}

/** Get a single certification by ID */
export async function getCertification(id: number): Promise<Certification | null> {
  const row = await certRepo.getById(id);
  return row ? (row as Certification) : null;
}

/** List certifications for a user */
export async function getUserCertifications(
  userId: number,
  opts?: { include_inactive?: boolean; include_expired?: boolean },
): Promise<Certification[]> {
  const conditions: string[] = ['user_id = ?', 'deleted_at IS NULL'];
  const params: any[] = [userId];

  if (!opts?.include_inactive) {
    conditions.push('is_active = 1');
  }
  if (!opts?.include_expired) {
    conditions.push("(expiry_date IS NULL OR expiry_date >= date('now'))");
  }

  return (await certRepo.findAll(
    conditions.join(' AND '),
    params,
    'expiry_date ASC',
  )) as Certification[];
}

/** Get certifications expiring within N days */
export async function getExpiringCertifications(days: number = 30): Promise<Certification[]> {
  const db = await getDb();
  const result = await db.query(
    `SELECT c.*, u.display_name as holder_name
     FROM certifications c
     JOIN users u ON u.id = c.user_id
     WHERE c.deleted_at IS NULL AND c.is_active = 1
       AND c.expiry_date IS NOT NULL
       AND c.expiry_date <= date('now', '+' || ? || ' days')
       AND c.expiry_date >= date('now')
     ORDER BY c.expiry_date ASC`,
    [days],
  );
  return result.values as Certification[];
}

/** Update a certification */
export async function updateCertification(id: number, data: CertificationUpdate): Promise<Certification | null> {
  const updated = await certRepo.update(id, {
    ...data,
    updated_at: new Date().toISOString(),
  });
  if (!updated) return null;
  return getCertification(id);
}

/** Soft-delete a certification */
export async function deleteCertification(id: number): Promise<boolean> {
  return certRepo.update(id, { deleted_at: new Date().toISOString() });
}

// ═══════════════════════════════════════════════════════════════════
// WAGE HISTORY (immutable — insert only, no update/delete)
// ═══════════════════════════════════════════════════════════════════

/** Add a wage history entry */
export async function addWageEntry(data: WageHistoryCreate): Promise<WageHistoryEntry> {
  const id = await wageRepo.insert({
    user_id: data.user_id,
    pay_rate: data.pay_rate,
    effective_date: data.effective_date,
    reason: data.reason ?? null,
    changed_by: data.changed_by ?? null,
    created_at: new Date().toISOString(),
  });
  return (await wageRepo.getById(id)) as WageHistoryEntry;
}

/** Get wage history for a user, newest first */
export async function getWageHistory(userId: number): Promise<WageHistoryEntry[]> {
  return (await wageRepo.findAll(
    'user_id = ?',
    [userId],
    'effective_date DESC',
  )) as WageHistoryEntry[];
}

/** Get current pay rate for a user */
export async function getCurrentPayRate(userId: number): Promise<number | null> {
  const db = await getDb();
  const result = await db.query(
    `SELECT pay_rate FROM wage_history
     WHERE user_id = ? AND effective_date <= date('now')
     ORDER BY effective_date DESC, id DESC LIMIT 1`,
    [userId],
  );
  return result.values[0]?.pay_rate ?? null;
}

// ═══════════════════════════════════════════════════════════════════
// EMPLOYEE NOTES
// ═══════════════════════════════════════════════════════════════════

/** Create an employee note */
export async function createEmployeeNote(data: EmployeeNoteCreate): Promise<EmployeeNote> {
  const now = new Date().toISOString();
  const id = await noteRepo.insert({
    user_id: data.user_id,
    note_type: data.note_type ?? 'general',
    title: data.title,
    body: data.body,
    is_private: data.is_private ?? 0,
    created_by: data.created_by,
    created_at: now,
    updated_at: now,
  });
  return (await noteRepo.getById(id)) as EmployeeNote;
}

/** List notes for a user */
export async function getEmployeeNotes(
  userId: number,
  opts?: { note_type?: string; include_private?: boolean },
): Promise<EmployeeNote[]> {
  const conditions: string[] = ['user_id = ?', 'deleted_at IS NULL'];
  const params: any[] = [userId];

  if (opts?.note_type) {
    conditions.push('note_type = ?');
    params.push(opts.note_type);
  }
  if (!opts?.include_private) {
    conditions.push('is_private = 0');
  }

  return (await noteRepo.findAll(
    conditions.join(' AND '),
    params,
    'created_at DESC',
  )) as EmployeeNote[];
}

/** Update an employee note */
export async function updateEmployeeNote(id: number, data: EmployeeNoteUpdate): Promise<EmployeeNote | null> {
  const updated = await noteRepo.update(id, {
    ...data,
    updated_at: new Date().toISOString(),
  });
  if (!updated) return null;
  return (await noteRepo.getById(id)) as EmployeeNote;
}

/** Soft-delete an employee note */
export async function deleteEmployeeNote(id: number): Promise<boolean> {
  return noteRepo.update(id, { deleted_at: new Date().toISOString() });
}

// ═══════════════════════════════════════════════════════════════════
// USER SKILLS
// ═══════════════════════════════════════════════════════════════════

/** Add a skill to a user */
export async function addUserSkill(data: UserSkillCreate): Promise<UserSkill> {
  const id = await skillRepo.insert({
    user_id: data.user_id,
    skill_name: data.skill_name,
    proficiency: data.proficiency ?? 'intermediate',
    years_experience: data.years_experience ?? null,
    verified_by: data.verified_by ?? null,
    verified_at: data.verified_by ? new Date().toISOString() : null,
    created_at: new Date().toISOString(),
  });
  return (await skillRepo.getById(id)) as UserSkill;
}

/** List skills for a user */
export async function getUserSkills(userId: number): Promise<UserSkill[]> {
  return (await skillRepo.findAll(
    'user_id = ? AND deleted_at IS NULL',
    [userId],
    'skill_name ASC',
  )) as UserSkill[];
}

/** Update a skill */
export async function updateUserSkill(id: number, data: UserSkillUpdate): Promise<UserSkill | null> {
  const updated = await skillRepo.update(id, data);
  if (!updated) return null;
  return (await skillRepo.getById(id)) as UserSkill;
}

/** Soft-delete a skill */
export async function deleteUserSkill(id: number): Promise<boolean> {
  return skillRepo.update(id, { deleted_at: new Date().toISOString() });
}

/** Search skills across all users (for finding experts) */
export async function searchSkills(
  skillName: string,
  opts?: { proficiency?: string },
): Promise<(UserSkill & { display_name: string })[]> {
  const db = await getDb();
  const conditions: string[] = [
    'us.deleted_at IS NULL',
    'us.skill_name LIKE ?',
  ];
  const params: any[] = [`%${skillName}%`];

  if (opts?.proficiency) {
    conditions.push('us.proficiency = ?');
    params.push(opts.proficiency);
  }

  const result = await db.query(
    `SELECT us.*, u.display_name
     FROM user_skills us
     JOIN users u ON u.id = us.user_id
     WHERE ${conditions.join(' AND ')}
     ORDER BY us.proficiency DESC, us.years_experience DESC`,
    params,
  );
  return result.values as any[];
}

// ═══════════════════════════════════════════════════════════════════
// EMPLOYEE TEAMS
// ═══════════════════════════════════════════════════════════════════

/** Create a team */
export async function createTeam(data: TeamCreate): Promise<Team> {
  const now = new Date().toISOString();
  const id = await teamRepo.insert({
    name: data.name,
    description: data.description ?? null,
    lead_user_id: data.lead_user_id ?? null,
    is_active: 1,
    created_at: now,
    updated_at: now,
  });
  return (await getTeam(id))!;
}

/** Get a team with member count */
export async function getTeam(teamId: number): Promise<Team | null> {
  const db = await getDb();
  const result = await db.query(
    `SELECT t.*,
       (SELECT COUNT(*) FROM employee_team_members m
        WHERE m.team_id = t.id AND m.deleted_at IS NULL) as member_count,
       (SELECT u.display_name FROM users u WHERE u.id = t.lead_user_id) as lead_name
     FROM employee_teams t
     WHERE t.id = ? AND t.deleted_at IS NULL`,
    [teamId],
  );
  return (result.values[0] as Team) ?? null;
}

/** List all teams */
export async function listTeams(opts?: {
  include_inactive?: boolean;
}): Promise<Team[]> {
  const db = await getDb();
  const conditions: string[] = ['t.deleted_at IS NULL'];
  if (!opts?.include_inactive) {
    conditions.push('t.is_active = 1');
  }

  const result = await db.query(
    `SELECT t.*,
       (SELECT COUNT(*) FROM employee_team_members m
        WHERE m.team_id = t.id AND m.deleted_at IS NULL) as member_count,
       (SELECT u.display_name FROM users u WHERE u.id = t.lead_user_id) as lead_name
     FROM employee_teams t
     WHERE ${conditions.join(' AND ')}
     ORDER BY t.name ASC`,
  );
  return result.values as Team[];
}

/** Update a team */
export async function updateTeam(id: number, data: TeamUpdate): Promise<Team | null> {
  const updated = await teamRepo.update(id, {
    ...data,
    updated_at: new Date().toISOString(),
  });
  if (!updated) return null;
  return getTeam(id);
}

/** Soft-delete a team */
export async function deleteTeam(id: number): Promise<boolean> {
  return teamRepo.update(id, { deleted_at: new Date().toISOString() });
}

// ═══════════════════════════════════════════════════════════════════
// TEAM MEMBERS
// ═══════════════════════════════════════════════════════════════════

/** Add a member to a team */
export async function addTeamMember(
  teamId: number,
  userId: number,
  role: string = 'member',
): Promise<TeamMember> {
  const id = await memberRepo.insert({
    team_id: teamId,
    user_id: userId,
    role,
    joined_at: new Date().toISOString(),
  });
  return (await memberRepo.getById(id)) as TeamMember;
}

/** Get members of a team */
export async function getTeamMembers(teamId: number): Promise<TeamMember[]> {
  const db = await getDb();
  const result = await db.query(
    `SELECT m.*, u.display_name
     FROM employee_team_members m
     JOIN users u ON u.id = m.user_id
     WHERE m.team_id = ? AND m.deleted_at IS NULL
     ORDER BY m.role ASC, u.display_name ASC`,
    [teamId],
  );
  return result.values as TeamMember[];
}

/** Remove a member from a team (soft-delete) */
export async function removeTeamMember(memberId: number): Promise<boolean> {
  return memberRepo.update(memberId, { deleted_at: new Date().toISOString() });
}

/** Get teams a user belongs to */
export async function getUserTeams(userId: number): Promise<Team[]> {
  const db = await getDb();
  const result = await db.query(
    `SELECT t.*, m.role as member_role
     FROM employee_teams t
     JOIN employee_team_members m ON m.team_id = t.id
     WHERE m.user_id = ? AND m.deleted_at IS NULL AND t.deleted_at IS NULL
     ORDER BY t.name ASC`,
    [userId],
  );
  return result.values as Team[];
}

/** Update a team member's role */
export async function updateTeamMemberRole(
  teamId: number,
  userId: number,
  role: 'lead' | 'member',
): Promise<boolean> {
  const db = await getDb();
  const result = await db.run(
    `UPDATE employee_team_members SET role = ?
     WHERE team_id = ? AND user_id = ? AND deleted_at IS NULL`,
    [role, teamId, userId],
  );
  return result.changes.changes > 0;
}


// ═══════════════════════════════════════════════════════════════════
// EMPLOYEES (CRUD on `users` table)
// ═══════════════════════════════════════════════════════════════════

// ── Additional Types ─────────────────────────────────────────────

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

const userRepo = new BaseRepo('users');

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


// ═══════════════════════════════════════════════════════════════════
// HATS (ROLES)
// ═══════════════════════════════════════════════════════════════════

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

const hatRepo = new BaseRepo('hats');

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


// ═══════════════════════════════════════════════════════════════════
// PERMISSION MATRIX
// ═══════════════════════════════════════════════════════════════════

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

export interface PermissionMatrixRow {
  permission_key: string;
  domain: string;
  hat_values: Record<number, boolean>;
}

export interface PermissionMatrixData {
  hats: Array<{ id: number; name: string; level: number }>;
  domains: Record<string, PermissionMatrixRow[]>;
}

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


// ═══════════════════════════════════════════════════════════════════
// JOB LEAD ELEVATIONS
// ═══════════════════════════════════════════════════════════════════

export interface JobLeadElevation {
  id: number;
  user_id: number;
  user_name?: string;
  job_id: number;
  job_name?: string;
  permission_key: string;
  granted_by: number;
  granted_by_name?: string;
  granted_at: string | null;
  expires_at: string | null;
}

export interface JobLeadElevationCreateData {
  job_id: number;
  permission_key: string;
  expires_at?: string | null;
}

const elevationRepo = new BaseRepo('job_lead_elevations');

/** List all job-lead elevations for a user */
export async function getUserElevations(userId: number): Promise<JobLeadElevation[]> {
  try {
    const db = await getDb();
    const result = await db.query(
      `SELECT e.*,
              u.display_name as user_name,
              j.name as job_name,
              g.display_name as granted_by_name
       FROM job_lead_elevations e
       LEFT JOIN users u ON u.id = e.user_id
       LEFT JOIN jobs j ON j.id = e.job_id
       LEFT JOIN users g ON g.id = e.granted_by
       WHERE e.user_id = ? AND e.deleted_at IS NULL
         AND (e.expires_at IS NULL OR e.expires_at > datetime('now'))
       ORDER BY e.granted_at DESC`,
      [userId],
    );
    return result.values as JobLeadElevation[];
  } catch {
    // Table may not exist yet — graceful degradation
    return [];
  }
}

/** Grant a job-specific permission elevation to a user */
export async function grantElevation(
  userId: number,
  data: JobLeadElevationCreateData,
  grantedBy: number,
): Promise<{ id: number }> {
  const id = await elevationRepo.insert({
    user_id: userId,
    job_id: data.job_id,
    permission_key: data.permission_key,
    granted_by: grantedBy,
    granted_at: new Date().toISOString(),
    expires_at: data.expires_at ?? null,
  });
  return { id };
}

/** Revoke (soft-delete) a single job-lead elevation */
export async function revokeElevation(elevationId: number): Promise<{ id: number }> {
  await elevationRepo.update(elevationId, {
    deleted_at: new Date().toISOString(),
  });
  return { id: elevationId };
}

/** Revoke all elevations for a user on a specific job */
export async function revokeAllElevationsForJob(
  userId: number,
  jobId: number,
): Promise<{ count: number }> {
  const db = await getDb();
  const result = await db.run(
    `UPDATE job_lead_elevations
     SET deleted_at = datetime('now')
     WHERE user_id = ? AND job_id = ? AND deleted_at IS NULL`,
    [userId, jobId],
  );
  return { count: result.changes.changes };
}


// ═══════════════════════════════════════════════════════════════════
// FILE OPERATIONS (simplified for local / Tauri)
// ═══════════════════════════════════════════════════════════════════

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
 * Store a certification document path.
 * In local mode we just record the file path in the certifications row.
 */
export async function uploadCertificationDocument(
  certId: number,
  filePath: string,
): Promise<{ document_path: string }> {
  await certRepo.update(certId, {
    document_path: filePath,
    updated_at: new Date().toISOString(),
  });
  return { document_path: filePath };
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
export interface CSVImportResult {
  created: number;
  skipped: number;
  errors: Array<{ row: number; error: string }>;
}

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
