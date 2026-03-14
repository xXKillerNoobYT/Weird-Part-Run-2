/**
 * Peer Manager — discovers and syncs with other WiredPart devices.
 *
 * Dual discovery: mDNS (LAN via axum) + Apple Multipeer Connectivity (BT+Wi-Fi).
 * Both transports feed into the same peer list and sync flow.
 *
 * 1. Start the Rust sync server + mDNS (via Tauri IPC)
 * 2. Start Multipeer advertising + browsing (on Apple platforms)
 * 3. Poll for discovered peers from both sources
 * 4. Initiate sync with each peer sequentially
 *    - LAN peers: HTTP push/pull via the axum sync server
 *    - Multipeer peers: JSON payload via Multipeer send/receive
 * 5. Process received changes from both the Rust inbox and Multipeer queue
 *
 * Sync order: Office computer first (if present), then by
 * least-recently-synced device.
 */

import { isTauri } from '../lib/environment';

// ── Types ────────────────────────────────────────────────────────────

export interface DiscoveredPeer {
  device_id: string;
  device_name: string;
  company_id: string;
  host: string;
  port: number;
  version: string;
  discovered_at: string;
  /** Transport used to reach this peer */
  transport: 'lan' | 'multipeer';
  /** Multipeer connection state (only for transport === 'multipeer') */
  multipeer_state?: 'found' | 'connecting' | 'connected';
}

export interface PeerSyncResult {
  peer_device_id: string;
  peer_name: string;
  pushed: number;
  pulled: number;
  success: boolean;
  error?: string;
  synced_at: string;
}

export interface PeerManagerState {
  running: boolean;
  sync_port: number;
  peers: DiscoveredPeer[];
  last_peer_syncs: Record<string, PeerSyncResult>;
  syncing_with: string | null; // device_id of peer currently syncing with
}

// ── State ────────────────────────────────────────────────────────────

let state: PeerManagerState = {
  running: false,
  sync_port: 0,
  peers: [],
  last_peer_syncs: {},
  syncing_with: null,
};

const listeners: Set<(state: PeerManagerState) => void> = new Set();
let peerPollInterval: ReturnType<typeof setInterval> | null = null;
let syncPollInterval: ReturnType<typeof setInterval> | null = null;

export function getPeerManagerState(): PeerManagerState {
  return { ...state };
}

export function onPeerManagerStateChange(
  fn: (state: PeerManagerState) => void,
): () => void {
  listeners.add(fn);
  return () => listeners.delete(fn);
}

function updateState(partial: Partial<PeerManagerState>) {
  state = { ...state, ...partial };
  for (const fn of listeners) {
    try { fn(state); } catch { /* ignore */ }
  }
}

// ── Tauri IPC Wrappers ───────────────────────────────────────────────

async function invoke<T>(cmd: string, args?: Record<string, unknown>): Promise<T> {
  const { invoke: tauriInvoke } = await import('@tauri-apps/api/core');
  return tauriInvoke<T>(cmd, args);
}

// ── Initialization ───────────────────────────────────────────────────

/**
 * Start the P2P sync system. Call after user authenticates.
 *
 * @param deviceId   — this device's UUID
 * @param deviceName — human-readable name (e.g. "Shop Computer")
 * @param companyId  — company identifier for same-company filtering
 */
