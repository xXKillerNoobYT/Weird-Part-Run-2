/**
 * Dashboard API functions — KPIs, quick actions, and Fast Drive.
 */

import apiClient from './client';
import type {
  ApiResponse,
  HomeDashboardData,
  FastDriveContext,
  FastDriveStartRequest,
  FastDriveResult,
  CertAlertItem,
} from '../lib/types';


/** Fetch live KPI counts and quick actions. */
export async function getDashboard(): Promise<HomeDashboardData> {
  const { data } = await apiClient.get<ApiResponse<HomeDashboardData>>(
    '/dashboard',
  );
  return data.data!;
}

/** Fetch the current user's Fast Drive context (vehicle + destinations). */
export async function getFastDriveContext(): Promise<FastDriveContext> {
  const { data } = await apiClient.get<ApiResponse<FastDriveContext>>(
    '/dashboard/fast-drive',
  );
  return data.data!;
}

/** Log a trip leg via the Fast Drive flow. */
export async function startDrive(
  req: FastDriveStartRequest,
): Promise<FastDriveResult> {
  const { data } = await apiClient.post<ApiResponse<FastDriveResult>>(
    '/dashboard/fast-drive/start',
    req,
  );
  return data.data!;
}

/** Fetch certification expiry alerts (< 60 days). */
export async function getCertAlerts(): Promise<CertAlertItem[]> {
  const { data } = await apiClient.get<ApiResponse<CertAlertItem[]>>(
    '/dashboard/cert-alerts',
  );
  return data.data!;
}
