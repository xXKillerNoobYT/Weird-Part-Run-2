/**
 * Security API functions — company keys, device certificates,
 * shared channels, and security audit log.
 *
 * Maps to the backend /api/security/* endpoints.
 */

import apiClient from './client';
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
    const { data } = await apiClient.post<ApiResponse<CompanyKeys>>(
        '/security/company/init',
        { company_id: companyId, company_name: companyName },
    );
    return data.data!;
}

/** Get a company's key metadata. */
export async function getCompany(companyId: string): Promise<CompanyKeys | null> {
    const { data } = await apiClient.get<ApiResponse<CompanyKeys | null>>(
        '/security/company',
        { params: { company_id: companyId } },
    );
    return data.data ?? null;
}

/** List all companies (summary — no private keys). */
export async function listCompanies(): Promise<CompanyKeySummary[]> {
    const { data } = await apiClient.get<ApiResponse<CompanyKeySummary[]>>(
        '/security/companies',
    );
    return data.data ?? [];
}

/** Rotate a company's root + shop keys. Revokes all device certs. */
export async function rotateCompanyKeys(companyId: string): Promise<CompanyKeys> {
    const { data } = await apiClient.post<ApiResponse<CompanyKeys>>(
        '/security/company/rotate',
        { company_id: companyId },
    );
    return data.data!;
}


// ── Device Certificates ─────────────────────────────────────────

/** Issue a signed certificate for a device (admin). */
export async function issueCertificate(params: {
    device_id: string;
    company_id: string;
    device_public_key: string;
    validity_days?: number;
}): Promise<DeviceCertificate> {
    const { data } = await apiClient.post<ApiResponse<DeviceCertificate>>(
        '/security/certs/issue',
        params,
    );
    return data.data!;
}

/** Verify a device certificate against the company root key. */
export async function verifyCertificate(params: {
    device_id: string;
    company_id: string;
    certificate_data: string;
    signature: string;
}): Promise<CertVerifyResult> {
    const { data } = await apiClient.post<ApiResponse<CertVerifyResult>>(
        '/security/certs/verify',
        params,
    );
    return data.data!;
}

/** Get the current active certificate for a device. */
export async function getDeviceCert(deviceId: string, companyId: string): Promise<DeviceCertificate | null> {
    const { data } = await apiClient.get<ApiResponse<DeviceCertificate | null>>(
        `/security/certs/${encodeURIComponent(deviceId)}`,
        { params: { company_id: companyId } },
    );
    return data.data ?? null;
}

/** Revoke a device's certificate (blocks it from syncing). */
export async function revokeCertificate(params: {
    device_id: string;
    company_id: string;
    reason?: string;
}): Promise<{ revoked: boolean }> {
    const { data } = await apiClient.post<ApiResponse<{ revoked: boolean }>>(
        '/security/certs/revoke',
        params,
    );
    return data.data!;
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
    const { data } = await apiClient.post<ApiResponse<SharedChannel>>(
        '/security/channels',
        params,
    );
    return data.data!;
}

/** List active shared channels, optionally filtered by company. */
export async function listSharedChannels(companyId?: string): Promise<SharedChannel[]> {
    const { data } = await apiClient.get<ApiResponse<SharedChannel[]>>(
        '/security/channels',
        { params: companyId ? { company_id: companyId } : {} },
    );
    return data.data ?? [];
}

/** Deactivate (soft-delete) a shared channel. */
export async function deactivateSharedChannel(channelId: number): Promise<{ deactivated: boolean }> {
    const { data } = await apiClient.post<ApiResponse<{ deactivated: boolean }>>(
        `/security/channels/${channelId}/deactivate`,
    );
    return data.data!;
}

/** Accept a pending shared channel invitation. */
export async function acceptChannelInvitation(channelId: number, companyId: string): Promise<{ accepted: boolean }> {
    const { data } = await apiClient.post<ApiResponse<{ accepted: boolean }>>(
        `/security/channels/${channelId}/accept`,
        null,
        { params: { company_id: companyId } },
    );
    return data.data!;
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
    const { data } = await apiClient.post<ApiResponse<BtHelloPayload | null>>(
        '/security/bt/hello',
        { device_id: deviceId, company_id: companyId },
    );
    return data.data ?? null;
}

/** Verify an incoming BT_HELLO and get a BT_HELLO_ACK to send back. */
export async function btVerifyHello(
    hello: Record<string, unknown>,
    responderDeviceId: string,
    responderCompanyId: string,
): Promise<BtHelloAckPayload | { valid: false; reason: string }> {
    const { data } = await apiClient.post<ApiResponse<BtHelloAckPayload | { valid: false; reason: string }>>(
        '/security/bt/verify-hello',
        { hello, responder_device_id: responderDeviceId, responder_company_id: responderCompanyId },
    );
    return data.data!;
}

/** Verify a BT_HELLO_ACK — completing mutual authentication. */
export async function btVerifyAck(
    ack: Record<string, unknown>,
    initiatorDeviceId: string,
    initiatorCompanyId: string,
    originalNonce: string,
): Promise<{ valid: boolean; reason?: string; peer_device_id?: string }> {
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
}


// ── Security Audit ──────────────────────────────────────────────

/** Fetch security audit log with optional filters. */
export async function getSecurityAuditLog(params?: {
    event_type?: string;
    device_id?: string;
    company_id?: string;
    limit?: number;
}): Promise<SecurityAuditEvent[]> {
    const { data } = await apiClient.get<ApiResponse<SecurityAuditEvent[]>>(
        '/security/audit',
        { params: params ?? {} },
    );
    return data.data ?? [];
}