export async function startPeerSync(
  deviceId: string,
  deviceName: string,
  companyId: string,
): Promise<void> {
  if (!isTauri() || state.running) return;

  try {
    // Start the Rust sync server + mDNS (LAN discovery)
    const port = await invoke<number>('start_p2p_sync', {
      device_id: deviceId,
      device_name: deviceName,
      company_id: companyId,
    });

    updateState({ running: true, sync_port: port });
    console.log(`[peer-manager] P2P sync active on port ${port}`);

    // Send company public key to Rust for Ed25519 cert verification (Phase 5)
    try {
      const { getDevicePublicKey: _getDevicePublicKey } = await import('./services/security-service');
      // The company public key is stored in localStorage by the bootstrap process.
      // It's the admin's Ed25519 public key, used to verify device certificates.
      const companyPubKey = localStorage.getItem('wp_security_company_public_key');
      if (companyPubKey) {
        await invoke('set_company_public_key', { public_key_b64: companyPubKey });
        console.log('[peer-manager] Company public key set for Ed25519 verification');
      }
    } catch (err) {
      // Non-critical — falls back to company_id-only auth (Phase 4 compat)
      console.warn('[peer-manager] Could not set company public key:', err);
    }

    // Start Multipeer Connectivity (Apple platforms only)
    try {
      const { btService } = await import('./services/bt-service');
      await btService.start(deviceId, deviceName, companyId);
    } catch (err) {
      // Non-critical — LAN sync still works without Multipeer
      console.warn('[peer-manager] Multipeer not available:', err);
    }

    // Poll for discovered peers every 10 seconds (both mDNS + Multipeer)
    peerPollInterval = setInterval(async () => {
      try {
        await pollAllPeers();
      } catch (err) {
        console.error('[peer-manager] Peer poll error:', err);
      }
    }, 10_000);

    // Check the Rust inbox for received changes every 5 seconds
    syncPollInterval = setInterval(async () => {
      try {
        await processInbox();
      } catch (err) {
        console.error('[peer-manager] Inbox processing error:', err);
      }
    }, 5_000);

    // Do an initial peer poll
    await pollAllPeers();
  } catch (err) {
    console.error('[peer-manager] Failed to start P2P sync:', err);
  }
}

/**
 * Stop the P2P sync system (e.g., on logout)
 */
export async function stopPeerSync(): Promise<void> {
  if (peerPollInterval) {
    clearInterval(peerPollInterval);
    peerPollInterval = null;
  }
  if (syncPollInterval) {
    clearInterval(syncPollInterval);
    syncPollInterval = null;
  }

  // Stop Multipeer
  try {
    const { btService } = await import('./services/bt-service');
    await btService.stop();
  } catch { /* ignore */ }

  updateState({ running: false, sync_port: 0, peers: [], syncing_with: null });
}

// ── Peer Discovery (mDNS + Multipeer) ────────────────────────────────

/**
 * Poll both mDNS (LAN) and Multipeer (BT+Wi-Fi) for peers, then merge
 * into a deduplicated list. If the same device appears in both, prefer
 * the LAN entry (faster transport) but note Multipeer is also available.
 */
async function pollAllPeers(): Promise<void> {
  const merged: DiscoveredPeer[] = [];
  const seenDeviceIds = new Set<string>();

  // 1. LAN peers from mDNS (via Rust sync server)
  try {
    const lanPeers = await invoke<any[]>('get_discovered_peers');
    for (const p of lanPeers) {
      seenDeviceIds.add(p.device_id);
      merged.push({
        ...p,
        transport: 'lan' as const,
      });
    }
  } catch (err) {
    console.error('[peer-manager] mDNS peer poll error:', err);
  }

  // 2. Multipeer peers (Apple BT+Wi-Fi)
  try {
    const { btService } = await import('./services/bt-service');
    if (btService.status === 'running') {
      for (const mp of btService.nearbyDevices) {
        if (seenDeviceIds.has(mp.deviceId)) {
          // Already found via LAN — skip (LAN is faster)
          continue;
        }
        seenDeviceIds.add(mp.deviceId);
        merged.push({
          device_id: mp.deviceId,
          device_name: mp.name ?? 'Unknown Device',
          company_id: mp.companyId,
          host: '',  // No HTTP host for Multipeer peers
          port: 0,
          version: '',
          discovered_at: new Date().toISOString(),
          transport: 'multipeer' as const,
          multipeer_state: mp.state,
        });
      }
    }
  } catch {
    // Multipeer not available — no problem
  }

  updateState({ peers: merged });
}

// ── Sync With a Specific Peer ────────────────────────────────────────

/**
 * Initiate sync with a specific peer. This is a pull-push cycle:
 * 1. Push our pending changes to the peer's sync server
 * 2. Pull the peer's changes from their sync server
 * 3. Apply received changes to local SQLite
 */
