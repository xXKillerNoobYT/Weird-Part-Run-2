/**
 * Supplier Portal API — Public endpoints for supplier-facing portal.
 *
 * These endpoints use token-based auth (not staff auth). The portal token
 * is passed via X-Portal-Token header. Uses a separate axios instance
 * that doesn't include staff auth interceptors.
 */

import axios from 'axios';
import { adaptedRequest } from './adapter';
import type {
    SupplierPortalInfo,
    SupplierPortalPO,
    SupplierPortalPODetail,
    SupplierPortalAcknowledge,
} from '../lib/types';

// Base URL — same server, just no auth interceptor
const portalClient = axios.create({
    baseURL: '/api/supplier-portal/view',
    headers: { 'Content-Type': 'application/json' },
});

/** Helper to set the portal token in headers */
function tokenHeaders(token: string) {
    return { headers: { 'X-Portal-Token': token } };
}

// ── Portal Info ─────────────────────────────────────────────────

/** Validate a portal token and get supplier info */
export async function getPortalInfo(
    token: string,
): Promise<SupplierPortalInfo> {
    return adaptedRequest(
        async () => {
            const { data } = await portalClient.get<{ data: SupplierPortalInfo }>(
                '',
                tokenHeaders(token),
            );
            return data.data;
        },
        async () => {
            const { getPortalToken } = await import('../local/services/supplier-portal-service');
            return await getPortalToken(token as any) as unknown as SupplierPortalInfo;
        },
    );
}

// ── PO List ─────────────────────────────────────────────────────

/** List POs visible to the supplier */
export async function getPortalPOs(
    token: string,
    params?: { status?: string; limit?: number; offset?: number },
): Promise<SupplierPortalPO[]> {
    return adaptedRequest(
        async () => {
            const { data } = await portalClient.get<{ data: SupplierPortalPO[] }>(
                '/pos',
                { ...tokenHeaders(token), params },
            );
            return data.data;
        },
        async () => {
            throw new Error('Supplier portal view requires server connection');
        },
    );
}

// ── PO Detail ───────────────────────────────────────────────────

/** Get full PO detail for a specific PO */
export async function getPortalPODetail(
    token: string,
    poId: number,
): Promise<SupplierPortalPODetail> {
    return adaptedRequest(
        async () => {
            const { data } = await portalClient.get<{ data: SupplierPortalPODetail }>(
                `/pos/${poId}`,
                tokenHeaders(token),
            );
            return data.data;
        },
        async () => {
            throw new Error('Supplier portal view requires server connection');
        },
    );
}

// ── Acknowledge PO ───────────────────────────────────────────────

/** Acknowledge receipt of a PO */
export async function acknowledgePortalPO(
    token: string,
    body: SupplierPortalAcknowledge,
): Promise<{ message: string; po_id: number; acknowledged_at: string }> {
    return adaptedRequest(
        async () => {
            const { data } = await portalClient.post<{
                data: { message: string; po_id: number; acknowledged_at: string };
            }>(`/pos/${body.po_id}/acknowledge`, body, tokenHeaders(token));
            return data.data;
        },
        async () => {
            const { createAcknowledgment } = await import('../local/services/supplier-portal-service');
            return await createAcknowledgment({ ...body, supplier_id: 0 } as any) as unknown as { message: string; po_id: number; acknowledged_at: string };
        },
    );
}

// ── Supplier Notes (Phase 17 Gap 2) ─────────────────────────────

/** Add a follow-up note to a PO (post-acknowledgment) */
export async function addPortalNote(
    token: string,
    poId: number,
    message: string,
): Promise<{ id: number; po_id: number }> {
    return adaptedRequest(
        async () => {
            const { data } = await portalClient.post<{
                data: { id: number; po_id: number };
            }>(`/pos/${poId}/note`, { message }, tokenHeaders(token));
            return data.data;
        },
        async () => {
            throw new Error('Supplier portal view requires server connection');
        },
    );
}
