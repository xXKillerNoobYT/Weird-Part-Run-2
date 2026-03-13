/**
 * Bluetooth / Multipeer Service — device discovery and data exchange
 * for device-to-device sync via Apple Multipeer Connectivity.
 *
 * On macOS/iOS: Uses Apple Multipeer Connectivity (via Tauri IPC → Rust FFI
 * → ObjC bridge) which automatically combines BLE + Wi-Fi for best speed.
 * Up to 5 MB/s when Wi-Fi Direct kicks in.
 *
 * On other platforms (Windows/Linux): Multipeer is unavailable. P2P sync
 * falls back to Wi-Fi LAN only (via the Phase 4 mDNS + axum sync server).
 *
 * On web (desktop browser): Fully unavailable — no BT access.
 *
 * Architecture:
 *   Tauri IPC commands (invoke) → Rust multipeer.rs → ObjC MultipeerBridge
 *   TS polls Rust side for peer list and received messages on intervals.
 *   Sync data flows through peer-manager.ts, not directly through this service.
 *
 * This service handles:
 *   - Starting/stopping Multipeer advertising + browsing
 *   - Polling for discovered peers
 *   - Polling for received messages (queued by ObjC)
 *   - Sending data to a connected peer
 *   - Status + event notifications to UI
 */

import { isTauri } from '../../lib/environment';

// ── Types ──────────────────────────────────────────────────────────

/** A peer discovered via Multipeer Connectivity */
export interface NearbyDevice {
  deviceId: string;       // WiredPart device UUID
  name: string | null;    // Human-readable name ("Shop Computer")
  companyId: string;      // Company ID for same-company filtering
  state: 'found' | 'connecting' | 'connected';
  lastSeen: number;       // timestamp ms (local)
}

export type BtServiceStatus =
  | 'unavailable'   // Not on Apple platform or web fallback
  | 'ready'         // Multipeer available, not running
  | 'running'       // Advertising + browsing for peers
  | 'syncing'       // Actively sending/receiving data with a peer
  | 'error';

export interface BtSyncResult {
  peerId: string;
  peerName: string | null;
  changesSent: number;
  changesReceived: number;
  durationMs: number;
  status: 'completed' | 'failed' | 'aborted';
  error?: string;
}

/** Message received from a peer via Multipeer */
export interface ReceivedMessage {
  from_device_id: string;
  data: string;         // UTF-8 JSON payload
  received_at: string;  // ISO 8601 timestamp
}

export type BtStatusListener = (status: BtServiceStatus) => void;
export type BtDeviceListener = (devices: NearbyDevice[]) => void;
export type BtSyncListener = (result: BtSyncResult) => void;

// ── Tauri IPC Helper ──────────────────────────────────────────────

async function invoke<T>(cmd: string, args?: Record<string, unknown>): Promise<T> {
  const { invoke: tauriInvoke } = await import('@tauri-apps/api/core');
  return tauriInvoke<T>(cmd, args);
}

// ── Multipeer Peer Type (matches Rust MultipeerPeer struct) ───────

interface MultipeerPeer {
  device_id: string;
  device_name: string;
  company_id: string;
  state: string;  // "found" | "connecting" | "connected"
}

// ── BT Mesh Service ────────────────────────────────────────────────

class BluetoothMeshService {
  private _status: BtServiceStatus = 'unavailable';
  private _nearbyDevices: Map<string, NearbyDevice> = new Map();
  private _statusListeners: Set<BtStatusListener> = new Set();
  private _deviceListeners: Set<BtDeviceListener> = new Set();
  private _syncListeners: Set<BtSyncListener> = new Set();
  private _peerPollTimer: ReturnType<typeof setInterval> | null = null;
  private _messagePollTimer: ReturnType<typeof setInterval> | null = null;

  constructor() {
    this._checkAvailability();
  }

  // ── Initialisation ─────────────────────────────────────────────

  private async _checkAvailability() {
    if (!isTauri()) {
      // Web fallback — Multipeer not available in desktop browsers
      this._setStatus('unavailable');
      return;
    }

    // Check if we're on an Apple platform where Multipeer is available
    try {
      const running = await invoke<boolean>('multipeer_is_running');
      // If the command returns without error, Multipeer is available
      this._setStatus(running ? 'running' : 'ready');
    } catch {
      // Command errored — likely not on macOS/iOS (non-Apple stub returns error)
      this._setStatus('unavailable');
    }
  }

