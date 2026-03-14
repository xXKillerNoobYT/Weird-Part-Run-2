/**
 * Backup management API functions.
 *
 * Browser mode: hits FastAPI /api/backups/* endpoints.
 * Tauri mode: uses local scheduler-service for SQLite backups.
 *             App-level backups are a server-only concept (no-op locally).
 */

import apiClient from './client';
import { adaptedRequest } from './adapter';
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
  return adaptedRequest(
    async () => {
      const { data } = await apiClient.get<ApiResponse<BackupSettings>>(
        '/backups/settings',
      );
      return data.data!;
    },
    // Local: return defaults — backup scheduling is handled by scheduler-service
    async () => ({
      backup_db_enabled: true,
      backup_db_hour: 2,
      backup_db_minute: 0,
      backup_db_retention: 3,
      backup_app_enabled: false,
      backup_app_hour: 3,
      backup_app_minute: 0,
      backup_app_retention: 3,
      backup_dir: 'backups',
      backup_before_update: true,
    }),
  );
}

/** Update backup settings (partial — only provided fields change). */
export async function updateBackupSettings(
  settings: BackupSettingsUpdate,
): Promise<BackupSettings> {
  return adaptedRequest(
    async () => {
      const { data } = await apiClient.put<ApiResponse<BackupSettings>>(
        '/backups/settings',
        settings,
      );
      return data.data!;
    },
    // Local: store in settings table
    async () => {
      const { getDb } = await import('../local/db');
      const db = await getDb();
      const now = new Date().toISOString().replace('T', ' ').slice(0, 19);
      for (const [key, value] of Object.entries(settings)) {
        if (value !== undefined) {
          await db.query(
            `INSERT OR REPLACE INTO settings (key, value, category, updated_at)
             VALUES (?, ?, 'backup', ?)`,
            [`backup_${key}`, String(value), now],
          );
        }
      }
      return getBackupSettings();
    },
  );
}

/** List all backups of a given type, newest first. */
export async function listBackups(
  backupType: 'db' | 'app',
): Promise<BackupRecord[]> {
  return adaptedRequest(
    async () => {
      const { data } = await apiClient.get<ApiResponse<BackupRecord[]>>(
        `/backups/list/${backupType}`,
      );
      return data.data ?? [];
    },
    // Local: DB backups are managed by scheduler-service, no record table yet
    async () => [],
  );
}

/** Trigger an immediate manual backup. */
export async function triggerBackup(
  backupType: 'db' | 'app',
): Promise<BackupRecord> {
  return adaptedRequest(
    async () => {
      const { data } = await apiClient.post<ApiResponse<BackupRecord>>(
        `/backups/run/${backupType}`,
      );
      return data.data!;
    },
    // Local: trigger via scheduler-service
    async () => {
      if (backupType === 'app') {
        throw new Error('App backups are not available on this device.');
      }
      const { runJobManually } = await import('../local/services/scheduler-service');
      await runJobManually('db_backup');
      return {
        id: Date.now(),
        backup_type: 'db',
        file_path: 'local',
        file_name: `backup_${new Date().toISOString().slice(0, 10)}.sqlite`,
        size_bytes: null,
        created_at: new Date().toISOString(),
      };
    },
  );
}

/** Restore a database backup by ID. */
export async function restoreBackup(
  backupId: number,
): Promise<{ restored_from: string; safety_backup: string; message: string }> {
  return adaptedRequest(
    async () => {
      const { data } = await apiClient.post<
        ApiResponse<{ restored_from: string; safety_backup: string; message: string }>
      >(`/backups/restore/${backupId}`);
      return data.data!;
    },
    async () => {
      throw new Error('Backup restore must be done from the admin device.');
    },
  );
}

/** Delete a backup (file + record). */
export async function deleteBackup(backupId: number): Promise<void> {
  return adaptedRequest(
    async () => {
      await apiClient.delete(`/backups/${backupId}`);
    },
    async () => {
      throw new Error('Backup deletion must be done from the admin device.');
    },
  );
}

/** Download a backup file. Opens native save dialog (Tauri) or browser download. */
export async function downloadBackup(backupId: number, fileName: string): Promise<void> {
  return adaptedRequest(
    async () => {
      const response = await apiClient.get(`/backups/download/${backupId}`, {
        responseType: 'blob',
      });
      const { exportFile } = await import('../local/services/file-export-service');
      await exportFile(new Blob([response.data]), fileName);
    },
    async () => {
      throw new Error('Backup download not available locally.');
    },
  );
}

/** Run retention cleanup for a backup type. */
export async function cleanupBackups(
  backupType: 'db' | 'app',
): Promise<{ deleted_count: number }> {
  return adaptedRequest(
    async () => {
      const { data } = await apiClient.post<ApiResponse<{ deleted_count: number }>>(
        `/backups/cleanup/${backupType}`,
      );
      return data.data!;
    },
    async () => {
      const { runJobManually } = await import('../local/services/scheduler-service');
      await runJobManually('notification_cleanup');
      return { deleted_count: 0 };
    },
  );
}
