/**
 * Local Notebook Service — entries and tasks for offline use.
 *
 * Mirrors backend/app/services/notebook_service.py for field workers.
 * Supports: notebook list/detail, entry CRUD, task status updates.
 *
 * Template management is shop-only — templates are synced down
 * and used locally for creating notebooks.
 */

import { getDb } from '../db';
import { BaseRepo } from '../repos/base-repo';

// ── Types ──────────────────────────────────────────────────────────

export interface Notebook {
  id: number;
  title: string;
  description: string | null;
  job_id: number | null;
  template_id: number | null;
  created_by: number;
  is_archived: number;
  created_at: string;
  updated_at: string;
  // Joined
  job_name?: string;
  job_number?: string;
  creator_name?: string;
  section_count?: number;
  task_count?: number;
  open_task_count?: number;
}

export interface NotebookSection {
  id: number;
  notebook_id: number;
  name: string;
  section_type: string;
  sort_order: number;
  is_locked: number;
  created_at: string;
}

export interface NotebookEntry {
  id: number;
  section_id: number;
  title: string;
  content: string | null;
  entry_type: string;
  field_type: string | null;
  field_required: number;
  field_filled_by: number | null;
  task_status: string | null;
  task_due_date: string | null;
  task_assigned_to: number | null;
  task_parts_note: string | null;
  created_by: number;
  updated_by: number | null;
  is_deleted: number;
  sort_order: number;
  created_at: string;
  updated_at: string;
  // Joined
  creator_name?: string;
  assignee_name?: string;
}

export interface EntryCreate {
  title: string;
  content?: string;
  entry_type?: string;
  field_type?: string;
  field_required?: boolean;
  task_status?: string;
  task_due_date?: string;
  task_assigned_to?: number;
  task_parts_note?: string;
}

export interface TaskSummary {
  id: number;
  notebook_id: number;
  section_id: number;
  title: string;
  status: string;
  due_date: string | null;
  assigned_to: number | null;
  assignee_name: string | null;
  parts_note: string | null;
  job_id: number | null;
  notebook_title: string | null;
  created_at: string;
  updated_at: string;
}

const notebookRepo = new BaseRepo('notebooks');
const sectionRepo = new BaseRepo('notebook_sections');
const entryRepo = new BaseRepo('notebook_entries');

const TASK_STATUSES = ['planned', 'parts_ordered', 'parts_delivered', 'in_progress', 'done'];

// ── Notebook Functions ─────────────────────────────────────────────

/** List notebooks with optional job filter */
export async function listNotebooks(opts?: {
  job_id?: number;
  include_archived?: boolean;
  limit?: number;
}): Promise<Notebook[]> {
  const db = await getDb();
  const conditions: string[] = [];
  const params: any[] = [];

  if (opts?.job_id) {
    conditions.push('nb.job_id = ?');
    params.push(opts.job_id);
  }
  if (!opts?.include_archived) {
    conditions.push('nb.is_archived = 0');
  }

  const where = conditions.length ? `WHERE ${conditions.join(' AND ')}` : '';

  const result = await db.query(
    `SELECT nb.*,
       j.job_name, j.job_number,
       u.display_name as creator_name,
       (SELECT COUNT(*) FROM notebook_sections WHERE notebook_id = nb.id) as section_count,
       (SELECT COUNT(*) FROM notebook_entries ne
        JOIN notebook_sections ns ON ns.id = ne.section_id
        WHERE ns.notebook_id = nb.id AND ne.entry_type = 'task' AND ne.is_deleted = 0) as task_count,
       (SELECT COUNT(*) FROM notebook_entries ne
        JOIN notebook_sections ns ON ns.id = ne.section_id
        WHERE ns.notebook_id = nb.id AND ne.entry_type = 'task'
          AND ne.task_status != 'done' AND ne.is_deleted = 0) as open_task_count
     FROM notebooks nb
     LEFT JOIN jobs j ON j.id = nb.job_id
     LEFT JOIN users u ON u.id = nb.created_by
     ${where}
     ORDER BY nb.updated_at DESC
     LIMIT ?`,
    [...params, opts?.limit ?? 100],
  );
  return result.values as Notebook[];
}

