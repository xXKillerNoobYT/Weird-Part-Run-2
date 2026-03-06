/**
 * Tools & Kits API functions — tool registry, kit templates, checkout/return,
 * kit verification, maintenance tracking, dashboard stats.
 *
 * All functions follow: call apiClient → unwrap ApiResponse → return typed data.
 */

import apiClient from './client';
import type {
  ApiResponse,
  // Tools
  Tool,
  ToolListItem,
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
  const { data } = await apiClient.get<ApiResponse<{ items: Tool[]; total: number }>>(
    '/tools/',
    { params },
  );
  return data.data;
}

/** Get a single tool with full details */
export async function getTool(toolId: number): Promise<Tool> {
  const { data } = await apiClient.get<ApiResponse<Tool>>(`/tools/${toolId}`);
  return data.data;
}

/** Register a new tool */
export async function createTool(body: ToolCreate): Promise<Tool> {
  const { data } = await apiClient.post<ApiResponse<Tool>>('/tools/', body);
  return data.data;
}

/** Update tool fields */
export async function updateTool(toolId: number, body: ToolUpdate): Promise<Tool> {
  const { data } = await apiClient.put<ApiResponse<Tool>>(`/tools/${toolId}`, body);
  return data.data;
}

/** Retire (soft-delete) a tool */
export async function retireTool(toolId: number): Promise<Tool> {
  const { data } = await apiClient.delete<ApiResponse<Tool>>(`/tools/${toolId}`);
  return data.data;
}

/** Look up a tool by tool_number (QR scan) */
export async function scanTool(toolNumber: string): Promise<Tool> {
  const { data } = await apiClient.get<ApiResponse<Tool>>(`/tools/scan/${toolNumber}`);
  return data.data;
}


// =================================================================
// DASHBOARD
// =================================================================

/** Aggregate dashboard stats for all active tools */
export async function getToolsDashboard(): Promise<ToolsDashboardStats> {
  const { data } = await apiClient.get<ApiResponse<ToolsDashboardStats>>('/tools/dashboard');
  return data.data;
}

/** Get tools at a specific location */
export async function getToolsAtLocation(
  locationType: string,
  locationId: number
): Promise<Tool[]> {
  const { data } = await apiClient.get<ApiResponse<Tool[]>>('/tools/by-location', {
    params: { location_type: locationType, location_id: locationId },
  });
  return data.data;
}

/** Get most recent tool movements */
export async function getRecentMovements(limit = 20): Promise<ToolMovement[]> {
  const { data } = await apiClient.get<ApiResponse<ToolMovement[]>>(
    '/tools/recent-movements',
    { params: { limit } },
  );
  return data.data;
}


// =================================================================
// CHECKOUT / RETURN
// =================================================================

/** Check out a tool to a truck or job */
export async function checkoutTool(
  toolId: number,
  body: ToolCheckoutRequest
): Promise<Tool> {
  const { data } = await apiClient.post<ApiResponse<Tool>>(
    `/tools/${toolId}/checkout`,
    body,
  );
  return data.data;
}

/** Return a tool (typically to warehouse) */
export async function returnTool(
  toolId: number,
  body: ToolReturnRequest = {}
): Promise<Tool> {
  const { data } = await apiClient.post<ApiResponse<Tool>>(
    `/tools/${toolId}/return`,
    body,
  );
  return data.data;
}


// =================================================================
// MOVEMENTS
// =================================================================

/** Get movement history for a tool */
export async function getToolMovements(
  toolId: number,
  params: { limit?: number; offset?: number } = {}
): Promise<ToolMovement[]> {
  const { data } = await apiClient.get<ApiResponse<ToolMovement[]>>(
    `/tools/${toolId}/movements`,
    { params },
  );
  return data.data;
}


// =================================================================
// KIT TEMPLATES
// =================================================================

/** Get kit template (required components) for a tool */
export async function getKitTemplate(toolId: number): Promise<KitTemplateItem[]> {
  const { data } = await apiClient.get<ApiResponse<KitTemplateItem[]>>(
    `/tools/${toolId}/kit`,
  );
  return data.data;
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
  return data.data;
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
  return data.data;
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
  const { data } = await apiClient.post<ApiResponse<KitVerificationSession>>(
    `/tools/${toolId}/verify`,
    body,
  );
  return data.data;
}

/** Complete a verification session with all item updates */
export async function completeVerification(
  toolId: number,
  sessionId: number,
  body: KitVerificationCompleteRequest
): Promise<KitVerificationSession> {
  const { data } = await apiClient.put<ApiResponse<KitVerificationSession>>(
    `/tools/${toolId}/verify/${sessionId}`,
    body,
  );
  return data.data;
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
  return data.data;
}


// =================================================================
// MAINTENANCE TYPES
// =================================================================

/** Get all active tool maintenance types */
export async function getMaintenanceTypes(): Promise<ToolMaintenanceType[]> {
  const { data } = await apiClient.get<ApiResponse<ToolMaintenanceType[]>>(
    '/tools/maintenance-types',
  );
  return data.data;
}

/** Create a new maintenance type */
export async function createMaintenanceType(
  body: ToolMaintenanceTypeCreate
): Promise<ToolMaintenanceType> {
  const { data } = await apiClient.post<ApiResponse<ToolMaintenanceType>>(
    '/tools/maintenance-types',
    body,
  );
  return data.data;
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
  return data.data;
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
  return data.data;
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
  return data.data;
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
  return data.data;
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
  return data.data;
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
  return data.data;
}
