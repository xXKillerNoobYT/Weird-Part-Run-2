/**
 * Job Parts Orders (JPOs) API functions.
 */

import apiClient from '../client';
import { adaptedRequest } from '../adapter';
import type { ApiResponse } from '../../lib/types';
import type {
  JPOCreate,
  JPOUpdate,
  JPOResponse,
  JPOListItem,
  JPOApproval,
  SupplierRanking,
} from '../../lib/types';
import { unwrapPaginated } from './shared';


/** List all JPOs with optional filters */
export async function listJPOs(params?: {
  status?: string;
  job_id?: number;
  order_type?: 'job' | 'warehouse';
  requested_by?: number;
}): Promise<JPOListItem[]> {
  return adaptedRequest(
    async () => {
      const { data } = await apiClient.get<ApiResponse<unknown>>(
        '/orders/jpos',
        { params }
      );
      return unwrapPaginated<JPOListItem>(data.data);
    },
    async () => {
      const { listJPOs: local } = await import('../../local/services/order-service');
      const result = await local(params);
      return result.items as unknown as JPOListItem[];
    },
  );
}

/** Get full JPO with line items */
export async function getJPO(jpoId: number): Promise<JPOResponse> {
  return adaptedRequest(
    async () => {
      const { data } = await apiClient.get<ApiResponse<JPOResponse>>(
        `/orders/jpos/${jpoId}`
      );
      return data.data!;
    },
    async () => {
      const { getJPO: local, getJPOLines } = await import('../../local/services/order-service');
      const jpo = await local(jpoId);
      if (!jpo) throw new Error('JPO not found');
      const lines = await getJPOLines(jpoId);
      return { ...jpo, lines } as unknown as JPOResponse;
    },
  );
}

/** Create a new JPO */
export async function createJPO(jpo: JPOCreate): Promise<JPOResponse> {
  return adaptedRequest(
    async () => {
      const { data } = await apiClient.post<ApiResponse<JPOResponse>>(
        '/orders/jpos',
        jpo
      );
      return data.data!;
    },
    async () => {
      const { createJPO: local } = await import('../../local/services/order-service');
      return await local(jpo as any, 0) as unknown as JPOResponse;
    },
  );
}

/** Update a JPO (draft only) */
export async function updateJPO(
  jpoId: number,
  updates: JPOUpdate
): Promise<JPOResponse> {
  return adaptedRequest(
    async () => {
      const { data } = await apiClient.put<ApiResponse<JPOResponse>>(
    `/orders/jpos/${jpoId}`,
    updates
  );
  return data.data!;
    },
    async () => { throw new Error('Orders requires the shop server.'); },
  );
}

/** Submit a JPO for approval */
export async function submitJPO(jpoId: number): Promise<JPOResponse> {
  return adaptedRequest(
    async () => {
      const { data } = await apiClient.post<ApiResponse<JPOResponse>>(
        `/orders/jpos/${jpoId}/submit`
      );
      return data.data!;
    },
    async () => {
      const { submitJPO: local } = await import('../../local/services/order-service');
      const jpo = await local(jpoId, 0);
      if (!jpo) throw new Error('JPO not found or not in draft status');
      return jpo as unknown as JPOResponse;
    },
  );
}

/** Approve or reject a JPO */
export async function reviewJPO(
  jpoId: number,
  review: JPOApproval
): Promise<JPOResponse> {
  return adaptedRequest(
    async () => {
      const { data } = await apiClient.post<ApiResponse<JPOResponse>>(
    `/orders/jpos/${jpoId}/review`,
    review
  );
  return data.data!;
    },
    async () => { throw new Error('Orders requires the shop server.'); },
  );
}

/** Get supplier suggestions for a part */
export async function getPartSupplierSuggestions(
  partId: number,
  jobId?: number
): Promise<SupplierRanking[]> {
  return adaptedRequest(
    async () => {
      const { data } = await apiClient.get<ApiResponse<SupplierRanking[]>>(
    `/orders/jpos/suggestions/${partId}`,
    { params: jobId ? { job_id: jobId } : undefined }
  );
  return data.data ?? [];
    },
    async () => [] as unknown as SupplierRanking[],
  );
}
