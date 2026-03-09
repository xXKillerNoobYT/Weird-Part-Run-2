/**
 * Backup management API functions.
 *
 * Supports database and app backup operations:
 * settings, listing, triggering, restoring, and deleting backups.
 */

import apiClient from './client';
import type { ApiResponse } from '../lib/types';

// ── Types ────────────────────────────────────────────────────────

export interface BackupRecord {
  id: number;
  backup_type: 'db' | 'app';
  file_path: string;
  file_name: string;
  size_bytes: number | null;
  created_at: string | null;
}

export interface BackupSettings {
  backup_db_enabled: boolean;
  backup_db_hour: number;
  backup_db_minute: number;
  backup_db_retention: number;
  backup_app_enabled: boolean;
  backup_app_hour: number;
  backup_app_minute: number;
  backup_app_retention: number;
  backup_dir: string;
  backup_before_update: boolean;
}

export type BackupSettingsUpdate = Partial<{
  db_enabled: boolean;
  db_hour: number;
  db_minute: number;
  db_retention: number;
  app_enabled: boolean;
  app_hour: number;
  app_minute: number;
  app_retention: number;
  backup_dir: string;
  backup_before_update: boolean;
}>;

// ── API Functions ────────────────────────────────────────────────

/** Get current backup settings. */
export async function getBackupSettings(): Promise<BackupSettings> {
  const { data } = await apiClient.get<ApiResponse<BackupSettings>>(
    '/backups/settings',
  );
  return data.data!;
}

/** Update backup settings (partial — only provided fields change). */
export async function updateBackupSettings(
  settings: BackupSettingsUpdate,
): Promise<BackupSettings> {
  const { data } = await apiClient.put<ApiResponse<BackupSettings>>(
    '/backups/settings',
    settings,
  );
  return data.data!;
}

/** List all backups of a given type, newest first. */
export async function listBackups(
  backupType: 'db' | 'app',
): Promise<BackupRecord[]> {
  const { data } = await apiClient.get<ApiResponse<BackupRecord[]>>(
    `/backups/list/${backupType}`,
  );
  return data.data ?? [];
}

/** Trigger an immediate manual backup. */
export async function triggerBackup(
  backupType: 'db' | 'app',
): Promise<BackupRecord> {
  const { data } = await apiClient.post<ApiResponse<BackupRecord>>(
    `/backups/run/${backupType}`,
  );
  return data.data!;
}

/** Restore a database backup by ID. */
export async function restoreBackup(
  backupId: number,
): Promise<{ restored_from: string; safety_backup: string; message: string }> {
  const { data } = await apiClient.post<
    ApiResponse<{ restored_from: string; safety_backup: string; message: string }>
  >(`/backups/restore/${backupId}`);
  return data.data!;
}

/** Delete a backup (file + record). */
export async function deleteBackup(backupId: number): Promise<void> {
  await apiClient.delete(`/backups/${backupId}`);
}

/** Download a backup file. Opens the browser download dialog. */
export async function downloadBackup(backupId: number, fileName: string): Promise<void> {
  const response = await apiClient.get(`/backups/download/${backupId}`, {
    responseType: 'blob',
  });
  // Create a temporary download link and trigger it
  const url = window.URL.createObjectURL(new Blob([response.data]));
  const link = document.createElement('a');
  link.href = url;
  link.setAttribute('download', fileName);
  document.body.appendChild(link);
  link.click();
  link.remove();
  window.URL.revokeObjectURL(url);
}

/** Run retention cleanup for a backup type. */
export async function cleanupBackups(
  backupType: 'db' | 'app',
): Promise<{ deleted_count: number }> {
  const { data } = await apiClient.post<ApiResponse<{ deleted_count: number }>>(
    `/backups/cleanup/${backupType}`,
  );
  return data.data!;
}