/** Get a notebook with all sections and entries */
export async function getNotebook(notebookId: number): Promise<{
  notebook: Notebook;
  sections: (NotebookSection & { entries: NotebookEntry[] })[];
} | null> {
  const db = await getDb();

  // Get notebook
  const nbResult = await db.query(
    `SELECT nb.*, j.job_name, j.job_number, u.display_name as creator_name
     FROM notebooks nb
     LEFT JOIN jobs j ON j.id = nb.job_id
     LEFT JOIN users u ON u.id = nb.created_by
     WHERE nb.id = ?`,
    [notebookId],
  );
  const notebook = nbResult.values[0] as Notebook | undefined;
  if (!notebook) return null;

  // Get sections
  const sectionsResult = await db.query(
    `SELECT * FROM notebook_sections WHERE notebook_id = ? ORDER BY sort_order ASC`,
    [notebookId],
  );

  const sections: (NotebookSection & { entries: NotebookEntry[] })[] = [];

  for (const section of sectionsResult.values as NotebookSection[]) {
    const entriesResult = await db.query(
      `SELECT ne.*, u.display_name as creator_name, au.display_name as assignee_name
       FROM notebook_entries ne
       LEFT JOIN users u ON u.id = ne.created_by
       LEFT JOIN users au ON au.id = ne.task_assigned_to
       WHERE ne.section_id = ? AND ne.is_deleted = 0
       ORDER BY ne.sort_order ASC`,
      [section.id],
    );
    sections.push({ ...section, entries: entriesResult.values as NotebookEntry[] });
  }

  return { notebook, sections };
}

/** Create a new notebook (optionally from template) */
export async function createNotebook(
  data: { title: string; description?: string; job_id?: number; template_id?: number },
  userId: number,
): Promise<Notebook> {
  const now = new Date().toISOString();

  const nbId = await notebookRepo.insert({
    title: data.title,
    description: data.description ?? null,
    job_id: data.job_id ?? null,
    template_id: data.template_id ?? null,
    created_by: userId,
    is_archived: 0,
    created_at: now,
    updated_at: now,
  });

  // If template, copy sections and entries
  if (data.template_id) {
    await copyTemplateToNotebook(data.template_id, nbId, userId);
  }

  const result = await listNotebooks();
  return result.find((nb) => nb.id === nbId)!;
}

// ── Section Functions ──────────────────────────────────────────────

/** Create a section in a notebook */
export async function createSection(
  notebookId: number,
  data: { name: string; section_type?: string },
): Promise<NotebookSection> {
  const db = await getDb();

  // Get max sort_order
  const maxResult = await db.query(
    'SELECT MAX(sort_order) as max_order FROM notebook_sections WHERE notebook_id = ?',
    [notebookId],
  );
  const sortOrder = (maxResult.values[0]?.max_order ?? 0) + 1;

  const sectionId = await sectionRepo.insert({
    notebook_id: notebookId,
    name: data.name,
    section_type: data.section_type ?? 'notes',
    sort_order: sortOrder,
    is_locked: 0,
    created_at: new Date().toISOString(),
  });

  return (await sectionRepo.getById(sectionId)) as NotebookSection;
}

// ── Entry Functions ────────────────────────────────────────────────

/** Create an entry in a section */
export async function createEntry(
  sectionId: number,
  data: EntryCreate,
  userId: number,
): Promise<NotebookEntry> {
  const db = await getDb();
  const now = new Date().toISOString();

  const maxResult = await db.query(
    'SELECT MAX(sort_order) as max_order FROM notebook_entries WHERE section_id = ?',
    [sectionId],
  );
  const sortOrder = (maxResult.values[0]?.max_order ?? 0) + 1;

  const entryId = await entryRepo.insert({
    section_id: sectionId,
    title: data.title,
    content: data.content ?? null,
    entry_type: data.entry_type ?? 'note',
    field_type: data.field_type ?? null,
    field_required: data.field_required ? 1 : 0,
    field_filled_by: null,
    task_status: data.task_status ?? (data.entry_type === 'task' ? 'planned' : null),
    task_due_date: data.task_due_date ?? null,
    task_assigned_to: data.task_assigned_to ?? null,
    task_parts_note: data.task_parts_note ?? null,
    created_by: userId,
    updated_by: null,
    is_deleted: 0,
    deleted_by: null,
    deleted_at: null,
    sort_order: sortOrder,
    created_at: now,
    updated_at: now,
  });

  // Touch parent notebook
  const section = await sectionRepo.getById(sectionId);
  if (section) {
    await notebookRepo.update(section.notebook_id, { updated_at: now }, false);
  }

  return (await entryRepo.getById(entryId)) as NotebookEntry;
}

