/**
 * Bootstrap Client Service — artifact download, verification, and install
 * management for native (Tauri) app shells.
 *
 * Responsibilities:
 * 1. Download artifact binary from the shop server with progress tracking
 * 2. Compute SHA-256 checksum of the downloaded file (streaming)
 * 3. Verify checksum + signature against the shop's server-side record
 * 4. Report install lifecycle telemetry to the shop
 * 5. Persist download state across app restarts
 *
 * On web (desktop browser), downloads use standard fetch. On native
 * (Tauri), files are saved into the app's data directory via
 * @tauri-apps/plugin-fs. Both paths share the same verification logic.
 *
 * Architecture:
 * - The bootstrap shell calls `runBootstrapInstall()` after handshake
 * - Progress is reported via callback AND to the shop telemetry API
 * - Verification happens client-side (SHA-256) + server-side (verify endpoint)
 * - Install itself is platform-specific and outside this service's scope —
 *   this service returns the verified file path for the shell to hand off
 *   to the platform's native installer
 */

import { isTauri } from '../../lib/environment';

import {
  getActiveArtifact,
  logBootstrapInstallEvent,
  verifyArtifact,
  type BootstrapArtifact,
  type BootstrapPlatform,
  type InstallStatus,
} from '../../api/bootstrap';

// ── Constants ──────────────────────────────────────────────────────

const BOOTSTRAP_PREFIX = 'wp_bootstrap_';
const KEY_DOWNLOAD_STATE = `${BOOTSTRAP_PREFIX}download_state`;

// ── Types ──────────────────────────────────────────────────────────

export interface BootstrapDownloadState {
  artifactId: number;
  platform: BootstrapPlatform;
  version: string;
  downloadUrl: string;
  expectedChecksum: string;
  status: InstallStatus;
  progress: number;          // 0–100
  bytesDownloaded: number;
  bytesTotal: number;
  computedChecksum: string | null;
  checksumVerified: boolean;
  signatureVerified: boolean | null;
  filePath: string | null;   // Local path where file was saved (native only)
  error: string | null;
  startedAt: string;
  completedAt: string | null;
}

export interface BootstrapProgressCallback {
  (state: BootstrapDownloadState): void;
}

export interface BootstrapInstallOptions {
  /** Pairing code — required for telemetry events */
  pairingCode: string;
  /** Device identifier */
  deviceId: string;
  /** Target platform */
  platform: BootstrapPlatform;
  /** Force re-download even if a cached file exists */
  forceDownload?: boolean;
  /** Progress callback — called on each status change and periodically during download */
  onProgress?: BootstrapProgressCallback;
}

export interface BootstrapInstallResult {
  success: boolean;
  state: BootstrapDownloadState;
  artifact: BootstrapArtifact;
}

// ── Storage Helpers ────────────────────────────────────────────────

function stateSet(key: string, value: string): void {
  localStorage.setItem(key, value);
}

function stateGet(key: string): string | null {
  return localStorage.getItem(key);
}

function stateRemove(key: string): void {
  localStorage.removeItem(key);
}

// ── SHA-256 Streaming Hash ─────────────────────────────────────────

/**
 * Compute SHA-256 of a Uint8Array using Web Crypto API.
 * Works identically on both web and Tauri (both have crypto.subtle).
 */
async function sha256Hex(data: Uint8Array): Promise<string> {
  const hashBuf = await crypto.subtle.digest('SHA-256', data.buffer as ArrayBuffer);
  return Array.from(new Uint8Array(hashBuf))
    .map(b => b.toString(16).padStart(2, '0'))
    .join('');
}

/**
 * Incrementally accumulate chunks for SHA-256.
 *
 * Web Crypto doesn't support streaming digests, so we collect all
 * chunks and hash at the end.  For typical app binaries (<200 MB)
 * this is reasonable on mobile devices with 3–6 GB RAM.
 */
class ChunkedHasher {
  private chunks: Uint8Array[] = [];
  private totalSize = 0;

  append(chunk: Uint8Array): void {
    this.chunks.push(chunk);
    this.totalSize += chunk.length;
  }

  async finalise(): Promise<string> {
    // Merge all chunks into one buffer for Web Crypto
    const merged = new Uint8Array(this.totalSize);
    let offset = 0;
    for (const chunk of this.chunks) {
      merged.set(chunk, offset);
      offset += chunk.length;
    }
    return sha256Hex(merged);
  }

