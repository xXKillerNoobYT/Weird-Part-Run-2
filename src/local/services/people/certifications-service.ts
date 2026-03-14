/**
 * People — Certifications service.
 *
 * CRUD for employee certifications with expiry tracking.
 * Source table: certifications (migration 009_people_full)
 */

import { getDb } from '../../db';
import { BaseRepo } from '../../repos/base-repo';

// ── Types ──────────────────────────────────────────────────────────

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

// ── Repo ───────────────────────────────────────────────────────────

const certRepo = new BaseRepo('certifications');

// ── Functions ──────────────────────────────────────────────────────

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
