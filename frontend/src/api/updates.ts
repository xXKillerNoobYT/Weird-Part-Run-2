import apiClient from './client';
import type { ApiResponse } from '../lib/types';

export type UpdatePlatform = 'windows' | 'macos' | 'ios' | 'android';

export interface UpdateVersionRecord {
  id: number;
  version: string;
  previous_version: string | null;
  release_notes: string | null;
  checksum_sha256: string | null;
  signature: string | null;
  package_url: string | null;
  package_size_bytes: number | null;
  migration_scripts: string[];
  rollback_scripts: string[];
  min_compatible_version: string | null;
  max_compatible_version: string | null;
  criticality: 'critical' | 'normal' | 'optional';
  source: 'github' | 'manual' | 'rollup';
  fetched_at: string;
  published_at: string | null;
  created_at: string;
}

export interface ValidationRecord {
  id: number;
  version: string;
  platform: UpdatePlatform;
  status: 'pending' | 'running' | 'passed' | 'failed' | 'blocked';
  schema_diff_ok: number | null;
  migration_test_ok: number | null;
  rollback_test_ok: number | null;
  backward_compat_ok: number | null;
  error_log: string | null;
  validated_by: number | null;
  started_at: string | null;
  completed_at: string | null;
  created_at: string;
}

export interface FleetTargetRecord {
  id: number;
  platform: UpdatePlatform;
  current_target: string;
  latest_validated: string | null;
  devices_at_target: number;
  devices_total: number;
  devices_behind: number;
  auto_advance: number;
  updated_at: string;
  updated_by: number | null;
}

export interface DeviceUpdateStatusRecord {
  id: number;
  device_id: string;
  platform: UpdatePlatform;
  current_version: string;
  target_version: string | null;
  pending_versions: string[];
  last_install_version: string | null;
  last_install_at: string | null;
  last_install_status: 'success' | 'failed' | 'rolled_back' | null;
  install_error: string | null;
  backup_taken: number;
  reported_at: string;
}

export interface BackupSnapshotRecord {
  id: number;
  version_before: string;
  version_target: string;
  backup_path: string;
  backup_size_bytes: number | null;
  checksum_sha256: string | null;
  includes_db: number;
  includes_config: number;
  includes_binary: number;
  status: 'created' | 'verified' | 'restored' | 'expired';
  restored_at: string | null;
  created_at: string;
  created_by: number | null;
}

export interface RegisterVersionPayload {
  version: string;
  previous_version?: string | null;
  release_notes?: string | null;
  criticality?: 'critical' | 'normal' | 'optional';
  source?: 'github' | 'manual' | 'rollup';
  migration_scripts?: string[];
  rollback_scripts?: string[];
}

export interface FleetTargetPayload {
  current_target?: string | null;
  latest_validated?: string | null;
  auto_advance?: boolean | null;
}

export interface CreateValidationPayload {
  version: string;
  platform: UpdatePlatform;
}

export interface UpdateValidationPayload {
  version: string;
  platform: UpdatePlatform;
  status: 'pending' | 'running' | 'passed' | 'failed' | 'blocked';
  schema_diff_ok?: boolean | null;
  migration_test_ok?: boolean | null;
  rollback_test_ok?: boolean | null;
  backward_compat_ok?: boolean | null;
  error_log?: string | null;
}

export interface CreateBackupPayload {
  version_before: string;
  version_target: string;
  backup_path: string;
  backup_size_bytes?: number | null;
  checksum_sha256?: string | null;
  includes_db?: boolean;
  includes_config?: boolean;
  includes_binary?: boolean;
}

export interface PendingUpdateRecord {
  version: string;
  previous_version: string | null;
  criticality: string;
  migration_scripts: string[];
  rollback_scripts: string[];
  release_notes: string | null;
}

export async function listUpdateVersions(params?: { published_only?: boolean; limit?: number }): Promise<UpdateVersionRecord[]> {
  const { data } = await apiClient.get<ApiResponse<UpdateVersionRecord[]>>('/updates/versions', { params });
  return data.data ?? [];
}

export async function registerUpdateVersion(payload: RegisterVersionPayload): Promise<UpdateVersionRecord> {
  const { data } = await apiClient.post<ApiResponse<UpdateVersionRecord>>('/updates/versions', payload);
  return data.data as UpdateVersionRecord;
}