export async function syncWithPeer(peer: DiscoveredPeer): Promise<PeerSyncResult> {
  const {
    getPendingChanges, markSynced,
    getVectorClock, updateVectorClock,
    registerPeerDevice, updatePeerSyncTime,
  } = await import('./change-tracker');
  const { getDeviceId } = await import('../lib/device-identity');

  const deviceId = await getDeviceId();
  const now = new Date().toISOString();

  updateState({ syncing_with: peer.device_id });

  try {
    // Register this peer in our device registry
    await registerPeerDevice(peer.device_id, peer.device_name);

    // Get our pending changes
    const pendingChanges = await getPendingChanges();

    // Enrich changes with full record data for INSERT/UPDATE
    const enrichedChanges = await enrichChangesWithData(pendingChanges);

    let pushed = 0;
    let pulled = 0;

    if (peer.transport === 'multipeer' && peer.multipeer_state === 'connected') {
      // ── Multipeer sync path ──
      // Send changes as JSON over Apple Multipeer Connectivity.
      // Multipeer is a bidirectional pipe — we push our changes, and
      // the peer processes them and may push back via the receive queue.
      const { btService } = await import('./services/bt-service');

      if (enrichedChanges.length > 0) {
        const payload = JSON.stringify(enrichedChanges);
        const sent = await btService.sendToPeer(peer.device_id, payload);
        if (sent) {
          pushed = enrichedChanges.length;
          // Mark as synced
          const syncedIds = pendingChanges.map((c: any) => c.id);
          await markSynced(syncedIds, `mp-${Date.now()}`);
        }
      }

      // Note: Pulled changes arrive asynchronously via the Multipeer
      // receive queue — bt-service._pollMessages() handles them.

    } else {
      // ── LAN HTTP sync path (existing behavior) ──

      // Get auth fields for Ed25519 certificate verification (Phase 5)
      let auth: Record<string, any> = {};
      try {
        const { getSyncAuthFields } = await import('./services/security-service');
        const authFields = await getSyncAuthFields();
        if (authFields) {
          auth = {
            certificate_data: authFields.certificate_data,
            certificate_signature: authFields.signature,
          };
        }
      } catch {
        // Auth not available — Phase 4 compat (company_id-only)
      }

      // 1. Push our changes to the peer
      if (enrichedChanges.length > 0) {
        const pushResponse = await fetch(
          `http://${peer.host}:${peer.port}/sync/push`,
          {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({
              device_id: deviceId,
              company_id: peer.company_id,
              last_sync_at: state.last_peer_syncs[peer.device_id]?.synced_at ?? null,
              changes: enrichedChanges,
              auth,
            }),
            signal: AbortSignal.timeout(30000),
          },
        );

        if (pushResponse.ok) {
          const pushData = await pushResponse.json();
          pushed = pushData.accepted ?? 0;

          // Mark local changes as synced
          if (pushed > 0 && pushData.sync_batch_id) {
            const syncedIds = pendingChanges.map((c: any) => c.id);
            await markSynced(syncedIds, pushData.sync_batch_id);
          }
        }
      }

      // 2. Pull changes from the peer using vector clock for efficient delta sync
      const vectorClock = await getVectorClock();
      const pullResponse = await fetch(
        `http://${peer.host}:${peer.port}/sync/pull`,
        {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({
            device_id: deviceId,
            company_id: peer.company_id,
            vector_clock: vectorClock,
            last_sync_at: state.last_peer_syncs[peer.device_id]?.synced_at ?? null,
            auth,
          }),
          signal: AbortSignal.timeout(30000),
        },
      );

      if (pullResponse.ok) {
        const pullData = await pullResponse.json();
        const changes = pullData.changes ?? [];
        const serverDeviceId = pullData.server_device_id;
        pulled = changes.length;

        // 3. Apply received changes to local SQLite
        if (changes.length > 0) {
          await applyPeerChanges(changes);

          // Update our vector clock with the highest sequence we received from this peer
          const maxSeq = Math.max(...changes.map((c: any) => c.id ?? 0));
          if (maxSeq > 0 && serverDeviceId) {
            await updateVectorClock(serverDeviceId, maxSeq);
          }
        }
      }
    }

    // Update peer's last sync time in the device registry
    await updatePeerSyncTime(peer.device_id);

    const result: PeerSyncResult = {
      peer_device_id: peer.device_id,
      peer_name: peer.device_name,
      pushed,
      pulled,
      success: true,
      synced_at: now,
    };

    updateState({
      syncing_with: null,
      last_peer_syncs: { ...state.last_peer_syncs, [peer.device_id]: result },
    });

    // Update the Rust side's sync timestamp
    await invoke('update_sync_timestamp', { timestamp: now });

    console.log(
      `[peer-manager] Synced with ${peer.device_name}: pushed ${pushed}, pulled ${pulled}`,
    );

    return result;
  } catch (err) {
    const result: PeerSyncResult = {
      peer_device_id: peer.device_id,
      peer_name: peer.device_name,
      pushed: 0,
      pulled: 0,
      success: false,
      error: err instanceof Error ? err.message : 'Sync failed',
      synced_at: now,
    };

    updateState({
      syncing_with: null,
      last_peer_syncs: { ...state.last_peer_syncs, [peer.device_id]: result },
    });

    console.error(`[peer-manager] Sync with ${peer.device_name} failed:`, err);
    return result;
  }
}

