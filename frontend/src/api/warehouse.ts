/**
 * Warehouse API functions — dashboard, inventory, staging, movements,
 * audit, and helper endpoints.
 *
 * All functions follow the pattern: call apiClient → unwrap ApiResponse → return typed data.
 */

import apiClient from './client';
import type { ApiResponse, PaginatedData } from '../lib/types';
import type {
  // Dashboard
  DashboardData,
  DashboardKPIs,
  ActivitySummary,
  PendingTask,
  // Inventory
  WarehouseInventoryItem,
  WarehouseInventoryParams,
  // Receive Stock
  ReceiveStockRequest,
  ReceiveStockResult,
  // Staging
  StagingGroup,
  // Movements
  MovementRequest,
  ValidationResult,
  MovementPreview,
  MovementExecuteResponse,
  MovementLogEntry,
  MovementRule,
  ReasonCategories,
  // Audit
  AuditStartRequest,
  AuditCountRequest,
  AuditItemResponse,
  AuditResponse,
  AuditSummary,
  SuggestedRollingPart,
  // Helpers
  LocationOption,
  WizardPartSearchResult,
  SupplierPreferenceResponse,
  SupplierPreferenceSet,
} from '../lib/types';


// =================================================================
// DASHBOARD
// =================================================================

/** Combined dashboard: KPIs + activity + pending tasks */
export async function getDashboard(): Promise<DashboardData> {
  const { data } = await apiClient.get<ApiResponse<DashboardData>>(
    '/warehouse/dashboard'
  );
  return data.data!;
}

/** Dashboard KPI cards */
export async function getDashboardKPIs(): Promise<DashboardKPIs> {
  const { data } = await apiClient.get<ApiResponse<DashboardKPIs>>(
    '/warehouse/dashboard/kpis'
  );
  return data.data!;
}

/** Recent movement activity feed */
export async function getDashboardActivity(
  limit: number = 10
): Promise<ActivitySummary[]> {
  const { data } = await apiClient.get<ApiResponse<ActivitySummary[]>>(
    '/warehouse/dashboard/activity',
    { params: { limit } }
  );
  return data.data ?? [];
}

/** Pending tasks: staged items, audits, spot-checks */
export async function getDashboardPendingTasks(): Promise<PendingTask[]> {
  const { data } = await apiClient.get<ApiResponse<PendingTask[]>>(
    '/warehouse/dashboard/pending-tasks'
  );
  return data.data ?? [];
}


// =================================================================
// INVENTORY GRID
// =================================================================

/** Paginated warehouse inventory with filters and health bars */
export async function getWarehouseInventory(
  params: WarehouseInventoryParams = {}
): Promise<PaginatedData<WarehouseInventoryItem>> {
  const { data } = await apiClient.get<
    ApiResponse<PaginatedData<WarehouseInventoryItem>>
  >('/warehouse/inventory', { params });
  return (
    data.data ?? {
      items: [],
      total: 0,
      page: 1,
      page_size: 50,
      total_pages: 0,
    }
  );
}


// =================================================================
// RECEIVE STOCK (add new stock to warehouse)
// =================================================================

/** Add parts from catalog into warehouse inventory */
export async function receiveStock(
  req: ReceiveStockRequest
): Promise<ReceiveStockResult> {
  const { data } = await apiClient.post<ApiResponse<ReceiveStockResult>>(
    '/warehouse/receive-stock',
    req
  );
  return data.data!;
}


// =================================================================
// STAGING
// =================================================================

/** Pulled items grouped by destination with aging info */
export async function getStagingGroups(): Promise<StagingGroup[]> {
  const { data } = await apiClient.get<ApiResponse<StagingGroup[]>>(
    '/warehouse/staging'
  );
  return data.data ?? [];
}


// =================================================================
// MOVEMENTS
// =================================================================

/** Paginated movement history with filters */
export async function getMovements(params: {
  movement_type?: string;
  from_location_type?: string;
  to_location_type?: string;
  performed_by?: number;
  part_id?: number;
  date_from?: string;
  date_to?: string;
  page?: number;
  page_size?: number;
} = {}): Promise<PaginatedData<MovementLogEntry>> {
  const { data } = await apiClient.get<
    ApiResponse<PaginatedData<MovementLogEntry>>
  >('/warehouse/movements', { params });
  return (
    data.data ?? {
      items: [],
      total: 0,
      page: 1,
      page_size: 50,
      total_pages: 0,
    }
  );
}

/** Get a single movement with full details */
export async function getMovement(
  movementId: number
): Promise<MovementLogEntry> {
  const { data } = await apiClient.get<ApiResponse<MovementLogEntry>>(
    `/warehouse/movements/${movementId}`
  );
  return data.data!;
}

/** Pre-flight validation for a movement */
export async function validateMovement(
  req: MovementRequest
): Promise<ValidationResult> {
  const { data } = await apiClient.post<ApiResponse<ValidationResult>>(
    '/warehouse/movements/validate',
    req
  );
  return data.data!;
}

/** Preview before/after state of a movement batch */
export async function previewMovement(
  req: MovementRequest
): Promise<MovementPreview> {
  const { data } = await apiClient.post<ApiResponse<MovementPreview>>(
    '/warehouse/movements/preview',
    req
  );
  return data.data!;
}