  // ── Public API ─────────────────────────────────────────────────

  get status(): BtServiceStatus { return this._status; }
  get nearbyDevices(): NearbyDevice[] { return Array.from(this._nearbyDevices.values()); }

  /**
   * Start Multipeer advertising + browsing.
   * The ObjC layer handles auto-invite and auto-accept for same-company peers.
   */
  async start(deviceId: string, deviceName: string, companyId: string): Promise<boolean> {
    if (this._status === 'unavailable') {
      console.warn('[BT] Multipeer not available on this platform');
      return false;
    }

    if (this._status === 'running') {
      console.log('[BT] Multipeer already running');
      return true;
    }

    try {
      const ok = await invoke<boolean>('start_multipeer', {
        device_id: deviceId,
        device_name: deviceName,
        company_id: companyId,
      });

      if (ok) {
        this._setStatus('running');
        this._startPolling();
        console.log('[BT] Multipeer started — advertising + browsing');
      } else {
        this._setStatus('error');
        console.error('[BT] Multipeer start returned false');
      }

      return ok;
    } catch (err) {
      console.error('[BT] Failed to start Multipeer:', err);
      this._setStatus('error');
      return false;
    }
  }

  /** Stop Multipeer advertising + browsing. Disconnects all peers. */
  async stop(): Promise<void> {
    this._stopPolling();
    this._nearbyDevices.clear();

    if (this._status === 'unavailable') return;

    try {
      await invoke('stop_multipeer');
    } catch {
      // Ignore stop errors
    }

    this._setStatus('ready');
    this._notifyDeviceListeners();
    console.log('[BT] Multipeer stopped');
  }

  /**
   * Send data to a specific connected peer.
   * @param peerDeviceId — the WiredPart device_id of the target peer
   * @param jsonPayload — UTF-8 JSON string to send
   */
  async sendToPeer(peerDeviceId: string, jsonPayload: string): Promise<boolean> {
    if (this._status !== 'running' && this._status !== 'syncing') {
      return false;
    }

    try {
      await invoke('multipeer_send', {
        peer_device_id: peerDeviceId,
        data: jsonPayload,
      });
      return true;
    } catch (err) {
      console.error(`[BT] Send to ${peerDeviceId} failed:`, err);
      return false;
    }
  }

  /**
   * Pop the next received message from the ObjC queue.
   * Returns null if no messages pending.
   */
  async popReceived(): Promise<ReceivedMessage | null> {
    if (this._status === 'unavailable') return null;

    try {
      const msg = await invoke<ReceivedMessage | null>('multipeer_pop_received');
      return msg ?? null;
    } catch {
      return null;
    }
  }

  /** Get count of messages waiting in the receive queue */
  async getReceiveCount(): Promise<number> {
    if (this._status === 'unavailable') return 0;
    try {
      return await invoke<number>('multipeer_receive_count');
    } catch {
      return 0;
    }
  }

  /** Check if Multipeer is currently running */
  async isRunning(): Promise<boolean> {
    if (this._status === 'unavailable') return false;
    try {
      return await invoke<boolean>('multipeer_is_running');
    } catch {
      return false;
    }
  }

  /** Get list of connected peers (state === 'connected') */
  getConnectedPeers(): NearbyDevice[] {
    return this.nearbyDevices.filter(d => d.state === 'connected');
  }

  // ── Legacy API Compatibility ──────────────────────────────────
  // These methods keep the same surface as the old BLE-based API
  // so existing consumers (peer-manager.ts, SyncStatusIndicator)
  // don't need changes.

  /** @deprecated Use start() instead */
  async startScan(): Promise<void> {
    // No-op if already running — start() should be called explicitly
    // with device identity parameters
    console.warn('[BT] startScan() is deprecated — use start(deviceId, name, companyId)');
  }

  /** @deprecated Use stop() instead */
  async stopScan(): Promise<void> {
    await this.stop();
  }

  /** Check availability — always returns true on Apple, false elsewhere */
  async checkAvailability(): Promise<{ supported: boolean; enabled: boolean }> {
    if (!isTauri()) return { supported: false, enabled: false };

    try {
      // If invoke succeeds, Multipeer is available
      await invoke<boolean>('multipeer_is_running');
      return { supported: true, enabled: true };
    } catch {
      return { supported: false, enabled: false };
    }
  }

