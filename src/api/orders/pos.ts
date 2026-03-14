/**
 * Purchase Orders (POs) API functions — CRUD, drafts, active views.
 */

import apiClient from '../client';
import type { ApiResponse } from '../../lib/types';
import type {
  POCreate,
  POUpdate,
  POResponse,
  POListItem,
  POFromJPO,
} from '../../lib/types';
import { unwrapPaginated } from './shared';
import { adaptedRequest } from '../adapter';


/** List POs with optional filters */
export async function listPOs(params?: {
  status?: string;
  supplier_id?: number;
}): Promise<POListItem[]> {
  return adaptedRequest(
    async () => {
      const { data } = await apiClient.get<ApiResponse<unknown>>(
    '/orders/pos',
    { params }
  );
  return unwrapPaginated<POListItem>(data.data);
    },
    async () => [] as unknown as POListItem[],
  );
}

/** Get full PO with line items */
export async function getPO(poId: number): Promise<POResponse> {
  return adaptedRequest(
    async () => {
      const { data } = await apiClient.get<ApiResponse<POResponse>>(
    `/orders/pos/${poId}`
  );
  return data.data!;
    },
    async () => ({}) as unknown as POResponse,
  );
}

/** Create a standalone PO */
export async function createPO(po: POCreate): Promise<POResponse> {
  return adaptedRequest(
    async () => {
      const { data } = await apiClient.post<ApiResponse<POResponse>>(
    '/orders/pos',
    po
  );
  return data.data!;
    },
    async () => { throw new Error('Orders requires the shop server.'); },
  );
}

/** Create PO(s) from an approved JPO */
export async function createPOFromJPO(
  payload: POFromJPO
): Promise<POResponse[]> {
  return adaptedRequest(
    async () => {
      const { data } = await apiClient.post<ApiResponse<POResponse[]>>(
    '/orders/pos/from-jpo',
    payload
  );
  return data.data ?? [];
    },
    async () => { throw new Error('Orders requires the shop server.'); },
  );
}

/** Update a PO (draft only) */
export async function updatePO(
  poId: number,
  updates: POUpdate
): Promise<POResponse> {
  return adaptedRequest(
    async () => {
      const { data } = await apiClient.put<ApiResponse<POResponse>>(
    `/orders/pos/${poId}`,
    updates
  );
  return data.data!;
    },
    async () => { throw new Error('Orders requires the shop server.'); },
  );
}

/** Submit a PO to the supplier */
export async function submitPO(poId: number): Promise<POResponse> {
  return adaptedRequest(
    async () => {
      const { data } = await apiClient.post<ApiResponse<POResponse>>(
    `/orders/pos/${poId}/submit`
  );
  return data.data!;
    },
    async () => { throw new Error('Orders requires the shop server.'); },
  );
}

/** Update PO status (acknowledged, partially_received, etc.) */
export async function updatePOStatus(
  poId: number,
  status: string,
  notes?: string
): Promise<POResponse> {
  return adaptedRequest(
    async () => {
      const { data } = await apiClient.post<ApiResponse<POResponse>>(
    `/orders/pos/${poId}/status`,
    { status, notes }
  );
  return data.data!;
    },
    async () => { throw new Error('Orders requires the shop server.'); },
  );
}

/** Generate PO PDF and get download path */
export async function generatePOPdf(
  poId: number
): Promise<{ pdf_path: string }> {
  const { data } = await apiClient.post<ApiResponse<{ pdf_path: string }>>(
    `/orders/pos/${poId}/pdf`
  );
  return data.data!;
}

/** Get PO clipboard text (formatted plain text) */
export async function getPOClipboardText(
  poId: number
): Promise<{ text: string }> {
  const { data } = await apiClient.get<ApiResponse<{ text: string }>>(
    `/orders/pos/${poId}/clipboard`
  );
  return data.data!;
}

/** List draft POs */
export async function listDraftPOs(): Promise<POListItem[]> {
  return adaptedRequest(
    async () => {
      const { data } = await apiClient.get<ApiResponse<unknown>>(
    '/orders/drafts'
  );
  return unwrapPaginated<POListItem>(data.data);
    },
    async () => [] as unknown as POListItem[],
  );
}

/** List active POs (submitted / acknowledged / partially_received) */
export async function listActivePOs(): Promise<POListItem[]> {
  return adaptedRequest(
    async () => {
      const { data } = await apiClient.get<ApiResponse<unknown>>(
    '/orders/active'
  );
  return unwrapPaginated<POListItem>(data.data);
    },
    async () => [] as unknown as POListItem[],
  );
}