// ── Sync With All Peers (Sequential) ─────────────────────────────────

/**
 * Sync with all discovered peers, sequentially.
 * Prioritizes office computers, then least-recently-synced.
 */
export async function syncWithAllPeers(): Promise<PeerSyncResult[]> {
  const results: PeerSyncResult[] = [];

  // Sort peers: office-like names first, then by last sync time
  const sorted = [...state.peers].sort((a, b) => {
    const aIsOffice = isOfficePeer(a);
    const bIsOffice = isOfficePeer(b);
    if (aIsOffice && !bIsOffice) return -1;
    if (!aIsOffice && bIsOffice) return 1;

    // Then by least recently synced
    const aLastSync = state.last_peer_syncs[a.device_id]?.synced_at ?? '';
    const bLastSync = state.last_peer_syncs[b.device_id]?.synced_at ?? '';
    return aLastSync.localeCompare(bLastSync);
  });

  for (const peer of sorted) {
    // Skip Multipeer peers that aren't fully connected yet
    if (peer.transport === 'multipeer' && peer.multipeer_state !== 'connected') {
      continue;
    }
    const result = await syncWithPeer(peer);
    results.push(result);
  }

  return results;
}

/**
 * Heuristic: is this peer likely an office/shop computer?
 * (office computers have names like "Shop Computer", "Office Mac", etc.)
 */
function isOfficePeer(peer: DiscoveredPeer): boolean {
  const name = peer.device_name.toLowerCase();
  return (
    name.includes('office') ||
    name.includes('shop') ||
    name.includes('server') ||
    name.includes('main')
  );
}

// ── Process Incoming Changes from Rust Inbox ─────────────────────────

/**
 * Process changes received by the Rust sync server (from peers who
 * pushed to us). The Rust server stores them in an inbox; we read,
 * apply, and clear.
 */
async function processInbox(): Promise<void> {
  if (!state.running) return;

  const inbox = await invoke<any[]>('get_sync_inbox');
  if (!inbox || inbox.length === 0) return;

  await applyPeerChanges(inbox);
  await invoke('clear_sync_inbox');

  console.log(`[peer-manager] Processed ${inbox.length} inbox changes`);
}

// ── Apply Peer Changes to Local SQLite ───────────────────────────────

/**
 * Apply changes received from a peer to the local SQLite database.
 *
 * Uses the conflict-resolver engine for field-level merge with LWW:
 * - Non-conflicting field changes from different devices both apply
 * - Same-field conflicts resolved by later timestamp (LWW)
 * - All overwrites logged to _conflict_log for admin review
 *
 * Falls back to naive INSERT OR REPLACE if the conflict resolver errors.
 */
