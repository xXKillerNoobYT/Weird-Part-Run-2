/**
 * Fleet dashboard stats.
 */

import apiClient from '../client';
import type {
  ApiResponse,
  FleetDashboardStats,
} from '../../lib/types';
import { adaptedRequest } from '../adapter';


/** Get fleet-wide dashboard stats. */
export async function getFleetDashboard(): Promise<FleetDashboardStats> {
  return adaptedRequest(
    async () => {
      const { data } = await apiClient.get<ApiResponse<FleetDashboardStats>>(
    '/trucks/fleet/dashboard',
  );
  return data.data!;
    },
    async () => ({}) as unknown as FleetDashboardStats,
  );
}
