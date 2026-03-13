/**
 * Local Relay Service — peer-to-peer data relay for native devices.
 *
 * Manages the device-side of the P2P relay protocol:
 * 1. Maintain a relay manifest of undelivered data this device carries
 * 2. Prepare relay packages for peer transfer (BT/LAN)
 * 3. Accept incoming relay packages from peers
 * 4. Track delivery receipts and purge confirmed data
 * 5. Handle relay chain tracking for multi-hop scenarios
 *
 * On web (desktop browser), this is a no-op — browsers always talk
 * directly to the shop server over LAN.
 *
 * Architecture:
 * - Relay manifests are updated after each sync cycle
 * - Packages are created when BT handshake completes (via security-service)
 * - Receipts are fetched during shop sync and trigger local purge
 */

// ── Constants ──────────────────────────────────────────────────────

const RELAY_PREFIX = 'wp_relay_';
const KEY_PENDING_CHANGES = `${RELAY_PREFIX}pending_changes`;
const KEY_PENDING_MEDIA = `${RELAY_PREFIX}pending_media`;
const KEY_MANIFEST = `${RELAY_PREFIX}manifest`;
const KEY_RELAY_QUEUE = `${RELAY_PREFIX}outbound_queue`;

// ── Types ──────────────────────────────────────────────────────────

export interface LocalRelayManifest {
  deviceId: string;
  pendingChangeCount: number;
  pendingMediaCount: number;
  changeHashes: string[];
  mediaHashes: string[];
  originDeviceIds: string[];
  updatedAt: string;
}

export interface RelayQueueItem {
  id: string;
  originDeviceId: string;
  changes: Record<string, unknown>[];
  mediaBlobs?: string[];       // Base64 or file references
  createdAt: string;
  deliveredToShop: boolean;
  relayedToPeers: string[];    // Device IDs that received this
}

export interface RelayPackageLocal {
  senderId: string;
  receiverId: string;
  originDeviceId: string;
  changeCount: number;
  mediaCount: number;
  packageHash: string;
  changes: Record<string, unknown>[];
}

// ── Helpers ────────────────────────────────────────────────────────

function relaySet(key: string, value: string): void {
  localStorage.setItem(key, value);
}

function relayGet(key: string): string | null {
  return localStorage.getItem(key);
}

function relayRemove(key: string): void {
  localStorage.removeItem(key);
}

// ── Simple hash for relay dedup ────────────────────────────────────

async function hashPayload(payload: string): Promise<string> {
  if (typeof crypto !== 'undefined' && crypto.subtle) {
    const buf = new TextEncoder().encode(payload);
    const hashBuf = await crypto.subtle.digest('SHA-256', buf);
    return Array.from(new Uint8Array(hashBuf))
      .map(b => b.toString(16).padStart(2, '0'))
      .join('');
  }
  // Fallback: simple string hash
  let h = 0;
  for (let i = 0; i < payload.length; i++) {
    h = ((h << 5) - h + payload.charCodeAt(i)) | 0;
  }
  return Math.abs(h).toString(16);
}

// ── Relay Queue Management ─────────────────────────────────────────

/**
 * Get the current outbound relay queue — data this device is carrying
 * that hasn't been delivered to the shop yet.
 */
export async function getRelayQueue(): Promise<RelayQueueItem[]> {
  const raw = await relayGet(KEY_RELAY_QUEUE);
  if (!raw) return [];
  try {
    return JSON.parse(raw) as RelayQueueItem[];
  } catch {
    return [];
  }
}

/**
 * Add an item to the relay queue. Called when this device generates
 * local changes while offline, or when accepting relayed data from
 * a peer.
 */
export async function addToRelayQueue(item: RelayQueueItem): Promise<void> {
  const queue = await getRelayQueue();
  queue.push(item);
  await relaySet(KEY_RELAY_QUEUE, JSON.stringify(queue));
}

/**
 * Mark items in the relay queue as delivered to the shop.
 * Called after successful sync push or relay delivery.
 */
export async function markDelivered(itemIds: string[]): Promise<void> {
  const queue = await getRelayQueue();
  const idSet = new Set(itemIds);
  const updated = queue.map(q =>
    idSet.has(q.id) ? { ...q, deliveredToShop: true } : q
  );
  await relaySet(KEY_RELAY_QUEUE, JSON.stringify(updated));
}

/**
 * Purge delivered items from the queue. Called after receiving
 * delivery receipts from the shop confirming the data arrived.
 */
export async function purgeDeliveredItems(): Promise<number> {
  const queue = await getRelayQueue();
  const remaining = queue.filter(q => !q.deliveredToShop);
  const purged = queue.length - remaining.length;
  await relaySet(KEY_RELAY_QUEUE, JSON.stringify(remaining));
  return purged;
}

/**
 * Mark a relay queue item as relayed to a peer.
 * The item stays in the queue (still needs shop delivery) but
 * we track which peers received it for dedup.
 */
export async function markRelayedToPeer(
  itemId: string,
  peerDeviceId: string
): Promise<void> {
  const queue = await getRelayQueue();
  const updated = queue.map(q => {
    if (q.id === itemId && !q.relayedToPeers.includes(peerDeviceId)) {
      return { ...q, relayedToPeers: [...q.relayedToPeers, peerDeviceId] };
    }
    return q;
  });
  await relaySet(KEY_RELAY_QUEUE, JSON.stringify(updated));
}

