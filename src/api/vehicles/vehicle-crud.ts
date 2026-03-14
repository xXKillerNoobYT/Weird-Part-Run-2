/**
 * Vehicle CRUD operations.
 */

import apiClient from '../client';
import { adaptedRequest } from '../adapter';
import type {
  ApiResponse,
  StatusMessage,
  VehicleCreate,
  VehicleUpdate,
  Vehicle,
  VehicleListItem,
  MyVehicleDashboard,
} from '../../lib/types';


/** List vehicles with optional filters. */
export async function listVehicles(params?: {
  vehicle_type?: string;
  status?: string;
  driver_id?: number;
  search?: string;
  include_inactive?: boolean;
}): Promise<VehicleListItem[]> {
  return adaptedRequest(
    async () => {
      // Backend returns PaginatedData: { items, total, page, page_size, total_pages }
      const { data } = await apiClient.get<
        ApiResponse<{ items: VehicleListItem[]; total: number }>
      >('/trucks', { params });
      return data.data?.items ?? [];
    },
    async () => {
      const { listVehicles: local } = await import('../../local/services/fleet-service');
      return await local() as unknown as VehicleListItem[];
    },
  );
}

/** Create a new vehicle. */
export async function createVehicle(
  vehicle: VehicleCreate,
): Promise<Vehicle> {
  return adaptedRequest(
    async () => {
      const { data } = await apiClient.post<ApiResponse<Vehicle>>(
    '/trucks',
    vehicle,
  );
  return data.data!;
    },
    async () => { throw new Error('Fleet Management requires the shop server.'); },
  );
}

/** Get current user's assigned vehicle dashboard. */
export async function getMyVehicle(): Promise<MyVehicleDashboard> {
  return adaptedRequest(
    async () => {
      const { data } = await apiClient.get<ApiResponse<MyVehicleDashboard>>(
        '/trucks/my-vehicle',
      );
      return data.data!;
    },
    async () => {
      const { getMyVehicle: local } = await import('../../local/services/fleet-service');
      const vehicle = await local(0); // userId from local auth
      return (vehicle ?? {}) as unknown as MyVehicleDashboard;
    },
  );
}

/** Get full vehicle detail. */
export async function getVehicle(vehicleId: number): Promise<Vehicle> {
  return adaptedRequest(
    async () => {
      const { data } = await apiClient.get<ApiResponse<Vehicle>>(
        `/trucks/${vehicleId}`,
      );
      return data.data!;
    },
    async () => {
      const { getVehicle: local } = await import('../../local/services/fleet-service');
      const vehicle = await local(vehicleId);
      if (!vehicle) throw new Error('Vehicle not found');
      return vehicle as unknown as Vehicle;
    },
  );
}

/** Update a vehicle. */
export async function updateVehicle(
  vehicleId: number,
  update: VehicleUpdate,
): Promise<Vehicle> {
  return adaptedRequest(
    async () => {
      const { data } = await apiClient.put<ApiResponse<Vehicle>>(
    `/trucks/${vehicleId}`,
    update,
  );
  return data.data!;
    },
    async () => { throw new Error('Fleet Management requires the shop server.'); },
  );
}

/** Deactivate (soft delete) a vehicle. */
export async function deactivateVehicle(
  vehicleId: number,
): Promise<StatusMessage> {
  return adaptedRequest(
    async () => {
      const { data } = await apiClient.delete<ApiResponse<StatusMessage>>(
    `/trucks/${vehicleId}`,
  );
  return data.data!;
    },
    async () => { throw new Error('Fleet Management requires the shop server.'); },
  );
}
