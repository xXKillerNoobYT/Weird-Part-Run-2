/**
 * Special Items API functions (Phase 7A).
 */

import apiClient from '../client';
import type { ApiResponse } from '../../lib/types';
import type {
  SpecialItemCreate,
  SpecialItemResponse,
  SpecialItemResolve,
} from '../../lib/types';
import { adaptedRequest } from '../adapter';


/** List special items on a JPO */
export async function listSpecialItems(
  jpoId: number
): Promise<SpecialItemResponse[]> {
  return adaptedRequest(
    async () => {
      const { data } = await apiClient.get<ApiResponse<SpecialItemResponse[]>>(
    `/orders/jpos/${jpoId}/special-items`
  );
  return data.data ?? [];
    },
    async () => [] as unknown as SpecialItemResponse[],
  );
}

/** Add a special (non-catalog) item to a JPO */
export async function addSpecialItem(
  jpoId: number,
  item: SpecialItemCreate
): Promise<SpecialItemResponse> {
  return adaptedRequest(
    async () => {
      const { data } = await apiClient.post<ApiResponse<SpecialItemResponse>>(
    `/orders/jpos/${jpoId}/special-items`,
    item
  );
  return data.data!;
    },
    async () => { throw new Error('Orders requires the shop server.'); },
  );
}

/** Office resolves a flagged special item (links to catalog or clears flag) */
export async function resolveSpecialItem(
  itemId: number,
  body: SpecialItemResolve
): Promise<SpecialItemResponse> {
  return adaptedRequest(
    async () => {
      const { data } = await apiClient.put<ApiResponse<SpecialItemResponse>>(
    `/orders/special-items/${itemId}/resolve`,
    body
  );
  return data.data!;
    },
    async () => { throw new Error('Orders requires the shop server.'); },
  );
}

/** Place a special item into the parts catalog hierarchy (creates a new part + resolves the item) */
export async function placeSpecialItemInCatalog(
  itemId: number,
  body: { type_id: number; brand_id: number | null; color_id: number; manufacturer_part_number?: string }
): Promise<{ id: number; new_part_id: number; part_name: string }> {
  const { data } = await apiClient.post<ApiResponse<{ id: number; new_part_id: number; part_name: string }>>(
    `/orders/special-items/${itemId}/place-in-catalog`,
    body
  );
  return data.data!;
}

/** List all unresolved flagged special items (office queue) */
export async function listFlaggedSpecialItems(
  limit?: number
): Promise<SpecialItemResponse[]> {
  return adaptedRequest(
    async () => {
      const { data } = await apiClient.get<ApiResponse<SpecialItemResponse[]>>(
    '/orders/special-items/flagged',
    { params: limit ? { limit } : undefined }
  );
  return data.data ?? [];
    },
    async () => [] as unknown as SpecialItemResponse[],
  );
}
