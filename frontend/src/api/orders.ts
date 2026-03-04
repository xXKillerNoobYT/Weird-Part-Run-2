/**
 * Orders & Procurement API functions — JPOs, POs, receiving, returns, procurement.
 *
 * All functions follow the pattern: call apiClient → unwrap ApiResponse → return typed data.
 *
 * NOTE: List endpoints return paginated responses from the backend:
 *   { success, data: { items: [...], total: N } }
 * These functions unwrap the `items` array so callers get flat arrays.
 */

import apiClient from './client';
import type { ApiResponse, StatusMessage } from '../lib/types';
import type {
  // JPOs
  JPOCreate,
  JPOUpdate,
  JPOResponse,
  JPOListItem,
  JPOApproval,
  // POs
  POCreate,
  POUpdate,
  POResponse,
  POListItem,
  POFromJPO,
  // Receiving
  ReceiveByPO,
  // Returns
  ReturnCreate,
  ReturnUpdate,
  ReturnResponse,
  ReturnListItem,
  // Staging
  StagingZoneResponse,
  DistributeFromStaging,
  // History & Ratings
  StatusHistoryEntry,
  SupplierContactRatingCreate,
  SupplierContactRatingResponse,
  SupplierRanking,
  // Procurement
  ReorderSuggestion,
  ProcurementDashboard,
} from '../lib/types';


/** Helper: unwrap paginated backend response → flat items array */
function unwrapPaginated<T>(responseData: unknown): T[] {
  if (!responseData) return [];
  if (Array.isArray(responseData)) return responseData as T[];
  // PaginatedData shape: { items: T[], total: number, ... }
  const paginated = responseData as { items?: T[] };
  return paginated.items ?? [];
}


// =================================================================
// JOB PARTS ORDERS (JPOs)
// =================================================================

/** List all JPOs with optional status filter */
export async function listJPOs(params?: {
  status?: string;
  job_id?: number;
}): Promise<JPOListItem[]> {
  const { data } = await apiClient.get<ApiResponse<unknown>>(
    '/orders/jpos',
    { params }
  );
  return unwrapPaginated<JPOListItem>(data.data);
}

/** Get full JPO with line items */
export async function getJPO(jpoId: number): Promise<JPOResponse> {
  const { data } = await apiClient.get<ApiResponse<JPOResponse>>(
    `/orders/jpos/${jpoId}`
  );
  return data.data!;
}

/** Create a new JPO */
export async function createJPO(jpo: JPOCreate): Promise<JPOResponse> {
  const { data } = await apiClient.post<ApiResponse<JPOResponse>>(
    '/orders/jpos',
    jpo
  );
  return data.data!;
}

/** Update a JPO (draft only) */
export async function updateJPO(
  jpoId: number,
  updates: JPOUpdate
): Promise<JPOResponse> {
  const { data } = await apiClient.put<ApiResponse<JPOResponse>>(
    `/orders/jpos/${jpoId}`,
    updates
  );
  return data.data!;
}

/** Submit a JPO for approval */
export async function submitJPO(jpoId: number): Promise<JPOResponse> {
  const { data } = await apiClient.post<ApiResponse<JPOResponse>>(
    `/orders/jpos/${jpoId}/submit`
  );
  return data.data!;
}

/** Approve or reject a JPO */
export async function reviewJPO(
  jpoId: number,
  review: JPOApproval
): Promise<JPOResponse> {
  const { data } = await apiClient.post<ApiResponse<JPOResponse>>(
    `/orders/jpos/${jpoId}/review`,
    review
  );
  return data.data!;
}

/** Get supplier suggestions for a part */
export async function getPartSupplierSuggestions(
  partId: number,
  jobId?: number
): Promise<SupplierRanking[]> {
  const { data } = await apiClient.get<ApiResponse<SupplierRanking[]>>(
    `/orders/jpos/suggestions/${partId}`,
    { params: jobId ? { job_id: jobId } : undefined }
  );
  return data.data ?? [];
}


// =================================================================
// PURCHASE ORDERS (POs)
// =================================================================

/** List POs with optional filters */
export async function listPOs(params?: {
  status?: string;
  supplier_id?: number;
}): Promise<POListItem[]> {
  const { data } = await apiClient.get<ApiResponse<unknown>>(
    '/orders/pos',
    { params }
  );
  return unwrapPaginated<POListItem>(data.data);
}

/** Get full PO with line items */
export async function getPO(poId: number): Promise<POResponse> {
  const { data } = await apiClient.get<ApiResponse<POResponse>>(
    `/orders/pos/${poId}`
  );
  return data.data!;
}

