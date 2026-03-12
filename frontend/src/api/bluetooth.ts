/**
 * Bluetooth API — Endpoints for BT device scanning, pairing, and sync tunnel.
 *
 * Manages the Bluetooth RFCOMM tunnel between two Windows PCs:
 * - Scan for nearby BT devices
 * - Pair/unpair devices
 * - Start/stop the RFCOMM tunnel
 * - Monitor tunnel status and connection history
 * - Configure sync settings (role, interval, auto-connect)
 *
 * All endpoints require `manage_bluetooth` permission.
 */

import apiClient from './client';
import type { ApiResponse } from '../lib/types';

// ── Types ────────────────────────────────────────────────────────

export interface BtAvailability {
    available: boolean;
    platform_ok: boolean;
    adapter_found: boolean;
    error: string | null;
}

export interface BtDiscoveredDevice {
    address: string;           // "AA:BB:CC:DD:EE:FF"
    name: string;
    device_class: number;
    is_paired: boolean;        // Already paired in our DB
    is_connected: boolean;
}

export interface BtScanResponse {
    devices: BtDiscoveredDevice[];
    scan_duration_seconds: number;
    error?: string;
}

export interface BtPairedDevice {
    id: number;
    device_id: string | null;
    bt_address: string;
    display_name: string;
    role: 'primary' | 'secondary';
    pairing_code: string | null;
    is_active: boolean;
    last_connected_at: string | null;
    last_sync_at: string | null;
    paired_at: string | null;
    is_currently_connected: boolean;
}

export interface BtTunnelStatus {
    state: 'stopped' | 'starting' | 'listening' | 'connecting' | 'connected' | 'reconnecting' | 'error';
    mode: string;              // 'primary' | 'secondary' | 'none'
    remote_address: string;
    connected_since: string | null;
    last_heartbeat_at: string | null;
    bytes_sent: number;
    bytes_received: number;
    requests_forwarded: number;
    reconnect_count: number;
    last_error: string | null;
    uptime_seconds: number;
}

export interface BtConnectionLogEntry {
    id: number;
    local_device_id: string | null;
    remote_device_id: string | null;
    remote_bt_address: string;
    connected_at: string;
    disconnected_at: string | null;
    duration_seconds: number | null;
    bytes_sent: number;
    bytes_received: number;
    requests_forwarded: number;
    changes_synced: number;
    disconnect_reason: string | null;
    error_message: string | null;
}

export interface BtSyncConfig {
    bt_enabled: boolean;
    bt_device_role: 'primary' | 'secondary' | 'auto';
    bt_auto_connect: boolean;
    bt_sync_interval: number;  // seconds
    bt_tunnel_port: number;
}

export interface BtConnectionLog {
    entries: BtConnectionLogEntry[];
    total: number;
}

// ── Availability ─────────────────────────────────────────────────

export async function checkBtAvailability(): Promise<BtAvailability> {
    const { data } = await apiClient.get<ApiResponse<BtAvailability>>(
        '/api/bluetooth/availability',
    );
    return data.data!;
}

// ── Scanning ─────────────────────────────────────────────────────

export async function scanBtDevices(
    duration: number = 10,
): Promise<BtScanResponse> {
    const { data } = await apiClient.get<ApiResponse<BtScanResponse>>(
        '/api/bluetooth/scan',
        { params: { duration } },
    );
    return data.data!;
}

// ── Paired Devices ───────────────────────────────────────────────

export async function listPairedDevices(): Promise<BtPairedDevice[]> {
    const { data } = await apiClient.get<ApiResponse<BtPairedDevice[]>>(
        '/api/bluetooth/paired',
    );
    return data.data ?? [];
}

export async function pairDevice(payload: {
    bt_address: string;
    display_name?: string;
    role?: string;
}): Promise<BtPairedDevice> {
    const { data } = await apiClient.post<ApiResponse<BtPairedDevice>>(
        '/api/bluetooth/pair',
        payload,
    );
    return data.data!;
}

export async function unpairDevice(deviceId: number): Promise<void> {
    await apiClient.delete(`/api/bluetooth/pair/${deviceId}`);
}

// ── Tunnel Control ───────────────────────────────────────────────

export async function connectBt(payload: {
    bt_address: string;
    role?: string;
}): Promise<{ success: boolean; error?: string }> {
    const { data } = await apiClient.post<ApiResponse>(
        '/api/bluetooth/connect',
        payload,
    );
    return { success: data.success, error: data.error ?? undefined };
}

export async function disconnectBt(
    reason: string = 'manual',
): Promise<{ success: boolean; error?: string }> {
    const { data } = await apiClient.post<ApiResponse>(
        '/api/bluetooth/disconnect',
        { reason },
    );
    return { success: data.success, error: data.error ?? undefined };
}

export async function getBtTunnelStatus(): Promise<BtTunnelStatus> {
    const { data } = await apiClient.get<ApiResponse<BtTunnelStatus>>(
        '/api/bluetooth/status',
    );
    return data.data!;
}

// ── Connection Log ───────────────────────────────────────────────

export async function getBtConnectionLog(params?: {
    limit?: number;
    offset?: number;
    bt_address?: string;
}): Promise<BtConnectionLog> {
    const { data } = await apiClient.get<ApiResponse<BtConnectionLog>>(
        '/api/bluetooth/log',
        { params },
    );
    return data.data ?? { entries: [], total: 0 };
}

// ── Configuration ────────────────────────────────────────────────

export async function getBtConfig(): Promise<BtSyncConfig> {
    const { data } = await apiClient.get<ApiResponse<BtSyncConfig>>(
        '/api/bluetooth/config',
    );
    return data.data!;
}

export async function updateBtConfig(
    updates: Partial<BtSyncConfig>,
): Promise<BtSyncConfig> {
    const { data } = await apiClient.put<ApiResponse<BtSyncConfig>>(
        '/api/bluetooth/config',
        updates,
    );
    return data.data!;
}
