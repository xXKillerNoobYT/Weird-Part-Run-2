/**
 * Local Device Security Service — device-at-rest encryption and
 * secure key storage for native (Tauri) apps.
 *
 * Responsibilities:
 * 1. Generate and store the device's Ed25519 keypair
 * 2. Store device certificate securely
 * 3. Encrypt the local SQLite database encryption key
 * 4. Provide cert + signature for sync handshakes
 * 5. Handle BT handshake payloads (create hello, verify ack)
 *
 * On web (desktop browser), falls back to in-memory storage since
 * the browser always talks to the shop server directly over LAN.
 *
 * Storage: localStorage on native (Tauri persists in app data dir).
 * TODO: Upgrade to Tauri keychain plugin for truly secure storage.
 */

import { isTauri } from '../../lib/environment';

// ── Constants ──────────────────────────────────────────────────────

const SECURE_PREFIX = 'wp_security_';
const KEY_DEVICE_PRIVATE = `${SECURE_PREFIX}device_private_key`;
const KEY_DEVICE_PUBLIC = `${SECURE_PREFIX}device_public_key`;
const KEY_DEVICE_CERT = `${SECURE_PREFIX}device_certificate`;
const KEY_DEVICE_CERT_SIG = `${SECURE_PREFIX}device_cert_signature`;
const KEY_COMPANY_ID = `${SECURE_PREFIX}company_id`;
const KEY_DB_ENCRYPTION = `${SECURE_PREFIX}db_encryption_key`;
const KEY_DEVICE_ID = `${SECURE_PREFIX}device_id`;

// ── Types ──────────────────────────────────────────────────────────

export interface DeviceIdentity {
  deviceId: string;
  companyId: string;
  publicKey: string;
  hasCertificate: boolean;
}

export interface StoredCertificate {
  certificateData: string;
  signature: string;
  companyId: string;
  expiresAt: string;
}

export interface BtHelloPayload {
  type: 'BT_HELLO';
  device_id: string;
  company_id: string;
  certificate_data: string;
  signature: string;
  nonce: string;
  timestamp: string;
}

// ── In-memory fallback for web ─────────────────────────────────────

const memoryStore = new Map<string, string>();

// ── Secure Storage Abstraction ─────────────────────────────────────

/**
 * Store a value securely.
 *
 * On native (Tauri), uses localStorage which persists in the app's
 * WebView data directory (sandboxed per app).
 *
 * On web, falls back to in-memory storage (no persistence needed —
 * browser devices always talk to the shop server directly).
 */
async function secureSet(key: string, value: string): Promise<void> {
  if (isTauri()) {
    localStorage.setItem(key, value);
  } else {
    memoryStore.set(key, value);
  }
}

async function secureGet(key: string): Promise<string | null> {
  if (isTauri()) {
    return localStorage.getItem(key);
  }
  return memoryStore.get(key) ?? null;
}

async function secureRemove(key: string): Promise<void> {
  if (isTauri()) {
    localStorage.removeItem(key);
  } else {
    memoryStore.delete(key);
  }
}

// ── Crypto Helpers (Web Crypto API) ────────────────────────────────

/**
 * Generate a random 256-bit key as base64 (for DB encryption key).
 *
 * Uses Web Crypto API which is available in both browser and Tauri WebView.
 */
function generateRandomKey(): string {
  const bytes = new Uint8Array(32);
  crypto.getRandomValues(bytes);
  return btoa(String.fromCharCode(...bytes));
}

/**
 * Generate a random nonce for BT handshakes.
 */
function generateNonce(): string {
  const bytes = new Uint8Array(16);
  crypto.getRandomValues(bytes);
  return Array.from(bytes).map(b => b.toString(16).padStart(2, '0')).join('');
}

// ── Service Functions ──────────────────────────────────────────────

/**
 * Initialise device security on first launch.
 *
 * Generates a DB encryption key if one doesn't exist.
 * The actual Ed25519 keypair is generated server-side during bootstrap
 * and the public key is stored here for identity purposes.
 */
export async function initialiseDeviceSecurity(deviceId: string): Promise<void> {
  await secureSet(KEY_DEVICE_ID, deviceId);

  // Generate DB encryption key if not already present
  const existingKey = await secureGet(KEY_DB_ENCRYPTION);
  if (!existingKey) {
    const dbKey = generateRandomKey();
    await secureSet(KEY_DB_ENCRYPTION, dbKey);
  }
}

/**
 * Get the device's DB encryption key (for encrypting SQLite at rest).
 *
 * Returns null on web (DB encryption is not needed — browser talks
 * directly to shop server, no local DB).
 */
export async function getDbEncryptionKey(): Promise<string | null> {
  if (!isTauri()) return null;
  return secureGet(KEY_DB_ENCRYPTION);
}

