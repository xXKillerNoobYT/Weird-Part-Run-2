/**
 * PO Conversation Threads API functions (Phase 7B).
 */

import apiClient from '../client';
import type { ApiResponse } from '../../lib/types';
import type {
  POConversationCreate,
  POConversationEntry,
  POConversationFollowUp,
} from '../../lib/types';
import { adaptedRequest } from '../adapter';


/** Get the conversation thread for a PO */
export async function getPOConversation(
  poId: number,
  params?: { limit?: number; offset?: number }
): Promise<POConversationEntry[]> {
  return adaptedRequest(
    async () => {
      const { data } = await apiClient.get<ApiResponse<POConversationEntry[]>>(
    `/orders/pos/${poId}/conversation`,
    { params }
  );
  return data.data ?? [];
    },
    async () => [] as unknown as POConversationEntry[],
  );
}

/** Add a manual conversation entry to a PO thread */
export async function addPOConversationEntry(
  poId: number,
  body: POConversationCreate
): Promise<POConversationEntry> {
  return adaptedRequest(
    async () => {
      const { data } = await apiClient.post<ApiResponse<POConversationEntry>>(
    `/orders/pos/${poId}/conversation`,
    body
  );
  return data.data!;
    },
    async () => { throw new Error('Orders requires the shop server.'); },
  );
}

/** Get all conversation entries across POs for a supplier */
export async function getSupplierConversation(
  supplierId: number,
  params?: { limit?: number; offset?: number }
): Promise<POConversationEntry[]> {
  return adaptedRequest(
    async () => {
      const { data } = await apiClient.get<ApiResponse<POConversationEntry[]>>(
    `/orders/suppliers/${supplierId}/conversation`,
    { params }
  );
  return data.data ?? [];
    },
    async () => [] as unknown as POConversationEntry[],
  );
}

/** Toggle follow-up status on a conversation entry */
export async function toggleConversationFollowUp(
  entryId: number,
  body: POConversationFollowUp
): Promise<POConversationEntry> {
  return adaptedRequest(
    async () => {
      const { data } = await apiClient.put<ApiResponse<POConversationEntry>>(
    `/orders/conversation/${entryId}/follow-up`,
    body
  );
  return data.data!;
    },
    async () => { throw new Error('Orders requires the shop server.'); },
  );
}

/** List all open (unresolved) follow-ups, optionally filtered by supplier */
export async function listOpenFollowUps(
  params?: { supplier_id?: number; limit?: number }
): Promise<POConversationEntry[]> {
  return adaptedRequest(
    async () => {
      const { data } = await apiClient.get<ApiResponse<POConversationEntry[]>>(
    '/orders/conversation/follow-ups',
    { params }
  );
  return data.data ?? [];
    },
    async () => [] as unknown as POConversationEntry[],
  );
}
