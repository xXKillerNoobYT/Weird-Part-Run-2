/// P2P LAN Sync Server
///
/// Each WiredPart device runs a lightweight HTTP server on a random port.
/// Other devices on the LAN discover this port via mDNS and call these
/// endpoints to exchange change_log entries:
///
///   POST /sync/push    — receive changes from a peer
///   POST /sync/pull    — send my changes to a peer
///   GET  /sync/status  — health check + device info
///
/// The sync protocol is symmetrical — any device can initiate sync with
/// any other device. The TypeScript sync engine orchestrates which peer
/// to sync with and when.
///
/// Security:
/// - Phase 4: Trusts any device on the same LAN that knows the company_id.
/// - Phase 5: Ed25519 certificate verification. Each device presents a
///   certificate signed by the company admin key. If the company key is
///   set, unauthenticated requests are rejected.

use axum::{
    extract::State,
    http::StatusCode,
    routing::{get, post},
    Json, Router,
};
use serde::{Deserialize, Serialize};
use std::sync::Arc;
use tokio::net::TcpListener;
use tokio::sync::RwLock;

use crate::crypto::{verify_sync_auth, AuthResult, SyncAuth};

// ── Types ────────────────────────────────────────────────────────────

/// A single change from the _change_log table
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ChangeEntry {
    pub id: i64,
    pub device_id: String,
    pub table_name: String,
    pub record_id: String,
    pub operation: String, // INSERT, UPDATE, DELETE
    pub changed_fields: Option<String>, // JSON
    pub old_values: Option<String>,     // JSON
    pub record_data: Option<String>,    // JSON — full row for INSERT/UPDATE
    pub timestamp: String,
}

/// Request body for POST /sync/push
#[derive(Debug, Deserialize)]
#[allow(dead_code)]
pub struct SyncPushRequest {
    pub device_id: String,
    pub company_id: String,
    pub last_sync_at: Option<String>,
    pub changes: Vec<ChangeEntry>,
    /// Ed25519 certificate auth (Phase 5). Optional for Phase 4 compat.
    #[serde(default)]
    pub auth: SyncAuth,
}

/// Response for POST /sync/push
#[derive(Debug, Serialize)]
pub struct SyncPushResponse {
    pub accepted: usize,
    pub sync_batch_id: String,
}

/// Request body for POST /sync/pull
#[derive(Debug, Deserialize)]
#[allow(dead_code)]
pub struct SyncPullRequest {
    pub device_id: String,
    pub company_id: String,
    pub last_sync_at: Option<String>,
    /// Vector clock: { peer_device_id: last_seen_sequence }
    pub vector_clock: Option<std::collections::HashMap<String, i64>>,
    /// Ed25519 certificate auth (Phase 5). Optional for Phase 4 compat.
    #[serde(default)]
    pub auth: SyncAuth,
}

/// Response for POST /sync/pull
#[derive(Debug, Serialize)]
pub struct SyncPullResponse {
    pub changes: Vec<ChangeEntry>,
    pub sync_batch_id: String,
    pub server_device_id: String,
}

/// GET /sync/status response
#[derive(Debug, Serialize)]
pub struct SyncStatusResponse {
    pub device_id: String,
    pub device_name: String,
    pub company_id: String,
    pub app_version: String,
    pub pending_changes: usize,
    pub last_sync_at: Option<String>,
    pub port: u16,
}

// ── Shared State ─────────────────────────────────────────────────────

/// State shared between the sync server and the Tauri app.
/// The TypeScript side pushes/pulls change entries through Tauri IPC
/// commands that read/write this shared state.
#[derive(Debug)]
pub struct SyncServerState {
    pub device_id: String,
    pub device_name: String,
    pub company_id: String,
    pub port: u16,
    /// Changes received from peers, waiting to be applied by the TS sync engine
    pub inbox: Vec<ChangeEntry>,
    /// Changes from local DB ready to be sent to peers (populated by TS via IPC)
    pub outbox: Vec<ChangeEntry>,
    pub last_sync_at: Option<String>,
    /// Company admin's Ed25519 public key (base64). When set, all incoming
    /// sync requests must present a valid certificate signed by this key.
    /// When None, falls back to company_id-only auth (Phase 4 compat).
    pub company_public_key: Option<String>,
}

pub type SharedState = Arc<RwLock<SyncServerState>>;

// ── Auth Helper ──────────────────────────────────────────────────────

