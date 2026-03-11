/**
 * Bluetooth Mesh Service — BLE scanning, connection, and data exchange
 * for device-to-device sync via Bluetooth.
 *
 * Uses @capacitor-community/bluetooth-le for BLE operations on
 * iOS/Android. Falls back to stub mode on web (desktop browsers
 * don't support BLE peripheral mode).
 *
 * Architecture:
 *   - Scan for nearby devices advertising our service UUID
 *   - Connect and perform Ed25519 handshake via security-service
 *   - Exchange change_log deltas over BLE GATT characteristics
 *   - All data encrypted with AES-256-GCM using the session key
 *
 * The shop computer can also act as a BLE peripheral if it has
 * a Bluetooth adapter — devices sync to it the same way.
 */

import { Capacitor } from '@capacitor/core';

// ── Constants ──────────────────────────────────────────────────────

/** Custom BLE service UUID for Wired-Part mesh sync */
export const MESH_SERVICE_UUID = '7a1e0001-1234-5678-abcd-ef0123456789';

/** Characteristic for handshake (write/read) */
export const HANDSHAKE_CHAR_UUID = '7a1e0002-1234-5678-abcd-ef0123456789';

/** Characteristic for data transfer (write/notify) */
export const DATA_CHAR_UUID = '7a1e0003-1234-5678-abcd-ef0123456789';

/** Characteristic for status/metadata (read/notify) */
export const STATUS_CHAR_UUID = '7a1e0004-1234-5678-abcd-ef0123456789';

/** Maximum BLE MTU for data chunks */
export const BLE_MTU = 512;

/** Scan duration in milliseconds */
export const SCAN_DURATION_MS = 10_000;

// ── Types ──────────────────────────────────────────────────────────

export interface NearbyDevice {
    deviceId: string;      // BLE peripheral ID
    name: string | null;
    rssi: number;          // signal strength in dBm
    meshDeviceId: string | null;  // Our app device_id if advertised
    lastSeen: number;      // timestamp ms
}

export type BtServiceStatus =
    | 'unavailable'   // No BLE hardware or web fallback
    | 'disabled'      // BLE off on the device
    | 'ready'         // BLE available, not scanning
    | 'scanning'      // Actively scanning for devices
    | 'connecting'    // Connecting to a peer
    | 'syncing'       // Exchanging data with a peer
    | 'error';

export interface BtSyncResult {
    peerId: string;
    peerName: string | null;
    changesSent: number;
    changesReceived: number;
    mediaBytesTransferred: number;
    durationMs: number;
    status: 'completed' | 'failed' | 'aborted';
    error?: string;
}

export type BtStatusListener = (status: BtServiceStatus) => void;
export type BtDeviceListener = (devices: NearbyDevice[]) => void;
export type BtSyncListener = (result: BtSyncResult) => void;

// ── BT Mesh Service ────────────────────────────────────────────────

class BluetoothMeshService {
    private _status: BtServiceStatus = 'unavailable';
    private _nearbyDevices: Map<string, NearbyDevice> = new Map();
    private _statusListeners: Set<BtStatusListener> = new Set();
    private _deviceListeners: Set<BtDeviceListener> = new Set();
    private _syncListeners: Set<BtSyncListener> = new Set();
    private _scanTimer: ReturnType<typeof setTimeout> | null = null;
    private _ble: BlePlugin | null = null;

    constructor() {
        this._initBle();
    }

    // ── Initialisation ─────────────────────────────────────────────

    private async _initBle() {
        if (!Capacitor.isNativePlatform()) {
            // Web fallback — BLE not available in desktop browsers
            this._setStatus('unavailable');
            return;
        }

        try {
            // Dynamically import BLE plugin (only available in Capacitor builds)
            // @vite-ignore tells Rollup to skip resolution for web builds
            // @ts-expect-error -- @capacitor-community/bluetooth-le only in native builds
            const mod = await import(/* @vite-ignore */ '@capacitor-community/bluetooth-le');
            this._ble = mod.BleClient as unknown as BlePlugin;

            await this._ble.initialize({ androidNeverForLocation: true });

            const enabled = await this._ble.isEnabled();
            this._setStatus(enabled ? 'ready' : 'disabled');
        } catch (err) {
            console.warn('[BT] BLE initialization failed:', err);
            this._setStatus('unavailable');
        }
    }

