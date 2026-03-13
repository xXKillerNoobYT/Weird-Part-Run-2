/**
 * Security API functions — company keys, device certificates,
 * shared channels, Bluetooth handshake, and security audit log.
 *
 * Browser mode: hits FastAPI /api/security/* endpoints.
 * Tauri mode:   BT handshake and cert verify use local security-service.
 *               Admin-only operations (key rotation, shared channels) throw —
 *               they require the root private key which only the admin device holds.
 */

import apiClient from './client';
import { adaptedRequest } from './adapter';
import type { ApiResponse } from '../lib/types';

// ── Local types (security-domain specific) ──────────────────────

export interface CompanyKeys {
    company_id: string;
    company_name: string;
    root_key_public: string;
    root_key_encrypted?: string;   // only visible to super-admin
    sync_key?: string;
    shop_node_public: string;
    shop_node_encrypted?: string;
    key_version: number;
    rotated_at: string | null;
    created_at: string;
    updated_at: string;
}

export interface CompanyKeySummary {
    company_id: string;
    company_name: string;
    key_version: number;
    created_at: string;
    updated_at: string;
}

export interface DeviceCertificate {
    id: number;
    device_id: string;
    company_id: string;
    device_public_key: string;
    certificate_data: string;
    signature: string;
    issued_at: string;
    expires_at: string;
    issued_by: number | null;
    revoked_at: string | null;
    revoke_reason: string | null;
    created_at: string;
}

export interface CertVerifyResult {
    valid: boolean;
    reason?: string;
    payload?: Record<string, unknown>;
}

export interface SharedChannel {
    id: number;
    channel_name: string;
    owner_company_id: string;
    scope: Record<string, unknown>;
    permissions: Record<string, unknown>;
    is_active: boolean;
    expires_at: string | null;
    created_by: number | null;
    created_at: string;
    members?: SharedChannelMember[];
}

export interface SharedChannelMember {
    id: number;
    channel_id: number;
    company_id: string;
    role: string;
    accepted_at: string | null;
    created_at: string;
}

export interface SecurityAuditEvent {
    id: number;
    event_type: string;
    device_id: string | null;
    company_id: string | null;
    actor_user_id: number | null;
    details: Record<string, unknown>;
    ip_address: string | null;
    recorded_at: string;
}


// ── Company Key Management ──────────────────────────────────────

/** Initialise a company with generated root/shop keypairs. Idempotent. */
export async function initCompany(companyId: string, companyName = 'My Company'): Promise<CompanyKeys> {
    return adaptedRequest(
        async () => {
            const { data } = await apiClient.post<ApiResponse<CompanyKeys>>(
                '/security/company/init',
                { company_id: companyId, company_name: companyName },
            );
            return data.data!;
        },
        async () => {
            throw new Error('Company key initialization must be done from the admin device.');
        },
    );
}

/** Get a company's key metadata. */
export async function getCompany(companyId: string): Promise<CompanyKeys | null> {
    return adaptedRequest(
        async () => {
            const { data } = await apiClient.get<ApiResponse<CompanyKeys | null>>(
                '/security/company',
                { params: { company_id: companyId } },
            );
            return data.data ?? null;
        },
        // Local: no company key table locally — return null
        async () => null,
    );
}

/** List all companies (summary — no private keys). */
export async function listCompanies(): Promise<CompanyKeySummary[]> {
    return adaptedRequest(
        async () => {
            const { data } = await apiClient.get<ApiResponse<CompanyKeySummary[]>>(
                '/security/companies',
            );
            return data.data ?? [];
        },
        // Local: single-company device — no company table
        async () => [],
    );
}

/** Rotate a company's root + shop keys. Revokes all device certs. */
export async function rotateCompanyKeys(companyId: string): Promise<CompanyKeys> {
    return adaptedRequest(
        async () => {
            const { data } = await apiClient.post<ApiResponse<CompanyKeys>>(
                '/security/company/rotate',
                { company_id: companyId },
            );
            return data.data!;
        },
        async () => {
            throw new Error('Key rotation must be done from the admin device.');
        },
    );
}


// ── Device Certificates ─────────────────────────────────────────