export async function publishUpdateVersion(version: string): Promise<UpdateVersionRecord> {
  const { data } = await apiClient.post<ApiResponse<UpdateVersionRecord>>(`/updates/versions/${encodeURIComponent(version)}/publish`);
  return data.data as UpdateVersionRecord;
}

export async function listUpdateValidations(params?: { version?: string; platform?: UpdatePlatform }): Promise<ValidationRecord[]> {
  const { data } = await apiClient.get<ApiResponse<ValidationRecord[]>>('/updates/validations', { params });
  return data.data ?? [];
}

export async function listFleetTargets(): Promise<FleetTargetRecord[]> {
  const { data } = await apiClient.get<ApiResponse<FleetTargetRecord[]>>('/updates/fleet');
  return data.data ?? [];
}

export async function updateFleetTarget(platform: UpdatePlatform, payload: FleetTargetPayload): Promise<FleetTargetRecord> {
  const { data } = await apiClient.put<ApiResponse<FleetTargetRecord>>(`/updates/fleet/${platform}`, payload);
  return data.data as FleetTargetRecord;
}

export async function refreshFleetTarget(platform: UpdatePlatform): Promise<FleetTargetRecord> {
  const { data } = await apiClient.post<ApiResponse<FleetTargetRecord>>(`/updates/fleet/${platform}/refresh`);
  return data.data as FleetTargetRecord;
}

export async function listDeviceUpdateStatuses(params?: {
  platform?: UpdatePlatform;
  behind_only?: boolean;
  limit?: number;
}): Promise<DeviceUpdateStatusRecord[]> {
  const { data } = await apiClient.get<ApiResponse<DeviceUpdateStatusRecord[]>>('/updates/devices', { params });
  return data.data ?? [];
}

export async function listUpdateBackups(params?: { version_before?: string; limit?: number }): Promise<BackupSnapshotRecord[]> {
  const { data } = await apiClient.get<ApiResponse<BackupSnapshotRecord[]>>('/updates/backups', { params });
  return data.data ?? [];
}

// ── Validation CRUD ─────────────────────────────────────────────

export async function createValidation(payload: CreateValidationPayload): Promise<ValidationRecord> {
  const { data } = await apiClient.post<ApiResponse<ValidationRecord>>('/updates/validations', payload);
  return data.data as ValidationRecord;
}

export async function updateValidation(payload: UpdateValidationPayload): Promise<ValidationRecord> {
  const { data } = await apiClient.put<ApiResponse<ValidationRecord>>('/updates/validations', payload);
  return data.data as ValidationRecord;
}

// ── Single fleet target ─────────────────────────────────────────

export async function getFleetTarget(platform: UpdatePlatform): Promise<FleetTargetRecord | null> {
  const { data } = await apiClient.get<ApiResponse<FleetTargetRecord | null>>(`/updates/fleet/${platform}`);
  return data.data ?? null;
}

// ── Device detail + pending chain ───────────────────────────────

export async function getDeviceUpdateStatus(deviceId: string): Promise<DeviceUpdateStatusRecord | null> {
  const { data } = await apiClient.get<ApiResponse<DeviceUpdateStatusRecord | null>>(`/updates/devices/${encodeURIComponent(deviceId)}`);
  return data.data ?? null;
}

export async function getPendingUpdates(deviceId: string, platform: UpdatePlatform): Promise<PendingUpdateRecord[]> {
  const { data } = await apiClient.get<ApiResponse<PendingUpdateRecord[]>>(
    `/updates/devices/${encodeURIComponent(deviceId)}/pending`,
    { params: { platform } },
  );
  return data.data ?? [];
}

// ── Backup create + restore ─────────────────────────────────────

export async function createBackupSnapshot(payload: CreateBackupPayload): Promise<BackupSnapshotRecord> {
  const { data } = await apiClient.post<ApiResponse<BackupSnapshotRecord>>('/updates/backups', payload);
  return data.data as BackupSnapshotRecord;
}

export async function markBackupRestored(snapshotId: number): Promise<BackupSnapshotRecord> {
  const { data } = await apiClient.post<ApiResponse<BackupSnapshotRecord>>(`/updates/backups/${snapshotId}/restore`);
  return data.data as BackupSnapshotRecord;
}
