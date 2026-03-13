/**
 * Remote Sync API functions — internet sync, peers, channels, file sync.
 *
 * Maps to the backend /api/remote-sync/* endpoints.
 */

import apiClient from './client';
import type { ApiResponse } from '../lib/types';

// ══════════════════════════════════════════════════════════════════
// Types
// ══════════════════════════════════════════════════════════════════

export interface RemoteSyncConfig {
    id: number;
    is_enabled: number;
    public_url: string | null;
    listen_port: number;
    tls_cert_path: string | null;
    tls_key_path: string | null;
    proxy_mode: string;
    proxy_details: Record<string, unknown>;
    rate_limit_rpm: number;
    max_payload_kb: number;
    require_cert_auth: number;
    allowed_cidrs: string[];
    failban_enabled: number;
    failban_max_attempts: number;
    failban_lockout_minutes: number;
    multi_site_role: string;
    primary_shop_url: string | null;
    primary_shop_id: string | null;
    sync_interval_minutes: number;
    compress_payloads: number;
    media_defer_to_wifi: number;
    updated_at: string;
    updated_by: number | null;
}

export interface RemotePeer {
    id: number;
    peer_id: string;
    peer_name: string;
    peer_url: string;
    peer_type: string;
    company_id: string | null;
    public_key: string | null;
    shared_secret: string | null;
    is_verified: number;
    is_active: number;
    last_sync_at: string | null;
    last_sync_status: string;
    total_syncs: number;
    total_changes_sent: number;
    total_changes_received: number;
    error_count: number;
    last_error: string | null;
    created_at: string;
    updated_at: string;
}

export interface RemoteSyncSession {
    id: number;
    session_id: string;
    peer_id: string;
    session_type: string;
    direction: string;
    transport: string;
    status: string;
    changes_sent: number;
    changes_received: number;
    conflicts: number;
    bytes_transferred: number;
    auth_method: string | null;
    ip_address: string | null;
    error_message: string | null;
    started_at: string;
    completed_at: string | null;
    duration_ms: number | null;
}

export interface SharedChannelEnhanced {
    id: number;
    channel_name: string;
    owner_company_id: string;
    scope_json: string;
    permissions_json: string;
    scope: Record<string, unknown>;
    permissions: Record<string, unknown>;
    description: string | null;
    is_active: number;
    expires_at: string | null;
    auto_expire_days: number | null;
    last_renewed_at: string | null;
    renewed_by: number | null;
    revoked_at: string | null;
    revoked_by: number | null;
    revoke_reason: string | null;
    created_by: number | null;
    created_at: string;
    updated_at: string;
    members: SharedChannelMemberEnhanced[];
    redaction_rules?: RedactionRule[];
}

export interface SharedChannelMemberEnhanced {
    id: number;
    channel_id: number;
    company_id: string;
    role: string;
    accepted_at: string | null;
    last_sync_at: string | null;
    data_sent_count: number;
    data_received_count: number;
    created_at: string;
}

export interface RedactionRule {
    id: number;
    channel_id: number;
    table_name: string;
    field_name: string;
    redaction_type: string;
    replacement_value: string | null;
    is_active: number;
    created_at: string;
}

export interface SharedDataLogEntry {
    id: number;
    shared_channel_id: number;
    direction: string;
    table_name: string;
    record_id: number;
    operation: string;
    redactions_applied: string[];
    data_hash: string | null;
    peer_id: string | null;
    session_id: string | null;
    synced_at: string;
}

export interface ChannelStats {
    outbound: { record_count: number; table_count: number; first_exchange?: string; last_exchange?: string };
    inbound: { record_count: number; table_count: number; first_exchange?: string; last_exchange?: string };
}

export interface FileSyncPackage {
    id: number;
    package_id: string;
    package_type: string;
    direction: string;
    file_name: string;
    file_path: string | null;
    file_size_bytes: number;
    encryption_method: string | null;
    key_hint: string | null;
    tables_included: string[];
    record_count: number;
    changes_since: string | null;
    changes_until: string | null;
    status: string;
    created_by: number | null;
    applied_by: number | null;
    applied_at: string | null;
    error_message: string | null;
    expires_at: string | null;
    created_at: string;
}

export interface PeerHealthStatus {
    peer_id: string;
    peer_name: string;
    peer_url: string;
    peer_type: string;
    health: string;
    last_sync_at: string | null;
    last_sync_status: string;
    error_count: number;
}

