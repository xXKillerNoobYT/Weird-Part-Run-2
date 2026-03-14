/**
 * Supplier Portal Tokens API functions (Internal Management).
 */

import apiClient from '../client';
import type { ApiResponse } from '../../lib/types';


/** Create a new portal access token for a supplier */
export async function createPortalToken(body: {
  supplier_id: number;
  expires_in_days?: number;
  note?: string | null;
}): Promise<{
  id: number;
  supplier_id: number;
  supplier_name?: string | null;
  token: string;
  is_active: boolean;
  expires_at: string | null;
  last_used_at: string | null;
  note: string | null;
  created_by: number | null;
  created_at: string | null;
}> {
  const { data } = await apiClient.post<ApiResponse<{
    id: number; supplier_id: number; supplier_name?: string | null;
    token: string; is_active: boolean; expires_at: string | null;
    last_used_at: string | null; note: string | null;
    created_by: number | null; created_at: string | null;
  }>>('/supplier-portal/tokens', body);
  return data.data!;
}

/** List portal tokens (optionally filter by supplier) */
export async function listPortalTokens(
  supplierId?: number,
): Promise<{
  id: number; supplier_id: number; supplier_name?: string | null;
  token: string; is_active: boolean; expires_at: string | null;
  last_used_at: string | null; note: string | null;
  created_by: number | null; created_at: string | null;
}[]> {
  const { data } = await apiClient.get<ApiResponse<{
    id: number; supplier_id: number; supplier_name?: string | null;
    token: string; is_active: boolean; expires_at: string | null;
    last_used_at: string | null; note: string | null;
    created_by: number | null; created_at: string | null;
  }[]>>('/supplier-portal/tokens', {
    params: supplierId ? { supplier_id: supplierId } : undefined,
  });
  return data.data!;
}

/** Revoke a portal access token */
export async function revokePortalToken(tokenId: number): Promise<{ id: number }> {
  const { data } = await apiClient.delete<ApiResponse<{ id: number }>>(
    `/supplier-portal/tokens/${tokenId}`,
  );
  return data.data!;
}
