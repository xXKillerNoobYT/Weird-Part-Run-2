//! Foundation Models bridge — Rust FFI bindings + Tauri IPC commands.
//!
//! On macOS/iOS (26+): calls into Swift FoundationModelsBridge via C FFI.
//! On Windows: manages a local llama.cpp sidecar process with OpenAI-compatible API.
//! On other platforms: all commands return graceful fallbacks.
//!
//! The Swift bridge handles LanguageModelSession, Tool calling, and
//! async generation. This module wraps the C functions in safe Rust
//! and exposes them as Tauri `#[tauri::command]` functions for TypeScript.
//!
//! The Windows engine uses llama-server (llama.cpp) running as a sidecar.
//! It speaks the OpenAI-compatible /v1/chat/completions API on localhost.

use serde::{Deserialize, Serialize};
use std::ffi::{CStr, CString};

// ── Windows: llama.cpp HTTP backend ──────────────────────────────────

#[cfg(target_os = "windows")]
mod windows_llm {
    use serde::{Deserialize, Serialize};
    use std::collections::HashMap;
    use std::path::PathBuf;
    use std::process::{Child, Command};
    use std::sync::Mutex;

    /// Tracks the llama.cpp sidecar process and pending requests.
    pub struct WindowsLlmState {
        /// The llama-server child process (None if not started)
        sidecar: Option<Child>,
        /// Port the sidecar listens on
        port: u16,
        /// Cached availability status
        availability: Option<String>,
        /// Pending generation results: request_id -> Option<LlmResult>
        results: HashMap<String, Option<super::LlmResult>>,
    }

    // SAFETY: WindowsLlmState is only accessed through a Mutex.
    unsafe impl Send for WindowsLlmState {}
    unsafe impl Sync for WindowsLlmState {}

    lazy_static::lazy_static! {
        pub static ref STATE: Mutex<WindowsLlmState> = Mutex::new(WindowsLlmState {
            sidecar: None,
            port: 8086,
            availability: None,
            results: HashMap::new(),
        });
    }

    /// Path to the models directory: %APPDATA%\WiredPart\models\
    pub fn models_dir() -> PathBuf {
        let appdata = std::env::var("APPDATA")
            .unwrap_or_else(|_| std::env::var("LOCALAPPDATA").unwrap_or_else(|_| ".".into()));
        PathBuf::from(appdata).join("WiredPart").join("models")
    }

    /// Path to the llama-server binary: %APPDATA%\WiredPart\bin\llama-server.exe
    pub fn server_binary() -> PathBuf {
        let appdata = std::env::var("APPDATA")
            .unwrap_or_else(|_| std::env::var("LOCALAPPDATA").unwrap_or_else(|_| ".".into()));
        PathBuf::from(appdata).join("WiredPart").join("bin").join("llama-server.exe")
    }

    /// Find the first .gguf model file in the models directory.
    pub fn find_model() -> Option<PathBuf> {
        let dir = models_dir();
        if !dir.exists() {
            return None;
        }
        // Look for .gguf files, prefer ones with "Q4" or "Q5" in the name (good quality/size ratio)
        let mut models: Vec<PathBuf> = std::fs::read_dir(&dir)
            .ok()?
            .filter_map(|e| e.ok())
            .map(|e| e.path())
            .filter(|p| p.extension().map_or(false, |ext| ext == "gguf"))
            .collect();

        // Sort: prefer Q4_K_M or Q5_K_M quantizations
        models.sort_by(|a, b| {
            let a_name = a.file_name().unwrap_or_default().to_string_lossy().to_lowercase();
            let b_name = b.file_name().unwrap_or_default().to_string_lossy().to_lowercase();
            let a_preferred = a_name.contains("q4_k_m") || a_name.contains("q5_k_m");
            let b_preferred = b_name.contains("q4_k_m") || b_name.contains("q5_k_m");
            b_preferred.cmp(&a_preferred)
        });

        models.into_iter().next()
    }

    /// Start the llama-server sidecar if not already running.
    pub fn ensure_server_running() -> Result<u16, String> {
        let mut state = STATE.lock().map_err(|e| format!("Lock poisoned: {e}"))?;

        // Check if sidecar is still alive
        if let Some(ref mut child) = state.sidecar {
            match child.try_wait() {
                Ok(Some(_status)) => {
                    // Process exited, need to restart
                    state.sidecar = None;
                }
                Ok(None) => {
                    // Still running
                    return Ok(state.port);
                }
                Err(_) => {
                    state.sidecar = None;
                }
            }
        }

        let server_bin = server_binary();
        if !server_bin.exists() {
            return Err(format!(
                "llama-server.exe not found at {}. Download it from https://github.com/ggerganov/llama.cpp/releases and place it in {}",
                server_bin.display(),
                server_bin.parent().unwrap_or(&server_bin).display()
            ));
        }

        let model_path = find_model().ok_or_else(|| {
            format!(
                "No .gguf model file found in {}. Download a GGUF model (e.g. Phi-3-mini-4k-instruct-q4.gguf) and place it there.",
                models_dir().display()
            )
        })?;

        let port = state.port;

        log::info!(
            "Starting llama-server on port {} with model {}",
            port,
            model_path.display()
        );

        let child = Command::new(&server_bin)
            .args([
                "--model", &model_path.to_string_lossy(),
                "--port", &port.to_string(),
                "--host", "127.0.0.1",
                "--ctx-size", "4096",
                "--threads", "4",
                "--parallel", "1",
                // Run headless — no terminal popup
            ])
            .stdout(std::process::Stdio::null())
            .stderr(std::process::Stdio::null())
            .spawn()
            .map_err(|e| format!("Failed to start llama-server: {e}"))?;

        state.sidecar = Some(child);

        Ok(port)
    }

