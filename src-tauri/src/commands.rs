/// Tauri IPC Commands for P2P LAN Sync
///
/// These commands are callable from the TypeScript frontend via
/// `invoke('command_name', { args })`. They bridge the gap between
/// the Rust-side sync server / mDNS discovery and the TS sync engine.
///
/// The frontend calls these to:
/// 1. Start the sync server + mDNS advertisement
/// 2. Get list of discovered peers on the LAN
/// 3. Read received sync data from the inbox
/// 4. Populate the outbox with local changes for peers to pull
/// 5. Get the sync server's port and status

use crate::discovery::{DiscoveredPeer, DiscoveryManager};
use crate::sync_server::{ChangeEntry, SharedState, SyncServerState};
use std::sync::Arc;
use tauri::State;
use tokio::sync::RwLock;

/// Managed state that holds the discovery manager (Option because
/// it's initialized lazily via the start_sync command)
pub struct ManagedDiscovery(pub std::sync::Mutex<Option<DiscoveryManager>>);

/// Start the P2P sync server and mDNS advertisement.
/// Called once from TS after the user authenticates and we know
/// the device_id, device_name, and company_id.
#[tauri::command]
pub async fn start_p2p_sync(
    device_id: String,
    device_name: String,
    company_id: String,
    sync_state: State<'_, SharedState>,
    discovery_state: State<'_, ManagedDiscovery>,
) -> Result<u16, String> {
    // Update shared state with device info
    {
        let mut s = sync_state.write().await;
        s.device_id = device_id.clone();
        s.device_name = device_name.clone();
        s.company_id = company_id.clone();
    }

    // Start the HTTP sync server
    let port = crate::sync_server::start_sync_server(Arc::clone(&sync_state))
        .await
        .map_err(|e| format!("Failed to start sync server: {}", e))?;

    // Start mDNS discovery + advertisement
    let dm = DiscoveryManager::new(device_id, company_id)
        .map_err(|e| format!("Discovery init failed: {}", e))?;

    dm.advertise(port, &device_name)
        .map_err(|e| format!("mDNS advertise failed: {}", e))?;

    dm.start_browsing()
        .map_err(|e| format!("mDNS browse failed: {}", e))?;

    // Store the discovery manager
    if let Ok(mut guard) = discovery_state.0.lock() {
        *guard = Some(dm);
    }

    log::info!("[p2p] Sync server started on port {}, mDNS active", port);
    Ok(port)
}

/// Get all discovered peers on the LAN (same company only)
#[tauri::command]
pub fn get_discovered_peers(
    discovery_state: State<'_, ManagedDiscovery>,
) -> Vec<DiscoveredPeer> {
    discovery_state
        .0
        .lock()
        .ok()
        .and_then(|guard| guard.as_ref().map(|dm| dm.get_peers()))
        .unwrap_or_default()
}

/// Get changes received from peers (the sync server inbox).
/// The TS sync engine calls this periodically, applies the changes
/// to local SQLite, then calls clear_sync_inbox.
#[tauri::command]
pub async fn get_sync_inbox(
    sync_state: State<'_, SharedState>,
) -> Result<Vec<ChangeEntry>, String> {
    let s = sync_state.read().await;
    Ok(s.inbox.clone())
}

/// Clear the inbox after the TS sync engine has processed the changes
#[tauri::command]
pub async fn clear_sync_inbox(
    sync_state: State<'_, SharedState>,
) -> Result<(), String> {
    let mut s = sync_state.write().await;
    s.inbox.clear();
    Ok(())
}

/// Update the outbox with local changes that peers can pull.
/// The TS sync engine calls this with pending _change_log entries.
#[tauri::command]
pub async fn set_sync_outbox(
    changes: Vec<ChangeEntry>,
    sync_state: State<'_, SharedState>,
) -> Result<(), String> {
    let mut s = sync_state.write().await;
    s.outbox = changes;
    Ok(())
}

/// Get the sync server port (so TS knows what port we're on)
#[tauri::command]
pub async fn get_sync_port(
    sync_state: State<'_, SharedState>,
) -> Result<u16, String> {
    let s = sync_state.read().await;
    Ok(s.port)
}

/// Get sync server status
#[tauri::command]
pub async fn get_sync_server_status(
    sync_state: State<'_, SharedState>,
) -> Result<serde_json::Value, String> {
    let s = sync_state.read().await;
    Ok(serde_json::json!({
        "device_id": s.device_id,
        "device_name": s.device_name,
        "company_id": s.company_id,
        "port": s.port,
        "inbox_count": s.inbox.len(),
        "outbox_count": s.outbox.len(),
        "last_sync_at": s.last_sync_at,
    }))
}

/// Push changes into the sync inbox (used by Multipeer / BT transport).
///
/// The LAN HTTP sync server pushes directly into the inbox via handle_push().
/// Multipeer messages arrive on the TS side, so they need an IPC path to
/// deposit changes into the same inbox. The TS processInbox() then applies
/// them exactly as it would LAN-received changes.
#[tauri::command]
pub async fn push_to_sync_inbox(
    changes: Vec<ChangeEntry>,
    sync_state: State<'_, SharedState>,
) -> Result<usize, String> {
    let count = changes.len();
    let mut s = sync_state.write().await;
    s.inbox.extend(changes);
    log::debug!("[p2p] {} changes pushed to inbox via IPC", count);
    Ok(count)
}

/// Update last_sync_at timestamp (called by TS after successful sync)
#[tauri::command]
pub async fn update_sync_timestamp(
    timestamp: String,
    sync_state: State<'_, SharedState>,
) -> Result<(), String> {
    let mut s = sync_state.write().await;
    s.last_sync_at = Some(timestamp);
    Ok(())
}

/// Set the company's Ed25519 public key for certificate verification.
///
/// Called by the TS security service after loading the company cert from
/// secure storage. Once set, all incoming sync push/pull requests must
/// present a valid certificate signed by this key.
///
/// Pass an empty string to clear the key (revert to Phase 4 compat mode).
#[tauri::command]
pub async fn set_company_public_key(
    public_key_b64: String,
    sync_state: State<'_, SharedState>,
) -> Result<(), String> {
    let mut s = sync_state.write().await;
    if public_key_b64.is_empty() {
        s.company_public_key = None;
        log::info!("[p2p] Company public key cleared — Phase 4 compat mode");
    } else {
        // Validate that it's a valid base64 string of correct length
        use base64::Engine;
        let b64 = base64::engine::general_purpose::STANDARD;
        match b64.decode(&public_key_b64) {
            Ok(bytes) if bytes.len() == 32 => {
                s.company_public_key = Some(public_key_b64);
                log::info!("[p2p] Company public key set — Ed25519 verification active");
            }
            Ok(bytes) => {
                return Err(format!(
                    "Company public key must be 32 bytes, got {}",
                    bytes.len()
                ));
            }
            Err(e) => {
                return Err(format!("Invalid base64 for company public key: {e}"));
            }
        }
    }
    Ok(())
}

/// Create the initial SharedState and ManagedDiscovery for Tauri managed state
pub fn create_sync_state() -> SharedState {
    Arc::new(RwLock::new(SyncServerState {
        device_id: String::new(),
        device_name: String::new(),
        company_id: String::new(),
        port: 0,
        inbox: Vec::new(),
        outbox: Vec::new(),
        last_sync_at: None,
        company_public_key: None,
    }))
}

pub fn create_discovery_state() -> ManagedDiscovery {
    ManagedDiscovery(std::sync::Mutex::new(None))
}
