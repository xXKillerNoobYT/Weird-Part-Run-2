/**
 * Bulk PO Actions API functions (Phase 7E).
 */

import apiClient from '../client';
import type { ApiResponse } from '../../lib/types';
import type {
  BulkPOSubmit,
  BulkPOStatusUpdate,
  BulkActionResult,
} from '../../lib/types';
import { adaptedRequest } from '../adapter';


/** Submit multiple draft POs to suppliers at once */
export async function bulkSubmitPOs(
  body: BulkPOSubmit
): Promise<BulkActionResult[]> {
  return adaptedRequest(
    async () => {
      const { data } = await apiClient.post<ApiResponse<BulkActionResult[]>>(
    '/orders/pos/bulk-submit',
    body
  );
  return data.data ?? [];
    },
    async () => { throw new Error('Orders requires the shop server.'); },
  );
}

/** Update status on multiple POs at once */
export async function bulkUpdatePOStatus(
  body: BulkPOStatusUpdate
): Promise<BulkActionResult[]> {
  return adaptedRequest(
    async () => {
      const { data } = await apiClient.post<ApiResponse<BulkActionResult[]>>(
    '/orders/pos/bulk-status',
    body
  );
  return data.data ?? [];
    },
    async () => { throw new Error('Orders requires the shop server.'); },
  );
}
