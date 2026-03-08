/**
 * Sync API — admin endpoints for device registry, sync history, and conflict log.
 *
 * These endpoints are shop-side only (not available on device Capacitor builds).
 * All require manage_people permission.
 */

import apiClient from './client';
import type { ApiResponse } from '../lib/types';

export interface SyncDevice {
  device_id: string;
  device_name: string | null;
  platform: string | null;  // 'ios' | 'android' | 'web' | 'unknown'
  user_id: number | null;
  last_sync_at: string | null;
  last_sync_batch_id: string | null;
  pending_changes: number;
  registered_at: string;
}

export interface SyncBatch {
  id: string;
  device_id: string;
  direction: string;          // 'push' | 'pull' | 'full'
  changes_sent: number;
  changes_received: number;
  conflicts_resolved: number;
  started_at: string;
  completed_at: string | null;
  status: string;             // 'in_progress' | 'completed' | 'failed'
}

export interface SyncConflict {
  id: number;
  table_name: string;
  record_id: number;
  device_a_id: string | null;
  device_b_id: string | null;
  resolution: string;         // 'device_wins' | 'shop_wins' | 'merged'
  device_values: string | null;   // JSON string
  shop_values: string | null;     // JSON string
  resolved_values: string | null; // JSON string
  resolved_at: string;
}

export interface HardSyncRequestPayload {
  device_id: string;
  reason_code?: string;
  pending_outbound_hashes?: string[];
  include_tables?: string[];
  preserve_pending_data?: boolean;
  notes?: string;
}

export interface HardSyncPackage {
  hard_sync_id: number;
  sync_batch_id: string;
  device_id: string;
  tables: Record<string, any[]>;
  table_count: number;
  total_rows: number;
  preserve_pending_data: boolean;
  server_time: string;
}

export interface HardSyncCompletePayload {
  hard_sync_id: number;
  device_id: string;
  sync_batch_id: string;
  applied_tables?: string[];
  restored_pending_count?: number;
  notes?: string;
}

export interface HardSyncEvent {
  id: number;
  device_id: string;
  requested_by: number | null;
  reason_code: string | null;
  pending_outbound_hashes: string | null;
  include_tables: string | null;
  preserve_pending_data: number;
  sync_batch_id: string | null;
  package_summary: string | null;
  status: 'requested' | 'package_ready' | 'in_progress' | 'completed' | 'failed';
  requested_at: string;
  started_at: string | null;
  completed_at: string | null;
  notes: string | null;
}

/** List all registered sync devices */
export async function listSyncDevices(): Promise<SyncDevice[]> {
  const { data } = await apiClient.get<ApiResponse<SyncDevice[]>>('/sync/devices');
  return data.data ?? [];
}

/** Get sync batch history, optionally filtered to one device */
export async function getSyncHistory(
  deviceId?: string,
  limit = 50
): Promise<SyncBatch[]> {
  const { data } = await apiClient.get<ApiResponse<SyncBatch[]>>('/sync/history', {
    params: { device_id: deviceId || undefined, limit },
  });
  return data.data ?? [];
}

/** Get recent sync conflicts */
export async function getSyncConflicts(limit = 50): Promise<SyncConflict[]> {
  const { data } = await apiClient.get<ApiResponse<SyncConflict[]>>('/sync/conflicts', {
    params: { limit },
  });
  return data.data ?? [];
}

/** Revoke a device — removes it from the sync registry */
export async function revokeDevice(deviceId: string): Promise<void> {
  await apiClient.delete(`/sync/devices/${encodeURIComponent(deviceId)}`);
}

/** Request hard-sync recovery package for a device */
export async function requestHardSync(payload: HardSyncRequestPayload): Promise<HardSyncPackage> {
  const { data } = await apiClient.post<ApiResponse<HardSyncPackage>>('/sync/hard-sync/request', payload);
  return data.data as HardSyncPackage;
}

/** Mark hard-sync as completed by the device */
export async function completeHardSync(payload: HardSyncCompletePayload): Promise<void> {
  await apiClient.post('/sync/hard-sync/complete', payload);
}

/** List hard-sync events for admin visibility */
export async function getHardSyncHistory(deviceId?: string, limit = 50): Promise<HardSyncEvent[]> {
  const { data } = await apiClient.get<ApiResponse<HardSyncEvent[]>>('/sync/hard-sync/history', {
    params: { device_id: deviceId || undefined, limit },
  });
  return data.data ?? [];
}
