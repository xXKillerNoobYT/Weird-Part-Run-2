/**
 * People — Job Lead Elevations service.
 *
 * Grant/revoke temporary job-specific permission elevations to employees.
 * Source table: job_lead_elevations (migration 015_job_team_suppliers)
 */

import { getDb } from '../../db';
import { BaseRepo } from '../../repos/base-repo';

// ── Types ──────────────────────────────────────────────────────────

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

// ── Repo ───────────────────────────────────────────────────────────

const elevationRepo = new BaseRepo('job_lead_elevations');

// ── Functions ──────────────────────────────────────────────────────

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
