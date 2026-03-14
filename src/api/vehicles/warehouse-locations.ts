/**
 * Warehouse/shop location operations.
 */

import apiClient from '../client';
import type {
  ApiResponse,
  StatusMessage,
  WarehouseLocationCreate,
  WarehouseLocationUpdate,
  WarehouseLocation,
} from '../../lib/types';
import { adaptedRequest } from '../adapter';


/** List warehouse/shop locations. */
export async function listWarehouseLocations(params?: {
  include_inactive?: boolean;
}): Promise<WarehouseLocation[]> {
  return adaptedRequest(
    async () => {
      const { data } = await apiClient.get<ApiResponse<WarehouseLocation[]>>(
    '/trucks/warehouse-locations',
    { params },
  );
  return data.data ?? [];
    },
    async () => [] as unknown as WarehouseLocation[],
  );
}

/** Create a new warehouse/shop location. */
export async function createWarehouseLocation(
  location: WarehouseLocationCreate,
): Promise<WarehouseLocation> {
  return adaptedRequest(
    async () => {
      const { data } = await apiClient.post<ApiResponse<WarehouseLocation>>(
    '/trucks/warehouse-locations',
    location,
  );
  return data.data!;
    },
    async () => { throw new Error('Fleet Management requires the shop server.'); },
  );
}

/** Update a warehouse/shop location. */
export async function updateWarehouseLocation(
  locationId: number,
  update: WarehouseLocationUpdate,
): Promise<WarehouseLocation> {
  return adaptedRequest(
    async () => {
      const { data } = await apiClient.put<ApiResponse<WarehouseLocation>>(
    `/trucks/warehouse-locations/${locationId}`,
    update,
  );
  return data.data!;
    },
    async () => { throw new Error('Fleet Management requires the shop server.'); },
  );
}

/** Deactivate a warehouse/shop location. */
export async function deactivateWarehouseLocation(
  locationId: number,
): Promise<StatusMessage> {
  return adaptedRequest(
    async () => {
      const { data } = await apiClient.delete<ApiResponse<StatusMessage>>(
    `/trucks/warehouse-locations/${locationId}`,
  );
  return data.data!;
    },
    async () => { throw new Error('Fleet Management requires the shop server.'); },
  );
}
