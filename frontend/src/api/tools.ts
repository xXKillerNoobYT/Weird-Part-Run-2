/**
 * Tools & Kits API functions — tool registry, kit templates, checkout/return,
 * kit verification, maintenance tracking, dashboard stats.
 *
 * All functions follow: call apiClient → unwrap ApiResponse → return typed data.
 */

import apiClient from './client';
import { adaptedRequest } from './adapter';
import type {
  ApiResponse,
  // Tools
  Tool,
  ToolCreate,
  ToolUpdate,
  // Kit Templates
  KitTemplateItem,
  KitTemplateItemCreate,
  KitTemplateItemUpdate,
  // Movements
  ToolMovement,
  ToolCheckoutRequest,
  ToolReturnRequest,
  ToolTransferRequest,
  // Kit Verification
  KitVerificationSession,
  KitVerificationStartRequest,
  KitVerificationCompleteRequest,
  // Maintenance
  ToolMaintenanceType,
  ToolMaintenanceTypeCreate,
  ToolMaintenanceTypeUpdate,
  ToolMaintenanceSchedule,
  ToolMaintenanceScheduleCreate,
  ToolMaintenanceRecord,
  ToolMaintenanceRecordCreate,
  ToolMaintenanceAlert,
  // Dashboard
  ToolsDashboardStats,
  // Depreciation
  DepreciationConfig,
  DepreciationSummary,
  DepreciationReportItem,
  // Todo-Tool linking
  EntryToolLink,
  EntryToolLinkCreate,
} from '../lib/types';


// =================================================================
// TOOL CRUD
// =================================================================

export interface ToolListParams {
  category?: string;
  status?: string;
  location_type?: string;
  search?: string;
  is_active?: boolean;
  page?: number;
  page_size?: number;
}

/** Paginated tool list with filters and joined details */
export async function getTools(
  params: ToolListParams = {}
): Promise<{ items: Tool[]; total: number }> {
  return adaptedRequest(
    async () => {
      const { data } = await apiClient.get<ApiResponse<{ items: Tool[]; total: number }>>(
        '/tools/',
        { params },
      );
      return data.data!;
    },
    async () => {
      const { listTools } = await import('../local/services/tool-service');
      return await listTools(params) as unknown as { items: Tool[]; total: number };
    },
  );
}

/** Get a single tool with full details */
export async function getTool(toolId: number): Promise<Tool> {
  return adaptedRequest(
    async () => {
      const { data } = await apiClient.get<ApiResponse<Tool>>(`/tools/${toolId}`);
      return data.data!;
    },
    async () => {
      const { getTool: local } = await import('../local/services/tool-service');
      const tool = await local(toolId);
      if (!tool) throw new Error('Tool not found');
      return tool as unknown as Tool;
    },
  );
}

/** Register a new tool */
export async function createTool(body: ToolCreate): Promise<Tool> {
  const { data } = await apiClient.post<ApiResponse<Tool>>('/tools/', body);
  return data.data!;
}

/** Update tool fields */
export async function updateTool(toolId: number, body: ToolUpdate): Promise<Tool> {
  const { data } = await apiClient.put<ApiResponse<Tool>>(`/tools/${toolId}`, body);
  return data.data!;
}

/** Retire (soft-delete) a tool */
export async function retireTool(toolId: number): Promise<Tool> {
  const { data } = await apiClient.delete<ApiResponse<Tool>>(`/tools/${toolId}`);
  return data.data!;
}

/** Look up a tool by tool_number (QR scan) */
export async function scanTool(toolNumber: string): Promise<Tool> {
  return adaptedRequest(
    async () => {
      const { data } = await apiClient.get<ApiResponse<Tool>>(`/tools/scan/${toolNumber}`);
      return data.data!;
    },
    async () => {
      const { getToolByBarcode } = await import('../local/services/tool-service');
      const tool = await getToolByBarcode(toolNumber);
      if (!tool) throw new Error('Tool not found');
      return tool as unknown as Tool;
    },
  );
}