  /** Get the merged bytes (for saving to disk). */
  getMergedBytes(): Uint8Array {
    const merged = new Uint8Array(this.totalSize);
    let offset = 0;
    for (const chunk of this.chunks) {
      merged.set(chunk, offset);
      offset += chunk.length;
    }
    return merged;
  }

  get size(): number {
    return this.totalSize;
  }
}

// ── State Persistence ──────────────────────────────────────────────

async function saveDownloadState(state: BootstrapDownloadState): Promise<void> {
  await stateSet(KEY_DOWNLOAD_STATE, JSON.stringify(state));
}

export async function getDownloadState(): Promise<BootstrapDownloadState | null> {
  const raw = await stateGet(KEY_DOWNLOAD_STATE);
  if (!raw) return null;
  try {
    return JSON.parse(raw) as BootstrapDownloadState;
  } catch {
    return null;
  }
}

export async function clearDownloadState(): Promise<void> {
  await stateRemove(KEY_DOWNLOAD_STATE);
}

// ── Telemetry Helper ───────────────────────────────────────────────

async function reportEvent(
  opts: BootstrapInstallOptions,
  state: BootstrapDownloadState,
): Promise<void> {
  try {
    await logBootstrapInstallEvent({
      pairing_code: opts.pairingCode,
      device_id: opts.deviceId,
      platform: opts.platform,
      artifact_id: state.artifactId,
      status: state.status,
      error_message: state.error ?? undefined,
      progress_pct: state.progress,
      bytes_downloaded: state.bytesDownloaded,
      bytes_total: state.bytesTotal,
      checksum_computed: state.computedChecksum ?? undefined,
      checksum_verified: state.checksumVerified,
      signature_verified: state.signatureVerified,
      metadata: {
        source: 'bootstrap-client',
        version: state.version,
      },
    });
  } catch (err) {
    // Telemetry is best-effort — don't break the install flow
    console.warn('[bootstrap-client] Failed to report install event:', err);
  }
}

// ── Download With Progress ─────────────────────────────────────────

/**
 * Download an artifact file with streaming progress tracking.
 *
 * Uses fetch + ReadableStream which works on both web and Tauri's
 * WebView.  Returns the raw bytes and computed SHA-256 checksum.
 */
async function downloadWithProgress(
  url: string,
  _opts: BootstrapInstallOptions,
  state: BootstrapDownloadState,
  onProgress: BootstrapProgressCallback | undefined,
): Promise<{ bytes: Uint8Array; checksum: string }> {
  const response = await fetch(url);

  if (!response.ok) {
    throw new Error(`Download failed: HTTP ${response.status} ${response.statusText}`);
  }

  const contentLength = parseInt(response.headers.get('content-length') || '0', 10);
  state.bytesTotal = contentLength;

  // If the response body is not a ReadableStream, fall back to arrayBuffer
  if (!response.body) {
    const buf = await response.arrayBuffer();
    const bytes = new Uint8Array(buf);
    const checksum = await sha256Hex(bytes);
    state.bytesDownloaded = bytes.length;
    state.progress = 100;
    return { bytes, checksum };
  }

  // Stream the download for progress reporting
  const reader = response.body.getReader();
  const hasher = new ChunkedHasher();
  let lastReportTime = 0;

  for (; ;) {
    const { done, value } = await reader.read();
    if (done) break;

    hasher.append(value);

    // Update progress
    state.bytesDownloaded = hasher.size;
    if (contentLength > 0) {
      state.progress = Math.round((hasher.size / contentLength) * 100);
    }

    // Throttle progress callbacks to every 200ms
    const now = Date.now();
    if (now - lastReportTime > 200 && onProgress) {
      lastReportTime = now;
      onProgress({ ...state });
    }
  }

  const checksum = await hasher.finalise();
  const bytes = hasher.getMergedBytes();

  state.bytesDownloaded = bytes.length;
  state.progress = 100;

  return { bytes, checksum };
}

// ── Save File (Native) ────────────────────────────────────────────

