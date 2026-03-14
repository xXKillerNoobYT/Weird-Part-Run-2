/**
 * Vehicle assignment operations.
 */

import apiClient from '../client';
import { adaptedRequest } from '../adapter';
import type {
  ApiResponse,
  StatusMessage,
  VehicleAssignmentCreate,
  VehicleAssignment,
} from '../../lib/types';


/** List active assignments for a vehicle. */
export async function listAssignments(
  vehicleId: number,
): Promise<VehicleAssignment[]> {
  return adaptedRequest(
    async () => {
      const { data } = await apiClient.get<ApiResponse<VehicleAssignment[]>>(
        `/trucks/${vehicleId}/assignments`,
      );
      return data.data ?? [];
    },
    async () => {
      const { getVehicleAssignments } = await import('../../local/services/fleet-service');
      return await getVehicleAssignments(vehicleId) as unknown as VehicleAssignment[];
    },
  );
}

/** Assign a driver to a vehicle. */
export async function assignDriver(
  vehicleId: number,
  assignment: VehicleAssignmentCreate,
): Promise<VehicleAssignment> {
  return adaptedRequest(
    async () => {
      const { data } = await apiClient.post<ApiResponse<VehicleAssignment>>(
    `/trucks/${vehicleId}/assign`,
    assignment,
  );
  return data.data!;
    },
    async () => { throw new Error('Fleet Management requires the shop server.'); },
  );
}

/** Unassign a driver from a vehicle. */
export async function unassignDriver(
  vehicleId: number,
  userId: number,
): Promise<StatusMessage> {
  return adaptedRequest(
    async () => {
      const { data } = await apiClient.delete<ApiResponse<StatusMessage>>(
    `/trucks/${vehicleId}/assign/${userId}`,
  );
  return data.data!;
    },
    async () => { throw new Error('Fleet Management requires the shop server.'); },
  );
}

/** Toggle take-home status for a driver's assignment. */
export async function toggleTakeHome(
  vehicleId: number,
  payload: { user_id: number; is_take_home: boolean },
): Promise<StatusMessage> {
  return adaptedRequest(
    async () => {
      const { data } = await apiClient.put<ApiResponse<StatusMessage>>(
    `/trucks/${vehicleId}/take-home`,
    payload,
  );
  return data.data!;
    },
    async () => { throw new Error('Fleet Management requires the shop server.'); },
  );
}
