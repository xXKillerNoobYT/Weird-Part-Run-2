/**
 * Vehicle photo upload/removal.
 */

import apiClient from '../client';
import type { ApiResponse } from '../../lib/types';
import { adaptedRequest } from '../adapter';


/** Upload or replace a vehicle's photo. */
export async function uploadVehiclePhoto(
  vehicleId: number,
  file: File,
): Promise<{ photo_path: string }> {
  const formData = new FormData();
  formData.append('file', file);
  const { data } = await apiClient.post<ApiResponse<{ photo_path: string }>>(
    `/trucks/photo/${vehicleId}`,
    formData,
    { headers: { 'Content-Type': 'multipart/form-data' } },
  );
  return data.data!;
}

/** Remove a vehicle's photo. */
export async function removeVehiclePhoto(
  vehicleId: number,
): Promise<void> {
  return adaptedRequest(
    async () => {
      await apiClient.delete(`/trucks/photo/${vehicleId}`);
    },
    async () => { throw new Error('Fleet Management requires the shop server.'); },
  );
}
