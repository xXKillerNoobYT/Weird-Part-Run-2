/**
 * Sync API — admin endpoints for device registry, sync history, and conflict log.
 *
 * Browser mode: hits FastAPI /api/sync/* endpoints (admin dashboard).
 * Tauri mode:   Most endpoints return local-only data or empty arrays.
 *               Active sync happens via peer-manager and sync-engine, not these endpoints.
 *               Admin-heavy operations (hard sync, relay stats) throw on field devices.
 */

import apiClient from './client';
import { adaptedRequest } from './adapter';
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
  return adaptedRequest(
    async () => {
      const { data } = await apiClient.get<ApiResponse<SyncDevice[]>>('/sync/devices');
      return data.data ?? [];
    },
    // Local: return known peers from the local peer registry
    async () => {
      const { getDb } = await import('../local/db');
      const db = await getDb();
      const rows = await db.query(
        `SELECT device_id, device_name, platform, user_id, last_sync_at,
                last_sync_batch_id, 0 AS pending_changes, registered_at
         FROM devices
         WHERE deleted_at IS NULL
         ORDER BY last_sync_at DESC`,
      );
      return (rows.values ?? []) as SyncDevice[];
    },
  );
}

/** Get sync batch history, optionally filtered to one device */
export async function getSyncHistory(
  deviceId?: string,
  limit = 50
): Promise<SyncBatch[]> {
  return adaptedRequest(
    async () => {
      const { data } = await apiClient.get<ApiResponse<SyncBatch[]>>('/sync/history', {
        params: { device_id: deviceId || undefined, limit },
      });
      return data.data ?? [];
    },
    // Local: no sync batch table locally — return empty
    async () => [],
  );
}

/** Get recent sync conflicts */
export async function getSyncConflicts(limit = 50): Promise<SyncConflict[]> {
  return adaptedRequest(
    async () => {
      const { data } = await apiClient.get<ApiResponse<SyncConflict[]>>('/sync/conflicts', {
        params: { limit },
      });
      return data.data ?? [];
    },
    // Local: read from local _conflict_log if it exists
    async () => {
      const { getDb } = await import('../local/db');
      const db = await getDb();
      try {
        const rows = await db.query(
          `SELECT * FROM _conflict_log ORDER BY resolved_at DESC LIMIT ?`,
          [limit],
        );
        return (rows.values ?? []) as SyncConflict[];
      } catch {
        // Table may not exist yet
        return [];
      }
    },
  );
}

/** Revoke a device — removes it from the sync registry */
export async function revokeDevice(deviceId: string): Promise<void> {
  return adaptedRequest(
    async () => {
      await apiClient.delete(`/sync/devices/${encodeURIComponent(deviceId)}`);
    },
    async () => {
      // Local: soft-delete from devices table
      const { getDb } = await import('../local/db');
      const db = await getDb();
      await db.query(
        `UPDATE devices SET deleted_at = datetime('now') WHERE device_id = ?`,
        [deviceId],
      );
    },
  );
}

/** Request hard-sync recovery package for a device */
export async function requestHardSync(payload: HardSyncRequestPayload): Promise<HardSyncPackage> {
  return adaptedRequest(
    async () => {
      const { data } = await apiClient.post<ApiResponse<HardSyncPackage>>('/sync/hard-sync/request', payload);
      return data.data as HardSyncPackage;
    },
    async () => {
      throw new Error('Hard sync must be initiated from the admin device.');
    },
  );
}

/** Mark hard-sync as completed by the device */
export async function completeHardSync(payload: HardSyncCompletePayload): Promise<void> {
  return adaptedRequest(
    async () => {
      await apiClient.post('/sync/hard-sync/complete', payload);
    },
    async () => {
      throw new Error('Hard sync completion must be reported to the admin device.');
    },
  );
}