    /// Check if the server is up by hitting /health.
    pub fn health_check(port: u16) -> bool {
        // Synchronous HTTP check using a blocking client
        let url = format!("http://127.0.0.1:{}/health", port);
        match ureq::get(&url).timeout(std::time::Duration::from_secs(2)).call() {
            Ok(resp) => resp.status() == 200,
            Err(_) => false,
        }
    }

    /// OpenAI chat completion request format
    #[derive(Serialize)]
    struct ChatRequest {
        model: String,
        messages: Vec<ChatMessage>,
        max_tokens: u32,
        temperature: f32,
        stream: bool,
    }

    #[derive(Serialize)]
    struct ChatMessage {
        role: String,
        content: String,
    }

    /// OpenAI chat completion response format
    #[derive(Deserialize)]
    struct ChatResponse {
        choices: Vec<ChatChoice>,
    }

    #[derive(Deserialize)]
    struct ChatChoice {
        message: ChatChoiceMessage,
    }

    #[derive(Deserialize)]
    struct ChatChoiceMessage {
        content: String,
    }

    /// Submit a generation request. Spawns a background thread that calls the llama.cpp API.
    pub fn submit_request(
        request_id: String,
        prompt: String,
        instructions: String,
        _tools_json: Option<String>,
    ) -> Result<(), String> {
        let port = ensure_server_running()?;

        // Store a pending result
        {
            let mut state = STATE.lock().map_err(|e| format!("Lock poisoned: {e}"))?;
            state.results.insert(request_id.clone(), None);
        }

        // Spawn a thread to make the HTTP request
        let req_id = request_id;
        std::thread::spawn(move || {
            let url = format!("http://127.0.0.1:{}/v1/chat/completions", port);

            let chat_req = ChatRequest {
                model: "local".to_string(),
                messages: vec![
                    ChatMessage {
                        role: "system".to_string(),
                        content: instructions,
                    },
                    ChatMessage {
                        role: "user".to_string(),
                        content: prompt,
                    },
                ],
                max_tokens: 512,
                temperature: 0.3,
                stream: false,
            };

            let result = match ureq::post(&url)
                .timeout(std::time::Duration::from_secs(30))
                .send_json(&chat_req)
            {
                Ok(resp) => {
                    match resp.into_body().read_to_string() {
                        Ok(body) => {
                            match serde_json::from_str::<ChatResponse>(&body) {
                                Ok(chat_resp) => {
                                    if let Some(choice) = chat_resp.choices.first() {
                                        super::LlmResult {
                                            success: true,
                                            text: Some(choice.message.content.clone()),
                                            error: None,
                                        }
                                    } else {
                                        super::LlmResult {
                                            success: false,
                                            text: None,
                                            error: Some("No completion choices returned".into()),
                                        }
                                    }
                                }
                                Err(e) => super::LlmResult {
                                    success: false,
                                    text: None,
                                    error: Some(format!("Failed to parse response: {e}")),
                                },
                            }
                        }
                        Err(e) => super::LlmResult {
                            success: false,
                            text: None,
                            error: Some(format!("Failed to read response body: {e}")),
                        },
                    }
                }
                Err(e) => super::LlmResult {
                    success: false,
                    text: None,
                    error: Some(format!("HTTP request failed: {e}")),
                },
            };

            // Store the result
            if let Ok(mut state) = STATE.lock() {
                state.results.insert(req_id, Some(result));
            }
        });

        Ok(())
    }

    /// Poll for a completed result. Returns None if still pending.
    pub fn poll_result(request_id: &str) -> Option<super::LlmResult> {
        let state = STATE.lock().ok()?;
        state.results.get(request_id).and_then(|r| r.clone())
    }

    /// Cancel a pending request (removes it from the results map).
    pub fn cancel_request(request_id: &str) {
        if let Ok(mut state) = STATE.lock() {
            state.results.remove(request_id);
        }
    }