export interface FailbanEntry {
    id: number;
    ip_address: string;
    failure_count: number;
    first_failure: string;
    last_failure: string;
    locked_until: string | null;
    reason: string | null;
}

export interface RemoteSyncDashboard {
    is_enabled: number;
    multi_site_role: string;
    public_url: string | null;
    active_peers: number;
    active_sessions: number;
    last_24h: {
        total: number;
        completed: number;
        failed: number;
        total_sent: number;
        total_received: number;
    };
    failban_enabled: number;
}

export interface MultiSiteStatus {
    role: string;
    primary_shop_url: string | null;
    primary_shop_id: string | null;
    sync_interval_minutes: number;
    cluster_nodes: Record<string, unknown>[];
    multi_site_peers: RemotePeer[];
}

export interface AuthResult {
    valid: boolean;
    reason?: string;
    session_id?: string;
    config?: Record<string, unknown>;
    peer_name?: string;
}


// ══════════════════════════════════════════════════════════════════
// Config
// ══════════════════════════════════════════════════════════════════

export async function getRemoteSyncConfig(): Promise<RemoteSyncConfig> {
    const { data } = await apiClient.get<ApiResponse<RemoteSyncConfig>>('/remote-sync/config');
    return data.data!;
}

export async function updateRemoteSyncConfig(fields: Record<string, unknown>): Promise<RemoteSyncConfig> {
    const { data } = await apiClient.put<ApiResponse<RemoteSyncConfig>>(
        '/remote-sync/config',
        { fields },
    );
    return data.data!;
}


// ══════════════════════════════════════════════════════════════════
// Peers
// ══════════════════════════════════════════════════════════════════

export async function registerPeer(params: {
    peer_name: string;
    peer_url: string;
    peer_type?: string;
    company_id?: string;
    public_key?: string;
}): Promise<RemotePeer> {
    const { data } = await apiClient.post<ApiResponse<RemotePeer>>('/remote-sync/peers', params);
    return data.data!;
}

export async function listPeers(params?: {
    peer_type?: string;
    active_only?: boolean;
}): Promise<RemotePeer[]> {
    const { data } = await apiClient.get<ApiResponse<RemotePeer[]>>(
        '/remote-sync/peers',
        { params },
    );
    return data.data ?? [];
}

export async function getPeer(peerId: string): Promise<RemotePeer | null> {
    const { data } = await apiClient.get<ApiResponse<RemotePeer | null>>(
        `/remote-sync/peers/${peerId}`,
    );
    return data.data ?? null;
}

export async function updatePeer(peerId: string, fields: Record<string, unknown>): Promise<RemotePeer> {
    const { data } = await apiClient.put<ApiResponse<RemotePeer>>(
        `/remote-sync/peers/${peerId}`,
        fields,
    );
    return data.data!;
}

export async function verifyPeer(peerId: string, publicKey: string): Promise<RemotePeer> {
    const { data } = await apiClient.post<ApiResponse<RemotePeer>>(
        `/remote-sync/peers/${peerId}/verify`,
        { public_key: publicKey },
    );
    return data.data!;
}

export async function deactivatePeer(peerId: string): Promise<{ deactivated: boolean }> {
    const { data } = await apiClient.post<ApiResponse<{ deactivated: boolean }>>(
        `/remote-sync/peers/${peerId}/deactivate`,
    );
    return data.data!;
}


// ══════════════════════════════════════════════════════════════════
// Sessions
// ══════════════════════════════════════════════════════════════════

export async function listSessions(params?: {
    peer_id?: string;
    session_type?: string;
    status?: string;
    limit?: number;
}): Promise<RemoteSyncSession[]> {
    const { data } = await apiClient.get<ApiResponse<RemoteSyncSession[]>>(
        '/remote-sync/sessions',
        { params },
    );
    return data.data ?? [];
}

export async function getSession(sessionId: string): Promise<RemoteSyncSession | null> {
    const { data } = await apiClient.get<ApiResponse<RemoteSyncSession | null>>(
        `/remote-sync/sessions/${sessionId}`,
    );
    return data.data ?? null;
}


// ══════════════════════════════════════════════════════════════════
// Dashboard
// ══════════════════════════════════════════════════════════════════

