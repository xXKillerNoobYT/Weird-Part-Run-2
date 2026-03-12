/**
 * Notebooks API functions — templates, notebooks, sections, entries, permissions.
 *
 * All functions follow the pattern: call apiClient → unwrap ApiResponse → return typed data.
 */

import apiClient from './client';
import { adaptedRequest } from './adapter';
import type { ApiResponse, StatusMessage } from '../lib/types';
import type {
  // Templates
  TemplateCreate,
  TemplateUpdate,
  TemplateFull,
  TemplateResponse,
  TemplateSectionCreate,
  TemplateSectionUpdate,
  TemplateSectionResponse,
  TemplateEntryCreate,
  TemplateEntryResponse,
  // Notebooks
  NotebookCreate,
  NotebookUpdate,
  NotebookResponse,
  NotebookListItem,
  NotebookFull,
  // Sections
  SectionCreate,
  SectionUpdate,
  SectionResponse,
  // Entries
  EntryCreate,
  EntryUpdate,
  EntryResponse,
  TaskStatusUpdate,
  FieldValueUpdate,
  TaskAssignRequest,
} from '../lib/types';


// =================================================================
// TEMPLATES (Office — manage_notebooks permission)
// =================================================================

/** List all notebook templates */
export async function listTemplates(): Promise<TemplateResponse[]> {
  const { data } = await apiClient.get<ApiResponse<TemplateResponse[]>>(
    '/notebook-templates'
  );
  return data.data ?? [];
}

/** Get full template (sections + entries) */
export async function getTemplateFull(templateId: number): Promise<TemplateFull> {
  const { data } = await apiClient.get<ApiResponse<TemplateFull>>(
    `/notebook-templates/${templateId}`
  );
  return data.data!;
}

/** Create a new template */
export async function createTemplate(
  template: TemplateCreate
): Promise<TemplateResponse> {
  const { data } = await apiClient.post<ApiResponse<TemplateResponse>>(
    '/notebook-templates',
    template
  );
  return data.data!;
}

/** Update a template */
export async function updateTemplate(
  templateId: number,
  updates: TemplateUpdate
): Promise<TemplateResponse> {
  const { data } = await apiClient.put<ApiResponse<TemplateResponse>>(
    `/notebook-templates/${templateId}`,
    updates
  );
  return data.data!;
}

/** Delete a template */
export async function deleteTemplate(templateId: number): Promise<void> {
  await apiClient.delete<ApiResponse<StatusMessage>>(
    `/notebook-templates/${templateId}`
  );
}

/** Add a section to a template */
export async function addTemplateSection(
  templateId: number,
  section: TemplateSectionCreate
): Promise<TemplateSectionResponse> {
  const { data } = await apiClient.post<ApiResponse<TemplateSectionResponse>>(
    `/notebook-templates/${templateId}/sections`,
    section
  );
  return data.data!;
}

/** Update a template section */
export async function updateTemplateSection(
  sectionId: number,
  updates: TemplateSectionUpdate
): Promise<TemplateSectionResponse> {
  const { data } = await apiClient.put<ApiResponse<TemplateSectionResponse>>(
    `/notebook-templates/sections/${sectionId}`,
    updates
  );
  return data.data!;
}

/** Delete a template section */
export async function deleteTemplateSection(sectionId: number): Promise<void> {
  await apiClient.delete<ApiResponse<StatusMessage>>(
    `/notebook-templates/sections/${sectionId}`
  );
}

/** Add an entry to a template section */
export async function addTemplateEntry(
  sectionId: number,
  entry: TemplateEntryCreate
): Promise<TemplateEntryResponse> {
  const { data } = await apiClient.post<ApiResponse<TemplateEntryResponse>>(
    `/notebook-templates/sections/${sectionId}/entries`,
    entry
  );
  return data.data!;
}

/** Delete a template entry */
export async function deleteTemplateEntry(entryId: number): Promise<void> {
  await apiClient.delete<ApiResponse<StatusMessage>>(
    `/notebook-templates/entries/${entryId}`
  );
}


// =================================================================
// NOTEBOOKS
// =================================================================

/** List notebooks with optional filter */
export async function listNotebooks(params?: {
  filter?: 'all' | 'job' | 'general';
  search?: string;
}): Promise<NotebookListItem[]> {
  return adaptedRequest(
    async () => {
      const { data } = await apiClient.get<ApiResponse<NotebookListItem[]>>(
        '/notebooks',
        { params }
      );
      return data.data ?? [];
    },
    async () => {
      const { listNotebooks: local } = await import('../local/services/notebook-service');
      const opts = params?.filter === 'job' ? { job_id: -1 } : undefined;
      return await local(opts) as unknown as NotebookListItem[];
    },
  );
}