    /// Check availability: is llama-server + model present?
    pub fn check_availability() -> String {
        let mut state = STATE.lock().unwrap_or_else(|e| e.into_inner());

        // Return cached result if available
        if let Some(ref status) = state.availability {
            return status.clone();
        }

        let server_exists = server_binary().exists();
        let model_exists = find_model().is_some();

        let status = if !server_exists && !model_exists {
            "not_installed".to_string()
        } else if !server_exists {
            "no_server".to_string()
        } else if !model_exists {
            "no_model".to_string()
        } else {
            // Server + model exist, try to start and health check
            drop(state); // Release lock before ensure_server_running
            match ensure_server_running() {
                Ok(port) => {
                    // Give the server a moment to start, then health check
                    // We'll retry up to 5 times with 1-second sleeps
                    let mut available = false;
                    for _ in 0..10 {
                        if health_check(port) {
                            available = true;
                            break;
                        }
                        std::thread::sleep(std::time::Duration::from_millis(1000));
                    }
                    if available {
                        "available".to_string()
                    } else {
                        "not_ready".to_string()
                    }
                }
                Err(_) => "unavailable".to_string(),
            }
        };

        // Re-acquire lock to cache
        if let Ok(mut state) = STATE.lock() {
            state.availability = Some(status.clone());
        }

        status
    }

    /// Reset cached availability so next check re-evaluates.
    pub fn reset_availability() {
        if let Ok(mut state) = STATE.lock() {
            state.availability = None;
        }
    }

    /// Kill the sidecar process on shutdown.
    pub fn shutdown() {
        if let Ok(mut state) = STATE.lock() {
            if let Some(ref mut child) = state.sidecar {
                let _ = child.kill();
                let _ = child.wait();
            }
            state.sidecar = None;
        }
    }
}

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

/// Check if on-device AI is available.
///
/// Returns a string status:
/// - "available" — model is ready to use
/// - "not_eligible" — device doesn't support Apple Intelligence (Apple only)
/// - "not_enabled" — Apple Intelligence is not turned on (Apple only)
/// - "not_ready" — model is downloading or server starting
/// - "not_installed" — llama-server + model not found (Windows only)
/// - "no_server" — llama-server.exe missing (Windows only)
/// - "no_model" — no .gguf model file found (Windows only)
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

    #[cfg(target_os = "windows")]
    {
        windows_llm::check_availability()
    }

    #[cfg(not(any(target_os = "macos", target_os = "ios", target_os = "windows")))]
    {
        "not_native".to_string()
    }
}

/// Reset the cached availability status.
/// Call this after the user might have changed AI settings or installed a model.
#[tauri::command]
pub fn llm_reset_availability() {
    #[cfg(any(target_os = "macos", target_os = "ios"))]
    unsafe {
        wp_llm_reset_availability();
    }

    #[cfg(target_os = "windows")]
    {
        windows_llm::reset_availability();
    }
}

/// Submit a text generation request. Non-blocking — returns immediately.
///
/// The request is processed asynchronously by the on-device model (Apple)
/// or the llama.cpp sidecar (Windows).
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

    #[cfg(target_os = "windows")]
    {
        windows_llm::submit_request(request_id, prompt, instructions, tools_json)?;
        Ok(true)
    }

    #[cfg(not(any(target_os = "macos", target_os = "ios", target_os = "windows")))]
    {
        let _ = (request_id, prompt, instructions, tools_json);
        Err("On-device AI is not available on this platform".into())
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

    #[cfg(target_os = "windows")]
    {
        windows_llm::poll_result(&request_id)
    }

    #[cfg(not(any(target_os = "macos", target_os = "ios", target_os = "windows")))]
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

    #[cfg(target_os = "windows")]
    {
        windows_llm::cancel_request(&request_id);
    }

    #[cfg(not(any(target_os = "macos", target_os = "ios", target_os = "windows")))]
    {
        let _ = request_id;
    }
}

// ── New Windows-specific commands ────────────────────────────────────

/// Get the path where GGUF model files should be placed (Windows only).
/// Returns the full path to the models directory.
#[tauri::command]
pub fn llm_get_models_dir() -> String {
    #[cfg(target_os = "windows")]
    {
        windows_llm::models_dir().to_string_lossy().into_owned()
    }

    #[cfg(not(target_os = "windows"))]
    {
        String::new()
    }
}

/// Get the path where llama-server.exe should be placed (Windows only).
/// Returns the full path to the bin directory.
#[tauri::command]
pub fn llm_get_server_dir() -> String {
    #[cfg(target_os = "windows")]
    {
        windows_llm::server_binary()
            .parent()
            .map(|p| p.to_string_lossy().into_owned())
            .unwrap_or_default()
    }

    #[cfg(not(target_os = "windows"))]
    {
        String::new()
    }
}

/// Gracefully shut down the llama.cpp sidecar process (Windows only).
/// Called when the app is closing.
#[tauri::command]
pub fn llm_shutdown() {
    #[cfg(target_os = "windows")]
    {
        windows_llm::shutdown();
    }
}