/** Create a standalone PO */
export async function createPO(po: POCreate): Promise<POResponse> {
  const { data } = await apiClient.post<ApiResponse<POResponse>>(
    '/orders/pos',
    po
  );
  return data.data!;
}

/** Create PO(s) from an approved JPO */
export async function createPOFromJPO(
  payload: POFromJPO
): Promise<POResponse[]> {
  const { data } = await apiClient.post<ApiResponse<POResponse[]>>(
    '/orders/pos/from-jpo',
    payload
  );
  return data.data ?? [];
}

/** Update a PO (draft only) */
export async function updatePO(
  poId: number,
  updates: POUpdate
): Promise<POResponse> {
  const { data } = await apiClient.put<ApiResponse<POResponse>>(
    `/orders/pos/${poId}`,
    updates
  );
  return data.data!;
}

/** Submit a PO to the supplier */
export async function submitPO(poId: number): Promise<POResponse> {
  const { data } = await apiClient.post<ApiResponse<POResponse>>(
    `/orders/pos/${poId}/submit`
  );
  return data.data!;
}

/** Update PO status (acknowledged, partially_received, etc.) */
export async function updatePOStatus(
  poId: number,
  status: string,
  notes?: string
): Promise<POResponse> {
  const { data } = await apiClient.post<ApiResponse<POResponse>>(
    `/orders/pos/${poId}/status`,
    { status, notes }
  );
  return data.data!;
}

/** Generate PO PDF and get download path */
export async function generatePOPdf(
  poId: number
): Promise<{ pdf_path: string }> {
  const { data } = await apiClient.post<ApiResponse<{ pdf_path: string }>>(
    `/orders/pos/${poId}/pdf`
  );
  return data.data!;
}

/** Get PO clipboard text (formatted plain text) */
export async function getPOClipboardText(
  poId: number
): Promise<{ text: string }> {
  const { data } = await apiClient.get<ApiResponse<{ text: string }>>(
    `/orders/pos/${poId}/clipboard`
  );
  return data.data!;
}


// =================================================================
// DRAFT & ACTIVE PO VIEWS (filtered convenience endpoints)
// =================================================================

/** List draft POs */
export async function listDraftPOs(): Promise<POListItem[]> {
  const { data } = await apiClient.get<ApiResponse<unknown>>(
    '/orders/drafts'
  );
  return unwrapPaginated<POListItem>(data.data);
}

/** List active POs (submitted / acknowledged / partially_received) */
export async function listActivePOs(): Promise<POListItem[]> {
  const { data } = await apiClient.get<ApiResponse<unknown>>(
    '/orders/active'
  );
  return unwrapPaginated<POListItem>(data.data);
}


// =================================================================
// RECEIVING
// =================================================================

/** Receive items by PO */
export async function receiveByPO(
  payload: ReceiveByPO
): Promise<StatusMessage> {
  const { data } = await apiClient.post<ApiResponse<StatusMessage>>(
    '/orders/receiving/by-po',
    payload
  );
  return data.data!;
}

/** Get open PO lines for a supplier (for receive-by-supplier flow) */
export async function getOpenLinesBySupplier(
  supplierId: number
): Promise<POResponse[]> {
  const { data } = await apiClient.get<ApiResponse<POResponse[]>>(
    `/orders/receiving/by-supplier/${supplierId}`
  );
  return data.data ?? [];
}

/** Get open PO lines for a part (for receive-by-item flow) */
export async function getOpenLinesByPart(
  partId: number
): Promise<POResponse[]> {
  const { data } = await apiClient.get<ApiResponse<POResponse[]>>(
    `/orders/receiving/by-part/${partId}`
  );
  return data.data ?? [];
}


// =================================================================
// RETURNS
// =================================================================

/** List returns with optional filters */
export async function listReturns(params?: {
  return_type?: string;
  status?: string;
}): Promise<ReturnListItem[]> {
  const { data } = await apiClient.get<ApiResponse<unknown>>(
    '/orders/returns',
    { params }
  );
  return unwrapPaginated<ReturnListItem>(data.data);
}

/** Get full return with line items */
export async function getReturn(returnId: number): Promise<ReturnResponse> {
  const { data } = await apiClient.get<ApiResponse<ReturnResponse>>(
    `/orders/returns/${returnId}`
  );
  return data.data!;
}

/** Create a new return */
export async function createReturn(
  ret: ReturnCreate
): Promise<ReturnResponse> {
  const { data } = await apiClient.post<ApiResponse<ReturnResponse>>(
    '/orders/returns',
    ret
  );
  return data.data!;
}

