/**
 * People — Employee Notes service.
 *
 * CRUD for per-employee notes with privacy controls.
 * Source table: employee_notes (migration 009_people_full)
 */

import { BaseRepo } from '../../repos/base-repo';

// ── Types ──────────────────────────────────────────────────────────

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

// ── Repo ───────────────────────────────────────────────────────────

const noteRepo = new BaseRepo('employee_notes');

// ── Functions ──────────────────────────────────────────────────────

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
