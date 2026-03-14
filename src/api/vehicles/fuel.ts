/**
 * Fuel tracking operations.
 */

import apiClient from '../client';
import type {
  ApiResponse,
  FuelLogCreate,
  FuelLogUpdate,
  FuelLog,
  FuelSummary,
} from '../../lib/types';
import { adaptedRequest } from '../adapter';


/** Log a fuel purchase for a vehicle. */
export async function logFuel(vehicleId: number, body: FuelLogCreate): Promise<FuelLog> {
  return adaptedRequest(
    async () => {
      const { data } = await apiClient.post<ApiResponse<FuelLog>>(
    `/trucks/fuel/${vehicleId}`,
    body,
  );
  return data.data!;
    },
    async () => { throw new Error('Fleet Management requires the shop server.'); },
  );
}

/** Get fuel logs for a vehicle. */
export async function getVehicleFuelLogs(
  vehicleId: number,
  params?: { limit?: number; offset?: number },
): Promise<FuelLog[]> {
  return adaptedRequest(
    async () => {
      const { data } = await apiClient.get<ApiResponse<FuelLog[]>>(
    `/trucks/fuel/${vehicleId}`,
    { params },
  );
  return data.data!;
    },
    async () => [] as unknown as FuelLog[],
  );
}

/** Update a fuel log entry. */
export async function updateFuelLog(logId: number, body: FuelLogUpdate): Promise<FuelLog> {
  return adaptedRequest(
    async () => {
      const { data } = await apiClient.put<ApiResponse<FuelLog>>(
    `/trucks/fuel/log/${logId}`,
    body,
  );
  return data.data!;
    },
    async () => { throw new Error('Fleet Management requires the shop server.'); },
  );
}

/** Get fuel summary for a vehicle. */
export async function getVehicleFuelSummary(
  vehicleId: number,
  params?: { period_start?: string; period_end?: string },
): Promise<FuelSummary> {
  return adaptedRequest(
    async () => {
      const { data } = await apiClient.get<ApiResponse<FuelSummary>>(
    `/trucks/fuel-summary/${vehicleId}`,
    { params },
  );
  return data.data!;
    },
    async () => ({}) as unknown as FuelSummary,
  );
}

/** Get fleet-wide fuel summary. */
export async function getFleetFuelSummary(
  params?: { period_start?: string; period_end?: string },
): Promise<FuelSummary> {
  return adaptedRequest(
    async () => {
      const { data } = await apiClient.get<ApiResponse<FuelSummary>>(
    `/trucks/fleet/fuel-summary`,
    { params },
  );
  return data.data!;
    },
    async () => ({}) as unknown as FuelSummary,
  );
}