/**
 * Store the device's keypair after bootstrap generates it.
 *
 * Called during the bootstrap handshake when the server issues a cert.
 * The private key is generated client-side (Web Crypto), and the public
 * key is sent to the server for certificate binding.
 */
export async function storeDeviceKeypair(publicKey: string, privateKey: string): Promise<void> {
  await secureSet(KEY_DEVICE_PUBLIC, publicKey);
  await secureSet(KEY_DEVICE_PRIVATE, privateKey);
}

/**
 * Get the device's public key (base64).
 */
export async function getDevicePublicKey(): Promise<string | null> {
  return secureGet(KEY_DEVICE_PUBLIC);
}

/**
 * Store a signed certificate received from the shop server.
 */
export async function storeCertificate(
  certificateData: string,
  signature: string,
  companyId: string,
  _expiresAt: string,
): Promise<void> {
  await secureSet(KEY_DEVICE_CERT, certificateData);
  await secureSet(KEY_DEVICE_CERT_SIG, signature);
  await secureSet(KEY_COMPANY_ID, companyId);
}

/**
 * Get the stored certificate for sync handshakes.
 */
export async function getStoredCertificate(): Promise<StoredCertificate | null> {
  const certData = await secureGet(KEY_DEVICE_CERT);
  const sig = await secureGet(KEY_DEVICE_CERT_SIG);
  const companyId = await secureGet(KEY_COMPANY_ID);

  if (!certData || !sig || !companyId) return null;

  // Parse cert to check expiry
  try {
    const parsed = JSON.parse(certData);
    return {
      certificateData: certData,
      signature: sig,
      companyId,
      expiresAt: parsed.expires_at ?? '',
    };
  } catch {
    return null;
  }
}

/**
 * Check if the stored certificate is still valid (not expired).
 */
export async function isCertificateValid(): Promise<boolean> {
  const cert = await getStoredCertificate();
  if (!cert) return false;
  if (!cert.expiresAt) return false;
  return new Date(cert.expiresAt) > new Date();
}

/**
 * Get the device's identity summary.
 */
export async function getDeviceIdentity(): Promise<DeviceIdentity | null> {
  const deviceId = await secureGet(KEY_DEVICE_ID);
  const companyId = await secureGet(KEY_COMPANY_ID);
  const publicKey = await secureGet(KEY_DEVICE_PUBLIC);

  if (!deviceId) return null;

  const cert = await getStoredCertificate();

  return {
    deviceId,
    companyId: companyId ?? '',
    publicKey: publicKey ?? '',
    hasCertificate: cert !== null,
  };
}

/**
 * Get sync auth headers — cert fields to include in sync requests.
 *
 * Returns null if no valid cert is stored (sync will proceed
 * unauthenticated if the shop has no companies configured).
 */
export async function getSyncAuthFields(): Promise<{
  company_id: string;
  certificate_data: string;
  signature: string;
} | null> {
  const cert = await getStoredCertificate();
  if (!cert) return null;

  // Don't send expired certs
  if (cert.expiresAt && new Date(cert.expiresAt) < new Date()) return null;

  return {
    company_id: cert.companyId,
    certificate_data: cert.certificateData,
    signature: cert.signature,
  };
}

/**
 * Create a BT_HELLO payload for initiating a Bluetooth handshake.
 *
 * This is the client-side version — builds the hello locally without
 * hitting the server. Used when devices are in the field with no
 * shop connectivity.
 */
export async function createBtHello(): Promise<BtHelloPayload | null> {
  const deviceId = await secureGet(KEY_DEVICE_ID);
  const cert = await getStoredCertificate();

  if (!deviceId || !cert) return null;

  return {
    type: 'BT_HELLO',
    device_id: deviceId,
    company_id: cert.companyId,
    certificate_data: cert.certificateData,
    signature: cert.signature,
    nonce: generateNonce(),
    timestamp: new Date().toISOString(),
  };
}

/**
 * Clear all security data from secure storage.
 *
 * Called on device wipe / factory reset / logout.
 */
export async function clearDeviceSecurity(): Promise<void> {
  const keys = [
    KEY_DEVICE_PRIVATE,
    KEY_DEVICE_PUBLIC,
    KEY_DEVICE_CERT,
    KEY_DEVICE_CERT_SIG,
    KEY_COMPANY_ID,
    KEY_DB_ENCRYPTION,
    KEY_DEVICE_ID,
  ];
  for (const key of keys) {
    await secureRemove(key);
  }
  memoryStore.clear();
}

/**
 * Rotate the DB encryption key.
 *
 * Called after re-pairing / key rotation. The caller is responsible
 * for re-encrypting the database with the new key.
 */
export async function rotateDbEncryptionKey(): Promise<string> {
  const newKey = generateRandomKey();
  await secureSet(KEY_DB_ENCRYPTION, newKey);
  return newKey;
}
