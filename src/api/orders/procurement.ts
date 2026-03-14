/**
 * Procurement API functions — dashboard, suggestions, rankings.
 */

import apiClient from '../client';
import type { ApiResponse, StatusMessage } from '../../lib/types';
import type {
  ProcurementDashboard,
  ReorderSuggestion,
  SupplierRanking,
} from '../../lib/types';
import { adaptedRequest } from '../adapter';


/** Get procurement dashboard stats */
export async function getProcurementDashboard(): Promise<ProcurementDashboard> {
  return adaptedRequest(
    async () => {
      const { data } = await apiClient.get<ApiResponse<ProcurementDashboard>>(
    '/orders/procurement'
  );
  return data.data!;
    },
    async () => ({}) as unknown as ProcurementDashboard,
  );
}

/** Get reorder suggestions */
export async function getReorderSuggestions(): Promise<ReorderSuggestion[]> {
  return adaptedRequest(
    async () => {
      const { data } = await apiClient.get<ApiResponse<ReorderSuggestion[]>>(
    '/orders/procurement/suggestions'
  );
  return data.data ?? [];
    },
    async () => [] as unknown as ReorderSuggestion[],
  );
}

/** Get reorder suggestions grouped by supplier */
export async function getSupplierGroupedSuggestions(): Promise<Record<string, unknown>[]> {
  return adaptedRequest(
    async () => {
      const { data } = await apiClient.get<ApiResponse<Record<string, unknown>[]>>(
    '/orders/procurement/grouped'
  );
  return data.data ?? [];
    },
    async () => [] as unknown as Record<string, unknown>[],
  );
}

/** Get supplier rankings for a part */
export async function getSupplierRankings(
  partId: number
): Promise<SupplierRanking[]> {
  return adaptedRequest(
    async () => {
      const { data } = await apiClient.get<ApiResponse<SupplierRanking[]>>(
    `/orders/procurement/rank/${partId}`
  );
  return data.data ?? [];
    },
    async () => [] as unknown as SupplierRanking[],
  );
}

/** Request audit verification for specific parts before ordering */
export async function verifyProcurementCounts(
  partIds: number[]
): Promise<StatusMessage> {
  return adaptedRequest(
    async () => {
      const { data } = await apiClient.post<ApiResponse<StatusMessage>>(
    '/orders/procurement/verify',
    { part_ids: partIds }
  );
  return data.data!;
    },
    async () => { throw new Error('Orders requires the shop server.'); },
  );
}