/**
 * Save downloaded bytes to the device filesystem.
 *
 * On native (Tauri), writes into the app's data directory via
 * @tauri-apps/plugin-fs. On web, creates an object URL for download.
 *
 * Returns the local file path (native) or object URL (web).
 */
async function saveFile(
  bytes: Uint8Array,
  filename: string,
): Promise<string> {
  if (isTauri()) {
    try {
      const { writeFile, mkdir, BaseDirectory } = await import('@tauri-apps/plugin-fs');

      // Ensure bootstrap directory exists
      await mkdir('bootstrap', { baseDir: BaseDirectory.AppData, recursive: true }).catch(() => {});

      // Tauri's writeFile accepts Uint8Array directly — no base64 needed
      await writeFile(`bootstrap/${filename}`, bytes, { baseDir: BaseDirectory.AppData });

      return `bootstrap/${filename}`;
    } catch (err) {
      console.warn('[bootstrap-client] Filesystem write failed, using blob URL:', err);
      // Fall through to web fallback
    }
  }

  // Web fallback: create a blob URL (useful for the admin simulator)
  const blob = new Blob([bytes as BlobPart], { type: 'application/octet-stream' });
  return URL.createObjectURL(blob);
}

// ── Delete Cached Artifact ─────────────────────────────────────────

/**
 * Delete a previously downloaded artifact from the device filesystem.
 */
export async function deleteCachedArtifact(filename: string): Promise<void> {
  if (isTauri()) {
    try {
      const { remove, BaseDirectory } = await import('@tauri-apps/plugin-fs');
      await remove(`bootstrap/${filename}`, { baseDir: BaseDirectory.AppData });
    } catch {
      // Ignore — file may not exist
    }
  }
}

// ── Main Install Orchestrator ──────────────────────────────────────

/**
 * Run the complete bootstrap artifact install lifecycle:
 *
 * 1. Fetch active artifact metadata from shop
 * 2. Download artifact binary with progress tracking
 * 3. Compute SHA-256 checksum of downloaded bytes
 * 4. Verify checksum + signature against shop record
 * 5. Save verified file to device storage
 * 6. Return file path for native installer handoff
 *
 * Each step reports telemetry back to the shop so the admin dashboard
 * shows real-time progress for each device.
 */
