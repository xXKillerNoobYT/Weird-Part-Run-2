/**
 * Report Annotations — add, retrieve, update, and delete annotations on reports.
 *
 * Source table: report_annotations (migration 011_reports_pto)
 */

import { getDb } from '../../db';
import { BaseRepo } from '../../repos/base-repo';

// ── Types ──────────────────────────────────────────────────────────

export interface AnnotationCreate {
  report_type: string;
  context_key: string;
  content: string;
  author_id: number;
}

export interface AnnotationUpdate {
  content?: string;
}

export interface ReportAnnotation {
  id: number;
  report_type: string;
  context_key: string;
  content: string;
  author_id: number;
  deleted_at: string | null;
  created_at: string;
  updated_at: string;
  author_name?: string;
}

// ── Repo ───────────────────────────────────────────────────────────

const annotationRepo = new BaseRepo('report_annotations');

// ── Functions ──────────────────────────────────────────────────────

/** Add an annotation to a report */
export async function createAnnotation(data: AnnotationCreate): Promise<ReportAnnotation> {
  const now = new Date().toISOString();
  const id = await annotationRepo.insert({
    report_type: data.report_type,
    context_key: data.context_key,
    content: data.content,
    author_id: data.author_id,
    created_at: now,
    updated_at: now,
  });
  return (await annotationRepo.getById(id)) as ReportAnnotation;
}

/** Get annotations for a specific report context */
export async function getAnnotations(
  reportType: string,
  contextKey: string,
): Promise<ReportAnnotation[]> {
  const db = await getDb();
  const result = await db.query(
    `SELECT ra.*, u.display_name as author_name
     FROM report_annotations ra
     LEFT JOIN users u ON u.id = ra.author_id
     WHERE ra.report_type = ? AND ra.context_key = ? AND ra.deleted_at IS NULL
     ORDER BY ra.created_at DESC`,
    [reportType, contextKey],
  );
  return result.values as ReportAnnotation[];
}

/** Update an annotation */
export async function updateAnnotation(
  id: number,
  data: AnnotationUpdate,
): Promise<ReportAnnotation | null> {
  const updated = await annotationRepo.update(id, {
    ...data,
    updated_at: new Date().toISOString(),
  });
  if (!updated) return null;
  return (await annotationRepo.getById(id)) as ReportAnnotation;
}

/** Soft-delete an annotation */
export async function deleteAnnotation(id: number): Promise<boolean> {
  return annotationRepo.update(id, { deleted_at: new Date().toISOString() });
}
