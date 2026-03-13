//! Multipeer Connectivity bridge — Rust FFI bindings + Tauri IPC commands.
//!
//! On macOS/iOS: calls into the ObjC MultipeerBridge via C FFI.
//! On other platforms: all commands return errors gracefully.
//!
//! The ObjC bridge handles MCSession, MCBrowser, MCAdvertiser.
//! This module wraps the C functions in safe Rust and exposes them
//! as Tauri `#[tauri::command]` functions for TypeScript to invoke.

use serde::{Deserialize, Serialize};
use std::ffi::{CStr, CString};

// ── Types ────────────────────────────────────────────────────────────

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct MultipeerPeer {
    pub device_id: String,
    pub device_name: String,
    pub company_id: String,
    pub state: String, // "found" | "connecting" | "connected"
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ReceivedMessage {
    pub from_device_id: String,
    pub data: String, // base64-encoded
    pub received_at: String,
}

// ── FFI Declarations (macOS/iOS only) ────────────────────────────────

#[cfg(any(target_os = "macos", target_os = "ios"))]
extern "C" {
    fn wp_multipeer_init(
        device_id: *const libc::c_char,
        device_name: *const libc::c_char,
        company_id: *const libc::c_char,
    ) -> libc::c_int;

    fn wp_multipeer_start() -> libc::c_int;
    fn wp_multipeer_stop();
    fn wp_multipeer_cleanup();
    fn wp_multipeer_get_peers_json() -> *mut libc::c_char;
    fn wp_multipeer_send(
        peer_device_id: *const libc::c_char,
        data: *const u8,
        len: u32,
    ) -> libc::c_int;
    fn wp_multipeer_pop_received() -> *mut libc::c_char;
    fn wp_multipeer_receive_count() -> u32;
    fn wp_multipeer_is_running() -> bool;
    fn wp_multipeer_free_string(str: *mut libc::c_char);
}

// ── Safe Wrappers ────────────────────────────────────────────────────

/// Read a C string from the ObjC bridge, convert to Rust String, free the C string.
#[cfg(any(target_os = "macos", target_os = "ios"))]
unsafe fn read_and_free(ptr: *mut libc::c_char) -> Option<String> {
    if ptr.is_null() {
        return None;
    }
    let cstr = CStr::from_ptr(ptr);
    let s = cstr.to_string_lossy().into_owned();
    wp_multipeer_free_string(ptr);
    Some(s)
}

// ── Tauri Commands ───────────────────────────────────────────────────

/// Initialize and start Multipeer Connectivity.
/// Returns true if started successfully.
#[tauri::command]
pub fn start_multipeer(
    device_id: String,
    device_name: String,
    company_id: String,
) -> Result<bool, String> {
    #[cfg(any(target_os = "macos", target_os = "ios"))]
    {
        let c_device_id =
            CString::new(device_id).map_err(|e| format!("Invalid device_id: {e}"))?;
        let c_device_name =
            CString::new(device_name).map_err(|e| format!("Invalid device_name: {e}"))?;
        let c_company_id =
            CString::new(company_id).map_err(|e| format!("Invalid company_id: {e}"))?;

        unsafe {
            let init_result = wp_multipeer_init(
                c_device_id.as_ptr(),
                c_device_name.as_ptr(),
                c_company_id.as_ptr(),
            );
            if init_result != 0 {
                return Err("Failed to initialize Multipeer".into());
            }

            let start_result = wp_multipeer_start();
            if start_result != 0 {
                return Err("Failed to start Multipeer".into());
            }
        }

        log::info!("[multipeer] Started Multipeer Connectivity");
        Ok(true)
    }

    #[cfg(not(any(target_os = "macos", target_os = "ios")))]
    {
        let _ = (device_id, device_name, company_id);
        log::warn!("[multipeer] Multipeer not available on this platform");
        Err("Multipeer Connectivity is only available on macOS/iOS".into())
    }
}

/// Stop Multipeer Connectivity and disconnect all peers.
#[tauri::command]
pub fn stop_multipeer() {
    #[cfg(any(target_os = "macos", target_os = "ios"))]
    unsafe {
        wp_multipeer_stop();
    }

    log::info!("[multipeer] Stopped Multipeer Connectivity");
}

/// Get list of discovered Multipeer peers.
#[tauri::command]
pub fn get_multipeer_peers() -> Vec<MultipeerPeer> {
    #[cfg(any(target_os = "macos", target_os = "ios"))]
    {
        let json = unsafe {
            let ptr = wp_multipeer_get_peers_json();
            read_and_free(ptr).unwrap_or_else(|| "[]".to_string())
        };

        serde_json::from_str(&json).unwrap_or_default()
    }

    #[cfg(not(any(target_os = "macos", target_os = "ios")))]
    {
        Vec::new()
    }
}

/// Send data to a connected Multipeer peer.
/// Data is a UTF-8 JSON string (sync payloads are always JSON).
#[tauri::command]
pub fn multipeer_send(peer_device_id: String, data: String) -> Result<(), String> {
    #[cfg(any(target_os = "macos", target_os = "ios"))]
    {
        let bytes = data.as_bytes();

        let c_peer_id =
            CString::new(peer_device_id).map_err(|e| format!("Invalid peer_device_id: {e}"))?;

        let result = unsafe {
            wp_multipeer_send(c_peer_id.as_ptr(), bytes.as_ptr(), bytes.len() as u32)
        };

        if result != 0 {
            Err("Failed to send data to peer".into())
        } else {
            Ok(())
        }
    }

    #[cfg(not(any(target_os = "macos", target_os = "ios")))]
    {
        let _ = (peer_device_id, data);
        Err("Multipeer not available on this platform".into())
    }
}

/// Pop the next received message from the Multipeer queue.
/// Returns None if queue is empty.
#[tauri::command]
pub fn multipeer_pop_received() -> Option<ReceivedMessage> {
    #[cfg(any(target_os = "macos", target_os = "ios"))]
    {
        let json = unsafe {
            let ptr = wp_multipeer_pop_received();
            read_and_free(ptr)
        };

        json.and_then(|s| serde_json::from_str(&s).ok())
    }

    #[cfg(not(any(target_os = "macos", target_os = "ios")))]
    {
        None
    }
}

/// Get count of messages waiting in the receive queue.
#[tauri::command]
pub fn multipeer_receive_count() -> u32 {
    #[cfg(any(target_os = "macos", target_os = "ios"))]
    {
        unsafe { wp_multipeer_receive_count() }
    }

    #[cfg(not(any(target_os = "macos", target_os = "ios")))]
    {
        0
    }
}

/// Check if Multipeer is currently running.
#[tauri::command]
pub fn multipeer_is_running() -> bool {
    #[cfg(any(target_os = "macos", target_os = "ios"))]
    {
        unsafe { wp_multipeer_is_running() }
    }

    #[cfg(not(any(target_os = "macos", target_os = "ios")))]
    {
        false
    }
}
