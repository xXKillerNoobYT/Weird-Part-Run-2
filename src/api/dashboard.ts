/**
 * Dashboard API functions — KPIs, quick actions, and Fast Drive.
 */

import apiClient from './client';
import { adaptedRequest } from './adapter';
import type {
  ApiResponse,
  HomeDashboardData,
  FastDriveContext,
  FastDriveStartRequest,
  FastDriveResult,
  CertAlertItem,
  VehicleExpiryAlert,
} from '../lib/types';


/** Fetch live KPI counts and quick actions. */
export async function getDashboard(): Promise<HomeDashboardData> {
  return adaptedRequest(
    async () => {
      const { data } = await apiClient.get<ApiResponse<HomeDashboardData>>(
        '/dashboard',
      );
      return data.data!;
    },
    async () => {
      const { getDashboard } = await import('../local/services/dashboard-service');
      return getDashboard() as unknown as HomeDashboardData;
    },
  );
}

/** Fetch the current user's Fast Drive context (vehicle + destinations). */
export async function getFastDriveContext(): Promise<FastDriveContext> {
  return adaptedRequest(
    async () => {
      const { data } = await apiClient.get<ApiResponse<FastDriveContext>>(
        '/dashboard/fast-drive',
      );
      return data.data!;
    },
    async () => {
      const { getFastDriveContext } = await import('../local/services/dashboard-service');
      return getFastDriveContext(0) as unknown as FastDriveContext;
    },
  );
}

/** Log a trip leg via the Fast Drive flow. */
export async function startDrive(
  req: FastDriveStartRequest,
): Promise<FastDriveResult> {
  return adaptedRequest(
    async () => {
      const { data } = await apiClient.post<ApiResponse<FastDriveResult>>(
        '/dashboard/fast-drive/start',
        req,
      );
      return data.data!;
    },
    async () => {
      const { startDrive } = await import('../local/services/dashboard-service');
      return startDrive(0, req) as unknown as FastDriveResult;
    },
  );
}

/** Fetch certification expiry alerts (< 60 days). */
export async function getCertAlerts(): Promise<CertAlertItem[]> {
  return adaptedRequest(
    async () => {
      const { data } = await apiClient.get<ApiResponse<CertAlertItem[]>>(
        '/dashboard/cert-alerts',
      );
      return data.data!;
    },
    async () => {
      const { getCertAlerts } = await import('../local/services/dashboard-service');
      return getCertAlerts() as unknown as CertAlertItem[];
    },
  );
}

/** Fetch vehicle insurance/registration expiry alerts. */
export async function getVehicleExpiryAlerts(days = 60): Promise<VehicleExpiryAlert[]> {
  return adaptedRequest(
    async () => {
      const { data } = await apiClient.get<ApiResponse<VehicleExpiryAlert[]>>(
        '/dashboard/vehicle-alerts',
        { params: { days } },
      );
      return data.data!;
    },
    async () => {
      const { getVehicleExpiryAlerts } = await import('../local/services/dashboard-service');
      return getVehicleExpiryAlerts(days) as unknown as VehicleExpiryAlert[];
    },
  );
}
