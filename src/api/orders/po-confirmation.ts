/**
 * PO Confirmation Checklist API functions (Phase 7B).
 */

import apiClient from '../client';
import type { ApiResponse } from '../../lib/types';
import type {
  ConfirmationChecklistItem,
  ConfirmationChecklistUpdate,
} from '../../lib/types';
import { adaptedRequest } from '../adapter';


/** Get the confirmation checklist for a PO */
export async function getConfirmationChecklist(
  poId: number
): Promise<ConfirmationChecklistItem[]> {
  return adaptedRequest(
    async () => {
      const { data } = await apiClient.get<ApiResponse<ConfirmationChecklistItem[]>>(
    `/orders/pos/${poId}/confirmation-checklist`
  );
  return data.data ?? [];
    },
    async () => [] as unknown as ConfirmationChecklistItem[],
  );
}

/** Update the confirmation checklist for a PO (full replacement) */
export async function updateConfirmationChecklist(
  poId: number,
  body: ConfirmationChecklistUpdate
): Promise<ConfirmationChecklistItem[]> {
  return adaptedRequest(
    async () => {
      const { data } = await apiClient.post<ApiResponse<ConfirmationChecklistItem[]>>(
    `/orders/pos/${poId}/confirmation-checklist`,
    body
  );
  return data.data ?? [];
    },
    async () => { throw new Error('Orders requires the shop server.'); },
  );
}