/** Create a general (standalone) notebook */
export async function createNotebook(
  notebook: NotebookCreate
): Promise<NotebookResponse> {
  return adaptedRequest(
    async () => {
      const { data } = await apiClient.post<ApiResponse<NotebookResponse>>(
        '/notebooks',
        notebook
      );
      return data.data!;
    },
    async () => {
      const { createNotebook: local } = await import('../local/services/notebook-service');
      return await local(notebook as any, 0) as unknown as NotebookResponse;
    },
  );
}

/** Get full notebook (sections + entries, with can_edit computed) */
export async function getNotebookFull(notebookId: number): Promise<NotebookFull> {
  return adaptedRequest(
    async () => {
      const { data } = await apiClient.get<ApiResponse<NotebookFull>>(
        `/notebooks/${notebookId}/full`
      );
      return data.data!;
    },
    async () => {
      const { getNotebook } = await import('../local/services/notebook-service');
      const result = await getNotebook(notebookId);
      if (!result) throw new Error('Notebook not found');
      return result as unknown as NotebookFull;
    },
  );
}

/** Get or create a job's notebook (lazy creation) */
export async function getJobNotebook(jobId: number): Promise<NotebookFull> {
  const { data } = await apiClient.get<ApiResponse<NotebookFull>>(
    `/jobs/${jobId}/notebook`
  );
  return data.data!;
}

/** Update notebook title/description */
export async function updateNotebook(
  notebookId: number,
  updates: NotebookUpdate
): Promise<NotebookResponse> {
  const { data } = await apiClient.put<ApiResponse<NotebookResponse>>(
    `/notebooks/${notebookId}`,
    updates
  );
  return data.data!;
}

/** Archive a notebook */
export async function archiveNotebook(notebookId: number): Promise<void> {
  await apiClient.delete<ApiResponse<StatusMessage>>(
    `/notebooks/${notebookId}`
  );
}


// =================================================================
// SECTIONS
// =================================================================

/** Create a section in a notebook */
export async function createSection(
  notebookId: number,
  section: SectionCreate
): Promise<SectionResponse> {
  return adaptedRequest(
    async () => {
      const { data } = await apiClient.post<ApiResponse<SectionResponse>>(
        `/notebooks/${notebookId}/sections`,
        section
      );
      return data.data!;
    },
    async () => {
      const { createSection: local } = await import('../local/services/notebook-service');
      return await local(notebookId, section as any) as unknown as SectionResponse;
    },
  );
}

/** Update a section */
export async function updateSection(
  sectionId: number,
  updates: SectionUpdate
): Promise<SectionResponse> {
  const { data } = await apiClient.put<ApiResponse<SectionResponse>>(
    `/notebooks/sections/${sectionId}`,
    updates
  );
  return data.data!;
}

/** Delete a section */
export async function deleteSection(sectionId: number): Promise<void> {
  await apiClient.delete<ApiResponse<StatusMessage>>(
    `/notebooks/sections/${sectionId}`
  );
}

/** Reorder sections in a notebook */
export async function reorderSections(
  notebookId: number,
  orderedIds: number[]
): Promise<void> {
  await apiClient.put<ApiResponse<StatusMessage>>(
    `/notebooks/${notebookId}/sections/reorder`,
    { ordered_ids: orderedIds }
  );
}


// =================================================================
// ENTRIES
// =================================================================

/** Create an entry in a section */
export async function createEntry(
  sectionId: number,
  entry: EntryCreate
): Promise<EntryResponse> {
  return adaptedRequest(
    async () => {
      const { data } = await apiClient.post<ApiResponse<EntryResponse>>(
        `/notebooks/sections/${sectionId}/entries`,
        entry
      );
      return data.data!;
    },
    async () => {
      const { createEntry: local } = await import('../local/services/notebook-service');
      return await local(sectionId, entry as any, 0) as unknown as EntryResponse;
    },
  );
}

/** Update an entry */
export async function updateEntry(
  entryId: number,
  updates: EntryUpdate
): Promise<EntryResponse> {
  return adaptedRequest(
    async () => {
      const { data } = await apiClient.put<ApiResponse<EntryResponse>>(
        `/notebooks/entries/${entryId}`,
        updates
      );
      return data.data!;
    },
    async () => {
      const { updateEntry: local } = await import('../local/services/notebook-service');
      const result = await local(entryId, updates as any, 0);
      if (!result) throw new Error('Entry not found');
      return result as unknown as EntryResponse;
    },
  );
}

/** Update task status (stage transition) */
export async function updateTaskStatus(
  entryId: number,
  statusUpdate: TaskStatusUpdate
): Promise<EntryResponse> {
  return adaptedRequest(
    async () => {
      const { data } = await apiClient.patch<ApiResponse<EntryResponse>>(
        `/notebooks/entries/${entryId}/status`,
        statusUpdate
      );
      return data.data!;
    },
    async () => {
      const { updateTaskStatus: local } = await import('../local/services/notebook-service');
      const result = await local(entryId, (statusUpdate as any).status ?? (statusUpdate as any).task_status);
      if (!result) throw new Error('Entry not found');
      return result as unknown as EntryResponse;
    },
  );
}

