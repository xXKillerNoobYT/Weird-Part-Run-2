/**
 * People — Teams & Team Members service.
 *
 * CRUD for employee teams and membership management.
 * Source tables: employee_teams, employee_team_members (migration 009_people_full)
 */

import { getDb } from '../../db';
import { BaseRepo } from '../../repos/base-repo';

// ── Types ──────────────────────────────────────────────────────────

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

const teamRepo = new BaseRepo('employee_teams');
const memberRepo = new BaseRepo('employee_team_members');

// ── Team Functions ─────────────────────────────────────────────────

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

// ── Team Member Functions ──────────────────────────────────────────

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