/** List hard-sync events for admin visibility */
export async function getHardSyncHistory(deviceId?: string, limit = 50): Promise<HardSyncEvent[]> {
  return adaptedRequest(
    async () => {
      const { data } = await apiClient.get<ApiResponse<HardSyncEvent[]>>('/sync/hard-sync/history', {
        params: { device_id: deviceId || undefined, limit },
      });
      return data.data ?? [];
    },
    // Local: no hard sync history table
    async () => [],
  );
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
  return adaptedRequest(
    async () => {
      const { data } = await apiClient.get<ApiResponse<DeviceSyncProfile | null>>(
        `/sync/profile/${encodeURIComponent(deviceId)}`
      );
      return data.data ?? null;
    },
    // Local: read from local settings
    async () => {
      const { getDb } = await import('../local/db');
      const db = await getDb();
      const rows = await db.query(
        `SELECT * FROM devices WHERE device_id = ? AND deleted_at IS NULL`,
        [deviceId],
      );
      const device = rows.values?.[0] as Record<string, unknown> | undefined;
      if (!device) return null;
      return {
        device_id: deviceId,
        primary_user_id: (device.user_id as number) ?? null,
        storage_policy: 'all_jobs_core',
        media_policy: 'all_jobs',
        media_retention_days: 90,
        force_carry_undelivered_media: 1,
        allow_borrowed_user_overrides: 0,
        active_only_sync: 0,
        updated_by: null,
        updated_at: (device.updated_at as string) ?? new Date().toISOString(),
      } as DeviceSyncProfile;
    },
  );
}

/** Update sync/storage profile for a device */
export async function updateDeviceSyncProfile(
  deviceId: string,
  payload: DeviceSyncProfileUpdate
): Promise<DeviceSyncProfile> {
  return adaptedRequest(
    async () => {
      const { data } = await apiClient.put<ApiResponse<DeviceSyncProfile>>(
        `/sync/profile/${encodeURIComponent(deviceId)}`,
        payload
      );
      return data.data as DeviceSyncProfile;
    },
    async () => {
      throw new Error('Sync profile updates must be done from the admin device.');
    },
  );
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
  return adaptedRequest(
    async () => {
      const { data } = await apiClient.get<ApiResponse<MeshRelayEvent[]>>('/sync/mesh/relay-events', {
        params: { device_id: deviceId || undefined, limit },
      });
      return data.data ?? [];
    },
    // Local: no relay event tracking table yet
    async () => [],
  );
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
  return adaptedRequest(
    async () => {
      const { data } = await apiClient.get<ApiResponse<RelayManifest[]>>('/sync/relay/manifests');
      return data.data ?? [];
    },
    async () => [],
  );
}

/** Get a device's relay manifest */
export async function getRelayManifest(deviceId: string): Promise<RelayManifest | null> {
  return adaptedRequest(
    async () => {
      const { data } = await apiClient.get<ApiResponse<RelayManifest | null>>(
        `/sync/relay/manifests/${encodeURIComponent(deviceId)}`
      );
      return data.data ?? null;
    },
    async () => null,
  );
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
  return adaptedRequest(
    async () => {
      const { data } = await apiClient.get<ApiResponse<RelayPackage[]>>('/sync/relay/packages', {
        params: { device_id: deviceId || undefined, status: status || undefined, limit },
      });
      return data.data ?? [];
    },
    async () => [],
  );
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
  return adaptedRequest(
    async () => {
      const { data } = await apiClient.get<ApiResponse<DeliveryReceipt[]>>(
        `/sync/relay/receipts/pending/${encodeURIComponent(deviceId)}`,
        { params: { limit } }
      );
      return data.data ?? [];
    },
    async () => [],
  );
}

/** Acknowledge delivery receipts (device confirms it can purge) */
export async function acknowledgeReceipts(receiptIds: number[]): Promise<{ acknowledged_count: number }> {
  return adaptedRequest(
    async () => {
      const { data } = await apiClient.post<ApiResponse<{ acknowledged_count: number }>>(
        '/sync/relay/receipts/acknowledge',
        { receipt_ids: receiptIds }
      );
      return data.data as { acknowledged_count: number };
    },
    // Local: no-op — receipts are managed by the sync engine directly
    async () => ({ acknowledged_count: 0 }),
  );
}

/** List all delivery receipts (admin) */
export async function listDeliveryReceipts(
  deviceId?: string,
  acknowledged?: boolean,
  limit = 100
): Promise<DeliveryReceipt[]> {
  return adaptedRequest(
    async () => {
      const { data } = await apiClient.get<ApiResponse<DeliveryReceipt[]>>('/sync/relay/receipts', {
        params: {
          device_id: deviceId || undefined,
          acknowledged: acknowledged !== undefined ? acknowledged : undefined,
          limit,
        },
      });
      return data.data ?? [];
    },
    async () => [],
  );
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
  return adaptedRequest(
    async () => {
      const { data } = await apiClient.get<ApiResponse<RelayStats>>('/sync/relay/stats', {
        params: { device_id: deviceId || undefined },
      });
      return data.data as RelayStats;
    },
    // Local: return empty stats
    async () => ({
      events_by_type: [],
      packages_by_status: [],
      receipts_by_status: [],
      active_manifests: 0,
    }),
  );
}