/** Update an entry */
export async function updateEntry(
  entryId: number,
  data: Partial<EntryCreate>,
  userId: number,
): Promise<NotebookEntry | null> {
  const existing = await entryRepo.getById(entryId);
  if (!existing || existing.is_deleted) return null;

  const updateData: Record<string, any> = {
    updated_by: userId,
    updated_at: new Date().toISOString(),
  };

  if (data.title !== undefined) updateData.title = data.title;
  if (data.content !== undefined) updateData.content = data.content;
  if (data.task_status !== undefined) updateData.task_status = data.task_status;
  if (data.task_due_date !== undefined) updateData.task_due_date = data.task_due_date;
  if (data.task_assigned_to !== undefined) updateData.task_assigned_to = data.task_assigned_to;
  if (data.task_parts_note !== undefined) updateData.task_parts_note = data.task_parts_note;

  // Lock field after first fill
  if (existing.entry_type === 'field' && data.content && !existing.field_filled_by) {
    updateData.field_filled_by = userId;
  }

  await entryRepo.update(entryId, updateData);
  return (await entryRepo.getById(entryId)) as NotebookEntry;
}

/** Soft-delete an entry */
export async function deleteEntry(entryId: number, userId: number): Promise<boolean> {
  return entryRepo.update(entryId, {
    is_deleted: 1,
    deleted_by: userId,
    deleted_at: new Date().toISOString(),
  });
}

/** Update task status */
export async function updateTaskStatus(
  entryId: number,
  newStatus: string,
): Promise<NotebookEntry | null> {
  if (!TASK_STATUSES.includes(newStatus)) {
    throw new Error(`Invalid task status: ${newStatus}`);
  }

  const existing = await entryRepo.getById(entryId);
  if (!existing || existing.entry_type !== 'task') return null;

  await entryRepo.update(entryId, {
    task_status: newStatus,
    updated_at: new Date().toISOString(),
  });

  return (await entryRepo.getById(entryId)) as NotebookEntry;
}

// ── Task Queries ───────────────────────────────────────────────────

/** Get all tasks across notebooks for a job */
export async function getTasksForJob(jobId: number): Promise<TaskSummary[]> {
  const db = await getDb();
  const result = await db.query(
    `SELECT ne.id, ns.notebook_id, ne.section_id, ne.title,
       ne.task_status as status, ne.task_due_date as due_date,
       ne.task_assigned_to as assigned_to,
       u.display_name as assignee_name,
       ne.task_parts_note as parts_note,
       nb.job_id, nb.title as notebook_title,
       ne.created_at, ne.updated_at
     FROM notebook_entries ne
     JOIN notebook_sections ns ON ns.id = ne.section_id
     JOIN notebooks nb ON nb.id = ns.notebook_id
     LEFT JOIN users u ON u.id = ne.task_assigned_to
     WHERE nb.job_id = ? AND ne.entry_type = 'task' AND ne.is_deleted = 0
     ORDER BY ne.task_status ASC, ne.sort_order ASC`,
    [jobId],
  );
  return result.values as TaskSummary[];
}

/** Get all tasks assigned to a user */
export async function getMyTasks(userId: number): Promise<TaskSummary[]> {
  const db = await getDb();
  const result = await db.query(
    `SELECT ne.id, ns.notebook_id, ne.section_id, ne.title,
       ne.task_status as status, ne.task_due_date as due_date,
       ne.task_assigned_to as assigned_to,
       u.display_name as assignee_name,
       ne.task_parts_note as parts_note,
       nb.job_id, nb.title as notebook_title,
       ne.created_at, ne.updated_at
     FROM notebook_entries ne
     JOIN notebook_sections ns ON ns.id = ne.section_id
     JOIN notebooks nb ON nb.id = ns.notebook_id
     LEFT JOIN users u ON u.id = ne.task_assigned_to
     WHERE ne.task_assigned_to = ? AND ne.entry_type = 'task'
       AND ne.is_deleted = 0 AND ne.task_status != 'done'
     ORDER BY ne.task_due_date ASC NULLS LAST, ne.sort_order ASC`,
    [userId],
  );
  return result.values as TaskSummary[];
}

// ── Template Read Functions (synced down, read-only locally) ──────

