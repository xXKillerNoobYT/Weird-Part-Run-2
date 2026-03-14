/**
 * Report Templates — create, list, update, and delete saved report presets.
 *
 * Source table: report_templates (migration 011_reports_pto)
 */

import { getDb } from '../../db';
import { BaseRepo } from '../../repos/base-repo';

// ── Types ──────────────────────────────────────────────────────────

export interface TemplateCreate {
  name: string;
  report_type: string;
  config_json: Record<string, any>;
  created_by: number;
}

export interface TemplateUpdate {
  name?: string;
  config_json?: Record<string, any>;
}

export interface ReportTemplate {
  id: number;
  name: string;
  report_type: string;
  config_json: string; // JSON
  created_by: number;
  deleted_at: string | null;
  created_at: string;
  updated_at: string;
  created_by_name?: string;
}

// ── Repo ───────────────────────────────────────────────────────────

const templateRepo = new BaseRepo('report_templates');

// ── Functions ──────────────────────────────────────────────────────

/** Create a report template */
export async function createTemplate(data: TemplateCreate): Promise<ReportTemplate> {
  const now = new Date().toISOString();
  const id = await templateRepo.insert({
    name: data.name,
    report_type: data.report_type,
    config_json: JSON.stringify(data.config_json),
    created_by: data.created_by,
    created_at: now,
    updated_at: now,
  });
  return (await templateRepo.getById(id)) as ReportTemplate;
}

/** List templates for a report type */
export async function listTemplates(reportType?: string): Promise<ReportTemplate[]> {
  const db = await getDb();
  const conditions: string[] = ['rt.deleted_at IS NULL'];
  const params: any[] = [];

  if (reportType) {
    conditions.push('rt.report_type = ?');
    params.push(reportType);
  }

  const result = await db.query(
    `SELECT rt.*, u.display_name as created_by_name
     FROM report_templates rt
     LEFT JOIN users u ON u.id = rt.created_by
     WHERE ${conditions.join(' AND ')}
     ORDER BY rt.name ASC`,
    params,
  );
  return result.values as ReportTemplate[];
}

/** Update a template */
export async function updateTemplate(
  id: number,
  data: TemplateUpdate,
): Promise<ReportTemplate | null> {
  const updateData: Record<string, any> = {
    updated_at: new Date().toISOString(),
  };
  if (data.name !== undefined) updateData.name = data.name;
  if (data.config_json !== undefined) updateData.config_json = JSON.stringify(data.config_json);

  const updated = await templateRepo.update(id, updateData);
  if (!updated) return null;
  return (await templateRepo.getById(id)) as ReportTemplate;
}

/** Soft-delete a template */
export async function deleteTemplate(id: number): Promise<boolean> {
  return templateRepo.update(id, { deleted_at: new Date().toISOString() });
}
