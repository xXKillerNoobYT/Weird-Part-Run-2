/**
 * Vehicle inventory (stock on truck) operations.
 */

import apiClient from '../client';
import { adaptedRequest } from '../adapter';
import type {
  ApiResponse,
  VehicleInventoryItem,
  VehicleInventoryTransfer,
} from '../../lib/types';


/** Get parts inventory on a vehicle. */
export async function getVehicleInventory(
  vehicleId: number,
  params?: { search?: string },
): Promise<VehicleInventoryItem[]> {
  return adaptedRequest(
    async () => {
      const { data } = await apiClient.get<ApiResponse<VehicleInventoryItem[]>>(
        `/trucks/${vehicleId}/inventory`,
        { params },
      );
      return data.data ?? [];
    },
    async () => {
      const { getTruckInventory } = await import('../../local/services/fleet-service');
      return await getTruckInventory(vehicleId) as unknown as VehicleInventoryItem[];
    },
  );
}

/** Add parts to a vehicle (stock transfer). */
export async function addToVehicleInventory(
  vehicleId: number,
  transfer: VehicleInventoryTransfer,
): Promise<{ part_id: number; qty_added: number; vehicle_id: number }> {
  const { data } = await apiClient.post<
    ApiResponse<{ part_id: number; qty_added: number; vehicle_id: number }>
  >(`/trucks/${vehicleId}/inventory/add`, transfer);
  return data.data!;
}

/** Remove parts from a vehicle (stock transfer). */
export async function removeFromVehicleInventory(
  vehicleId: number,
  transfer: VehicleInventoryTransfer & {
    to_location_type?: string;
    to_location_id?: number;
  },
): Promise<{ part_id: number; qty_removed: number; vehicle_id: number }> {
  const { data } = await apiClient.post<
    ApiResponse<{ part_id: number; qty_removed: number; vehicle_id: number }>
  >(`/trucks/${vehicleId}/inventory/remove`, transfer);
  return data.data!;
}
