/**
 * Devices API — admin endpoints for device management, health telemetry,
 * error logs, overrides, BT encounters, media tracking, cluster management,
 * and log retention.
 *
 * Prefix: /devices
 * Most endpoints require manage_devices permission.
 */

import apiClient from './client';

// ── Types ───────────────────────────────────────────────────────

export interface DeviceSummary {
    device_id: string;
    device_name: string | null;
    platform: string | null;
    user_id: number | null;
    last_sync_at: string | null;
    last_sync_batch_id: string | null;
    pending_changes: number;
    registered_at: string;
    // Override fields
    override_action: string | null;
    override_set_at: string | null;
    override_set_by: number | null;
    is_disabled: number;
    disabled_reason: string | null;
    primary_user_id: number | null;
    primary_user_name: string | null;
    force_sync_flag: number;
    config_version: number | null;
    app_version: string | null;
    os_version: string | null;
    // Profile join
    storage_policy: string | null;
    media_policy: string | null;
    media_retention_days: number | null;
    // Health join
    battery_level: number | null;
    battery_charging: number | null;
    storage_used_mb: number | null;
    storage_total_mb: number | null;
    health_app_version: string | null;
    health_os_version: string | null;
    pending_sync_count: number | null;
    pending_media_count: number | null;
    last_health_at: string | null;
    // Error count
    unresolved_errors: number;
}

export interface DeviceDetail extends DeviceSummary {
    // Sync profile detail
    profile_primary_user_id: number | null;
    force_carry_undelivered_media: number | null;
    allow_borrowed_user_overrides: number | null;
    active_only_sync: number | null;
    // Latest health snapshot
    latest_health: HealthSnapshot | null;
    // Certificate info
    certificate: DeviceCertificate | null;
    unresolved_error_count: number;
}

export interface DeviceCertificate {
    id: number;
    device_id: string;
    company_id: string;
    issued_at: string;
    expires_at: string;
    revoked_at: string | null;
    crypto_version: string | null;
}

export interface HealthSnapshot {
    id: number;
    device_id: string;
    battery_level: number | null;
    battery_charging: number;
    storage_used_mb: number | null;
    storage_total_mb: number | null;
    app_version: string | null;
    os_version: string | null;
    pending_sync_count: number;
    pending_media_count: number;
    last_sync_at: string | null;
    memory_used_mb: number | null;
    snapshot_at: string;
}

export interface DeviceErrorLog {
    id: number;
    device_id: string;
    device_name: string | null;
    severity: 'info' | 'warning' | 'error' | 'critical';
    error_type: string;
    message: string;
    stack_trace: string | null;
    context_json: string | null;
    environment_json: string | null;
    occurred_at: string;
    uploaded_at: string;
    resolved_at: string | null;
    resolved_by: number | null;
    resolution_note: string | null;
}

export interface BtEncounter {
    id: number;
    local_device_id: string;
    remote_device_id: string;
    local_name: string | null;
    remote_name: string | null;
    encounter_start: string;
    encounter_end: string | null;
    changes_sent: number;
    changes_received: number;
    media_bytes_sent: number;
    media_bytes_received: number;
    signal_strength: number | null;
    status: 'in_progress' | 'completed' | 'failed' | 'aborted';
    failure_reason: string | null;
    created_at: string;
}

export interface PendingMedia {
    id: number;
    media_path: string;
    media_hash: string;
    origin_device_id: string;
    media_size_bytes: number;
    delivered_to_shop: number;
    shop_confirmed_at: string | null;
    created_at: string;
}

export interface ClusterNode {
    id: number;
    node_id: string;
    hostname: string | null;
    local_ip: string | null;
    port: number;
    last_seen_at: string;
    last_sync_at: string | null;
    is_primary: number;
    status: 'online' | 'offline' | 'syncing';
    app_version: string | null;
    db_version: number | null;
}

export interface RetentionConfig {
    id: number;
    log_type: string;
    device_retention_days: number;
    shop_retention_days: number;
    updated_at: string;
}

export interface DeviceOverrideInfo {
    action: string | null;
    reason?: string;
    set_at?: string | null;
}

export interface DeviceStorage {
    profile: Record<string, unknown> | null;
    storage_used_mb: number | null;
    storage_total_mb: number | null;
    pending_media_count: number;
    pending_media_bytes: number;
}


// ── Device List & Detail ────────────────────────────────────────

/** List all registered devices with health summaries */
export async function listDevices(includeDisabled = true): Promise<DeviceSummary[]> {
    const { data } = await apiClient.get('/devices', {
        params: { include_disabled: includeDisabled },
    });
    return Array.isArray(data) ? data : data.data ?? [];
}

/** Get full detail for a single device */
export async function getDevice(deviceId: string): Promise<DeviceDetail> {
    const { data } = await apiClient.get(`/devices/${encodeURIComponent(deviceId)}`);
    return (data.data ?? data) as DeviceDetail;
}

/** Rename a device */
export async function renameDevice(deviceId: string, name: string): Promise<void> {
    await apiClient.put(`/devices/${encodeURIComponent(deviceId)}/rename`, { name });
}