/** Update field value (first-fill logic) */
export async function updateFieldValue(
  entryId: number,
  fieldUpdate: FieldValueUpdate
): Promise<EntryResponse> {
  const { data } = await apiClient.patch<ApiResponse<EntryResponse>>(
    `/notebooks/entries/${entryId}/field-value`,
    fieldUpdate
  );
  return data.data!;
}

/** Delete an entry (soft or hard based on permissions) */
export async function deleteEntry(entryId: number): Promise<void> {
  return adaptedRequest(
    async () => {
      await apiClient.delete<ApiResponse<StatusMessage>>(
        `/notebooks/entries/${entryId}`
      );
    },
    async () => {
      const { deleteEntry: local } = await import('../local/services/notebook-service');
      await local(entryId, 0);
    },
  );
}

/** Assign a task to a user */
export async function assignTask(
  entryId: number,
  assignment: TaskAssignRequest
): Promise<EntryResponse> {
  const { data } = await apiClient.post<ApiResponse<EntryResponse>>(
    `/notebooks/entries/${entryId}/assign`,
    assignment
  );
  return data.data!;
}


// =================================================================
// PERMISSIONS
// =================================================================

/** Grant edit permission to a user */
export async function grantEditPermission(
  entryId: number,
  userId: number
): Promise<void> {
  await apiClient.post<ApiResponse<StatusMessage>>(
    `/notebooks/entries/${entryId}/permissions`,
    { user_id: userId }
  );
}

/** Revoke edit permission from a user */
export async function revokeEditPermission(
  entryId: number,
  userId: number
): Promise<void> {
  await apiClient.delete<ApiResponse<StatusMessage>>(
    `/notebooks/entries/${entryId}/permissions/${userId}`
  );
}


// =================================================================
// TEMPLATE DUPLICATION
// =================================================================

/** Deep-clone a template with all sections and entries under a new name */
export async function duplicateTemplate(
  templateId: number,
  newName: string,
): Promise<TemplateFull> {
  const { data } = await apiClient.post<ApiResponse<TemplateFull>>(
    `/notebook-templates/${templateId}/duplicate`,
    { new_name: newName },
  );
  return data.data!;
}


// =================================================================
// ENTRY REORDERING
// =================================================================

/** Reorder entries within a section */
export async function reorderEntries(
  sectionId: number,
  orderedIds: number[],
): Promise<void> {
  await apiClient.put(
    `/notebooks/sections/${sectionId}/entries/reorder`,
    { ordered_ids: orderedIds },
  );
}


// =================================================================
// BULK TASK OPERATIONS
// =================================================================

/** Bulk update task status and/or assignee for multiple entries */
export async function bulkUpdateTasks(
  entryIds: number[],
  taskStatus?: string,
  taskAssignedTo?: number,
): Promise<{ updated: number }> {
  const { data } = await apiClient.put<ApiResponse<{ updated: number }>>(
    '/notebooks/tasks/bulk',
    {
      entry_ids: entryIds,
      ...(taskStatus !== undefined && { task_status: taskStatus }),
      ...(taskAssignedTo !== undefined && { task_assigned_to: taskAssignedTo }),
    },
  );
  return data.data!;
}


// =================================================================
// NOTEBOOK ATTACHMENTS
// =================================================================

export interface NotebookAttachment {
  id: number;
  entry_id: number;
  file_path: string;
  file_name: string;
  file_type: string | null;
  file_size: number | null;
  uploaded_by: number | null;
  created_at: string;
}

/** List attachments for a notebook entry */
export async function listEntryAttachments(
  entryId: number,
): Promise<NotebookAttachment[]> {
  const { data } = await apiClient.get<ApiResponse<NotebookAttachment[]>>(
    `/notebooks/entries/${entryId}/attachments`,
  );
  return data.data ?? [];
}

/** Upload a file attachment to a notebook entry */
export async function uploadEntryAttachment(
  entryId: number,
  file: File,
): Promise<NotebookAttachment> {
  const formData = new FormData();
  formData.append('file', file);
  const { data } = await apiClient.post<ApiResponse<NotebookAttachment>>(
    `/notebooks/entries/${entryId}/attachments`,
    formData,
    { headers: { 'Content-Type': 'multipart/form-data' } },
  );
  return data.data!;
}

/** Delete a notebook attachment */
export async function deleteEntryAttachment(
  attachmentId: number,
): Promise<void> {
  await apiClient.delete(`/notebooks/attachments/${attachmentId}`);
}


// =================================================================
// JOB TASKS (cross-cutting)
// =================================================================

/** Get all tasks for a job (across all notebook sections) */
export async function getJobTasks(
  jobId: number,
  status?: string
): Promise<EntryResponse[]> {
  const { data } = await apiClient.get<ApiResponse<EntryResponse[]>>(
    `/jobs/${jobId}/tasks`,
    { params: status ? { status } : undefined }
  );
  return data.data ?? [];
}
