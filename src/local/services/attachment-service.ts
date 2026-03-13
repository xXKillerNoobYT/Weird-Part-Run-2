/**
 * Local Attachment Service — polymorphic order attachments.
 *
 * Manages file attachments for JPOs, POs, and Returns.
 * Files are stored on the local filesystem; this service tracks metadata.
 *
 * Source tables: migration 012_warehouse_attachments
 */

import { getDb } from '../db';
import { BaseRepo } from '../repos/base-repo';

// ── Types ──────────────────────────────────────────────────────────

export type EntityType = 'jpo' | 'po' | 'return';

export interface AttachmentCreate {
  entity_type: EntityType;
  entity_id: number;
  file_path: string;
  file_name: string;
  file_type?: string;
  file_size?: number;
  description?: string;
  uploaded_by?: number;
}

export interface AttachmentUpdate {
  description?: string;
}

export interface OrderAttachment {
  id: number;
  entity_type: string;
  entity_id: number;
  file_path: string;
  file_name: string;
  file_type: string | null;
  file_size: number | null;
  description: string | null;
  uploaded_by: number | null;
  deleted_at: string | null;
  created_at: string;
  // Joined
  uploaded_by_name?: string;
}

// ── Repos ──────────────────────────────────────────────────────────

const attachmentRepo = new BaseRepo('order_attachments');

// ═══════════════════════════════════════════════════════════════════
// ATTACHMENTS
// ═══════════════════════════════════════════════════════════════════

/** Create an attachment record */
export async function createAttachment(data: AttachmentCreate): Promise<OrderAttachment> {
  const id = await attachmentRepo.insert({
    entity_type: data.entity_type,
    entity_id: data.entity_id,
    file_path: data.file_path,
    file_name: data.file_name,
    file_type: data.file_type ?? null,
    file_size: data.file_size ?? null,
    description: data.description ?? null,
    uploaded_by: data.uploaded_by ?? null,
    created_at: new Date().toISOString(),
  });
  return (await getAttachment(id))!;
}

/** Get an attachment by ID */
export async function getAttachment(id: number): Promise<OrderAttachment | null> {
  const db = await getDb();
  const result = await db.query(
    `SELECT oa.*, u.display_name as uploaded_by_name
     FROM order_attachments oa
     LEFT JOIN users u ON u.id = oa.uploaded_by
     WHERE oa.id = ?`,
    [id],
  );
  return (result.values[0] as OrderAttachment) ?? null;
}

/** Get attachments for a specific entity (JPO, PO, or Return) */
export async function getAttachmentsForEntity(
  entityType: EntityType,
  entityId: number,
): Promise<OrderAttachment[]> {
  const db = await getDb();
  const result = await db.query(
    `SELECT oa.*, u.display_name as uploaded_by_name
     FROM order_attachments oa
     LEFT JOIN users u ON u.id = oa.uploaded_by
     WHERE oa.entity_type = ? AND oa.entity_id = ? AND oa.deleted_at IS NULL
     ORDER BY oa.created_at DESC`,
    [entityType, entityId],
  );
  return result.values as OrderAttachment[];
}

/** Count attachments for an entity */
export async function getAttachmentCount(
  entityType: EntityType,
  entityId: number,
): Promise<number> {
  return attachmentRepo.count(
    'entity_type = ? AND entity_id = ? AND deleted_at IS NULL',
    [entityType, entityId],
  );
}

/** Update attachment metadata (description only — file is immutable) */
export async function updateAttachment(
  id: number,
  data: AttachmentUpdate,
): Promise<OrderAttachment | null> {
  const updated = await attachmentRepo.update(id, data);
  if (!updated) return null;
  return getAttachment(id);
}

/** Soft-delete an attachment */
export async function deleteAttachment(id: number): Promise<boolean> {
  return attachmentRepo.update(id, { deleted_at: new Date().toISOString() });
}

/** Get recent attachments across all entities */
export async function getRecentAttachments(limit: number = 20): Promise<OrderAttachment[]> {
  const db = await getDb();
  const result = await db.query(
    `SELECT oa.*, u.display_name as uploaded_by_name
     FROM order_attachments oa
     LEFT JOIN users u ON u.id = oa.uploaded_by
     WHERE oa.deleted_at IS NULL
     ORDER BY oa.created_at DESC
     LIMIT ?`,
    [limit],
  );
  return result.values as OrderAttachment[];
}