/** Execute a stock movement — atomic all-or-nothing */
export async function executeMovement(
  req: MovementRequest
): Promise<MovementExecuteResponse> {
  const { data } = await apiClient.post<ApiResponse<MovementExecuteResponse>>(
    '/warehouse/movements/execute',
    req
  );
  return data.data!;
}


// =================================================================
// AUDIT
// =================================================================

/** List audits with optional status/type filters */
export async function listAudits(params: {
  status?: string;
  type?: string;
  limit?: number;
  offset?: number;
} = {}): Promise<AuditResponse[]> {
  const { data } = await apiClient.get<ApiResponse<AuditResponse[]>>(
    '/warehouse/audit',
    { params }
  );
  return data.data ?? [];
}

/** Start a new audit session */
export async function startAudit(
  req: AuditStartRequest
): Promise<AuditResponse> {
  const { data } = await apiClient.post<ApiResponse<AuditResponse>>(
    '/warehouse/audit',
    req
  );
  return data.data!;
}

/** Get parts suggested for the next rolling audit batch */
export async function getSuggestedRollingParts(
  limit: number = 20
): Promise<SuggestedRollingPart[]> {
  const { data } = await apiClient.get<ApiResponse<SuggestedRollingPart[]>>(
    '/warehouse/audit/suggested-rolling',
    { params: { limit } }
  );
  return data.data ?? [];
}

/** Get audit detail with progress stats */
export async function getAudit(auditId: number): Promise<AuditResponse> {
  const { data } = await apiClient.get<ApiResponse<AuditResponse>>(
    `/warehouse/audit/${auditId}`
  );
  return data.data!;
}

/** Get the next un-counted item for the card-swipe UI */
export async function getNextAuditItem(
  auditId: number
): Promise<AuditItemResponse | null> {
  const { data } = await apiClient.get<ApiResponse<AuditItemResponse | null>>(
    `/warehouse/audit/${auditId}/next`
  );
  return data.data ?? null;
}

/** Record a count for an audit item */
export async function recordAuditCount(
  auditId: number,
  itemId: number,
  req: AuditCountRequest
): Promise<void> {
  await apiClient.put(
    `/warehouse/audit/${auditId}/items/${itemId}`,
    req
  );
}

/** Finalize an audit */
export async function completeAudit(
  auditId: number
): Promise<AuditSummary> {
  const { data } = await apiClient.post<ApiResponse<AuditSummary>>(
    `/warehouse/audit/${auditId}/complete`
  );
  return data.data!;
}

/** Create stock adjustments for all discrepancies in an audit */
export async function applyAuditAdjustments(
  auditId: number
): Promise<{ adjustments_applied: number }> {
  const { data } = await apiClient.post<
    ApiResponse<{ adjustments_applied: number }>
  >(`/warehouse/audit/${auditId}/apply-adjustments`);
  return data.data!;
}


// =================================================================
// HELPERS
// =================================================================

/** Get all valid from/to locations for the wizard dropdowns */
export async function getLocations(): Promise<LocationOption[]> {
  const { data } = await apiClient.get<ApiResponse<LocationOption[]>>(
    '/warehouse/locations'
  );
  return data.data ?? [];
}

/** Part search scoped to a source location (for wizard Step 2) */
export async function searchPartsForWizard(params: {
  q?: string;
  location_type?: string;
  location_id?: number;
  limit?: number;
}): Promise<WizardPartSearchResult[]> {
  const { data } = await apiClient.get<ApiResponse<WizardPartSearchResult[]>>(
    '/warehouse/parts-search',
    { params }
  );
  return data.data ?? [];
}

/** Upload a verification photo — returns file path */
export async function uploadPhoto(
  file: File
): Promise<{ path: string; filename: string }> {
  const formData = new FormData();
  formData.append('file', file);
  const { data } = await apiClient.post<
    ApiResponse<{ path: string; filename: string }>
  >('/warehouse/upload-photo', formData, {
    headers: { 'Content-Type': 'multipart/form-data' },
  });
  return data.data!;
}

/** Resolve the preferred supplier for a part (cascade lookup) */
export async function getSupplierPreference(
  partId: number
): Promise<SupplierPreferenceResponse> {
  const { data } = await apiClient.get<
    ApiResponse<SupplierPreferenceResponse>
  >('/warehouse/supplier-preference', { params: { part_id: partId } });
  return data.data!;
}

/** Set or update the preferred supplier for a scope level */
export async function setSupplierPreference(
  req: SupplierPreferenceSet
): Promise<{ id: number }> {
  const { data } = await apiClient.post<ApiResponse<{ id: number }>>(
    '/warehouse/supplier-preference',
    req
  );
  return data.data!;
}

/** Remove a preferred supplier for a scope level */
export async function removeSupplierPreference(
  scopeType: string,
  scopeId: number
): Promise<void> {
  await apiClient.delete('/warehouse/supplier-preference', {
    params: { scope_type: scopeType, scope_id: scopeId },
  });
}

/** Get the categorized reason options for the movement wizard */
export async function getMovementReasons(): Promise<ReasonCategories> {
  const { data } = await apiClient.get<ApiResponse<ReasonCategories>>(
    '/warehouse/movement-reasons'
  );
  return data.data ?? {};
}

/** Get the valid movement paths and their rules */
export async function getMovementRules(): Promise<
  Record<string, MovementRule>
> {
  const { data } = await apiClient.get<
    ApiResponse<Record<string, MovementRule>>
  >('/warehouse/movement-rules');
  return data.data ?? {};
}