/** Issue a signed certificate for a device (admin). */
export async function issueCertificate(params: {
    device_id: string;
    company_id: string;
    device_public_key: string;
    validity_days?: number;
}): Promise<DeviceCertificate> {
    return adaptedRequest(
        async () => {
            const { data } = await apiClient.post<ApiResponse<DeviceCertificate>>(
                '/security/certs/issue',
                params,
            );
            return data.data!;
        },
        async () => {
            throw new Error('Certificate issuance requires the admin device with root private key.');
        },
    );
}

/** Verify a device certificate against the company root key. */
export async function verifyCertificate(params: {
    device_id: string;
    company_id: string;
    certificate_data: string;
    signature: string;
}): Promise<CertVerifyResult> {
    return adaptedRequest(
        async () => {
            const { data } = await apiClient.post<ApiResponse<CertVerifyResult>>(
                '/security/certs/verify',
                params,
            );
            return data.data!;
        },
        async () => {
            // Local: certificate verification uses stored root public key
            const { isCertificateValid } = await import('../local/services/security-service');
            const valid = await isCertificateValid();
            return { valid, reason: valid ? undefined : 'Certificate expired or not found' };
        },
    );
}

/** Get the current active certificate for a device. */
export async function getDeviceCert(deviceId: string, companyId: string): Promise<DeviceCertificate | null> {
    return adaptedRequest(
        async () => {
            const { data } = await apiClient.get<ApiResponse<DeviceCertificate | null>>(
                `/security/certs/${encodeURIComponent(deviceId)}`,
                { params: { company_id: companyId } },
            );
            return data.data ?? null;
        },
        async () => {
            const { getStoredCertificate } = await import('../local/services/security-service');
            const stored = await getStoredCertificate();
            if (!stored) return null;
            // Map stored certificate format to DeviceCertificate interface
            return {
                id: 0,
                device_id: deviceId,
                company_id: stored.companyId,
                device_public_key: '',
                certificate_data: stored.certificateData,
                signature: stored.signature,
                issued_at: '',
                expires_at: stored.expiresAt,
                issued_by: null,
                revoked_at: null,
                revoke_reason: null,
                created_at: '',
            } as DeviceCertificate;
        },
    );
}

/** Revoke a device's certificate (blocks it from syncing). */
export async function revokeCertificate(params: {
    device_id: string;
    company_id: string;
    reason?: string;
}): Promise<{ revoked: boolean }> {
    return adaptedRequest(
        async () => {
            const { data } = await apiClient.post<ApiResponse<{ revoked: boolean }>>(
                '/security/certs/revoke',
                params,
            );
            return data.data!;
        },
        async () => {
            throw new Error('Certificate revocation must be done from the admin device.');
        },
    );
}


// ── Shared Channels (Cross-Company) ─────────────────────────────

/** Create a cross-company sharing channel. */
export async function createSharedChannel(params: {
    channel_name: string;
    owner_company_id: string;
    partner_company_ids?: string[];
    scope?: Record<string, unknown>;
    permissions?: Record<string, unknown>;
    expires_at?: string | null;
}): Promise<SharedChannel> {
    return adaptedRequest(
        async () => {
            const { data } = await apiClient.post<ApiResponse<SharedChannel>>(
                '/security/channels',
                params,
            );
            return data.data!;
        },
        async () => {
            throw new Error('Shared channel management is not available on this device.');
        },
    );
}

/** List active shared channels, optionally filtered by company. */
export async function listSharedChannels(companyId?: string): Promise<SharedChannel[]> {
    return adaptedRequest(
        async () => {
            const { data } = await apiClient.get<ApiResponse<SharedChannel[]>>(
                '/security/channels',
                { params: companyId ? { company_id: companyId } : {} },
            );
            return data.data ?? [];
        },
        // Local: no shared channels stored locally yet
        async () => [],
    );
}

/** Deactivate (soft-delete) a shared channel. */
export async function deactivateSharedChannel(channelId: number): Promise<{ deactivated: boolean }> {
    return adaptedRequest(
        async () => {
            const { data } = await apiClient.post<ApiResponse<{ deactivated: boolean }>>(
                `/security/channels/${channelId}/deactivate`,
            );
            return data.data!;
        },
        async () => {
            throw new Error('Shared channel management is not available on this device.');
        },
    );
}