/** Update a return (draft only) */
export async function updateReturn(
  returnId: number,
  updates: ReturnUpdate
): Promise<ReturnResponse> {
  const { data } = await apiClient.put<ApiResponse<ReturnResponse>>(
    `/orders/returns/${returnId}`,
    updates
  );
  return data.data!;
}

/** Submit a return for approval */
export async function submitReturn(
  returnId: number
): Promise<ReturnResponse> {
  const { data } = await apiClient.post<ApiResponse<ReturnResponse>>(
    `/orders/returns/${returnId}/submit`
  );
  return data.data!;
}

/** Approve a return */
export async function approveReturn(
  returnId: number,
  notes?: string
): Promise<ReturnResponse> {
  const { data } = await apiClient.post<ApiResponse<ReturnResponse>>(
    `/orders/returns/${returnId}/approve`,
    notes ? { notes } : undefined
  );
  return data.data!;
}

/** Update return status (shipped, received_by_supplier, credited, closed) */
export async function updateReturnStatus(
  returnId: number,
  status: string,
  extras?: { tracking_number?: string; rma_number?: string; credit_amount?: number; notes?: string }
): Promise<ReturnResponse> {
  const { data } = await apiClient.post<ApiResponse<ReturnResponse>>(
    `/orders/returns/${returnId}/status`,
    { status, ...extras }
  );
  return data.data!;
}


// =================================================================
// PROCUREMENT
// =================================================================

/** Get procurement dashboard stats */
export async function getProcurementDashboard(): Promise<ProcurementDashboard> {
  const { data } = await apiClient.get<ApiResponse<ProcurementDashboard>>(
    '/orders/procurement'
  );
  return data.data!;
}

/** Get reorder suggestions */
export async function getReorderSuggestions(): Promise<ReorderSuggestion[]> {
  const { data } = await apiClient.get<ApiResponse<ReorderSuggestion[]>>(
    '/orders/procurement/suggestions'
  );
  return data.data ?? [];
}

/** Get reorder suggestions grouped by supplier */
export async function getSupplierGroupedSuggestions(): Promise<Record<string, unknown>[]> {
  const { data } = await apiClient.get<ApiResponse<Record<string, unknown>[]>>(
    '/orders/procurement/grouped'
  );
  return data.data ?? [];
}

/** Get supplier rankings for a part */
export async function getSupplierRankings(
  partId: number
): Promise<SupplierRanking[]> {
  const { data } = await apiClient.get<ApiResponse<SupplierRanking[]>>(
    `/orders/procurement/rank/${partId}`
  );
  return data.data ?? [];
}

/** Request audit verification for specific parts before ordering */
export async function verifyProcurementCounts(
  partIds: number[]
): Promise<StatusMessage> {
  const { data } = await apiClient.post<ApiResponse<StatusMessage>>(
    '/orders/procurement/verify',
    { part_ids: partIds }
  );
  return data.data!;
}


// =================================================================
// STAGING ZONES
// =================================================================

/** List all staging zones */
export async function listStagingZones(): Promise<StagingZoneResponse[]> {
  const { data } = await apiClient.get<ApiResponse<StagingZoneResponse[]>>(
    '/orders/staging'
  );
  return data.data ?? [];
}

/** Distribute items from a staging zone */
export async function distributeFromStaging(
  payload: DistributeFromStaging
): Promise<StatusMessage> {
  const { data } = await apiClient.post<ApiResponse<StatusMessage>>(
    '/orders/staging/distribute',
    payload
  );
  return data.data!;
}


// =================================================================
// STATUS HISTORY (Audit Trail)
// =================================================================

/** Get status history for an entity (jpo, po, return) */
export async function getStatusHistory(
  entityType: string,
  entityId: number
): Promise<StatusHistoryEntry[]> {
  const { data } = await apiClient.get<ApiResponse<StatusHistoryEntry[]>>(
    `/orders/history/${entityType}/${entityId}`
  );
  return data.data ?? [];
}


// =================================================================
// SUPPLIER CONTACT RATINGS
// =================================================================

/** Create a supplier contact rating */
export async function createContactRating(
  rating: SupplierContactRatingCreate
): Promise<SupplierContactRatingResponse> {
  const { data } = await apiClient.post<ApiResponse<SupplierContactRatingResponse>>(
    '/orders/ratings',
    rating
  );
  return data.data!;
}

/** Get contact ratings for a supplier */
export async function getContactRatings(
  supplierId: number
): Promise<SupplierContactRatingResponse[]> {
  const { data } = await apiClient.get<ApiResponse<{ ratings: SupplierContactRatingResponse[]; avg_score: number }>>(
    `/orders/ratings/${supplierId}`
  );
  return data.data?.ratings ?? [];
}