/** List all notebook templates (synced from shop) */
export async function listTemplates(): Promise<any[]> {
  const db = await getDb();
  const result = await db.query(
    `SELECT t.*, u.display_name as creator_name,
       (SELECT COUNT(*) FROM template_sections WHERE template_id = t.id) as section_count
     FROM notebook_templates t
     LEFT JOIN users u ON u.id = t.created_by
     WHERE t.is_active = 1
     ORDER BY t.name ASC`,
  );
  return result.values;
}

/** Get full template with sections and entries */
export async function getTemplateFull(templateId: number): Promise<any | null> {
  const db = await getDb();
  const tResult = await db.query(
    `SELECT t.*, u.display_name as creator_name
     FROM notebook_templates t
     LEFT JOIN users u ON u.id = t.created_by
     WHERE t.id = ?`,
    [templateId],
  );
  const template = tResult.values[0];
  if (!template) return null;

  const secResult = await db.query(
    `SELECT * FROM template_sections WHERE template_id = ? ORDER BY sort_order ASC`,
    [templateId],
  );

  const sections: any[] = [];
  for (const section of secResult.values) {
    const entResult = await db.query(
      `SELECT * FROM template_entries WHERE section_id = ? ORDER BY sort_order ASC`,
      [section.id],
    );
    sections.push({ ...section, entries: entResult.values });
  }

  return { ...template, sections };
}

// ── Get / Create Job Notebook ─────────────────────────────────────

/** Get or create a notebook for a job (lazy creation) */
export async function getJobNotebook(jobId: number, userId: number): Promise<any> {
  const db = await getDb();

  // Check if job already has a notebook
  const existing = await db.query(
    `SELECT nb.*, j.job_name, j.job_number, u.display_name as creator_name
     FROM notebooks nb
     LEFT JOIN jobs j ON j.id = nb.job_id
     LEFT JOIN users u ON u.id = nb.created_by
     WHERE nb.job_id = ? AND nb.is_archived = 0
     LIMIT 1`,
    [jobId],
  );

  if (existing.values.length > 0) {
    const nb = existing.values[0];
    const full = await getNotebook(nb.id);
    return full;
  }

  // Create one
  const jobResult = await db.query(`SELECT job_name FROM jobs WHERE id = ?`, [jobId]);
  const jobName = jobResult.values[0]?.job_name ?? `Job ${jobId}`;

  const created = await createNotebook(
    { title: `${jobName} Notebook`, job_id: jobId },
    userId,
  );
  return await getNotebook(created.id);
}

// ── Notebook Update / Archive ─────────────────────────────────────

/** Update notebook title/description */
export async function updateNotebook(
  notebookId: number,
  data: { title?: string; description?: string },
): Promise<any> {
  const updateData: Record<string, any> = { updated_at: new Date().toISOString() };
  if (data.title !== undefined) updateData.title = data.title;
  if (data.description !== undefined) updateData.description = data.description;
  await notebookRepo.update(notebookId, updateData);
  return await notebookRepo.getById(notebookId);
}

/** Archive a notebook (soft delete) */
export async function archiveNotebook(notebookId: number): Promise<void> {
  await notebookRepo.update(notebookId, {
    is_archived: 1,
    updated_at: new Date().toISOString(),
  });
}

// ── Section Update / Delete / Reorder ─────────────────────────────

/** Update a section */
export async function updateSection(
  sectionId: number,
  data: { name?: string; section_type?: string; is_locked?: boolean },
): Promise<any> {
  const updateData: Record<string, any> = {};
  if (data.name !== undefined) updateData.name = data.name;
  if (data.section_type !== undefined) updateData.section_type = data.section_type;
  if (data.is_locked !== undefined) updateData.is_locked = data.is_locked ? 1 : 0;
  await sectionRepo.update(sectionId, updateData);
  return await sectionRepo.getById(sectionId);
}

/** Delete a section (cascades to entries) */
export async function deleteSection(sectionId: number): Promise<void> {
  const db = await getDb();
  await db.run(`DELETE FROM notebook_entries WHERE section_id = ?`, [sectionId]);
  await db.run(`DELETE FROM notebook_sections WHERE id = ?`, [sectionId]);
}

/** Reorder sections in a notebook */
export async function reorderSections(
  notebookId: number,
  orderedIds: number[],
): Promise<void> {
  const db = await getDb();
  for (let i = 0; i < orderedIds.length; i++) {
    await db.run(
      `UPDATE notebook_sections SET sort_order = ? WHERE id = ? AND notebook_id = ?`,
      [i, orderedIds[i], notebookId],
    );
  }
}

// ── Entry Extras ──────────────────────────────────────────────────