/** Accept a pending shared channel invitation. */
export async function acceptChannelInvitation(channelId: number, companyId: string): Promise<{ accepted: boolean }> {
    return adaptedRequest(
        async () => {
            const { data } = await apiClient.post<ApiResponse<{ accepted: boolean }>>(
                `/security/channels/${channelId}/accept`,
                null,
                { params: { company_id: companyId } },
            );
            return data.data!;
        },
        async () => {
            throw new Error('Shared channel management is not available on this device.');
        },
    );
}


// ── Bluetooth Handshake ─────────────────────────────────────────

export interface BtHelloPayload {
    type: 'BT_HELLO';
    device_id: string;
    company_id: string;
    certificate_data: string;
    signature: string;
    nonce: string;
    timestamp: string;
}

export interface BtHelloAckPayload {
    type: 'BT_HELLO_ACK';
    device_id: string;
    company_id: string;
    certificate_data: string;
    signature: string;
    nonce_response: string;
    timestamp: string;
}

/** Create a BT_HELLO payload for initiating a Bluetooth handshake. */
export async function btCreateHello(deviceId: string, companyId: string): Promise<BtHelloPayload | null> {
    return adaptedRequest(
        async () => {
            const { data } = await apiClient.post<ApiResponse<BtHelloPayload | null>>(
                '/security/bt/hello',
                { device_id: deviceId, company_id: companyId },
            );
            return data.data ?? null;
        },
        async () => {
            const { createBtHello } = await import('../local/services/security-service');
            return createBtHello();
        },
    );
}

/** Verify an incoming BT_HELLO and get a BT_HELLO_ACK to send back. */
export async function btVerifyHello(
    hello: Record<string, unknown>,
    responderDeviceId: string,
    responderCompanyId: string,
): Promise<BtHelloAckPayload | { valid: false; reason: string }> {
    return adaptedRequest(
        async () => {
            const { data } = await apiClient.post<ApiResponse<BtHelloAckPayload | { valid: false; reason: string }>>(
                '/security/bt/verify-hello',
                { hello, responder_device_id: responderDeviceId, responder_company_id: responderCompanyId },
            );
            return data.data!;
        },
        async () => {
            // Local BT hello verification happens via Tauri IPC commands
            // (push_to_sync_inbox) — this HTTP-level function isn't used locally
            throw new Error('BT hello verification uses Tauri IPC, not this API path.');
        },
    );
}

/** Verify a BT_HELLO_ACK — completing mutual authentication. */
export async function btVerifyAck(
    ack: Record<string, unknown>,
    initiatorDeviceId: string,
    initiatorCompanyId: string,
    originalNonce: string,
): Promise<{ valid: boolean; reason?: string; peer_device_id?: string }> {
    return adaptedRequest(
        async () => {
            const { data } = await apiClient.post<ApiResponse<{ valid: boolean; reason?: string; peer_device_id?: string }>>(
                '/security/bt/verify-ack',
                {
                    ack,
                    initiator_device_id: initiatorDeviceId,
                    initiator_company_id: initiatorCompanyId,
                    original_nonce: originalNonce,
                },
            );
            return data.data!;
        },
        async () => {
            // Local BT ack verification happens via Tauri IPC commands
            throw new Error('BT ack verification uses Tauri IPC, not this API path.');
        },
    );
}


// ── Security Audit ──────────────────────────────────────────────

/** Fetch security audit log with optional filters. */
export async function getSecurityAuditLog(params?: {
    event_type?: string;
    device_id?: string;
    company_id?: string;
    limit?: number;
}): Promise<SecurityAuditEvent[]> {
    return adaptedRequest(
        async () => {
            const { data } = await apiClient.get<ApiResponse<SecurityAuditEvent[]>>(
                '/security/audit',
                { params: params ?? {} },
            );
            return data.data ?? [];
        },
        // Local: read from local activity_log filtered by security-related events
        async () => {
            const { getDb } = await import('../local/db');
            const db = await getDb();
            const limit = params?.limit ?? 100;
            const rows = await db.query(
                `SELECT id, action AS event_type, NULL AS device_id, NULL AS company_id,
                        user_id AS actor_user_id, details, NULL AS ip_address, created_at AS recorded_at
                 FROM activity_log
                 WHERE action LIKE '%security%' OR action LIKE '%cert%' OR action LIKE '%auth%'
                 ORDER BY created_at DESC
                 LIMIT ?`,
                [limit],
            );
            return (rows.values ?? []) as SecurityAuditEvent[];
        },
    );
}
