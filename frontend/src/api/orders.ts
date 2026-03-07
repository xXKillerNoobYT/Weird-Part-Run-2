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
  // Phase 7A: Special Items
  SpecialItemCreate,
  SpecialItemResponse,
  SpecialItemResolve,
  // Phase 7B: Office Workflow
  POConversationCreate,
  POConversationEntry,
  POConversationFollowUp,
  POGroupCreate,
  POGroupResponse,
  POGroupListItem,
  PendingApprovalItem,
  PendingApprovalCounts,
  BulkApprovalAction,
  BulkApprovalResult,
  ConfirmationChecklistItem,
  ConfirmationChecklistUpdate,
  // Phase 7C: Receiving Sessions & Return Sorting
  ReceivingSessionCreate,
  ReceivingSessionItemUpdate,
  ReceivingSessionCommit,
  ReceivingSessionResponse,
  ReceivingSessionListItem,
  ReturnSortingGuidance,
  ReturnSortingRequest,
  ReturnEligibilityCheck,
  BelowTargetCheck,
  // Phase 7E: Bulk Actions
  BulkPOSubmit,
  BulkPOStatusUpdate,
  BulkReturnApprove,
  BulkActionResult,
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

/** List all JPOs with optional filters */
export async function listJPOs(params?: {
  status?: string;
  job_id?: number;
  order_type?: 'job' | 'warehouse';
  requested_by?: number;
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
// SPECIAL ITEMS (Phase 7A)
// =================================================================

/** List special items on a JPO */
export async function listSpecialItems(
  jpoId: number
): Promise<SpecialItemResponse[]> {
  const { data } = await apiClient.get<ApiResponse<SpecialItemResponse[]>>(
    `/orders/jpos/${jpoId}/special-items`
  );
  return data.data ?? [];
}

/** Add a special (non-catalog) item to a JPO */
export async function addSpecialItem(
  jpoId: number,
  item: SpecialItemCreate
): Promise<SpecialItemResponse> {
  const { data } = await apiClient.post<ApiResponse<SpecialItemResponse>>(
    `/orders/jpos/${jpoId}/special-items`,
    item
  );
  return data.data!;
}

/** Office resolves a flagged special item (links to catalog or clears flag) */
export async function resolveSpecialItem(
  itemId: number,
  body: SpecialItemResolve
): Promise<SpecialItemResponse> {
  const { data } = await apiClient.put<ApiResponse<SpecialItemResponse>>(
    `/orders/special-items/${itemId}/resolve`,
    body
  );
  return data.data!;
}

/** List all unresolved flagged special items (office queue) */
export async function listFlaggedSpecialItems(
  limit?: number
): Promise<SpecialItemResponse[]> {
  const { data } = await apiClient.get<ApiResponse<SpecialItemResponse[]>>(
    '/orders/special-items/flagged',
    { params: limit ? { limit } : undefined }
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


// =================================================================
// PO CONVERSATION THREADS (Phase 7B)
// =================================================================

/** Get the conversation thread for a PO */
export async function getPOConversation(
  poId: number,
  params?: { limit?: number; offset?: number }
): Promise<POConversationEntry[]> {
  const { data } = await apiClient.get<ApiResponse<POConversationEntry[]>>(
    `/orders/pos/${poId}/conversation`,
    { params }
  );
  return data.data ?? [];
}

/** Add a manual conversation entry to a PO thread */
export async function addPOConversationEntry(
  poId: number,
  body: POConversationCreate
): Promise<POConversationEntry> {
  const { data } = await apiClient.post<ApiResponse<POConversationEntry>>(
    `/orders/pos/${poId}/conversation`,
    body
  );
  return data.data!;
}

/** Get all conversation entries across POs for a supplier */
export async function getSupplierConversation(
  supplierId: number,
  params?: { limit?: number; offset?: number }
): Promise<POConversationEntry[]> {
  const { data } = await apiClient.get<ApiResponse<POConversationEntry[]>>(
    `/orders/suppliers/${supplierId}/conversation`,
    { params }
  );
  return data.data ?? [];
}

/** Toggle follow-up status on a conversation entry */
export async function toggleConversationFollowUp(
  entryId: number,
  body: POConversationFollowUp
): Promise<POConversationEntry> {
  const { data } = await apiClient.put<ApiResponse<POConversationEntry>>(
    `/orders/conversation/${entryId}/follow-up`,
    body
  );
  return data.data!;
}

/** List all open (unresolved) follow-ups, optionally filtered by supplier */
export async function listOpenFollowUps(
  params?: { supplier_id?: number; limit?: number }
): Promise<POConversationEntry[]> {
  const { data } = await apiClient.get<ApiResponse<POConversationEntry[]>>(
    '/orders/conversation/follow-ups',
    { params }
  );
  return data.data ?? [];
}


// =================================================================
// PO GROUPS (Phase 7B)
// =================================================================

/** Create a PO group for bundled sending to a supplier */
export async function createPOGroup(
  body: POGroupCreate
): Promise<POGroupResponse> {
  const { data } = await apiClient.post<ApiResponse<POGroupResponse>>(
    '/orders/pos/group',
    body
  );
  return data.data!;
}

/** Get a PO group with its members */
export async function getPOGroup(
  groupId: number
): Promise<POGroupResponse> {
  const { data } = await apiClient.get<ApiResponse<POGroupResponse>>(
    `/orders/pos/group/${groupId}`
  );
  return data.data!;
}

/** List PO groups for a supplier */
export async function listPOGroupsForSupplier(
  supplierId: number,
  params?: { limit?: number }
): Promise<POGroupListItem[]> {
  const { data } = await apiClient.get<ApiResponse<POGroupListItem[]>>(
    `/orders/pos/groups/by-supplier/${supplierId}`,
    { params }
  );
  return data.data ?? [];
}


// =================================================================
// OFFICE APPROVALS QUEUE (Phase 7B)
// =================================================================

/** Get all pending JPOs + returns for the approval queue */
export async function getPendingApprovals(
  params?: { limit?: number; offset?: number }
): Promise<PendingApprovalItem[]> {
  const { data } = await apiClient.get<ApiResponse<PendingApprovalItem[]>>(
    '/orders/office/pending-approvals',
    { params }
  );
  return data.data ?? [];
}

/** Get counts for the pending-approvals badge */
export async function countPendingApprovals(): Promise<PendingApprovalCounts> {
  const { data } = await apiClient.get<ApiResponse<PendingApprovalCounts>>(
    '/orders/office/pending-approvals/count'
  );
  return data.data!;
}

/** Bulk approve or reject multiple JPOs/returns */
export async function bulkApproveOrReject(
  body: BulkApprovalAction
): Promise<BulkApprovalResult[]> {
  const { data } = await apiClient.post<ApiResponse<BulkApprovalResult[]>>(
    '/orders/office/bulk-approve',
    body
  );
  return data.data ?? [];
}


// =================================================================
// PO CONFIRMATION CHECKLIST (Phase 7B)
// =================================================================

/** Get the confirmation checklist for a PO */
export async function getConfirmationChecklist(
  poId: number
): Promise<ConfirmationChecklistItem[]> {
  const { data } = await apiClient.get<ApiResponse<ConfirmationChecklistItem[]>>(
    `/orders/pos/${poId}/confirmation-checklist`
  );
  return data.data ?? [];
}

/** Update the confirmation checklist for a PO (full replacement) */
export async function updateConfirmationChecklist(
  poId: number,
  body: ConfirmationChecklistUpdate
): Promise<ConfirmationChecklistItem[]> {
  const { data } = await apiClient.post<ApiResponse<ConfirmationChecklistItem[]>>(
    `/orders/pos/${poId}/confirmation-checklist`,
    body
  );
  return data.data ?? [];
}


// =================================================================
// RECEIVING SESSIONS (Phase 7C)
// =================================================================

/** Start a new receiving session for a PO */
export async function startReceivingSession(
  body: ReceivingSessionCreate
): Promise<ReceivingSessionResponse> {
  const { data } = await apiClient.post<ApiResponse<ReceivingSessionResponse>>(
    '/orders/receiving/sessions',
    body
  );
  return data.data!;
}

/** List receiving sessions with optional filters */
export async function listReceivingSessions(params?: {
  po_id?: number;
  status?: string;
  limit?: number;
  offset?: number;
}): Promise<ReceivingSessionListItem[]> {
  const { data } = await apiClient.get<ApiResponse<unknown>>(
    '/orders/receiving/sessions',
    { params }
  );
  return unwrapPaginated<ReceivingSessionListItem>(data.data);
}

/** Get full session detail with items, progress, PO info */
export async function getReceivingSession(
  sessionId: number
): Promise<ReceivingSessionResponse> {
  const { data } = await apiClient.get<ApiResponse<ReceivingSessionResponse>>(
    `/orders/receiving/sessions/${sessionId}`
  );
  return data.data!;
}

/** Update a single line item in a receiving session */
export async function updateReceivingSessionItem(
  sessionId: number,
  body: ReceivingSessionItemUpdate
): Promise<Record<string, unknown>> {
  const { data } = await apiClient.put<ApiResponse<Record<string, unknown>>>(
    `/orders/receiving/sessions/${sessionId}/items`,
    body
  );
  return data.data!;
}

/** Commit a receiving session — applies quantities to the PO */
export async function commitReceivingSession(
  sessionId: number,
  body?: ReceivingSessionCommit
): Promise<Record<string, unknown>> {
  const { data } = await apiClient.post<ApiResponse<Record<string, unknown>>>(
    `/orders/receiving/sessions/${sessionId}/commit`,
    body ?? {}
  );
  return data.data!;
}

/** Cancel a receiving session — discards progress */
export async function cancelReceivingSession(
  sessionId: number
): Promise<void> {
  await apiClient.post(
    `/orders/receiving/sessions/${sessionId}/cancel`
  );
}

/** Scan-mode lookup: find the PO line matching a scanned part */
export async function findPOLineByPartScan(
  sessionId: number,
  partId: number
): Promise<Record<string, unknown> | null> {
  try {
    const { data } = await apiClient.get<ApiResponse<Record<string, unknown>>>(
      `/orders/receiving/sessions/${sessionId}/scan/${partId}`
    );
    return data.data ?? null;
  } catch {
    return null;  // 404 = no match
  }
}


// =================================================================
// RETURN SORTING (Phase 7C)
// =================================================================

/** Get sorting guidance for all lines in a return */
export async function getSortingGuidance(
  returnId: number
): Promise<ReturnSortingGuidance[]> {
  const { data } = await apiClient.get<ApiResponse<ReturnSortingGuidance[]>>(
    `/orders/returns/${returnId}/sorting`
  );
  return data.data ?? [];
}

/** Apply sorting dispositions to a return's line items */
export async function processSortingDispositions(
  returnId: number,
  body: ReturnSortingRequest
): Promise<Record<string, unknown>> {
  const { data } = await apiClient.post<ApiResponse<Record<string, unknown>>>(
    `/orders/returns/${returnId}/sorting`,
    body
  );
  return data.data!;
}

/** Check whether a part can be returned to the supplier */
export async function checkReturnEligibility(
  partId: number,
  condition?: string
): Promise<ReturnEligibilityCheck> {
  const { data } = await apiClient.get<ApiResponse<ReturnEligibilityCheck>>(
    `/orders/returns/eligibility/${partId}`,
    { params: condition ? { condition } : undefined }
  );
  return data.data!;
}

/** Check whether a part is below its restock target */
export async function checkBelowTarget(
  partId: number
): Promise<BelowTargetCheck> {
  const { data } = await apiClient.get<ApiResponse<BelowTargetCheck>>(
    `/orders/returns/below-target/${partId}`
  );
  return data.data!;
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
  const { data } = await apiClient.get<ApiResponse<ReturnAnalytics>>(
    '/orders/returns/analytics',
    { params },
  );
  return data.data!;
}


// =================================================================
// BULK ACTIONS (Phase 7E)
// =================================================================

/** Submit multiple draft POs to suppliers at once */
export async function bulkSubmitPOs(
  body: BulkPOSubmit
): Promise<BulkActionResult[]> {
  const { data } = await apiClient.post<ApiResponse<BulkActionResult[]>>(
    '/orders/pos/bulk-submit',
    body
  );
  return data.data ?? [];
}

/** Update status on multiple POs at once */
export async function bulkUpdatePOStatus(
  body: BulkPOStatusUpdate
): Promise<BulkActionResult[]> {
  const { data } = await apiClient.post<ApiResponse<BulkActionResult[]>>(
    '/orders/pos/bulk-status',
    body
  );
  return data.data ?? [];
}

/** Approve multiple pending returns at once */
export async function bulkApproveReturns(
  body: BulkReturnApprove
): Promise<BulkActionResult[]> {
  const { data } = await apiClient.post<ApiResponse<BulkActionResult[]>>(
    '/orders/returns/bulk-approve',
    body
  );
  return data.data ?? [];
}


// ═══════════════════════════════════════════════════════════════
// PRICE HISTORY
// ═══════════════════════════════════════════════════════════════

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
  const { data } = await apiClient.get<ApiResponse<PriceHistoryResponse>>(
    `/orders/price-history/${partId}/${supplierId}`,
    { params: { limit } },
  );
  return data.data!;
}
