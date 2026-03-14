/**
 * Document alerts and fleet utilization reporting.
 */

import apiClient from '../client';
import type {
  ApiResponse,
  VehicleDocumentAlert,
  VehicleUtilizationReport,
} from '../../lib/types';
import { adaptedRequest } from '../adapter';


/** Vehicles with insurance or registration expiring soon. */
export async function getDocumentAlerts(
  daysAhead?: number,
): Promise<VehicleDocumentAlert[]> {
  return adaptedRequest(
    async () => {
      const { data } = await apiClient.get<ApiResponse<VehicleDocumentAlert[]>>(
    '/trucks/fleet/document-alerts',
    { params: daysAhead ? { days_ahead: daysAhead } : undefined },
  );
  return data.data!;
    },
    async () => [] as unknown as VehicleDocumentAlert[],
  );
}

/** Fleet utilization report: miles, costs, MPG per vehicle. */
export async function getUtilizationReport(
  periodStart: string,
  periodEnd: string,
): Promise<VehicleUtilizationReport> {
  return adaptedRequest(
    async () => {
      const { data } = await apiClient.get<ApiResponse<VehicleUtilizationReport>>(
    '/trucks/fleet/utilization',
    { params: { period_start: periodStart, period_end: periodEnd } },
  );
  return data.data!;
    },
    async () => ({}) as unknown as VehicleUtilizationReport,
  );
}