// ── Relay Manifest ─────────────────────────────────────────────────

/**
 * Build and store the current relay manifest from the queue state.
 * Called after every queue mutation so the manifest is always fresh.
 */
export async function refreshManifest(deviceId: string): Promise<LocalRelayManifest> {
  const queue = await getRelayQueue();
  const undelivered = queue.filter(q => !q.deliveredToShop);

  const changeHashes: string[] = [];
  const mediaHashes: string[] = [];
  const originIds = new Set<string>();
  let changeCount = 0;
  let mediaCount = 0;

  for (const item of undelivered) {
    changeCount += item.changes.length;
    mediaCount += (item.mediaBlobs?.length ?? 0);
    originIds.add(item.originDeviceId);

    // Hash each change for dedup
    for (const change of item.changes) {
      const h = await hashPayload(JSON.stringify(change));
      changeHashes.push(h);
    }
    if (item.mediaBlobs) {
      for (const blob of item.mediaBlobs) {
        const h = await hashPayload(blob.substring(0, 256));
        mediaHashes.push(h);
      }
    }
  }

  const manifest: LocalRelayManifest = {
    deviceId,
    pendingChangeCount: changeCount,
    pendingMediaCount: mediaCount,
    changeHashes,
    mediaHashes,
    originDeviceIds: [...originIds],
    updatedAt: new Date().toISOString(),
  };

  await relaySet(KEY_MANIFEST, JSON.stringify(manifest));
  return manifest;
}

/**
 * Get the current locally-stored manifest.
 */
export async function getLocalManifest(): Promise<LocalRelayManifest | null> {
  const raw = await relayGet(KEY_MANIFEST);
  if (!raw) return null;
  try {
    return JSON.parse(raw) as LocalRelayManifest;
  } catch {
    return null;
  }
}

// ── Relay Package Creation ─────────────────────────────────────────

/**
 * Prepare a relay package for a peer device.
 *
 * Selects undelivered data that the peer doesn't already have
 * (based on their manifest's change hashes) and bundles it.
 */
export async function prepareRelayPackage(
  thisDeviceId: string,
  peerDeviceId: string,
  peerHashes: string[] = []
): Promise<RelayPackageLocal | null> {
  const queue = await getRelayQueue();
  const undelivered = queue.filter(q => !q.deliveredToShop);

  if (undelivered.length === 0) return null;

  const peerHashSet = new Set(peerHashes);
  const changes: Record<string, unknown>[] = [];
  const originIds = new Set<string>();

  for (const item of undelivered) {
    // Skip items the peer already has (by hash dedup)
    for (const change of item.changes) {
      const h = await hashPayload(JSON.stringify(change));
      if (!peerHashSet.has(h)) {
        changes.push(change);
      }
    }
    originIds.add(item.originDeviceId);
  }

  if (changes.length === 0) return null;

  const packagePayload = JSON.stringify(changes);
  const packageHash = await hashPayload(packagePayload);

  return {
    senderId: thisDeviceId,
    receiverId: peerDeviceId,
    originDeviceId: [...originIds][0] ?? thisDeviceId,
    changeCount: changes.length,
    mediaCount: 0,
    packageHash,
    changes,
  };
}

/**
 * Accept an incoming relay package from a peer.
 *
 * Adds the relayed changes to our own queue so we can deliver
 * them to the shop (or relay further).
 */
export async function acceptRelayPackage(
  pkg: RelayPackageLocal
): Promise<void> {
  const item: RelayQueueItem = {
    id: `relay_${Date.now()}_${Math.random().toString(36).slice(2, 8)}`,
    originDeviceId: pkg.originDeviceId,
    changes: pkg.changes,
    createdAt: new Date().toISOString(),
    deliveredToShop: false,
    relayedToPeers: [pkg.senderId],  // Already have it from sender
  };

  await addToRelayQueue(item);
}

// ── Cleanup ────────────────────────────────────────────────────────

/**
 * Clear all relay data. Called during device reset or security wipe.
 */
export async function clearRelayData(): Promise<void> {
  await relayRemove(KEY_PENDING_CHANGES);
  await relayRemove(KEY_PENDING_MEDIA);
  await relayRemove(KEY_MANIFEST);
  await relayRemove(KEY_RELAY_QUEUE);
}

/**
 * Get relay queue statistics for display.
 */
export async function getRelayQueueStats(): Promise<{
  totalItems: number;
  deliveredItems: number;
  pendingItems: number;
  totalChanges: number;
  totalMedia: number;
  uniqueOrigins: number;
}> {
  const queue = await getRelayQueue();
  const delivered = queue.filter(q => q.deliveredToShop);
  const pending = queue.filter(q => !q.deliveredToShop);

  return {
    totalItems: queue.length,
    deliveredItems: delivered.length,
    pendingItems: pending.length,
    totalChanges: pending.reduce((acc, q) => acc + q.changes.length, 0),
    totalMedia: pending.reduce((acc, q) => acc + (q.mediaBlobs?.length ?? 0), 0),
    uniqueOrigins: new Set(pending.map(q => q.originDeviceId)).size,
  };
}