async function applyPeerChanges(changes: any[]): Promise<void> {
  try {
    const { resolveAndApplyChanges } = await import('./conflict-resolver');

    // Map raw peer changes to the conflict-resolver's IncomingChange format
    const incoming = changes.map((c) => ({
      id: c.id,
      device_id: c.device_id ?? 'unknown',
      table_name: c.table_name,
      record_id: String(c.record_id),
      operation: c.operation as 'INSERT' | 'UPDATE' | 'DELETE',
      changed_fields: c.changed_fields ?? null,
      old_values: c.old_values ?? null,
      record_data: c.record_data ?? null,
      timestamp: c.timestamp ?? new Date().toISOString(),
    }));

    const result = await resolveAndApplyChanges(incoming);

    console.log(
      `[peer-manager] Conflict resolver: applied=${result.applied}, conflicts=${result.conflicts}, skipped=${result.skipped}, errors=${result.errors}`,
    );
  } catch (err) {
    // Fallback: if conflict resolver fails, use naive approach so sync isn't blocked
    console.error('[peer-manager] Conflict resolver failed, falling back to naive apply:', err);
    await applyPeerChangesNaive(changes);
  }
}

/**
 * Naive fallback — INSERT OR REPLACE without field-level merge.
 * Only used if the conflict resolver encounters an unexpected error.
 */
async function applyPeerChangesNaive(changes: any[]): Promise<void> {
  const { getDb } = await import('./db');
  const db = await getDb();

  for (const change of changes) {
    const { table_name, record_id, operation, record_data, changed_fields } = change;

    try {
      if (operation === 'DELETE') {
        try {
          await db.run(
            `UPDATE [${table_name}] SET deleted_at = datetime('now') WHERE id = ?`,
            [record_id],
          );
        } catch {
          await db.run(`DELETE FROM [${table_name}] WHERE id = ?`, [record_id]);
        }
      } else if (record_data) {
        const data = typeof record_data === 'string'
          ? JSON.parse(record_data)
          : record_data;
        const keys = Object.keys(data);
        const placeholders = keys.map(() => '?').join(', ');
        const values = keys.map((k) => data[k]);

        await db.run(
          `INSERT OR REPLACE INTO [${table_name}] (${keys.join(', ')}) VALUES (${placeholders})`,
          values,
        );
      } else if (changed_fields && operation === 'UPDATE') {
        const fields = typeof changed_fields === 'string'
          ? JSON.parse(changed_fields)
          : changed_fields;
        const keys = Object.keys(fields);
        if (keys.length === 0) continue;

        const setClause = keys.map((k) => `${k} = ?`).join(', ');
        const values = keys.map((k) => fields[k]);

        await db.run(
          `UPDATE [${table_name}] SET ${setClause} WHERE id = ?`,
          [...values, record_id],
        );
      }
    } catch (err) {
      console.error(`[peer-manager] Naive apply failed: ${table_name}.${record_id}`, err);
    }
  }
}

// ── Enrich Changes with Full Record Data ─────────────────────────────

/**
 * For INSERT and UPDATE changes, fetch the full current row from SQLite
 * so the receiving peer can INSERT OR REPLACE it.
 */
async function enrichChangesWithData(changes: any[]): Promise<any[]> {
  const { getDb } = await import('./db');
  const db = await getDb();
  const enriched: any[] = [];

  for (const change of changes) {
    const entry = { ...change };

    if (change.operation !== 'DELETE') {
      try {
        const rows = await db.query(
          `SELECT * FROM [${change.table_name}] WHERE id = ?`,
          [change.record_id],
        );
        if (rows.values && rows.values.length > 0) {
          entry.record_data = JSON.stringify(rows.values[0]);
        }
      } catch {
        // Table or record might not exist — skip enrichment
      }
    }

    enriched.push(entry);
  }

  return enriched;
}

// ── Update Outbox (for peers pulling from us) ────────────────────────

/**
 * Refresh the Rust sync server's outbox with our latest pending changes.
 * Called periodically so peers that pull from us get fresh data.
 */
export async function refreshOutbox(): Promise<void> {
  if (!isTauri() || !state.running) return;

  const { getPendingChanges } = await import('./change-tracker');
  const pendingChanges = await getPendingChanges();
  const enriched = await enrichChangesWithData(pendingChanges);

  await invoke('set_sync_outbox', { changes: enriched });
}
