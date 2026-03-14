//! Foundation Models bridge — Rust FFI bindings + Tauri IPC commands.
//!
//! On macOS/iOS (26+): calls into Swift FoundationModelsBridge via C FFI.
//! On other platforms: all commands return graceful fallbacks.
//!
//! The Swift bridge handles LanguageModelSession, Tool calling, and
//! async generation. This module wraps the C functions in safe Rust
//! and exposes them as Tauri `#[tauri::command]` functions for TypeScript.

use serde::{Deserialize, Serialize};
use std::ffi::{CStr, CString};

// ── Types ────────────────────────────────────────────────────────────

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct LlmResult {
    pub success: bool,
    pub text: Option<String>,
    pub error: Option<String>,
}

// ── FFI Declarations (macOS/iOS only) ────────────────────────────────

#[cfg(any(target_os = "macos", target_os = "ios"))]
extern "C" {
    fn wp_llm_check_availability() -> i32;
    fn wp_llm_reset_availability();
    fn wp_llm_submit_request(
        request_id: *const libc::c_char,
        prompt: *const libc::c_char,
        instructions: *const libc::c_char,
        tools_json: *const libc::c_char,
    ) -> i32;
    fn wp_llm_poll_result(request_id: *const libc::c_char) -> *mut libc::c_char;
    fn wp_llm_cancel_request(request_id: *const libc::c_char);
    fn wp_llm_free_string(str: *mut libc::c_char);
}

// ── Safe Wrappers ────────────────────────────────────────────────────

/// Read a C string from the Swift bridge, convert to Rust String, free the C string.
#[cfg(any(target_os = "macos", target_os = "ios"))]
unsafe fn read_and_free(ptr: *mut libc::c_char) -> Option<String> {
    if ptr.is_null() {
        return None;
    }
    let cstr = unsafe { CStr::from_ptr(ptr) };
    let s = cstr.to_string_lossy().into_owned();
    unsafe { wp_llm_free_string(ptr) };
    Some(s)
}

// ── Tauri Commands ───────────────────────────────────────────────────

/// Check if Apple Foundation Models is available on this device.
///
/// Returns a string status:
/// - "available" — model is ready to use
/// - "not_eligible" — device doesn't support Apple Intelligence
/// - "not_enabled" — Apple Intelligence is not turned on
/// - "not_ready" — model is downloading
/// - "unavailable" — unknown reason
/// - "not_native" — not running in a Tauri native app (web browser)
#[tauri::command]
pub fn llm_check_availability() -> String {
    #[cfg(any(target_os = "macos", target_os = "ios"))]
    {
        let status = unsafe { wp_llm_check_availability() };
        match status {
            0 => "available".to_string(),
            1 => "not_eligible".to_string(),
            2 => "not_enabled".to_string(),
            3 => "not_ready".to_string(),
            _ => "unavailable".to_string(),
        }
    }

    #[cfg(not(any(target_os = "macos", target_os = "ios")))]
    {
        "not_native".to_string()
    }
}

/// Reset the cached availability status.
/// Call this after the user might have toggled Apple Intelligence in Settings.
#[tauri::command]
pub fn llm_reset_availability() {
    #[cfg(any(target_os = "macos", target_os = "ios"))]
    unsafe {
        wp_llm_reset_availability();
    }
}

/// Submit a text generation request. Non-blocking — returns immediately.
///
/// The request is processed asynchronously by the on-device model.
/// Poll for the result with `llm_poll_result(request_id)`.
///
/// Returns true if the request was queued successfully.
#[tauri::command]
pub fn llm_request(
    request_id: String,
    prompt: String,
    instructions: String,
    tools_json: Option<String>,
) -> Result<bool, String> {
    #[cfg(any(target_os = "macos", target_os = "ios"))]
    {
        let c_request_id =
            CString::new(request_id).map_err(|e| format!("Invalid request_id: {e}"))?;
        let c_prompt = CString::new(prompt).map_err(|e| format!("Invalid prompt: {e}"))?;
        let c_instructions =
            CString::new(instructions).map_err(|e| format!("Invalid instructions: {e}"))?;
        let c_tools = tools_json
            .as_deref()
            .map(|s| CString::new(s).map_err(|e| format!("Invalid tools_json: {e}")))
            .transpose()?;

        let result = unsafe {
            wp_llm_submit_request(
                c_request_id.as_ptr(),
                c_prompt.as_ptr(),
                c_instructions.as_ptr(),
                c_tools.as_ref().map_or(std::ptr::null(), |c| c.as_ptr()),
            )
        };

        if result != 0 {
            Err("Failed to submit LLM request".into())
        } else {
            Ok(true)
        }
    }

    #[cfg(not(any(target_os = "macos", target_os = "ios")))]
    {
        let _ = (request_id, prompt, instructions, tools_json);
        Err("Foundation Models is only available on macOS/iOS".into())
    }
}

/// Poll for a completed generation result.
///
/// Returns the result JSON if generation is complete, or null if still processing.
#[tauri::command]
pub fn llm_poll_result(request_id: String) -> Option<LlmResult> {
    #[cfg(any(target_os = "macos", target_os = "ios"))]
    {
        let c_request_id = CString::new(request_id).ok()?;

        let json = unsafe {
            let ptr = wp_llm_poll_result(c_request_id.as_ptr());
            read_and_free(ptr)
        };

        json.and_then(|s| serde_json::from_str(&s).ok())
    }

    #[cfg(not(any(target_os = "macos", target_os = "ios")))]
    {
        let _ = request_id;
        None
    }
}

/// Cancel a pending generation request.
#[tauri::command]
pub fn llm_cancel_request(request_id: String) {
    #[cfg(any(target_os = "macos", target_os = "ios"))]
    {
        if let Ok(c_request_id) = CString::new(request_id) {
            unsafe {
                wp_llm_cancel_request(c_request_id.as_ptr());
            }
        }
    }

    #[cfg(not(any(target_os = "macos", target_os = "ios")))]
    {
        let _ = request_id;
    }
}
