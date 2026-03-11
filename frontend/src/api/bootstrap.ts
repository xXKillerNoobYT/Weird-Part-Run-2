/**
 * Bootstrap API — pairing codes, artifact registry, bootstrap handshake,
 * and install telemetry for mobile shell provisioning.
 */

import apiClient from './client';
import type { ApiResponse } from '../lib/types';

export type BootstrapPlatform = 'ios' | 'android' | 'windows' | 'macos';
export type InstallStatus =
  | 'requested' | 'downloading' | 'downloaded'
  | 'verifying' | 'verified' | 'installing'
  | 'installed' | 'failed';

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
  progress_pct: number;
  bytes_downloaded: number;
  bytes_total: number;
  checksum_computed: string | null;
  checksum_verified: number;
  signature_verified: number | null;
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
  progress_pct?: number;
  bytes_downloaded?: number;
  bytes_total?: number;
  checksum_computed?: string;
  checksum_verified?: boolean;
  signature_verified?: boolean | null;
}

export interface ArtifactVerifyPayload {
  artifact_id: number;
  client_checksum_sha256: string;
}

export interface ArtifactVerifyResult {
  valid: boolean;
  checksum_match: boolean;
  signature_valid: boolean | null;
  artifact_id: number;
  version: string | null;
  detail: string;
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

// ── Artifact Verification & Active Lookup ───────────────────────

/** Get the currently active artifact for a given platform (no auth required). */
export async function getActiveArtifact(platform: BootstrapPlatform): Promise<BootstrapArtifact> {
  const { data } = await apiClient.get<ApiResponse<BootstrapArtifact>>(
    `/bootstrap/artifacts/active/${platform}`,
  );
  return data.data as BootstrapArtifact;
}

/** Verify a downloaded artifact's checksum against the server record (no auth required). */
export async function verifyArtifact(payload: ArtifactVerifyPayload): Promise<ArtifactVerifyResult> {
  const { data } = await apiClient.post<ApiResponse<ArtifactVerifyResult>>(
    '/bootstrap/artifacts/verify',
    payload,
  );
  return data.data as ArtifactVerifyResult;
}

/** Sign an artifact with the shop's Ed25519 key (admin only). */
export async function signArtifact(artifactId: number): Promise<BootstrapArtifact> {
  const { data } = await apiClient.post<ApiResponse<BootstrapArtifact>>(
    `/bootstrap/artifacts/${artifactId}/sign`,
  );
  return data.data as BootstrapArtifact;
}