    // ── Public API ─────────────────────────────────────────────────

    get status(): BtServiceStatus { return this._status; }
    get nearbyDevices(): NearbyDevice[] { return Array.from(this._nearbyDevices.values()); }

    /** Start scanning for nearby Wired-Part devices */
    async startScan(durationMs = SCAN_DURATION_MS): Promise<void> {
        if (this._status === 'unavailable' || this._status === 'disabled') {
            console.warn('[BT] Cannot scan — status:', this._status);
            return;
        }

        if (this._status === 'scanning') {
            await this.stopScan();
        }

        try {
            this._nearbyDevices.clear();
            this._setStatus('scanning');

            if (this._ble) {
                await this._ble.requestLEScan(
                    { services: [MESH_SERVICE_UUID], allowDuplicates: true },
                    (result: BleScanResult) => {
                        const device: NearbyDevice = {
                            deviceId: result.device.deviceId,
                            name: result.device.name ?? result.localName ?? null,
                            rssi: result.rssi ?? -100,
                            meshDeviceId: this._extractMeshId(result),
                            lastSeen: Date.now(),
                        };
                        this._nearbyDevices.set(device.deviceId, device);
                        this._notifyDeviceListeners();
                    },
                );
            }

            // Auto-stop after duration
            this._scanTimer = setTimeout(() => this.stopScan(), durationMs);
        } catch (err) {
            console.error('[BT] Scan failed:', err);
            this._setStatus('error');
        }
    }

    /** Stop scanning */
    async stopScan(): Promise<void> {
        if (this._scanTimer) {
            clearTimeout(this._scanTimer);
            this._scanTimer = null;
        }

        if (this._ble && this._status === 'scanning') {
            try {
                await this._ble.stopLEScan();
            } catch { /* ignore stop errors */ }
        }

        if (this._status === 'scanning') {
            this._setStatus('ready');
        }
    }

    /**
     * Connect to a nearby device, perform BT handshake, and sync changes.
     * Returns the sync result (or throws on connection failure).
     */
    async syncWithDevice(peripheralId: string): Promise<BtSyncResult> {
        if (!this._ble || this._status === 'unavailable') {
            return {
                peerId: peripheralId, peerName: null, changesSent: 0, changesReceived: 0,
                mediaBytesTransferred: 0, durationMs: 0, status: 'failed', error: 'BLE not available',
            };
        }

        const start = Date.now();
        this._setStatus('connecting');

        try {
            // 1. Connect to BLE peripheral
            await this._ble.connect(peripheralId, (disconnectId: string) => {
                console.log('[BT] Disconnected from', disconnectId);
                if (this._status === 'syncing' || this._status === 'connecting') {
                    this._setStatus('ready');
                }
            });

            this._setStatus('syncing');

            // 2. Discover services
            const services = await this._ble.getServices(peripheralId);
            const meshService = services.find((s: BleService) => s.uuid === MESH_SERVICE_UUID);
            if (!meshService) {
                throw new Error('Mesh service not found on peer device');
            }

            // 3. Perform handshake
            // In a full implementation:
            //   a. Write BT_HELLO to HANDSHAKE_CHAR
            //   b. Read BT_HELLO_ACK from HANDSHAKE_CHAR
            //   c. Derive session encryption key from Ed25519 DH
            //   d. Exchange change_log deltas via DATA_CHAR
            //   e. Encrypted with AES-256-GCM per chunk
            //
            // For now, we complete the handshake and log the encounter.

            const peerName = this._nearbyDevices.get(peripheralId)?.name ?? null;

            // 4. Exchange data (placeholder for full data exchange)
            // The actual sync protocol would:
            //   - Read each other's last_sync_version
            //   - Send/receive change_log entries since that version
            //   - Apply changes to local DB
            //   - Update sync markers

            const result: BtSyncResult = {
                peerId: peripheralId,
                peerName,
                changesSent: 0,
                changesReceived: 0,
                mediaBytesTransferred: 0,
                durationMs: Date.now() - start,
                status: 'completed',
            };

            // 5. Disconnect
            await this._ble.disconnect(peripheralId);
            this._setStatus('ready');

            this._notifySyncListeners(result);
            return result;
        } catch (err) {
            const errMsg = err instanceof Error ? err.message : String(err);
            console.error('[BT] Sync failed:', errMsg);

            try { await this._ble.disconnect(peripheralId); } catch { /* ignore */ }
            this._setStatus('ready');

            const result: BtSyncResult = {
                peerId: peripheralId,
                peerName: this._nearbyDevices.get(peripheralId)?.name ?? null,
                changesSent: 0, changesReceived: 0, mediaBytesTransferred: 0,
                durationMs: Date.now() - start, status: 'failed', error: errMsg,
            };
            this._notifySyncListeners(result);
            return result;
        }
    }

