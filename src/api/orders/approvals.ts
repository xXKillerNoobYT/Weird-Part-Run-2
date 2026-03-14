/**
 * Office Approvals Queue API functions (Phase 7B).
 */

import apiClient from '../client';
import type { ApiResponse } from '../../lib/types';
import type {
  PendingApprovalItem,
  PendingApprovalCounts,
  BulkApprovalAction,
  BulkApprovalResult,
  OrderSummary,
} from '../../lib/types';
import { adaptedRequest } from '../adapter';


/** Get all pending JPOs + returns for the approval queue */
export async function getPendingApprovals(
  params?: { limit?: number; offset?: number }
): Promise<PendingApprovalItem[]> {
  return adaptedRequest(
    async () => {
      const { data } = await apiClient.get<ApiResponse<PendingApprovalItem[]>>(
    '/orders/office/pending-approvals',
    { params }
  );
  return data.data ?? [];
    },
    async () => [] as unknown as PendingApprovalItem[],
  );
}

/** Get counts for the pending-approvals badge */
export async function countPendingApprovals(): Promise<PendingApprovalCounts> {
  return adaptedRequest(
    async () => {
      const { data } = await apiClient.get<ApiResponse<PendingApprovalCounts>>(
    '/orders/office/pending-approvals/count'
  );
  return data.data!;
    },
    async () => ({}) as unknown as PendingApprovalCounts,
  );
}

/** Bulk approve or reject multiple JPOs/returns */
export async function bulkApproveOrReject(
  body: BulkApprovalAction
): Promise<BulkApprovalResult[]> {
  return adaptedRequest(
    async () => {
      const { data } = await apiClient.post<ApiResponse<BulkApprovalResult[]>>(
    '/orders/office/bulk-approve',
    body
  );
  return data.data ?? [];
    },
    async () => { throw new Error('Orders requires the shop server.'); },
  );
}

/** Cross-job aggregate summary of approved JPO lines still needing POs (Phase 17 Gap 4) */
export async function getOrderSummary(): Promise<OrderSummary> {
  return adaptedRequest(
    async () => {
      const { data } = await apiClient.get<ApiResponse<OrderSummary>>(
    '/orders/office/order-summary'
  );
  return data.data!;
    },
    async () => ({}) as unknown as OrderSummary,
  );
}
