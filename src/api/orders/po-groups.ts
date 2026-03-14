/**
 * PO Groups API functions (Phase 7B) — bundled PO sending.
 */

import apiClient from '../client';
import type { ApiResponse } from '../../lib/types';
import type {
  POGroupCreate,
  POGroupResponse,
  POGroupListItem,
} from '../../lib/types';
import { adaptedRequest } from '../adapter';


/** Create a PO group for bundled sending to a supplier */
export async function createPOGroup(
  body: POGroupCreate
): Promise<POGroupResponse> {
  return adaptedRequest(
    async () => {
      const { data } = await apiClient.post<ApiResponse<POGroupResponse>>(
    '/orders/pos/group',
    body
  );
  return data.data!;
    },
    async () => { throw new Error('Orders requires the shop server.'); },
  );
}

/** Get a PO group with its members */
export async function getPOGroup(
  groupId: number
): Promise<POGroupResponse> {
  return adaptedRequest(
    async () => {
      const { data } = await apiClient.get<ApiResponse<POGroupResponse>>(
    `/orders/pos/group/${groupId}`
  );
  return data.data!;
    },
    async () => ({}) as unknown as POGroupResponse,
  );
}

/** List PO groups for a supplier */
export async function listPOGroupsForSupplier(
  supplierId: number,
  params?: { limit?: number }
): Promise<POGroupListItem[]> {
  return adaptedRequest(
    async () => {
      const { data } = await apiClient.get<ApiResponse<POGroupListItem[]>>(
    `/orders/pos/groups/by-supplier/${supplierId}`,
    { params }
  );
  return data.data ?? [];
    },
    async () => [] as unknown as POGroupListItem[],
  );
}

/** Generate a bundled PDF for a PO group */
export async function generatePOGroupPdf(
  groupId: number
): Promise<{ pdf_path: string; individual_pdfs: string[]; po_count: number }> {
  const { data } = await apiClient.post<
    ApiResponse<{ pdf_path: string; individual_pdfs: string[]; po_count: number }>
  >(`/orders/pos/group/${groupId}/pdf`);
  return data.data!;
}

/** Get combined clipboard text for all POs in a group */
export async function getPOGroupClipboardText(
  groupId: number
): Promise<{ text: string }> {
  const { data } = await apiClient.get<ApiResponse<{ text: string }>>(
    `/orders/pos/group/${groupId}/clipboard`
  );
  return data.data!;
}