// ── Primary User ────────────────────────────────────────────────

/** Reassign primary user on a device */
export async function setPrimaryUser(deviceId: string, userId: number): Promise<void> {
    await apiClient.put(`/devices/${encodeURIComponent(deviceId)}/primary-user`, {
        user_id: userId,
    });
}


// ── Override Actions ────────────────────────────────────────────

/** Set an override flag on a device */
export async function setDeviceOverride(
    deviceId: string,
    action: 'force_logout' | 'force_wipe' | 'force_sync',
    reason?: string,
): Promise<void> {
    await apiClient.post(`/devices/${encodeURIComponent(deviceId)}/override`, {
        action,
        reason,
    });
}

/** Clear any pending override on a device */
export async function clearDeviceOverride(deviceId: string): Promise<void> {
    await apiClient.delete(`/devices/${encodeURIComponent(deviceId)}/override`);
}

/** Check if a device has a pending override */
export async function checkDeviceOverride(deviceId: string): Promise<DeviceOverrideInfo | null> {
    const { data } = await apiClient.get(`/devices/${encodeURIComponent(deviceId)}/override`);
    return (data.data ?? data)?.override ?? null;
}

/** Device consumes (acknowledges) a pending override */
export async function consumeDeviceOverride(deviceId: string): Promise<string | null> {
    const { data } = await apiClient.post(
        `/devices/${encodeURIComponent(deviceId)}/override/consume`
    );
    return (data.data ?? data)?.action ?? null;
}

/** Disable a device (lost/stolen) */
export async function disableDevice(deviceId: string, reason: string): Promise<void> {
    await apiClient.post(`/devices/${encodeURIComponent(deviceId)}/disable`, { reason });
}

/** Re-enable a previously disabled device */
export async function enableDevice(deviceId: string): Promise<void> {
    await apiClient.post(`/devices/${encodeURIComponent(deviceId)}/enable`);
}

/** Flag a device for a full wipe */
export async function forceWipeDevice(deviceId: string): Promise<void> {
    await apiClient.post(`/devices/${encodeURIComponent(deviceId)}/force-wipe`);
}

/** Flag a device to sync immediately */
export async function forceSyncDevice(deviceId: string): Promise<void> {
    await apiClient.post(`/devices/${encodeURIComponent(deviceId)}/force-sync`);
}

/** Push config refresh to a device */
export async function pushDeviceConfig(deviceId: string): Promise<void> {
    await apiClient.post(`/devices/${encodeURIComponent(deviceId)}/push-config`);
}


// ── Error Logs ──────────────────────────────────────────────────

export interface ErrorListParams {
    device_id?: string;
    severity?: string;
    unresolved_only?: boolean;
    limit?: number;
    offset?: number;
}

/** List error logs across all devices */
export async function listAllErrors(params?: ErrorListParams): Promise<DeviceErrorLog[]> {
    const { data } = await apiClient.get('/devices/errors/all', { params });
    return Array.isArray(data) ? data : data.data ?? [];
}

/** List error logs for a specific device */
export async function listDeviceErrors(
    deviceId: string,
    params?: Omit<ErrorListParams, 'device_id'>,
): Promise<DeviceErrorLog[]> {
    const { data } = await apiClient.get(
        `/devices/${encodeURIComponent(deviceId)}/errors`,
        { params },
    );
    return Array.isArray(data) ? data : data.data ?? [];
}

/** Upload error logs from a device */
export async function uploadErrors(
    deviceId: string,
    errors: Array<{
        severity?: string;
        error_type?: string;
        message: string;
        stack_trace?: string;
        context_json?: string;
        environment_json?: string;
        occurred_at?: string;
    }>,
): Promise<number> {
    const { data } = await apiClient.post(
        `/devices/${encodeURIComponent(deviceId)}/errors`,
        { errors },
    );
    return (data.data ?? data)?.uploaded ?? 0;
}

/** Resolve a specific error log entry */
export async function resolveError(errorId: number, note?: string): Promise<void> {
    await apiClient.post(`/devices/errors/${errorId}/resolve`, { note });
}

/** Resolve all unresolved errors for a device */
export async function resolveAllErrors(deviceId: string): Promise<number> {
    const { data } = await apiClient.post(
        `/devices/${encodeURIComponent(deviceId)}/errors/resolve-all`,
    );
    return (data.data ?? data)?.resolved ?? 0;
}


// ── Health Telemetry ────────────────────────────────────────────

/** Upload a health snapshot from a device */
export async function uploadHealth(
    deviceId: string,
    snapshot: {
        battery_level?: number;
        battery_charging?: boolean;
        storage_used_mb?: number;
        storage_total_mb?: number;
        app_version?: string;
        os_version?: string;
        pending_sync_count?: number;
        pending_media_count?: number;
        last_sync_at?: string;
        memory_used_mb?: number;
    },
): Promise<number> {
    const { data } = await apiClient.post(
        `/devices/${encodeURIComponent(deviceId)}/health`,
        snapshot,
    );
    return (data.data ?? data)?.id ?? 0;
}