// =================================================================
// DASHBOARD
// =================================================================

/** Aggregate dashboard stats for all active tools */
export async function getToolsDashboard(): Promise<ToolsDashboardStats> {
  const { data } = await apiClient.get<ApiResponse<ToolsDashboardStats>>('/tools/dashboard');
  return data.data!;
}

/** Get tools at a specific location */
export async function getToolsAtLocation(
  locationType: string,
  locationId: number
): Promise<Tool[]> {
  return adaptedRequest(
    async () => {
      const { data } = await apiClient.get<ApiResponse<Tool[]>>('/tools/by-location', {
        params: { location_type: locationType, location_id: locationId },
      });
      return data.data!;
    },
    async () => {
      const { getToolsAtLocation: local } = await import('../local/services/tool-service');
      return await local(locationType, locationId) as unknown as Tool[];
    },
  );
}

/** Get most recent tool movements */
export async function getRecentMovements(limit = 20): Promise<ToolMovement[]> {
  const { data } = await apiClient.get<ApiResponse<ToolMovement[]>>(
    '/tools/recent-movements',
    { params: { limit } },
  );
  return data.data!;
}


// =================================================================
// CHECKOUT / RETURN
// =================================================================

/** Check out a tool to a truck or job */
export async function checkoutTool(
  toolId: number,
  body: ToolCheckoutRequest
): Promise<Tool> {
  return adaptedRequest(
    async () => {
      const { data } = await apiClient.post<ApiResponse<Tool>>(
        `/tools/${toolId}/checkout`,
        body,
      );
      return data.data!;
    },
    async () => {
      const { checkoutTool: local } = await import('../local/services/tool-service');
      return await local(toolId, body as any, 0) as unknown as Tool;
    },
  );
}

/** Return a tool (typically to warehouse) */
export async function returnTool(
  toolId: number,
  body: ToolReturnRequest = {}
): Promise<Tool> {
  return adaptedRequest(
    async () => {
      const { data } = await apiClient.post<ApiResponse<Tool>>(
        `/tools/${toolId}/return`,
        body,
      );
      return data.data!;
    },
    async () => {
      const { returnTool: local } = await import('../local/services/tool-service');
      return await local(toolId, body as any, 0) as unknown as Tool;
    },
  );
}


// =================================================================
// MOVEMENTS
// =================================================================

/** Get movement history for a tool */
export async function getToolMovements(
  toolId: number,
  params: { limit?: number; offset?: number } = {}
): Promise<ToolMovement[]> {
  return adaptedRequest(
    async () => {
      const { data } = await apiClient.get<ApiResponse<ToolMovement[]>>(
        `/tools/${toolId}/movements`,
        { params },
      );
      return data.data!;
    },
    async () => {
      const { getToolHistory } = await import('../local/services/tool-service');
      return await getToolHistory(toolId, params.limit) as unknown as ToolMovement[];
    },
  );
}


// =================================================================
// KIT TEMPLATES
// =================================================================

/** Get kit template (required components) for a tool */
export async function getKitTemplate(toolId: number): Promise<KitTemplateItem[]> {
  return adaptedRequest(
    async () => {
      const { data } = await apiClient.get<ApiResponse<KitTemplateItem[]>>(
        `/tools/${toolId}/kit`,
      );
      return data.data!;
    },
    async () => {
      const { getKitTemplate: local } = await import('../local/services/tool-service');
      return await local(toolId) as unknown as KitTemplateItem[];
    },
  );
}

/** Add a required component to a tool's kit */
export async function addKitComponent(
  toolId: number,
  body: KitTemplateItemCreate
): Promise<KitTemplateItem> {
  const { data } = await apiClient.post<ApiResponse<KitTemplateItem>>(
    `/tools/${toolId}/kit`,
    body,
  );
  return data.data!;
}

