/**
 * Notebooks types — templates, notebooks, sections, entries, task status unions.
 */

// ═══════════════════════════════════════════════════════════════════
// NOTEBOOKS MODULE (Phase 4.5)
// ═══════════════════════════════════════════════════════════════════

// ── Entry/Section/Task Type Unions ───────────────────────────────

export type EntryType = 'note' | 'task' | 'field';
export type FieldType = 'text' | 'checkbox' | 'textarea';
export type TaskStatus = 'planned' | 'parts_ordered' | 'parts_delivered' | 'in_progress' | 'done';
export type SectionType = 'info' | 'notes' | 'tasks';

export const TASK_STATUS_LABELS: Record<TaskStatus, string> = {
  planned: 'Planned',
  parts_ordered: 'Parts Ordered',
  parts_delivered: 'Parts Delivered',
  in_progress: 'In Progress',
  done: 'Done',
};

export const TASK_STATUS_COLORS: Record<TaskStatus, string> = {
  planned: 'gray',
  parts_ordered: 'amber',
  parts_delivered: 'blue',
  in_progress: 'sky',
  done: 'green',
};

export const TASK_STATUS_ORDER: TaskStatus[] = [
  'planned', 'parts_ordered', 'parts_delivered', 'in_progress', 'done',
];

// ── Template Types ──────────────────────────────────────────────

export interface TemplateCreate {
  name: string;
  description?: string;
  job_type?: string;
  is_default?: boolean;
}

export interface TemplateUpdate {
  name?: string;
  description?: string;
  job_type?: string;
  is_default?: boolean;
}

export interface TemplateResponse {
  id: number;
  name: string;
  description?: string | null;
  job_type?: string | null;
  is_default: boolean;
  created_by?: number | null;
  created_at?: string | null;
  updated_at?: string | null;
}

export interface TemplateEntryCreate {
  title: string;
  default_content?: string;
  entry_type?: EntryType;
  field_type?: FieldType;
  field_required?: boolean;
  sort_order?: number;
}

export interface TemplateEntryResponse {
  id: number;
  section_id: number;
  title: string;
  default_content?: string | null;
  entry_type: EntryType;
  field_type?: FieldType | null;
  field_required: boolean;
  sort_order: number;
}

export interface TemplateSectionCreate {
  name: string;
  section_type?: SectionType;
  sort_order?: number;
  is_locked?: boolean;
}

export interface TemplateSectionUpdate {
  name?: string;
  sort_order?: number;
  is_locked?: boolean;
}

export interface TemplateSectionResponse {
  id: number;
  template_id: number;
  name: string;
  section_type: SectionType;
  sort_order: number;
  is_locked: boolean;
}

export interface TemplateSectionWithEntries extends TemplateSectionResponse {
  entries: TemplateEntryResponse[];
}

export interface TemplateFull {
  id: number;
  name: string;
  description?: string | null;
  job_type?: string | null;
  is_default: boolean;
  created_by?: number | null;
  created_at?: string | null;
  updated_at?: string | null;
  sections: TemplateSectionWithEntries[];
}

// ── Notebook Types ──────────────────────────────────────────────

export interface NotebookCreate {
  title: string;
  description?: string;
}

export interface NotebookUpdate {
  title?: string;
  description?: string;
}

export interface NotebookResponse {
  id: number;
  title: string;
  description?: string | null;
  job_id?: number | null;
  template_id?: number | null;
  created_by: number;
  creator_name?: string | null;
  is_archived: boolean;
  created_at?: string | null;
  updated_at?: string | null;
}

export interface NotebookListItem {
  id: number;
  title: string;
  description?: string | null;
  job_id?: number | null;
  job_name?: string | null;
  job_number?: string | null;
  created_by: number;
  creator_name?: string | null;
  is_archived: boolean;
  open_task_count: number;
  total_task_count: number;
  created_at?: string | null;
  updated_at?: string | null;
}

// ── Section Types ───────────────────────────────────────────────

export interface SectionCreate {
  name: string;
  section_type?: SectionType;
}

export interface SectionUpdate {
  name?: string;
  sort_order?: number;
}

export interface SectionResponse {
  id: number;
  notebook_id: number;
  name: string;
  section_type: SectionType;
  sort_order: number;
  is_locked: boolean;
  created_at?: string | null;
}

export interface SectionReorderRequest {
  ordered_ids: number[];
}

// ── Entry Types ─────────────────────────────────────────────────

export interface EntryCreate {
  title: string;
  content?: string;
  entry_type?: EntryType;
  field_type?: FieldType;
  field_required?: boolean;
  task_status?: TaskStatus;
  task_due_date?: string;
  task_assigned_to?: number;
  task_parts_note?: string;
}

export interface EntryUpdate {
  title?: string;
  content?: string;
  task_status?: TaskStatus;
  task_due_date?: string;
  task_assigned_to?: number;
  task_parts_note?: string;
}

export interface EntryResponse {
  id: number;
  section_id: number;
  title: string;
  content?: string | null;
  entry_type: EntryType;
  field_type?: FieldType | null;
  field_required: boolean;
  field_filled_by?: number | null;
  task_status?: TaskStatus | null;
  task_due_date?: string | null;
  task_assigned_to?: number | null;
  task_assigned_to_name?: string | null;
  task_parts_note?: string | null;
  created_by: number;
  creator_name?: string | null;
  can_edit: boolean;
  sort_order: number;
  created_at?: string | null;
  updated_at?: string | null;
}

export interface TaskStatusUpdate {
  status: TaskStatus;
  parts_note?: string;
}

export interface FieldValueUpdate {
  value: string;
}

export interface TaskAssignRequest {
  user_id: number;
}

// ── Nested Response Types ───────────────────────────────────────

export interface SectionWithEntries extends SectionResponse {
  entries: EntryResponse[];
}

export interface NotebookFull {
  notebook: NotebookResponse;
  sections: SectionWithEntries[];
}

export interface TaskSummary {
  planned: number;
  parts_ordered: number;
  parts_delivered: number;
  in_progress: number;
  done: number;
  total: number;
  open: number;
}
