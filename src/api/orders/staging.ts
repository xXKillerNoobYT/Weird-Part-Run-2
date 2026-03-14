/**
 * Staging Zones API functions.
 */

import apiClient from '../client';
import type { ApiResponse, StatusMessage } from '../../lib/types';
import type {
  StagingZoneResponse,
  DistributeFromStaging,
} from '../../lib/types';
import { adaptedRequest } from '../adapter';


/** List all staging zones */
export async function listStagingZones(): Promise<StagingZoneResponse[]> {
  return adaptedRequest(
    async () => {
      const { data } = await apiClient.get<ApiResponse<StagingZoneResponse[]>>(
    '/orders/staging'
  );
  return data.data ?? [];
    },
    async () => [] as unknown as StagingZoneResponse[],
  );
}

/** Distribute items from a staging zone */
export async function distributeFromStaging(
  payload: DistributeFromStaging
): Promise<StatusMessage> {
  return adaptedRequest(
    async () => {
      const { data } = await apiClient.post<ApiResponse<StatusMessage>>(
    '/orders/staging/distribute',
    payload
  );
  return data.data!;
    },
    async () => { throw new Error('Orders requires the shop server.'); },
  );
}
