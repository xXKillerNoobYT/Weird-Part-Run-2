/**
 * Bootstrap API — pairing codes, artifact registry, bootstrap handshake,
 * and install telemetry for mobile shell provisioning.
 */

import apiClient from './client';
import type { ApiResponse } from '../lib/types';

export type BootstrapPlatform = 'ios' | 'android' | 'windows' | 'macos';
export type InstallStatus = 'requested' | 'downloaded' | 'installed' | 'failed';

export interface PairingCodeRecord {
  code: string;
  created_by: number | null;
  device_id: string | null;
  device_name: string | null;
  platform: BootstrapPlatform | null;
  bootstrap_version: string | null;
  public_key: string | null;
  created_at: string;
  expires_at: string;
  used_at: string | null;
  notes: string | null;
}

export interface PairingCodeCreatePayload {
  ttl_minutes: number;
  notes?: string;
}

export interface BootstrapArtifact {
  id: number;
  platform: BootstrapPlatform;
  version: string;
  manifest_json: string;
  manifest: Record<string, any>;
  download_url: string;
  checksum_sha256: string;
  signature: string | null;
  min_bootstrap_version: string;
  is_active: number;
  created_by: number | null;
  created_at: string;
}

export interface BootstrapArtifactUpsertPayload {
  platform: BootstrapPlatform;
  version: string;
  manifest: Record<string, any>;
  download_url: string;
  checksum_sha256: string;
  signature?: string;
  min_bootstrap_version?: string;
}

export interface BootstrapInstallEvent {
  id: number;
  device_id: string;
  platform: BootstrapPlatform;
  artifact_id: number | null;
  status: InstallStatus;
  error_message: string | null;
  metadata_json: string | null;
  metadata: Record<string, any>;
  created_at: string;
}

export interface BootstrapInstallEventPayload {
  pairing_code: string;
  device_id: string;
  platform: BootstrapPlatform;
  artifact_id?: number | null;
  status: InstallStatus;
  error_message?: string;
  metadata?: Record<string, any>;
}

export interface BootstrapHandshakePayload {
  pairing_code: string;
  device_id: string;
  device_name: string;
  platform: BootstrapPlatform;
  bootstrap_version: string;
  public_key?: string;
}

export interface BootstrapHandshakeResult {
  device_id: string;
  platform: BootstrapPlatform;
  bootstrap_version: string;
  artifact: BootstrapArtifact | null;
  certificate: any;
  sync_endpoints: Record<string, string>;
}

export async function createPairingCode(payload: PairingCodeCreatePayload): Promise<PairingCodeRecord> {
  const { data } = await apiClient.post<ApiResponse<PairingCodeRecord>>('/bootstrap/pairing-codes', payload);
  return data.data as PairingCodeRecord;
}

export async function listPairingCodes(limit = 100): Promise<PairingCodeRecord[]> {
  const { data } = await apiClient.get<ApiResponse<PairingCodeRecord[]>>('/bootstrap/pairing-codes', {
    params: { limit },
  });
  return data.data ?? [];
}

export async function upsertBootstrapArtifact(payload: BootstrapArtifactUpsertPayload): Promise<BootstrapArtifact> {
  const { data } = await apiClient.post<ApiResponse<BootstrapArtifact>>('/bootstrap/artifacts', payload);
  return data.data as BootstrapArtifact;
}

export async function listBootstrapArtifacts(platform?: BootstrapPlatform, limit = 50): Promise<BootstrapArtifact[]> {
  const { data } = await apiClient.get<ApiResponse<BootstrapArtifact[]>>('/bootstrap/artifacts', {
    params: { platform: platform || undefined, limit },
  });
  return data.data ?? [];
}

export async function bootstrapHandshake(payload: BootstrapHandshakePayload): Promise<BootstrapHandshakeResult> {
  const { data } = await apiClient.post<ApiResponse<BootstrapHandshakeResult>>('/bootstrap/handshake', payload);
  return data.data as BootstrapHandshakeResult;
}

export async function logBootstrapInstallEvent(payload: BootstrapInstallEventPayload): Promise<BootstrapInstallEvent> {
  const { data } = await apiClient.post<ApiResponse<BootstrapInstallEvent>>('/bootstrap/install-events', payload);
  return data.data as BootstrapInstallEvent;
}

export async function listBootstrapInstallEvents(deviceId?: string, limit = 100): Promise<BootstrapInstallEvent[]> {
  const { data } = await apiClient.get<ApiResponse<BootstrapInstallEvent[]>>('/bootstrap/install-events', {
    params: { device_id: deviceId || undefined, limit },
  });
  return data.data ?? [];
}