/// Verify a sync request's auth against the server's state.
/// Returns Ok(()) if auth passes, Err(StatusCode) if rejected.
fn check_auth(
    auth: &SyncAuth,
    request_company_id: &str,
    state: &SyncServerState,
) -> Result<(), StatusCode> {
    // Company ID must always match
    if request_company_id != state.company_id {
        log::warn!(
            "[sync-server] Company ID mismatch: got '{}', expected '{}'",
            request_company_id,
            state.company_id
        );
        return Err(StatusCode::FORBIDDEN);
    }

    // Ed25519 certificate verification (Phase 5)
    let company_key = state.company_public_key.as_deref();
    match verify_sync_auth(auth, &state.company_id, company_key) {
        AuthResult::Verified { device_id, .. } => {
            log::debug!("[sync-server] Verified device: {}", device_id);
            Ok(())
        }
        AuthResult::AllowedNoKey => {
            // No company key configured — Phase 4 compatibility mode
            Ok(())
        }
        AuthResult::Required => {
            log::warn!(
                "[sync-server] Certificate required but not provided by device '{}'",
                request_company_id
            );
            Err(StatusCode::UNAUTHORIZED)
        }
        AuthResult::Rejected(reason) => {
            log::warn!("[sync-server] Certificate rejected: {}", reason);
            Err(StatusCode::FORBIDDEN)
        }
    }
}

// ── Route Handlers ───────────────────────────────────────────────────

/// POST /sync/push — receive changes from a peer device
async fn handle_push(
    State(state): State<SharedState>,
    Json(req): Json<SyncPushRequest>,
) -> Result<Json<SyncPushResponse>, StatusCode> {
    // Verify auth (read lock first to check, then upgrade to write)
    {
        let s = state.read().await;
        check_auth(&req.auth, &req.company_id, &s)?;
    }

    let mut s = state.write().await;

    let accepted = req.changes.len();
    let batch_id = uuid::Uuid::new_v4().to_string();

    // Store received changes in inbox for the TS sync engine to process
    s.inbox.extend(req.changes);

    log::info!(
        "[sync-server] Accepted {} changes from device '{}'",
        accepted,
        req.device_id
    );

    Ok(Json(SyncPushResponse {
        accepted,
        sync_batch_id: batch_id,
    }))
}

/// POST /sync/pull — send our changes to a requesting peer
async fn handle_pull(
    State(state): State<SharedState>,
    Json(req): Json<SyncPullRequest>,
) -> Result<Json<SyncPullResponse>, StatusCode> {
    let s = state.read().await;

    // Verify auth
    check_auth(&req.auth, &req.company_id, &s)?;

    let batch_id = uuid::Uuid::new_v4().to_string();

    // Filter outbox changes the peer hasn't seen yet.
    // If the peer provides a vector clock, use it to filter.
    // Otherwise, use last_sync_at timestamp as fallback.
    let changes = if let Some(ref vc) = req.vector_clock {
        // Send changes the peer hasn't seen from us
        let peer_last_seen = vc.get(&s.device_id).copied().unwrap_or(0);
        s.outbox
            .iter()
            .filter(|c| c.id > peer_last_seen)
            .cloned()
            .collect()
    } else if let Some(ref since) = req.last_sync_at {
        s.outbox
            .iter()
            .filter(|c| c.timestamp > *since)
            .cloned()
            .collect()
    } else {
        // First sync — send everything
        s.outbox.clone()
    };

    log::info!(
        "[sync-server] Sending {} changes to device '{}'",
        changes.len(),
        req.device_id
    );

    Ok(Json(SyncPullResponse {
        changes,
        sync_batch_id: batch_id,
        server_device_id: s.device_id.clone(),
    }))
}

/// GET /sync/status — health check + device info
async fn handle_status(State(state): State<SharedState>) -> Json<SyncStatusResponse> {
    let s = state.read().await;
    Json(SyncStatusResponse {
        device_id: s.device_id.clone(),
        device_name: s.device_name.clone(),
        company_id: s.company_id.clone(),
        app_version: env!("CARGO_PKG_VERSION").to_string(),
        pending_changes: s.outbox.len(),
        last_sync_at: s.last_sync_at.clone(),
        port: s.port,
    })
}

// ── Server Startup ───────────────────────────────────────────────────

/// Build the axum router with all sync endpoints
fn build_router(state: SharedState) -> Router {
    Router::new()
        .route("/sync/push", post(handle_push))
        .route("/sync/pull", post(handle_pull))
        .route("/sync/status", get(handle_status))
        .with_state(state)
}

/// Start the sync HTTP server on a random available port.
/// Returns the port number so it can be advertised via mDNS.
pub async fn start_sync_server(state: SharedState) -> Result<u16, Box<dyn std::error::Error>> {
    // Bind to 0.0.0.0:0 to get a random available port
    let listener = TcpListener::bind("0.0.0.0:0").await?;
    let port = listener.local_addr()?.port();

    // Update state with assigned port
    {
        let mut s = state.write().await;
        s.port = port;
    }

    let app = build_router(state);

    log::info!("[sync-server] Listening on port {}", port);

    // Spawn the server in a background task
    tokio::spawn(async move {
        if let Err(e) = axum::serve(listener, app).await {
            log::error!("[sync-server] Server error: {}", e);
        }
    });

    Ok(port)
}