  // ── Event Listeners ────────────────────────────────────────────

  onStatusChange(listener: BtStatusListener): () => void {
    this._statusListeners.add(listener);
    return () => { this._statusListeners.delete(listener); };
  }

  onDevicesUpdated(listener: BtDeviceListener): () => void {
    this._deviceListeners.add(listener);
    return () => { this._deviceListeners.delete(listener); };
  }

  onSyncComplete(listener: BtSyncListener): () => void {
    this._syncListeners.add(listener);
    return () => { this._syncListeners.delete(listener); };
  }

  // ── Polling ──────────────────────────────────────────────────────

  private _startPolling() {
    this._stopPolling();

    // Poll for peer list every 5 seconds
    this._peerPollTimer = setInterval(() => this._pollPeers(), 5_000);

    // Poll for received messages every 3 seconds
    this._messagePollTimer = setInterval(() => this._pollMessages(), 3_000);

    // Immediate first poll
    this._pollPeers();
  }

  private _stopPolling() {
    if (this._peerPollTimer) {
      clearInterval(this._peerPollTimer);
      this._peerPollTimer = null;
    }
    if (this._messagePollTimer) {
      clearInterval(this._messagePollTimer);
      this._messagePollTimer = null;
    }
  }

  /** Poll the Rust/ObjC side for current peer list */
  private async _pollPeers() {
    try {
      const peers = await invoke<MultipeerPeer[]>('get_multipeer_peers');
      const now = Date.now();

      // Update our device map
      const currentIds = new Set<string>();
      for (const p of peers) {
        currentIds.add(p.device_id);
        const existing = this._nearbyDevices.get(p.device_id);
        this._nearbyDevices.set(p.device_id, {
          deviceId: p.device_id,
          name: p.device_name,
          companyId: p.company_id,
          state: p.state as NearbyDevice['state'],
          lastSeen: existing?.lastSeen ?? now,
        });
      }

      // Remove peers that disappeared
      for (const id of this._nearbyDevices.keys()) {
        if (!currentIds.has(id)) {
          this._nearbyDevices.delete(id);
        }
      }

      this._notifyDeviceListeners();
    } catch (err) {
      console.error('[BT] Peer poll error:', err);
    }
  }

  /**
   * Poll for received messages and push them into the Rust sync inbox.
   *
   * Multipeer messages arrive on the TS side (via ObjC → Rust → TS polling).
   * We parse the JSON payload (array of ChangeEntry objects) and push them
   * into the same Rust inbox that the LAN sync server uses.
   *
   * The peer-manager already polls the inbox every 5 seconds via
   * processInbox() → applyPeerChanges(), so we don't need a separate
   * code path — just deposit Multipeer messages into the Rust inbox.
   */
  private async _pollMessages() {
    try {
      const count = await this.getReceiveCount();
      if (count === 0) return;

      // Pop all messages and push them to the Rust sync inbox
      for (let i = 0; i < count; i++) {
        const msg = await this.popReceived();
        if (!msg) break;

        try {
          // The ObjC bridge base64-encodes received bytes — decode first
          const jsonStr = atob(msg.data);
          // Parse the JSON payload — it should be an array of sync changes
          const changes = JSON.parse(jsonStr);
          if (Array.isArray(changes) && changes.length > 0) {
            // Push changes to the Rust inbox via IPC — peer-manager's
            // processInbox() will pick them up on its next poll cycle
            const pushed = await invoke<number>('push_to_sync_inbox', { changes });
            console.log(
              `[BT] Deposited ${pushed} changes from ${msg.from_device_id} into sync inbox`,
            );
          }
        } catch (parseErr) {
          console.error('[BT] Failed to parse received message:', parseErr);
        }
      }
    } catch (err) {
      console.error('[BT] Message poll error:', err);
    }
  }

  // ── Internals ──────────────────────────────────────────────────

  private _setStatus(status: BtServiceStatus) {
    this._status = status;
    this._statusListeners.forEach(l => l(status));
  }

  private _notifyDeviceListeners() {
    const devices = this.nearbyDevices;
    this._deviceListeners.forEach(l => l(devices));
  }

  _notifySyncListeners(result: BtSyncResult) {
    this._syncListeners.forEach(l => l(result));
  }
}


// ── Singleton ──────────────────────────────────────────────────────

export const btService = new BluetoothMeshService();