/** Update field value (first-fill logic) */
export async function updateFieldValue(
  entryId: number,
  data: { content: string },
  userId: number,
): Promise<any> {
  return updateEntry(entryId, { content: data.content }, userId);
}

/** Assign a task to a user */
export async function assignTask(
  entryId: number,
  data: { user_id: number },
  userId: number,
): Promise<any> {
  return updateEntry(entryId, { task_assigned_to: data.user_id }, userId);
}

/** Reorder entries within a section */
export async function reorderEntries(
  sectionId: number,
  orderedIds: number[],
): Promise<void> {
  const db = await getDb();
  for (let i = 0; i < orderedIds.length; i++) {
    await db.run(
      `UPDATE notebook_entries SET sort_order = ? WHERE id = ? AND section_id = ?`,
      [i, orderedIds[i], sectionId],
    );
  }
}

/** Bulk update task status and/or assignee */
export async function bulkUpdateTasks(
  entryIds: number[],
  taskStatus?: string,
  taskAssignedTo?: number,
): Promise<{ updated: number }> {
  const db = await getDb();
  const sets: string[] = ['updated_at = datetime(\'now\')'];
  const params: any[] = [];

  if (taskStatus !== undefined) {
    sets.push('task_status = ?');
    params.push(taskStatus);
  }
  if (taskAssignedTo !== undefined) {
    sets.push('task_assigned_to = ?');
    params.push(taskAssignedTo);
  }

  const placeholders = entryIds.map(() => '?').join(',');
  params.push(...entryIds);

  await db.run(
    `UPDATE notebook_entries SET ${sets.join(', ')} WHERE id IN (${placeholders}) AND entry_type = 'task'`,
    params,
  );
  return { updated: entryIds.length };
}

// ── Job Tasks (cross-cutting query) ──────────────────────────────

/** Get all tasks for a job with optional status filter */
export async function getJobTasks(
  jobId: number,
  status?: string,
): Promise<any[]> {
  const db = await getDb();
  let statusFilter = '';
  const params: any[] = [jobId];
  if (status) {
    statusFilter = 'AND ne.task_status = ?';
    params.push(status);
  }
  const result = await db.query(
    `SELECT ne.*, ns.notebook_id, nb.title as notebook_title,
       u.display_name as creator_name, au.display_name as assignee_name
     FROM notebook_entries ne
     JOIN notebook_sections ns ON ns.id = ne.section_id
     JOIN notebooks nb ON nb.id = ns.notebook_id
     LEFT JOIN users u ON u.id = ne.created_by
     LEFT JOIN users au ON au.id = ne.task_assigned_to
     WHERE nb.job_id = ? AND ne.entry_type = 'task' AND ne.is_deleted = 0
       ${statusFilter}
     ORDER BY ne.task_status ASC, ne.sort_order ASC`,
    params,
  );
  return result.values;
}

// ── Internal Helpers ───────────────────────────────────────────────

async function copyTemplateToNotebook(
  templateId: number,
  notebookId: number,
  userId: number,
): Promise<void> {
  const db = await getDb();
  const now = new Date().toISOString();

  // Get template sections
  const sections = await db.query(
    'SELECT * FROM template_sections WHERE template_id = ? ORDER BY sort_order ASC',
    [templateId],
  );

  for (const section of sections.values) {
    const sectionId = await sectionRepo.insert({
      notebook_id: notebookId,
      name: section.name,
      section_type: section.section_type,
      sort_order: section.sort_order,
      is_locked: section.is_locked,
      created_at: now,
    }, false); // don't track template copies for sync

    // Get template entries for this section
    const entries = await db.query(
      'SELECT * FROM template_entries WHERE section_id = ? ORDER BY sort_order ASC',
      [section.id],
    );

    for (const entry of entries.values) {
      await entryRepo.insert({
        section_id: sectionId,
        title: entry.title,
        content: entry.default_content,
        entry_type: entry.entry_type,
        field_type: entry.field_type,
        field_required: entry.field_required,
        field_filled_by: null,
        task_status: entry.entry_type === 'task' ? 'planned' : null,
        task_due_date: null,
        task_assigned_to: null,
        task_parts_note: null,
        created_by: userId,
        updated_by: null,
        is_deleted: 0,
        deleted_by: null,
        deleted_at: null,
        sort_order: entry.sort_order,
        created_at: now,
        updated_at: now,
      }, false); // don't track template copies for sync
    }
  }
}
