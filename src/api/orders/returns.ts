/**
 * Returns, Return Sorting & Return Analytics API functions.
 */

import apiClient from '../client';
import type { ApiResponse } from '../../lib/types';
import type {
  ReturnCreate,
  ReturnUpdate,
  ReturnResponse,
  ReturnListItem,
  ReturnSortingGuidance,
  ReturnSortingRequest,
  ReturnEligibilityCheck,
  BelowTargetCheck,
  BulkReturnApprove,
  BulkActionResult,
} from '../../lib/types';
import { unwrapPaginated } from './shared';
import { adaptedRequest } from '../adapter';


// =================================================================
// RETURNS
// =================================================================

/** List returns with optional filters */
export async function listReturns(params?: {
  return_type?: string;
  status?: string;
}): Promise<ReturnListItem[]> {
  return adaptedRequest(
    async () => {
      const { data } = await apiClient.get<ApiResponse<unknown>>(
    '/orders/returns',
    { params }
  );
  return unwrapPaginated<ReturnListItem>(data.data);
    },
    async () => [] as unknown as ReturnListItem[],
  );
}

/** Get full return with line items */
export async function getReturn(returnId: number): Promise<ReturnResponse> {
  return adaptedRequest(
    async () => {
      const { data } = await apiClient.get<ApiResponse<ReturnResponse>>(
    `/orders/returns/${returnId}`
  );
  return data.data!;
    },
    async () => ({}) as unknown as ReturnResponse,
  );
}

/** Create a new return */
export async function createReturn(
  ret: ReturnCreate
): Promise<ReturnResponse> {
  return adaptedRequest(
    async () => {
      const { data } = await apiClient.post<ApiResponse<ReturnResponse>>(
    '/orders/returns',
    ret
  );
  return data.data!;
    },
    async () => { throw new Error('Orders requires the shop server.'); },
  );
}

/** Update a return (draft only) */
export async function updateReturn(
  returnId: number,
  updates: ReturnUpdate
): Promise<ReturnResponse> {
  return adaptedRequest(
    async () => {
      const { data } = await apiClient.put<ApiResponse<ReturnResponse>>(
    `/orders/returns/${returnId}`,
    updates
  );
  return data.data!;
    },
    async () => { throw new Error('Orders requires the shop server.'); },
  );
}

/** Submit a return for approval */
export async function submitReturn(
  returnId: number
): Promise<ReturnResponse> {
  return adaptedRequest(
    async () => {
      const { data } = await apiClient.post<ApiResponse<ReturnResponse>>(
    `/orders/returns/${returnId}/submit`
  );
  return data.data!;
    },
    async () => { throw new Error('Orders requires the shop server.'); },
  );
}

/** Approve a return */
export async function approveReturn(
  returnId: number,
  notes?: string
): Promise<ReturnResponse> {
  return adaptedRequest(
    async () => {
      const { data } = await apiClient.post<ApiResponse<ReturnResponse>>(
    `/orders/returns/${returnId}/approve`,
    notes ? { notes } : undefined
  );
  return data.data!;
    },
    async () => { throw new Error('Orders requires the shop server.'); },
  );
}

/** Update return status (shipped, received_by_supplier, credited, closed) */
export async function updateReturnStatus(
  returnId: number,
  status: string,
  extras?: { tracking_number?: string; rma_number?: string; credit_amount?: number; notes?: string }
): Promise<ReturnResponse> {
  return adaptedRequest(
    async () => {
      const { data } = await apiClient.post<ApiResponse<ReturnResponse>>(
    `/orders/returns/${returnId}/status`,
    { status, ...extras }
  );
  return data.data!;
    },
    async () => { throw new Error('Orders requires the shop server.'); },
  );
}


// =================================================================
// RETURN SORTING (Phase 7C)
// =================================================================

/** Get sorting guidance for all lines in a return */
export async function getSortingGuidance(
  returnId: number
): Promise<ReturnSortingGuidance[]> {
  return adaptedRequest(
    async () => {
      const { data } = await apiClient.get<ApiResponse<ReturnSortingGuidance[]>>(
    `/orders/returns/${returnId}/sorting`
  );
  return data.data ?? [];
    },
    async () => [] as unknown as ReturnSortingGuidance[],
  );
}

/** Apply sorting dispositions to a return's line items */
export async function processSortingDispositions(
  returnId: number,
  body: ReturnSortingRequest
): Promise<Record<string, unknown>> {
  return adaptedRequest(
    async () => {
      const { data } = await apiClient.post<ApiResponse<Record<string, unknown>>>(
    `/orders/returns/${returnId}/sorting`,
    body
  );
  return data.data!;
    },
    async () => { throw new Error('Orders requires the shop server.'); },
  );
}

/** Check whether a part can be returned to the supplier */
export async function checkReturnEligibility(
  partId: number,
  condition?: string
): Promise<ReturnEligibilityCheck> {
  return adaptedRequest(
    async () => {
      const { data } = await apiClient.get<ApiResponse<ReturnEligibilityCheck>>(
    `/orders/returns/eligibility/${partId}`,
    { params: condition ? { condition } : undefined }
  );
  return data.data!;
    },
    async () => ({}) as unknown as ReturnEligibilityCheck,
  );
}

/** Check whether a part is below its restock target */
export async function checkBelowTarget(
  partId: number
): Promise<BelowTargetCheck> {
  return adaptedRequest(
    async () => {
      const { data } = await apiClient.get<ApiResponse<BelowTargetCheck>>(
    `/orders/returns/below-target/${partId}`
  );
  return data.data!;
    },
    async () => ({}) as unknown as BelowTargetCheck,
  );
}


// =================================================================
// RETURN ANALYTICS
// =================================================================

export interface ReturnAnalytics {
  totals: { total_returns: number; total_items: number; total_cost: number };
  by_reason: { reason: string; count: number; total_qty: number }[];
  by_type: { return_type: string; return_count: number; total_qty: number }[];
  by_condition: { condition: string; count: number; total_qty: number }[];
  by_disposition: { disposition: string; count: number; total_qty: number; total_cost: number }[];
  top_parts: { part_id: number; part_name: string; part_code: string; total_qty: number; return_count: number }[];
}

/** Get return reason analytics for a period */
export async function getReturnAnalytics(params?: {
  start_date?: string;
  end_date?: string;
}): Promise<ReturnAnalytics> {
  return adaptedRequest(
    async () => {
      const { data } = await apiClient.get<ApiResponse<ReturnAnalytics>>(
    '/orders/returns/analytics',
    { params },
  );
  return data.data!;
    },
    async () => ({}) as unknown as ReturnAnalytics,
  );
}


// =================================================================
// BULK RETURN ACTIONS (Phase 7E)
// =================================================================

/** Approve multiple pending returns at once */
export async function bulkApproveReturns(
  body: BulkReturnApprove
): Promise<BulkActionResult[]> {
  return adaptedRequest(
    async () => {
      const { data } = await apiClient.post<ApiResponse<BulkActionResult[]>>(
    '/orders/returns/bulk-approve',
    body
  );
  return data.data ?? [];
    },
    async () => { throw new Error('Orders requires the shop server.'); },
  );
}
