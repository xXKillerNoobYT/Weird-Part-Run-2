/**
 * Status History, Supplier Contact Ratings & Price History API functions.
 */

import apiClient from '../client';
import type { ApiResponse } from '../../lib/types';
import type {
  StatusHistoryEntry,
  SupplierContactRatingCreate,
  SupplierContactRatingResponse,
} from '../../lib/types';
import { adaptedRequest } from '../adapter';


// =================================================================
// STATUS HISTORY (Audit Trail)
// =================================================================

/** Get status history for an entity (jpo, po, return) */
export async function getStatusHistory(
  entityType: string,
  entityId: number
): Promise<StatusHistoryEntry[]> {
  return adaptedRequest(
    async () => {
      const { data } = await apiClient.get<ApiResponse<StatusHistoryEntry[]>>(
    `/orders/history/${entityType}/${entityId}`
  );
  return data.data ?? [];
    },
    async () => [] as unknown as StatusHistoryEntry[],
  );
}


// =================================================================
// SUPPLIER CONTACT RATINGS
// =================================================================

/** Create a supplier contact rating */
export async function createContactRating(
  rating: SupplierContactRatingCreate
): Promise<SupplierContactRatingResponse> {
  return adaptedRequest(
    async () => {
      const { data } = await apiClient.post<ApiResponse<SupplierContactRatingResponse>>(
    '/orders/ratings',
    rating
  );
  return data.data!;
    },
    async () => { throw new Error('Orders requires the shop server.'); },
  );
}

/** Get contact ratings for a supplier */
export async function getContactRatings(
  supplierId: number
): Promise<SupplierContactRatingResponse[]> {
  return adaptedRequest(
    async () => {
      const { data } = await apiClient.get<ApiResponse<{ ratings: SupplierContactRatingResponse[]; avg_score: number }>>(
    `/orders/ratings/${supplierId}`
  );
  return data.data?.ratings ?? [];
    },
    async () => [] as unknown as SupplierContactRatingResponse[],
  );
}


// =================================================================
// PRICE HISTORY
// =================================================================

export interface PriceVariance {
  current: number;
  previous: number;
  change: number;
  pct: number;
}

export interface PriceHistoryEntry {
  id: number;
  part_id: number;
  supplier_id: number;
  price: number;
  effective_date: string;
  source: string;
  reference_id: number | null;
  notes: string | null;
  supplier_name: string;
  part_number: string;
}

export interface PriceHistoryResponse {
  history: PriceHistoryEntry[];
  latest_price: number | null;
  variance: PriceVariance | null;
}

/** Get price history for a part+supplier combo */
export async function getPriceHistory(
  partId: number,
  supplierId: number,
  limit: number = 20,
): Promise<PriceHistoryResponse> {
  return adaptedRequest(
    async () => {
      const { data } = await apiClient.get<ApiResponse<PriceHistoryResponse>>(
    `/orders/price-history/${partId}/${supplierId}`,
    { params: { limit } },
  );
  return data.data!;
    },
    async () => ({}) as unknown as PriceHistoryResponse,
  );
}