export async function getRemoteSyncDashboard(): Promise<RemoteSyncDashboard> {
    const { data } = await apiClient.get<ApiResponse<RemoteSyncDashboard>>(
        '/remote-sync/dashboard',
    );
    return data.data!;
}


// ══════════════════════════════════════════════════════════════════
// Authentication (machine-to-machine)
// ══════════════════════════════════════════════════════════════════

export async function authenticateRemoteDevice(params: {
    device_id: string;
    company_id: string;
    certificate_data: string;
    signature: string;
}): Promise<AuthResult> {
    const { data } = await apiClient.post<ApiResponse<AuthResult>>(
        '/remote-sync/auth/device',
        params,
    );
    return data.data!;
}

export async function authenticatePeerShop(params: {
    peer_id: string;
    public_key: string;
    challenge_response?: string;
}): Promise<AuthResult> {
    const { data } = await apiClient.post<ApiResponse<AuthResult>>(
        '/remote-sync/auth/peer',
        params,
    );
    return data.data!;
}


// ══════════════════════════════════════════════════════════════════
// Multi-Site
// ══════════════════════════════════════════════════════════════════

export async function getMultiSiteStatus(): Promise<MultiSiteStatus> {
    const { data } = await apiClient.get<ApiResponse<MultiSiteStatus>>(
        '/remote-sync/multi-site',
    );
    return data.data!;
}

export async function setMultiSiteRole(params: {
    role: string;
    primary_shop_url?: string;
    primary_shop_id?: string;
}): Promise<RemoteSyncConfig> {
    const { data } = await apiClient.put<ApiResponse<RemoteSyncConfig>>(
        '/remote-sync/multi-site/role',
        params,
    );
    return data.data!;
}


// ══════════════════════════════════════════════════════════════════
// Fail2Ban
// ══════════════════════════════════════════════════════════════════

export async function listFailban(): Promise<FailbanEntry[]> {
    const { data } = await apiClient.get<ApiResponse<FailbanEntry[]>>('/remote-sync/failban');
    return data.data ?? [];
}

export async function clearFailban(ip?: string): Promise<{ cleared: number }> {
    const { data } = await apiClient.delete<ApiResponse<{ cleared: number }>>(
        '/remote-sync/failban',
        { params: ip ? { ip } : undefined },
    );
    return data.data!;
}


// ══════════════════════════════════════════════════════════════════
// Shared Channels (Enhanced)
// ══════════════════════════════════════════════════════════════════

export async function createSharedChannel(params: {
    channel_name: string;
    owner_company_id: string;
    partner_company_ids?: string[];
    scope?: Record<string, unknown>;
    permissions?: Record<string, unknown>;
    description?: string;
    expires_at?: string;
    auto_expire_days?: number;
}): Promise<SharedChannelEnhanced> {
    const { data } = await apiClient.post<ApiResponse<SharedChannelEnhanced>>(
        '/remote-sync/channels',
        params,
    );
    return data.data!;
}

export async function listSharedChannels(params?: {
    company_id?: string;
    include_inactive?: boolean;
}): Promise<SharedChannelEnhanced[]> {
    const { data } = await apiClient.get<ApiResponse<SharedChannelEnhanced[]>>(
        '/remote-sync/channels',
        { params },
    );
    return data.data ?? [];
}

export async function getSharedChannel(channelId: number): Promise<SharedChannelEnhanced | null> {
    const { data } = await apiClient.get<ApiResponse<SharedChannelEnhanced | null>>(
        `/remote-sync/channels/${channelId}`,
    );
    return data.data ?? null;
}

export async function updateSharedChannel(channelId: number, fields: {
    scope?: Record<string, unknown>;
    permissions?: Record<string, unknown>;
    description?: string;
    expires_at?: string;
    auto_expire_days?: number;
}): Promise<SharedChannelEnhanced> {
    const { data } = await apiClient.put<ApiResponse<SharedChannelEnhanced>>(
        `/remote-sync/channels/${channelId}`,
        fields,
    );
    return data.data!;
}

export async function renewSharedChannel(channelId: number, newExpiresAt?: string): Promise<SharedChannelEnhanced> {
    const { data } = await apiClient.post<ApiResponse<SharedChannelEnhanced>>(
        `/remote-sync/channels/${channelId}/renew`,
        { new_expires_at: newExpiresAt },
    );
    return data.data!;
}