/** Update a kit template component */
export async function updateKitComponent(
  toolId: number,
  itemId: number,
  body: KitTemplateItemUpdate
): Promise<KitTemplateItem> {
  const { data } = await apiClient.put<ApiResponse<KitTemplateItem>>(
    `/tools/${toolId}/kit/${itemId}`,
    body,
  );
  return data.data!;
}

/** Remove a component from a tool's kit */
export async function removeKitComponent(
  toolId: number,
  itemId: number
): Promise<void> {
  await apiClient.delete(`/tools/${toolId}/kit/${itemId}`);
}


// =================================================================
// KIT VERIFICATION
// =================================================================

/** Start a kit verification session */
export async function startVerification(
  toolId: number,
  body: KitVerificationStartRequest
): Promise<KitVerificationSession> {
  return adaptedRequest(
    async () => {
      const { data } = await apiClient.post<ApiResponse<KitVerificationSession>>(
        `/tools/${toolId}/verify`,
        body,
      );
      return data.data!;
    },
    async () => {
      const { startVerification: local } = await import('../local/services/tool-service');
      return await local(toolId, (body as any).trigger_type ?? 'manual', 0) as unknown as KitVerificationSession;
    },
  );
}

/** Complete a verification session with all item updates */
export async function completeVerification(
  toolId: number,
  sessionId: number,
  body: KitVerificationCompleteRequest
): Promise<KitVerificationSession> {
  return adaptedRequest(
    async () => {
      const { data } = await apiClient.put<ApiResponse<KitVerificationSession>>(
        `/tools/${toolId}/verify/${sessionId}`,
        body,
      );
      return data.data!;
    },
    async () => {
      const { completeVerification: local } = await import('../local/services/tool-service');
      return await local(toolId, sessionId, (body as any).items ?? [], (body as any).notes) as unknown as KitVerificationSession;
    },
  );
}

/** Get kit verification history for a tool */
export async function getVerificationHistory(
  toolId: number,
  limit = 20
): Promise<KitVerificationSession[]> {
  const { data } = await apiClient.get<ApiResponse<KitVerificationSession[]>>(
    `/tools/${toolId}/verify/history`,
    { params: { limit } },
  );
  return data.data!;
}


// =================================================================
// MAINTENANCE TYPES
// =================================================================

/** Get all active tool maintenance types */
export async function getMaintenanceTypes(): Promise<ToolMaintenanceType[]> {
  const { data } = await apiClient.get<ApiResponse<ToolMaintenanceType[]>>(
    '/tools/maintenance-types',
  );
  return data.data!;
}

/** Create a new maintenance type */
export async function createMaintenanceType(
  body: ToolMaintenanceTypeCreate
): Promise<ToolMaintenanceType> {
  const { data } = await apiClient.post<ApiResponse<ToolMaintenanceType>>(
    '/tools/maintenance-types',
    body,
  );
  return data.data!;
}

/** Update a maintenance type */
export async function updateMaintenanceType(
  typeId: number,
  body: ToolMaintenanceTypeUpdate
): Promise<ToolMaintenanceType> {
  const { data } = await apiClient.put<ApiResponse<ToolMaintenanceType>>(
    `/tools/maintenance-types/${typeId}`,
    body,
  );
  return data.data!;
}

/** Delete (deactivate) a maintenance type */
export async function deleteMaintenanceType(typeId: number): Promise<void> {
  await apiClient.delete(`/tools/maintenance-types/${typeId}`);
}


// =================================================================
// PER-TOOL MAINTENANCE
// =================================================================

/** Get maintenance schedules for a tool */
export async function getToolSchedule(
  toolId: number
): Promise<ToolMaintenanceSchedule[]> {
  const { data } = await apiClient.get<ApiResponse<ToolMaintenanceSchedule[]>>(
    `/tools/${toolId}/maintenance/schedule`,
  );
  return data.data!;
}

/** Create or update a maintenance schedule for a tool */
export async function setToolSchedule(
  toolId: number,
  body: ToolMaintenanceScheduleCreate
): Promise<ToolMaintenanceSchedule> {
  const { data } = await apiClient.post<ApiResponse<ToolMaintenanceSchedule>>(
    `/tools/${toolId}/maintenance/schedule`,
    body,
  );
  return data.data!;
}

