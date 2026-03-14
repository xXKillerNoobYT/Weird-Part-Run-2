/**
 * Receiving & Receiving Sessions API functions (Phase 7C).
 */

import apiClient from '../client';
import type { ApiResponse, StatusMessage } from '../../lib/types';
import type {
  ReceiveByPO,
  POResponse,
  ReceivingSessionCreate,
  ReceivingSessionItemUpdate,
  ReceivingSessionCommit,
  ReceivingSessionResponse,
  ReceivingSessionListItem,
} from '../../lib/types';
import { unwrapPaginated } from './shared';
import { adaptedRequest } from '../adapter';


// =================================================================
// RECEIVING
// =================================================================

/** Receive items by PO */
export async function receiveByPO(
  payload: ReceiveByPO
): Promise<StatusMessage> {
  return adaptedRequest(
    async () => {
      const { data } = await apiClient.post<ApiResponse<StatusMessage>>(
    '/orders/receiving/by-po',
    payload
  );
  return data.data!;
    },
    async () => { throw new Error('Orders requires the shop server.'); },
  );
}

/** Get open PO lines for a supplier (for receive-by-supplier flow) */
export async function getOpenLinesBySupplier(
  supplierId: number
): Promise<POResponse[]> {
  return adaptedRequest(
    async () => {
      const { data } = await apiClient.get<ApiResponse<POResponse[]>>(
    `/orders/receiving/by-supplier/${supplierId}`
  );
  return data.data ?? [];
    },
    async () => [] as unknown as POResponse[],
  );
}

/** Get open PO lines for a part (for receive-by-item flow) */
export async function getOpenLinesByPart(
  partId: number
): Promise<POResponse[]> {
  return adaptedRequest(
    async () => {
      const { data } = await apiClient.get<ApiResponse<POResponse[]>>(
    `/orders/receiving/by-part/${partId}`
  );
  return data.data ?? [];
    },
    async () => [] as unknown as POResponse[],
  );
}


// =================================================================
// RECEIVING SESSIONS (Phase 7C)
// =================================================================

/** Start a new receiving session for a PO */
export async function startReceivingSession(
  body: ReceivingSessionCreate
): Promise<ReceivingSessionResponse> {
  return adaptedRequest(
    async () => {
      const { data } = await apiClient.post<ApiResponse<ReceivingSessionResponse>>(
    '/orders/receiving/sessions',
    body
  );
  return data.data!;
    },
    async () => { throw new Error('Orders requires the shop server.'); },
  );
}

/** List receiving sessions with optional filters */
export async function listReceivingSessions(params?: {
  po_id?: number;
  status?: string;
  limit?: number;
  offset?: number;
}): Promise<ReceivingSessionListItem[]> {
  return adaptedRequest(
    async () => {
      const { data } = await apiClient.get<ApiResponse<unknown>>(
    '/orders/receiving/sessions',
    { params }
  );
  return unwrapPaginated<ReceivingSessionListItem>(data.data);
    },
    async () => [] as unknown as ReceivingSessionListItem[],
  );
}

/** Get full session detail with items, progress, PO info */
export async function getReceivingSession(
  sessionId: number
): Promise<ReceivingSessionResponse> {
  return adaptedRequest(
    async () => {
      const { data } = await apiClient.get<ApiResponse<ReceivingSessionResponse>>(
    `/orders/receiving/sessions/${sessionId}`
  );
  return data.data!;
    },
    async () => ({}) as unknown as ReceivingSessionResponse,
  );
}

/** Update a single line item in a receiving session */
export async function updateReceivingSessionItem(
  sessionId: number,
  body: ReceivingSessionItemUpdate
): Promise<Record<string, unknown>> {
  return adaptedRequest(
    async () => {
      const { data } = await apiClient.put<ApiResponse<Record<string, unknown>>>(
    `/orders/receiving/sessions/${sessionId}/items`,
    body
  );
  return data.data!;
    },
    async () => { throw new Error('Orders requires the shop server.'); },
  );
}

/** Commit a receiving session — applies quantities to the PO */
export async function commitReceivingSession(
  sessionId: number,
  body?: ReceivingSessionCommit
): Promise<Record<string, unknown>> {
  return adaptedRequest(
    async () => {
      const { data } = await apiClient.post<ApiResponse<Record<string, unknown>>>(
    `/orders/receiving/sessions/${sessionId}/commit`,
    body ?? {}
  );
  return data.data!;
    },
    async () => { throw new Error('Orders requires the shop server.'); },
  );
}

/** Cancel a receiving session — discards progress */
export async function cancelReceivingSession(
  sessionId: number
): Promise<void> {
  return adaptedRequest(
    async () => {
      await apiClient.post(
    `/orders/receiving/sessions/${sessionId}/cancel`
  );
    },
    async () => { throw new Error('Orders requires the shop server.'); },
  );
}

/** Scan-mode lookup: find the PO line matching a scanned part */
export async function findPOLineByPartScan(
  sessionId: number,
  partId: number
): Promise<Record<string, unknown> | null> {
  return adaptedRequest(
    async () => {
      try {
    const { data } = await apiClient.get<ApiResponse<Record<string, unknown>>>(
      `/orders/receiving/sessions/${sessionId}/scan/${partId}`
    );
    return data.data ?? null;
  } catch {
    return null;  // 404 = no match
  }
    },
    async () => ({}) as unknown as Record<string, unknown> | null,
  );
}
