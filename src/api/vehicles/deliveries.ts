/**
 * Vehicle delivery item operations.
 */

import apiClient from '../client';
import type {
  ApiResponse,
  DeliveryItemBulkCreate,
  VehicleDeliveryItem,
} from '../../lib/types';
import { adaptedRequest } from '../adapter';


/** Get delivery items for a vehicle. */
export async function listDeliveries(
  vehicleId: number,
  params?: { status?: string; job_id?: number },
): Promise<VehicleDeliveryItem[]> {
  return adaptedRequest(
    async () => {
      const { data } = await apiClient.get<ApiResponse<VehicleDeliveryItem[]>>(
    `/trucks/${vehicleId}/deliveries`,
    { params },
  );
  return data.data ?? [];
    },
    async () => [] as unknown as VehicleDeliveryItem[],
  );
}

/** Assign parts for delivery on a vehicle. */
export async function assignDeliveryItems(
  vehicleId: number,
  payload: DeliveryItemBulkCreate,
): Promise<VehicleDeliveryItem[]> {
  return adaptedRequest(
    async () => {
      const { data } = await apiClient.post<ApiResponse<VehicleDeliveryItem[]>>(
    `/trucks/${vehicleId}/deliveries`,
    payload,
  );
  return data.data ?? [];
    },
    async () => { throw new Error('Fleet Management requires the shop server.'); },
  );
}

/** Update delivery item status (loaded, in_transit, etc.). */
export async function updateDeliveryStatus(
  vehicleId: number,
  itemId: number,
  payload: { status: string },
): Promise<VehicleDeliveryItem> {
  return adaptedRequest(
    async () => {
      const { data } = await apiClient.put<ApiResponse<VehicleDeliveryItem>>(
    `/trucks/${vehicleId}/deliveries/${itemId}/status`,
    payload,
  );
  return data.data!;
    },
    async () => { throw new Error('Fleet Management requires the shop server.'); },
  );
}

/** Mark a delivery item as delivered (triggers stock movement). */
export async function markDelivered(
  vehicleId: number,
  itemId: number,
  payload?: { qty_delivered?: number },
): Promise<VehicleDeliveryItem> {
  return adaptedRequest(
    async () => {
      const { data } = await apiClient.put<ApiResponse<VehicleDeliveryItem>>(
    `/trucks/${vehicleId}/deliveries/${itemId}/deliver`,
    payload ?? {},
  );
  return data.data!;
    },
    async () => { throw new Error('Fleet Management requires the shop server.'); },
  );
}

/** Return an undelivered item. */
export async function returnDelivery(
  vehicleId: number,
  itemId: number,
  payload?: { return_to?: 'truck' | 'warehouse'; notes?: string },
): Promise<VehicleDeliveryItem> {
  return adaptedRequest(
    async () => {
      const { data } = await apiClient.put<ApiResponse<VehicleDeliveryItem>>(
    `/trucks/${vehicleId}/deliveries/${itemId}/return`,
    payload ?? {},
  );
  return data.data!;
    },
    async () => { throw new Error('Fleet Management requires the shop server.'); },
  );
}