export async function revokeSharedChannel(channelId: number, reason?: string): Promise<{ revoked: boolean }> {
    const { data } = await apiClient.post<ApiResponse<{ revoked: boolean }>>(
        `/remote-sync/channels/${channelId}/revoke`,
        { reason },
    );
    return data.data!;
}

export async function acceptSharedChannel(channelId: number, companyId: string): Promise<{ accepted: boolean }> {
    const { data } = await apiClient.post<ApiResponse<{ accepted: boolean }>>(
        `/remote-sync/channels/${channelId}/accept`,
        null,
        { params: { company_id: companyId } },
    );
    return data.data!;
}


// ══════════════════════════════════════════════════════════════════
// Redaction Rules
// ══════════════════════════════════════════════════════════════════

export async function addRedactionRule(channelId: number, params: {
    table_name: string;
    field_name: string;
    redaction_type?: string;
    replacement_value?: string;
}): Promise<RedactionRule> {
    const { data } = await apiClient.post<ApiResponse<RedactionRule>>(
        `/remote-sync/channels/${channelId}/redactions`,
        params,
    );
    return data.data!;
}

export async function listRedactionRules(channelId: number): Promise<RedactionRule[]> {
    const { data } = await apiClient.get<ApiResponse<RedactionRule[]>>(
        `/remote-sync/channels/${channelId}/redactions`,
    );
    return data.data ?? [];
}

export async function removeRedactionRule(channelId: number, ruleId: number): Promise<{ removed: boolean }> {
    const { data } = await apiClient.delete<ApiResponse<{ removed: boolean }>>(
        `/remote-sync/channels/${channelId}/redactions/${ruleId}`,
    );
    return data.data!;
}


// ══════════════════════════════════════════════════════════════════
// Data Exchange Log
// ══════════════════════════════════════════════════════════════════

export async function getChannelDataLog(channelId: number, params?: {
    direction?: string;
    table_name?: string;
    limit?: number;
}): Promise<SharedDataLogEntry[]> {
    const { data } = await apiClient.get<ApiResponse<SharedDataLogEntry[]>>(
        `/remote-sync/channels/${channelId}/data-log`,
        { params },
    );
    return data.data ?? [];
}

export async function getChannelStats(channelId: number): Promise<ChannelStats> {
    const { data } = await apiClient.get<ApiResponse<ChannelStats>>(
        `/remote-sync/channels/${channelId}/stats`,
    );
    return data.data!;
}


// ══════════════════════════════════════════════════════════════════
// File-Based Sync
// ══════════════════════════════════════════════════════════════════

export async function exportFileSyncPackage(params: {
    tables?: string[];
    changes_since?: string;
    passphrase?: string;
    key_hint?: string;
    expires_days?: number;
}): Promise<FileSyncPackage> {
    const { data } = await apiClient.post<ApiResponse<FileSyncPackage>>(
        '/remote-sync/file-sync/export',
        params,
    );
    return data.data!;
}

export async function importFileSyncPackage(params: {
    file_path: string;
    passphrase?: string;
}): Promise<FileSyncPackage & { applied_count?: number; errors?: string[] }> {
    const { data } = await apiClient.post<ApiResponse<FileSyncPackage & { applied_count?: number; errors?: string[] }>>(
        '/remote-sync/file-sync/import',
        params,
    );
    return data.data!;
}

export async function listFileSyncPackages(params?: {
    direction?: string;
    status?: string;
    limit?: number;
}): Promise<FileSyncPackage[]> {
    const { data } = await apiClient.get<ApiResponse<FileSyncPackage[]>>(
        '/remote-sync/file-sync/packages',
        { params },
    );
    return data.data ?? [];
}

export async function getFileSyncPackage(packageId: string): Promise<FileSyncPackage | null> {
    const { data } = await apiClient.get<ApiResponse<FileSyncPackage | null>>(
        `/remote-sync/file-sync/packages/${packageId}`,
    );
    return data.data ?? null;
}


// ══════════════════════════════════════════════════════════════════
// Health
// ══════════════════════════════════════════════════════════════════

export async function checkPeerHealth(): Promise<PeerHealthStatus[]> {
    const { data } = await apiClient.get<ApiResponse<PeerHealthStatus[]>>(
        '/remote-sync/health',
    );
    return data.data ?? [];
}