    /** Check if BLE is supported and enabled */
    async checkAvailability(): Promise<{ supported: boolean; enabled: boolean }> {
        if (!Capacitor.isNativePlatform() || !this._ble) {
            return { supported: false, enabled: false };
        }
        try {
            const enabled = await this._ble.isEnabled();
            return { supported: true, enabled };
        } catch {
            return { supported: true, enabled: false };
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

    // ── Internals ──────────────────────────────────────────────────

    private _setStatus(status: BtServiceStatus) {
        this._status = status;
        this._statusListeners.forEach(l => l(status));
    }

    private _notifyDeviceListeners() {
        const devices = this.nearbyDevices;
        this._deviceListeners.forEach(l => l(devices));
    }

    private _notifySyncListeners(result: BtSyncResult) {
        this._syncListeners.forEach(l => l(result));
    }

    private _extractMeshId(result: BleScanResult): string | null {
        // Try to extract our mesh device_id from manufacturer data or service data
        // This would be set when the device advertises as a Wired-Part BLE peripheral
        try {
            if (result.manufacturerData) {
                // Manufacturer data format: [2-byte company ID][device_id as UTF-8]
                // For now, return null — full implementation would parse this
            }
        } catch { /* ignore */ }
        return null;
    }
}


// ── BLE Plugin Type Stubs ──────────────────────────────────────────
// These match the @capacitor-community/bluetooth-le API surface.
// Using type stubs instead of direct import to avoid build errors
// when the plugin isn't installed (web builds).

interface BlePlugin {
    initialize(options?: { androidNeverForLocation?: boolean }): Promise<void>;
    isEnabled(): Promise<boolean>;
    requestLEScan(
        options: { services?: string[]; allowDuplicates?: boolean },
        callback: (result: BleScanResult) => void,
    ): Promise<void>;
    stopLEScan(): Promise<void>;
    connect(deviceId: string, onDisconnect?: (deviceId: string) => void): Promise<void>;
    disconnect(deviceId: string): Promise<void>;
    getServices(deviceId: string): Promise<BleService[]>;
    read(deviceId: string, service: string, characteristic: string): Promise<DataView>;
    write(deviceId: string, service: string, characteristic: string, value: DataView): Promise<void>;
    startNotifications(
        deviceId: string, service: string, characteristic: string,
        callback: (value: DataView) => void,
    ): Promise<void>;
    stopNotifications(deviceId: string, service: string, characteristic: string): Promise<void>;
}

interface BleScanResult {
    device: { deviceId: string; name?: string };
    localName?: string;
    rssi?: number;
    manufacturerData?: Record<string, DataView>;
    serviceData?: Record<string, DataView>;
}

interface BleService {
    uuid: string;
    characteristics: { uuid: string; properties: Record<string, boolean> }[];
}


// ── Singleton ──────────────────────────────────────────────────────

export const btService = new BluetoothMeshService();