/** Log a maintenance service */
export async function logService(
  toolId: number,
  body: ToolMaintenanceRecordCreate
): Promise<ToolMaintenanceRecord> {
  const { data } = await apiClient.post<ApiResponse<ToolMaintenanceRecord>>(
    `/tools/${toolId}/maintenance/log`,
    body,
  );
  return data.data!;
}

/** Get maintenance service history for a tool */
export async function getServiceHistory(
  toolId: number,
  params: { limit?: number; offset?: number } = {}
): Promise<ToolMaintenanceRecord[]> {
  const { data } = await apiClient.get<ApiResponse<ToolMaintenanceRecord[]>>(
    `/tools/${toolId}/maintenance/history`,
    { params },
  );
  return data.data!;
}


// =================================================================
// MAINTENANCE ALERTS
// =================================================================

/** Get overdue and upcoming maintenance alerts */
export async function getMaintenanceAlerts(
  daysAhead = 14
): Promise<{ overdue: ToolMaintenanceAlert[]; upcoming: ToolMaintenanceAlert[] }> {
  const { data } = await apiClient.get<
    ApiResponse<{ overdue: ToolMaintenanceAlert[]; upcoming: ToolMaintenanceAlert[] }>
  >('/tools/maintenance-alerts', { params: { days_ahead: daysAhead } });
  return data.data!;
}


// =================================================================
// PENDING KIT VERIFICATIONS
// =================================================================

export interface PendingVerification {
  session_id: number;
  tool_id: number;
  trigger_type: string;
  created_at: string;
  tool_number: string;
  description: string;
}

/** Get all incomplete kit verification sessions (auto-triggered but not completed) */
export async function getPendingVerifications(): Promise<PendingVerification[]> {
  const { data } = await apiClient.get<ApiResponse<PendingVerification[]>>(
    '/tools/pending-verifications',
  );
  return data.data ?? [];
}


// =================================================================
// TOOL PHOTOS
// =================================================================

/** Upload or replace a tool's photo */
export async function uploadToolPhoto(
  toolId: number,
  file: File,
): Promise<{ photo_path: string }> {
  const formData = new FormData();
  formData.append('file', file);
  const { data } = await apiClient.post<ApiResponse<{ photo_path: string }>>(
    `/tools/${toolId}/photo`,
    formData,
    { headers: { 'Content-Type': 'multipart/form-data' } },
  );
  return data.data!;
}


// =================================================================
// BULK TOOL OPERATIONS
// =================================================================

interface BulkToolResult {
  tool_id: number;
  movement_id?: number;
  record_id?: number;
  error?: string;
}

/** Check out multiple tools at once */
export async function bulkCheckoutTools(
  toolIds: number[],
  locationType: string,
  locationId: number,
  notes?: string,
): Promise<{ checked_out: BulkToolResult[]; errors: BulkToolResult[] }> {
  const { data } = await apiClient.post<
    ApiResponse<{ checked_out: BulkToolResult[]; errors: BulkToolResult[] }>
  >('/tools/bulk/checkout', {
    tool_ids: toolIds,
    location_type: locationType,
    location_id: locationId,
    notes,
  });
  return data.data!;
}

/** Return multiple tools at once */
export async function bulkReturnTools(
  toolIds: number[],
  notes?: string,
): Promise<{ returned: BulkToolResult[]; errors: BulkToolResult[] }> {
  const { data } = await apiClient.post<
    ApiResponse<{ returned: BulkToolResult[]; errors: BulkToolResult[] }>
  >('/tools/bulk/return', {
    tool_ids: toolIds,
    notes,
  });
  return data.data!;
}