export async function runBootstrapInstall(
  opts: BootstrapInstallOptions,
): Promise<BootstrapInstallResult> {
  const { pairingCode: _pairingCode, deviceId: _deviceId, platform, forceDownload: _forceDownload, onProgress } = opts;

  // ── Step 1: Fetch active artifact ────────────────────────────
  let artifact: BootstrapArtifact;
  try {
    artifact = await getActiveArtifact(platform);
  } catch (err) {
    throw new Error(
      `No active artifact found for platform "${platform}". ` +
      `Register one in the admin panel first.`,
    );
  }

  // Build filename from artifact metadata
  const ext = platform === 'ios' ? 'ipa' : platform === 'android' ? 'apk' : 'bin';
  const filename = `weirdpart-${platform}-${artifact.version}.${ext}`;

  // Initialise download state
  const state: BootstrapDownloadState = {
    artifactId: artifact.id,
    platform,
    version: artifact.version,
    downloadUrl: artifact.download_url,
    expectedChecksum: artifact.checksum_sha256,
    status: 'requested',
    progress: 0,
    bytesDownloaded: 0,
    bytesTotal: 0,
    computedChecksum: null,
    checksumVerified: false,
    signatureVerified: null,
    filePath: null,
    error: null,
    startedAt: new Date().toISOString(),
    completedAt: null,
  };

  // ── Report: requested ────────────────────────────────────────
  await saveDownloadState(state);
  onProgress?.({ ...state });
  await reportEvent(opts, state);

  try {
    // ── Step 2: Download with progress ─────────────────────────
    state.status = 'downloading';
    await saveDownloadState(state);
    onProgress?.({ ...state });
    await reportEvent(opts, state);

    const { bytes, checksum } = await downloadWithProgress(
      artifact.download_url,
      opts,
      state,
      onProgress,
    );

    // ── Report: downloaded ─────────────────────────────────────
    state.status = 'downloaded';
    state.computedChecksum = checksum;
    await saveDownloadState(state);
    onProgress?.({ ...state });
    await reportEvent(opts, state);

    // ── Step 3: Client-side checksum verification ──────────────
    state.status = 'verifying';
    onProgress?.({ ...state });
    await reportEvent(opts, state);

    // Local comparison first (fast, offline-capable)
    const localMatch =
      checksum.toLowerCase() === artifact.checksum_sha256.toLowerCase();

    if (!localMatch) {
      state.checksumVerified = false;
      state.status = 'failed';
      state.error = `Checksum mismatch: expected ${artifact.checksum_sha256}, got ${checksum}`;
      state.completedAt = new Date().toISOString();
      await saveDownloadState(state);
      onProgress?.({ ...state });
      await reportEvent(opts, state);
      return { success: false, state, artifact };
    }

    // ── Step 4: Server-side verification ───────────────────────
    try {
      const verifyResult = await verifyArtifact({
        artifact_id: artifact.id,
        client_checksum_sha256: checksum,
      });

      state.checksumVerified = verifyResult.checksum_match;
      state.signatureVerified = verifyResult.signature_valid;

      if (!verifyResult.valid) {
        state.status = 'failed';
        state.error = `Server verification failed: ${verifyResult.detail}`;
        state.completedAt = new Date().toISOString();
        await saveDownloadState(state);
        onProgress?.({ ...state });
        await reportEvent(opts, state);
        return { success: false, state, artifact };
      }
    } catch (err) {
      // Server unreachable — but local checksum matched, proceed with warning
      console.warn(
        '[bootstrap-client] Server verification unavailable, proceeding with local checksum:',
        err,
      );
      state.checksumVerified = localMatch;
      state.signatureVerified = null;
    }

    // ── Report: verified ───────────────────────────────────────
    state.status = 'verified';
    await saveDownloadState(state);
    onProgress?.({ ...state });
    await reportEvent(opts, state);

    // ── Step 5: Save to device storage ─────────────────────────
    state.status = 'installing';
    onProgress?.({ ...state });
    await reportEvent(opts, state);

    const filePath = await saveFile(bytes, filename);
    state.filePath = filePath;

    // ── Report: installed ──────────────────────────────────────
    state.status = 'installed';
    state.completedAt = new Date().toISOString();
    await saveDownloadState(state);
    onProgress?.({ ...state });
    await reportEvent(opts, state);

    return { success: true, state, artifact };

  } catch (err) {
    // ── Handle any unexpected error ────────────────────────────
    state.status = 'failed';
    state.error = err instanceof Error ? err.message : String(err);
    state.completedAt = new Date().toISOString();
    await saveDownloadState(state);
    onProgress?.({ ...state });
    await reportEvent(opts, state);
    return { success: false, state, artifact };
  }
}

// ── Resume / Retry ─────────────────────────────────────────────────

/**
 * Check if there's a previously interrupted download that can be retried.
 *
 * Returns the saved state if it's in a retryable status (downloading,
 * downloaded, verifying). Returns null if no state exists or it's
 * already completed.
 */
export async function getRetryableDownload(): Promise<BootstrapDownloadState | null> {
  const state = await getDownloadState();
  if (!state) return null;

  const retryableStatuses: InstallStatus[] = [
    'requested',
    'downloading',
    'downloaded',
    'verifying',
  ];

  if (retryableStatuses.includes(state.status)) {
    return state;
  }

  return null;
}

/**
 * Get a human-readable label for each install status.
 */
export function getStatusLabel(status: InstallStatus): string {
  switch (status) {
    case 'requested': return 'Preparing download…';
    case 'downloading': return 'Downloading…';
    case 'downloaded': return 'Download complete';
    case 'verifying': return 'Verifying integrity…';
    case 'verified': return 'Verified ✓';
    case 'installing': return 'Installing…';
    case 'installed': return 'Installed ✓';
    case 'failed': return 'Failed';
    default: return status;
  }
}

/**
 * Get a colour variant for each install status (for Badge/UI display).
 */
export function getStatusVariant(
  status: InstallStatus,
): 'success' | 'warning' | 'danger' | 'info' | 'neutral' {
  switch (status) {
    case 'installed':
    case 'verified': return 'success';
    case 'failed': return 'danger';
    case 'downloading':
    case 'verifying':
    case 'installing': return 'warning';
    case 'downloaded': return 'info';
    default: return 'neutral';
  }
}