/** Get health snapshot history for a device */
export async function getHealthHistory(
    deviceId: string,
    hours = 48,
): Promise<HealthSnapshot[]> {
    const { data } = await apiClient.get(
        `/devices/${encodeURIComponent(deviceId)}/health`,
        { params: { hours } },
    );
    return Array.isArray(data) ? data : data.data ?? [];
}

/** Get the most recent health snapshot */
export async function getLatestHealth(deviceId: string): Promise<HealthSnapshot | null> {
    try {
        const { data } = await apiClient.get(
            `/devices/${encodeURIComponent(deviceId)}/health/latest`,
        );
        return (data.data ?? data) as HealthSnapshot;
    } catch {
        return null;
    }
}


// ── Storage Info ────────────────────────────────────────────────

/** Get storage configuration and usage for a device */
export async function getDeviceStorage(deviceId: string): Promise<DeviceStorage> {
    const { data } = await apiClient.get(
        `/devices/${encodeURIComponent(deviceId)}/storage`,
    );
    return (data.data ?? data) as DeviceStorage;
}


// ── BT Encounters ──────────────────────────────────────────────

/** List Bluetooth encounter log */
export async function listBtEncounters(
    deviceId?: string,
    limit = 50,
): Promise<BtEncounter[]> {
    const { data } = await apiClient.get('/devices/bt/encounters', {
        params: { device_id: deviceId, limit },
    });
    return Array.isArray(data) ? data : data.data ?? [];
}

/** Device logs a BT encounter */
export async function logBtEncounter(encounter: {
    local_device_id: string;
    remote_device_id: string;
    encounter_start: string;
    encounter_end?: string;
    changes_sent?: number;
    changes_received?: number;
    media_bytes_sent?: number;
    media_bytes_received?: number;
    signal_strength?: number;
    status?: string;
    failure_reason?: string;
}): Promise<number> {
    const { data } = await apiClient.post('/devices/bt/encounters', encounter);
    return (data.data ?? data)?.id ?? 0;
}


// ── Media Delivery Tracking ────────────────────────────────────

/** Register a media file for delivery tracking */
export async function registerMedia(media: {
    media_path: string;
    media_hash: string;
    origin_device_id: string;
    media_size_bytes?: number;
}): Promise<number> {
    const { data } = await apiClient.post('/devices/media/register', media);
    return (data.data ?? data)?.id ?? 0;
}

/** Confirm media delivery to shop */
export async function confirmMediaDelivery(mediaHashes: string[]): Promise<number> {
    const { data } = await apiClient.post('/devices/media/confirm', {
        media_hashes: mediaHashes,
    });
    return (data.data ?? data)?.confirmed ?? 0;
}

/** List pending media for a device */
export async function getPendingMedia(deviceId: string): Promise<PendingMedia[]> {
    const { data } = await apiClient.get(
        `/devices/${encodeURIComponent(deviceId)}/media/pending`,
    );
    return Array.isArray(data) ? data : data.data ?? [];
}


// ── Shop Cluster ────────────────────────────────────────────────

/** List all shop cluster nodes */
export async function listClusterNodes(): Promise<ClusterNode[]> {
    const { data } = await apiClient.get('/devices/cluster/nodes');
    return Array.isArray(data) ? data : data.data ?? [];
}

/** Register or update a cluster node */
export async function registerClusterNode(node: {
    node_id?: string;
    hostname?: string;
    local_ip?: string;
    port?: number;
    app_version?: string;
    db_version?: number;
}): Promise<string> {
    const { data } = await apiClient.post('/devices/cluster/register', node);
    return (data.data ?? data)?.node_id ?? '';
}

/** Designate a node as primary shop PC */
export async function setClusterPrimary(nodeId: string): Promise<void> {
    await apiClient.post(`/devices/cluster/${encodeURIComponent(nodeId)}/primary`);
}

/** Record that a cluster node synced */
export async function markClusterSync(nodeId: string): Promise<void> {
    await apiClient.post(`/devices/cluster/${encodeURIComponent(nodeId)}/sync`);
}


// ── Log Retention ───────────────────────────────────────────────

/** Get log retention configuration */
export async function getRetentionConfig(): Promise<RetentionConfig[]> {
    const { data } = await apiClient.get('/devices/admin/retention');
    return Array.isArray(data) ? data : data.data ?? [];
}

/** Update retention policy for a log type */
export async function updateRetention(
    logType: string,
    deviceDays: number,
    shopDays: number,
): Promise<void> {
    await apiClient.put(`/devices/admin/retention/${encodeURIComponent(logType)}`, {
        device_retention_days: deviceDays,
        shop_retention_days: shopDays,
    });
}

/** Manually trigger log retention cleanup */
export async function runRetentionCleanup(): Promise<Record<string, number>> {
    const { data } = await apiClient.post('/devices/admin/retention/run');
    return (data.data ?? data)?.purged ?? {};
}
