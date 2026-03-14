/**
 * Warehouse API functions — dashboard, inventory, staging, movements,
 * audit, and helper endpoints.
 *
 * All functions follow the pattern: call apiClient → unwrap ApiResponse → return typed data.
 * In Tauri/native mode, read-only functions are routed to local TypeScript services.
 * Shop-only operations (audit, staging, receive-stock) remain HTTP-only.
 */

import apiClient from './client';
import { adaptedRequest } from './adapter';
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
  PendingPullGroup,
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
  return adaptedRequest(
    async () => {
      const { data } = await apiClient.get<ApiResponse<DashboardData>>(
        '/warehouse/dashboard'
      );
      return data.data!;
    },
    async () => {
      // Compose dashboard from individual local service functions
      const { getDashboardKPIs: localKPIs, getRecentActivity } = await import(
        '../local/services/warehouse-service'
      );
      const [kpis, recentActivity] = await Promise.all([
        localKPIs(),
        getRecentActivity(10),
      ]);
      return {
        kpis: kpis as unknown as DashboardKPIs,
        recent_activity: recentActivity as unknown as ActivitySummary[],
        pending_tasks: [], // No pending tasks in field-worker mode
      };
    },
  );
}

/** Dashboard KPI cards */
export async function getDashboardKPIs(): Promise<DashboardKPIs> {
  return adaptedRequest(
    async () => {
      const { data } = await apiClient.get<ApiResponse<DashboardKPIs>>(
        '/warehouse/dashboard/kpis'
      );
      return data.data!;
    },
    async () => {
      const { getDashboardKPIs: local } = await import('../local/services/warehouse-service');
      return await local() as unknown as DashboardKPIs;
    },
  );
}

/** Recent movement activity feed */
export async function getDashboardActivity(
  limit: number = 10
): Promise<ActivitySummary[]> {
  return adaptedRequest(
    async () => {
      const { data } = await apiClient.get<ApiResponse<ActivitySummary[]>>(
        '/warehouse/dashboard/activity',
        { params: { limit } }
      );
      return data.data ?? [];
    },
    async () => {
      const { getRecentActivity } = await import('../local/services/warehouse-service');
      return await getRecentActivity(limit) as unknown as ActivitySummary[];
    },
  );
}

/** Pending tasks: staged items, audits, spot-checks */
export async function getDashboardPendingTasks(): Promise<PendingTask[]> {
  return adaptedRequest(
    async () => {
      const { data } = await apiClient.get<ApiResponse<PendingTask[]>>(
        '/warehouse/dashboard/pending-tasks'
      );
      return data.data ?? [];
    },
    async () => {
      // Field workers don't manage pending tasks — return empty
      return [];
    },
  );
}


// =================================================================
// INVENTORY GRID
// =================================================================

/** Paginated warehouse inventory with filters and health bars */
export async function getWarehouseInventory(
  params: WarehouseInventoryParams = {}
): Promise<PaginatedData<WarehouseInventoryItem>> {
  return adaptedRequest(
    async () => {
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
    },
    async () => {
      const { getInventoryGrid } = await import('../local/services/warehouse-service');
      const result = await getInventoryGrid({
        search: params.search,
        category_id: params.category_id,
        status: params.stock_status,
        sort: params.sort_by,
        limit: params.page_size ?? 50,
        offset: ((params.page ?? 1) - 1) * (params.page_size ?? 50),
      });
      const pageSize = params.page_size ?? 50;
      return {
        items: result.items as unknown as WarehouseInventoryItem[],
        total: result.total,
        page: params.page ?? 1,
        page_size: pageSize,
        total_pages: Math.ceil(result.total / pageSize),
      };
    },
  );
}


// =================================================================
// RECEIVE STOCK (shop-only)
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
// STAGING (shop-only)
// =================================================================

/** Pulled items grouped by destination with aging info */
export async function getStagingGroups(): Promise<StagingGroup[]> {
  const { data } = await apiClient.get<ApiResponse<StagingGroup[]>>(
    '/warehouse/staging'
  );
  return data.data ?? [];
}

/** JPO line items received but not yet pulled from warehouse — grouped by job */
export async function getPendingPulls(): Promise<PendingPullGroup[]> {
  const { data } = await apiClient.get<ApiResponse<PendingPullGroup[]>>(
    '/warehouse/staging/pending-pulls'
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
  return adaptedRequest(
    async () => {
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
    },
    async () => {
      const { getRecentMovements } = await import('../local/services/movement-service');
      const items = await getRecentMovements(params.page_size ?? 50);
      return {
        items: items as unknown as MovementLogEntry[],
        total: items.length,
        page: params.page ?? 1,
        page_size: params.page_size ?? 50,
        total_pages: 1,
      };
    },
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
  return adaptedRequest(
    async () => {
      const { data } = await apiClient.post<ApiResponse<ValidationResult>>(
        '/warehouse/movements/validate',
        req
      );
      return data.data!;
    },
    async () => {
      const { validateMovement: local } = await import('../local/services/movement-service');
      return await local(req as any) as unknown as ValidationResult;
    },
  );
}

/** Preview before/after state of a movement batch */
export async function previewMovement(
  req: MovementRequest
): Promise<MovementPreview> {
  return adaptedRequest(
    async () => {
      const { data } = await apiClient.post<ApiResponse<MovementPreview>>(
        '/warehouse/movements/preview',
        req
      );
      return data.data!;
    },
    async () => {
      const { calculatePreview } = await import('../local/services/movement-service');
      return await calculatePreview(req as any) as unknown as MovementPreview;
    },
  );
}

/** Execute a stock movement — atomic all-or-nothing */
export async function executeMovement(
  req: MovementRequest
): Promise<MovementExecuteResponse> {
  return adaptedRequest(
    async () => {
      const { data } = await apiClient.post<ApiResponse<MovementExecuteResponse>>(
        '/warehouse/movements/execute',
        req
      );
      return data.data!;
    },
    async () => {
      const { executeMovement: local } = await import('../local/services/movement-service');
      return await local(req as any, 0) as unknown as MovementExecuteResponse;
    },
  );
}


// =================================================================
// AUDIT (shop-only)
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

/** Get the top N parts most urgently needing a spot check */
export async function getSuggestedSpotCheckParts(
  limit: number = 3
): Promise<SuggestedRollingPart[]> {
  const { data } = await apiClient.get<ApiResponse<SuggestedRollingPart[]>>(
    '/warehouse/audit/suggested-spot-check',
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
  return adaptedRequest(
    async () => {
      const { data } = await apiClient.get<ApiResponse<WizardPartSearchResult[]>>(
        '/warehouse/parts-search',
        { params }
      );
      return data.data ?? [];
    },
    async () => {
      const { searchWarehouseParts } = await import('../local/local-client');
      const results = await searchWarehouseParts(params.q ?? '', params.limit ?? 20);
      return results as unknown as WizardPartSearchResult[];
    },
  );
}

/** Upload a verification photo — returns file path (shop-only) */
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
