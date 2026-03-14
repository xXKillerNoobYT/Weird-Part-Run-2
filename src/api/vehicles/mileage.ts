/**
 * Mileage logging, trip legs, estimates, and summaries.
 */

import apiClient from '../client';
import type {
  ApiResponse,
  MileageLogCreate,
  MileageLogUpdate,
  MileageLog,
  TripLegCreate,
  TripLeg,
  MileageEstimate,
  MileageSummary,
} from '../../lib/types';
import { adaptedRequest } from '../adapter';


/** Get mileage logs for a vehicle. */
export async function getMileageLogs(
  vehicleId: number,
  params?: { limit?: number; offset?: number },
): Promise<MileageLog[]> {
  return adaptedRequest(
    async () => {
      const { data } = await apiClient.get<ApiResponse<MileageLog[]>>(
    `/trucks/${vehicleId}/mileage`,
    { params },
  );
  return data.data ?? [];
    },
    async () => [] as unknown as MileageLog[],
  );
}

/** Log daily mileage for a vehicle. */
export async function logMileage(
  vehicleId: number,
  log: MileageLogCreate,
): Promise<MileageLog> {
  return adaptedRequest(
    async () => {
      const { data } = await apiClient.post<ApiResponse<MileageLog>>(
    `/trucks/${vehicleId}/mileage`,
    log,
  );
  return data.data!;
    },
    async () => { throw new Error('Fleet Management requires the shop server.'); },
  );
}

/** Update a mileage log entry. */
export async function updateMileageLog(
  vehicleId: number,
  logId: number,
  update: MileageLogUpdate,
): Promise<MileageLog> {
  return adaptedRequest(
    async () => {
      const { data } = await apiClient.put<ApiResponse<MileageLog>>(
    `/trucks/${vehicleId}/mileage/${logId}`,
    update,
  );
  return data.data!;
    },
    async () => { throw new Error('Fleet Management requires the shop server.'); },
  );
}

/** Get trip legs for a mileage log. */
export async function getTripLegs(
  vehicleId: number,
  logId: number,
): Promise<TripLeg[]> {
  return adaptedRequest(
    async () => {
      const { data } = await apiClient.get<ApiResponse<TripLeg[]>>(
    `/trucks/${vehicleId}/mileage/${logId}/trips`,
  );
  return data.data ?? [];
    },
    async () => [] as unknown as TripLeg[],
  );
}

/** Add trip legs to a mileage log (bulk). */
export async function addTripLegs(
  vehicleId: number,
  logId: number,
  legs: TripLegCreate[],
): Promise<TripLeg[]> {
  return adaptedRequest(
    async () => {
      const { data } = await apiClient.post<ApiResponse<TripLeg[]>>(
    `/trucks/${vehicleId}/mileage/${logId}/trips`,
    { legs },
  );
  return data.data ?? [];
    },
    async () => { throw new Error('Fleet Management requires the shop server.'); },
  );
}

/** Estimate trip mileage based on manual distances. */
export async function estimateMileage(params: {
  vehicle_id?: number;
  job_id?: number;
  user_id?: number;
}): Promise<MileageEstimate> {
  return adaptedRequest(
    async () => {
      const { data } = await apiClient.get<ApiResponse<MileageEstimate>>(
    '/trucks/mileage/estimate',
    { params },
  );
  return data.data!;
    },
    async () => ({}) as unknown as MileageEstimate,
  );
}

/** Get mileage summary for a period. */
export async function getMileageSummary(params: {
  vehicle_id?: number;
  driver_id?: number;
  period_start?: string;
  period_end?: string;
}): Promise<MileageSummary> {
  return adaptedRequest(
    async () => {
      const { data } = await apiClient.get<ApiResponse<MileageSummary>>(
    '/trucks/mileage/summary',
    { params },
  );
  return data.data!;
    },
    async () => ({}) as unknown as MileageSummary,
  );
}
