/**
 * People — User Skills service.
 *
 * CRUD for employee skills with proficiency tracking and expert search.
 * Source table: user_skills (migration 009_people_full)
 */

import { getDb } from '../../db';
import { BaseRepo } from '../../repos/base-repo';

// ── Types ──────────────────────────────────────────────────────────

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

// ── Repo ───────────────────────────────────────────────────────────

const skillRepo = new BaseRepo('user_skills');

// ── Functions ──────────────────────────────────────────────────────

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
