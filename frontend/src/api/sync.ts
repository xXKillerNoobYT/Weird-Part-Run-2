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

// ── Device Sync Profiles ────────────────────────────────────────

export interface DeviceSyncProfile {
  device_id: string;
  primary_user_id: number | null;
  storage_policy: string;      // 'active_jobs_core_only' | 'all_jobs_core' | 'minimal'
  media_policy: string;        // 'all_jobs' | 'assigned_jobs_only' | 'thumbnails_only' | 'none' | 'last_n_days'
  media_retention_days: number;
  force_carry_undelivered_media: number;
  allow_borrowed_user_overrides: number;
  active_only_sync: number;
  updated_by: number | null;
  updated_at: string;
}

export interface DeviceSyncProfileUpdate {
  primary_user_id?: number | null;
  storage_policy?: string;
  media_policy?: string;
  media_retention_days?: number;
  force_carry_undelivered_media?: boolean;
  allow_borrowed_user_overrides?: boolean;
  active_only_sync?: boolean;
}

/** Get sync/storage profile for a device */
export async function getDeviceSyncProfile(deviceId: string): Promise<DeviceSyncProfile | null> {
  const { data } = await apiClient.get<ApiResponse<DeviceSyncProfile | null>>(
    `/sync/profile/${encodeURIComponent(deviceId)}`
  );
  return data.data ?? null;
}

/** Update sync/storage profile for a device */
export async function updateDeviceSyncProfile(
  deviceId: string,
  payload: DeviceSyncProfileUpdate
): Promise<DeviceSyncProfile> {
  const { data } = await apiClient.put<ApiResponse<DeviceSyncProfile>>(
    `/sync/profile/${encodeURIComponent(deviceId)}`,
    payload
  );
  return data.data as DeviceSyncProfile;
}

// ── Mesh Relay Events ───────────────────────────────────────────

export interface MeshRelayEvent {
  id: number;
  source_device_id: string;
  peer_device_id: string;
  relay_type: string;           // 'gossip' | 'handoff' | 'shop_delivery' | 'shop_ack'
  carried_change_count: number;
  carried_media_count: number;
  undelivered_after_count: number;
  metadata: Record<string, unknown>;
  recorded_at: string;
}

/** List mesh relay events (admin) */
export async function getMeshRelayEvents(deviceId?: string, limit = 100): Promise<MeshRelayEvent[]> {
  const { data } = await apiClient.get<ApiResponse<MeshRelayEvent[]>>('/sync/mesh/relay-events', {
    params: { device_id: deviceId || undefined, limit },
  });
  return data.data ?? [];
}

// ── Relay Manifests ─────────────────────────────────────────────

export interface RelayManifest {
  device_id: string;
  pending_change_count: number;
  pending_media_count: number;
  change_hashes: string[];
  media_hashes: string[];
  origin_device_ids: string[];
  updated_at: string;
}

/** List all relay manifests (admin) */
export async function listRelayManifests(): Promise<RelayManifest[]> {
  const { data } = await apiClient.get<ApiResponse<RelayManifest[]>>('/sync/relay/manifests');
  return data.data ?? [];
}

/** Get a device's relay manifest */
export async function getRelayManifest(deviceId: string): Promise<RelayManifest | null> {
  const { data } = await apiClient.get<ApiResponse<RelayManifest | null>>(
    `/sync/relay/manifests/${encodeURIComponent(deviceId)}`
  );
  return data.data ?? null;
}

// ── Relay Packages ──────────────────────────────────────────────

export interface RelayPackage {
  id: number;
  sender_device_id: string;
  receiver_device_id: string;
  origin_device_id: string;
  change_count: number;
  media_count: number;
  package_hash: string | null;
  status: 'created' | 'transferred' | 'confirmed' | 'failed';
  failure_reason: string | null;
  created_at: string;
  transferred_at: string | null;
  confirmed_at: string | null;
}

/** List relay packages (admin) */
export async function listRelayPackages(
  deviceId?: string,
  status?: string,
  limit = 100
): Promise<RelayPackage[]> {
  const { data } = await apiClient.get<ApiResponse<RelayPackage[]>>('/sync/relay/packages', {
    params: { device_id: deviceId || undefined, status: status || undefined, limit },
  });
  return data.data ?? [];
}

// ── Delivery Receipts ───────────────────────────────────────────

export interface DeliveryReceipt {
  id: number;
  origin_device_id: string;
  delivered_by_device_id: string;
  receipt_type: 'changes' | 'media' | 'mixed';
  change_count: number;
  media_count: number;
  delivered_hashes: string[];
  acknowledged_by_origin: number;
  acknowledged_at: string | null;
  issued_at: string;
  relay_chain: string[];
}

/** Get pending (unacknowledged) delivery receipts for a device */
export async function getPendingReceipts(deviceId: string, limit = 100): Promise<DeliveryReceipt[]> {
  const { data } = await apiClient.get<ApiResponse<DeliveryReceipt[]>>(
    `/sync/relay/receipts/pending/${encodeURIComponent(deviceId)}`,
    { params: { limit } }
  );
  return data.data ?? [];
}

/** Acknowledge delivery receipts (device confirms it can purge) */
export async function acknowledgeReceipts(receiptIds: number[]): Promise<{ acknowledged_count: number }> {
  const { data } = await apiClient.post<ApiResponse<{ acknowledged_count: number }>>(
    '/sync/relay/receipts/acknowledge',
    { receipt_ids: receiptIds }
  );
  return data.data as { acknowledged_count: number };
}

/** List all delivery receipts (admin) */
export async function listDeliveryReceipts(
  deviceId?: string,
  acknowledged?: boolean,
  limit = 100
): Promise<DeliveryReceipt[]> {
  const { data } = await apiClient.get<ApiResponse<DeliveryReceipt[]>>('/sync/relay/receipts', {
    params: {
      device_id: deviceId || undefined,
      acknowledged: acknowledged !== undefined ? acknowledged : undefined,
      limit,
    },
  });
  return data.data ?? [];
}

// ── Relay Stats ─────────────────────────────────────────────────

export interface RelayStats {
  events_by_type: Array<{
    relay_type: string;
    cnt: number;
    total_changes: number;
    total_media: number;
  }>;
  packages_by_status: Array<{
    status: string;
    cnt: number;
  }>;
  receipts_by_status: Array<{
    acknowledged_by_origin: number;
    cnt: number;
    total_changes: number;
    total_media: number;
  }>;
  active_manifests: number;
}

/** Get aggregate relay statistics for the admin dashboard */
export async function getRelayStats(deviceId?: string): Promise<RelayStats> {
  const { data } = await apiClient.get<ApiResponse<RelayStats>>('/sync/relay/stats', {
    params: { device_id: deviceId || undefined },
  });
  return data.data as RelayStats;
}
