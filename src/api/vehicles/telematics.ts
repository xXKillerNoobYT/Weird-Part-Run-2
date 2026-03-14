/**
 * Telematics device management, GPS positions, and events.
 */

import apiClient from '../client';
import type {
  ApiResponse,
  StatusMessage,
  TelematicsDeviceCreate,
  TelematicsDevice,
  TelematicsPosition,
  TelematicsEvent,
  VehicleLocationSummary,
} from '../../lib/types';
import { adaptedRequest } from '../adapter';


/** List all registered telematics devices. */
export async function listTelematicsDevices(
  params?: { active_only?: boolean },
): Promise<TelematicsDevice[]> {
  return adaptedRequest(
    async () => {
      const { data } = await apiClient.get<ApiResponse<TelematicsDevice[]>>(
    '/trucks/telematics/devices',
    { params },
  );
  return data.data!;
    },
    async () => [] as unknown as TelematicsDevice[],
  );
}

/** Register a telematics device on a vehicle. */
export async function registerTelematicsDevice(
  body: TelematicsDeviceCreate,
): Promise<TelematicsDevice> {
  return adaptedRequest(
    async () => {
      const { data } = await apiClient.post<ApiResponse<TelematicsDevice>>(
    '/trucks/telematics/devices',
    body,
  );
  return data.data!;
    },
    async () => { throw new Error('Fleet Management requires the shop server.'); },
  );
}

/** Deactivate a telematics device. */
export async function deactivateTelematicsDevice(deviceId: number): Promise<StatusMessage> {
  return adaptedRequest(
    async () => {
      const { data } = await apiClient.delete<ApiResponse<StatusMessage>>(
    `/trucks/telematics/devices/${deviceId}`,
  );
  return data.data!;
    },
    async () => { throw new Error('Fleet Management requires the shop server.'); },
  );
}

/** Get GPS breadcrumbs for a vehicle. */
export async function getVehiclePositions(
  vehicleId: number,
  params?: { since?: string; limit?: number },
): Promise<TelematicsPosition[]> {
  return adaptedRequest(
    async () => {
      const { data } = await apiClient.get<ApiResponse<TelematicsPosition[]>>(
    `/trucks/telematics/positions/${vehicleId}`,
    { params },
  );
  return data.data!;
    },
    async () => [] as unknown as TelematicsPosition[],
  );
}

/** Get telematics events for a vehicle. */
export async function getVehicleEvents(
  vehicleId: number,
  params?: { since?: string; event_type?: string; limit?: number },
): Promise<TelematicsEvent[]> {
  return adaptedRequest(
    async () => {
      const { data } = await apiClient.get<ApiResponse<TelematicsEvent[]>>(
    `/trucks/telematics/events/${vehicleId}`,
    { params },
  );
  return data.data!;
    },
    async () => [] as unknown as TelematicsEvent[],
  );
}

/** Get last known location for every vehicle with a device. */
export async function getFleetPositions(): Promise<VehicleLocationSummary[]> {
  return adaptedRequest(
    async () => {
      const { data } = await apiClient.get<ApiResponse<VehicleLocationSummary[]>>(
    '/trucks/fleet/positions',
  );
  return data.data!;
    },
    async () => [] as unknown as VehicleLocationSummary[],
  );
}
