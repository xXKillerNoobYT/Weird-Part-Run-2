/**
 * Vehicle transfer operations.
 */

import apiClient from '../client';
import type {
  ApiResponse,
  VehicleTransferCreate,
  VehicleTransfer,
} from '../../lib/types';
import { adaptedRequest } from '../adapter';


/** List vehicle transfers. */
export async function listTransfers(
  params?: { transfer_status?: string; vehicle_id?: number; limit?: number; offset?: number },
): Promise<VehicleTransfer[]> {
  return adaptedRequest(
    async () => {
      const { data } = await apiClient.get<ApiResponse<VehicleTransfer[]>>(
    '/trucks/fleet/transfers',
    { params },
  );
  return data.data!;
    },
    async () => [] as unknown as VehicleTransfer[],
  );
}

/** Request a vehicle transfer. */
export async function requestTransfer(body: VehicleTransferCreate): Promise<VehicleTransfer> {
  return adaptedRequest(
    async () => {
      const { data } = await apiClient.post<ApiResponse<VehicleTransfer>>(
    '/trucks/fleet/transfers',
    body,
  );
  return data.data!;
    },
    async () => { throw new Error('Fleet Management requires the shop server.'); },
  );
}

/** Approve a transfer request. */
export async function approveTransfer(transferId: number): Promise<VehicleTransfer> {
  return adaptedRequest(
    async () => {
      const { data } = await apiClient.post<ApiResponse<VehicleTransfer>>(
    `/trucks/fleet/transfers/${transferId}/approve`,
  );
  return data.data!;
    },
    async () => { throw new Error('Fleet Management requires the shop server.'); },
  );
}

/** Mark a transfer as in-transit. */
export async function startTransferTransit(transferId: number): Promise<VehicleTransfer> {
  return adaptedRequest(
    async () => {
      const { data } = await apiClient.post<ApiResponse<VehicleTransfer>>(
    `/trucks/fleet/transfers/${transferId}/transit`,
  );
  return data.data!;
    },
    async () => { throw new Error('Fleet Management requires the shop server.'); },
  );
}

/** Complete a transfer. */
export async function completeTransfer(transferId: number): Promise<VehicleTransfer> {
  return adaptedRequest(
    async () => {
      const { data } = await apiClient.post<ApiResponse<VehicleTransfer>>(
    `/trucks/fleet/transfers/${transferId}/complete`,
  );
  return data.data!;
    },
    async () => { throw new Error('Fleet Management requires the shop server.'); },
  );
}

/** Cancel a transfer. */
export async function cancelTransfer(
  transferId: number,
  reason?: string,
): Promise<VehicleTransfer> {
  return adaptedRequest(
    async () => {
      const { data } = await apiClient.post<ApiResponse<VehicleTransfer>>(
    `/trucks/fleet/transfers/${transferId}/cancel`,
    undefined,
    { params: { reason } },
  );
  return data.data!;
    },
    async () => { throw new Error('Fleet Management requires the shop server.'); },
  );
}