/** Log maintenance for multiple tools at once */
export async function bulkLogMaintenance(
  toolIds: number[],
  maintenanceTypeId: number,
  notes?: string,
): Promise<{ serviced: BulkToolResult[]; errors: BulkToolResult[] }> {
  const { data } = await apiClient.post<
    ApiResponse<{ serviced: BulkToolResult[]; errors: BulkToolResult[] }>
  >('/tools/bulk/maintenance', {
    tool_ids: toolIds,
    maintenance_type_id: maintenanceTypeId,
    notes,
  });
  return data.data!;
}


// =================================================================
// TOOL TRANSFER
// =================================================================

/** Transfer a tool directly between locations (atomic) */
export async function transferTool(
  toolId: number,
  body: ToolTransferRequest,
): Promise<Tool> {
  const { data } = await apiClient.post<ApiResponse<Tool>>(
    `/tools/${toolId}/transfer`,
    body,
  );
  return data.data!;
}


// =================================================================
// DEPRECIATION
// =================================================================

/** Get depreciation summary for a single tool */
export async function getToolDepreciation(
  toolId: number,
): Promise<DepreciationSummary> {
  const { data } = await apiClient.get<ApiResponse<DepreciationSummary>>(
    `/tools/${toolId}/depreciation`,
  );
  return data.data!;
}

/** Configure depreciation and generate schedule */
export async function configureDepreciation(
  toolId: number,
  body: DepreciationConfig,
): Promise<{ schedule: unknown[]; message: string }> {
  const { data } = await apiClient.post<
    ApiResponse<{ schedule: unknown[]; message: string }>
  >(`/tools/${toolId}/depreciation`, body);
  return data.data!;
}

/** Get depreciation report across all configured tools */
export async function getDepreciationReport(): Promise<DepreciationReportItem[]> {
  const { data } = await apiClient.get<ApiResponse<DepreciationReportItem[]>>(
    '/tools/depreciation/report',
  );
  return data.data!;
}


// =================================================================
// CALIBRATION
// =================================================================

/** Log a calibration service with certificate details */
export async function logCalibration(
  toolId: number,
  body: {
    service_date?: string | null;
    cost?: number;
    vendor?: string | null;
    description?: string | null;
    notes?: string | null;
    calibration_certificate?: string | null;
    calibration_provider?: string | null;
    calibration_standard?: string | null;
    calibration_result?: string | null;
  },
): Promise<{ record_id: number }> {
  const { data } = await apiClient.post<ApiResponse<{ record_id: number }>>(
    `/tools/${toolId}/calibration`,
    body,
  );
  return data.data!;
}


// =================================================================
// TODO-TOOL LINKING
// =================================================================

/** Get all tools linked to a notebook entry */
export async function getEntryTools(
  entryId: number,
): Promise<EntryToolLink[]> {
  const { data } = await apiClient.get<ApiResponse<EntryToolLink[]>>(
    `/tools/entry-tools/${entryId}`,
  );
  return data.data!;
}

/** Link a tool to a notebook task entry */
export async function linkToolToEntry(
  entryId: number,
  body: EntryToolLinkCreate,
): Promise<EntryToolLink> {
  const { data } = await apiClient.post<ApiResponse<EntryToolLink>>(
    `/tools/entry-tools/${entryId}`,
    body,
  );
  return data.data!;
}

/** Remove a tool link from a notebook entry */
export async function unlinkToolFromEntry(
  entryId: number,
  toolId: number,
): Promise<void> {
  await apiClient.delete(`/tools/entry-tools/${entryId}/${toolId}`);
}

/** Get all notebook entries that reference a specific tool */
export async function getToolReferences(
  toolId: number,
): Promise<unknown[]> {
  const { data } = await apiClient.get<ApiResponse<unknown[]>>(
    `/tools/${toolId}/references`,
  );
  return data.data!;
}


// =================================================================
// EXPORT
// =================================================================

/** Download tools as CSV file */
export async function exportToolsCsv(params?: {
  category?: string;
  status?: string;
  location_type?: string;
  include_retired?: boolean;
}): Promise<Blob> {
  const { data } = await apiClient.get('/tools/export/csv', {
    params,
    responseType: 'blob',
  });
  return data;
}
