/**
 * Vehicle maintenance types, schedules, records, and costs.
 */

import apiClient from '../client';
import type {
  ApiResponse,
  MaintenanceTypeCreate,
  MaintenanceTypeUpdate,
  MaintenanceType,
  MaintenanceScheduleCreate,
  MaintenanceSchedule,
  MaintenanceRecordCreate,
  MaintenanceRecord,
  MaintenanceAlert,
  MaintenanceCostSummary,
} from '../../lib/types';
import { adaptedRequest } from '../adapter';


// =================================================================
// MAINTENANCE TYPES (Admin)
// =================================================================

/** List all maintenance types. */
export async function listMaintenanceTypes(params?: {
  active_only?: boolean;
}): Promise<MaintenanceType[]> {
  return adaptedRequest(
    async () => {
      const { data } = await apiClient.get<ApiResponse<MaintenanceType[]>>(
    '/trucks/maintenance-types',
    { params },
  );
  return data.data ?? [];
    },
    async () => [] as unknown as MaintenanceType[],
  );
}

/** Create a new maintenance type. */
export async function createMaintenanceType(
  mtype: MaintenanceTypeCreate,
): Promise<MaintenanceType> {
  return adaptedRequest(
    async () => {
      const { data } = await apiClient.post<ApiResponse<MaintenanceType>>(
    '/trucks/maintenance-types',
    mtype,
  );
  return data.data!;
    },
    async () => { throw new Error('Fleet Management requires the shop server.'); },
  );
}

/** Update a maintenance type. */
export async function updateMaintenanceType(
  typeId: number,
  update: MaintenanceTypeUpdate,
): Promise<MaintenanceType> {
  return adaptedRequest(
    async () => {
      const { data } = await apiClient.put<ApiResponse<MaintenanceType>>(
    `/trucks/maintenance-types/${typeId}`,
    update,
  );
  return data.data!;
    },
    async () => { throw new Error('Fleet Management requires the shop server.'); },
  );
}


// =================================================================
// MAINTENANCE SCHEDULES
// =================================================================

/** Get per-vehicle maintenance schedule. */
export async function getMaintenanceSchedule(
  vehicleId: number,
): Promise<MaintenanceSchedule[]> {
  return adaptedRequest(
    async () => {
      const { data } = await apiClient.get<ApiResponse<MaintenanceSchedule[]>>(
    `/trucks/${vehicleId}/maintenance/schedule`,
  );
  return data.data ?? [];
    },
    async () => [] as unknown as MaintenanceSchedule[],
  );
}

/** Set or update a schedule entry for a vehicle. */
export async function setMaintenanceSchedule(
  vehicleId: number,
  schedule: MaintenanceScheduleCreate,
): Promise<MaintenanceSchedule> {
  return adaptedRequest(
    async () => {
      const { data } = await apiClient.post<ApiResponse<MaintenanceSchedule>>(
    `/trucks/${vehicleId}/maintenance/schedule`,
    schedule,
  );
  return data.data!;
    },
    async () => { throw new Error('Fleet Management requires the shop server.'); },
  );
}

/** Get fleet-wide upcoming maintenance (within N days). */
export async function getUpcomingMaintenance(params?: {
  days_ahead?: number;
  vehicle_id?: number;
}): Promise<MaintenanceAlert[]> {
  return adaptedRequest(
    async () => {
      const { data } = await apiClient.get<ApiResponse<MaintenanceAlert[]>>(
    '/trucks/maintenance/upcoming',
    { params },
  );
  return data.data ?? [];
    },
    async () => [] as unknown as MaintenanceAlert[],
  );
}

/** Get fleet-wide overdue maintenance. */
export async function getOverdueMaintenance(params?: {
  vehicle_id?: number;
}): Promise<MaintenanceAlert[]> {
  return adaptedRequest(
    async () => {
      const { data } = await apiClient.get<ApiResponse<MaintenanceAlert[]>>(
    '/trucks/maintenance/overdue',
    { params },
  );
  return data.data ?? [];
    },
    async () => [] as unknown as MaintenanceAlert[],
  );
}


// =================================================================
// MAINTENANCE RECORDS (Service History)
// =================================================================

/** Get service history for a vehicle. */
export async function getServiceHistory(
  vehicleId: number,
  params?: {
    maintenance_type_id?: number;
    limit?: number;
    offset?: number;
  },
): Promise<MaintenanceRecord[]> {
  return adaptedRequest(
    async () => {
      const { data } = await apiClient.get<ApiResponse<MaintenanceRecord[]>>(
    `/trucks/${vehicleId}/maintenance/history`,
    { params },
  );
  return data.data ?? [];
    },
    async () => [] as unknown as MaintenanceRecord[],
  );
}

/** Log a maintenance service for a vehicle. */
export async function logService(
  vehicleId: number,
  record: MaintenanceRecordCreate,
): Promise<MaintenanceRecord> {
  return adaptedRequest(
    async () => {
      const { data } = await apiClient.post<ApiResponse<MaintenanceRecord>>(
    `/trucks/${vehicleId}/maintenance/log`,
    record,
  );
  return data.data!;
    },
    async () => { throw new Error('Fleet Management requires the shop server.'); },
  );
}

/** Get maintenance cost summary for a vehicle. */
export async function getMaintenanceCosts(
  vehicleId: number,
  params?: { period_start?: string; period_end?: string },
): Promise<MaintenanceCostSummary> {
  return adaptedRequest(
    async () => {
      const { data } = await apiClient.get<ApiResponse<MaintenanceCostSummary>>(
    `/trucks/${vehicleId}/maintenance/costs`,
    { params },
  );
  return data.data!;
    },
    async () => ({}) as unknown as MaintenanceCostSummary,
  );
}
