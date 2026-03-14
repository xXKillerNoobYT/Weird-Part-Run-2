/// FoundationModelsBridge.swift — C-compatible interface for Apple Foundation Models.
///
/// This file exposes the FoundationModels framework to Rust via `@_cdecl` functions.
/// The pattern mirrors MultipeerBridge.m but uses Swift instead of ObjC because
/// FoundationModels is a Swift-only framework (iOS 26+ / macOS 26+).
///
/// Architecture:
///   TypeScript → Tauri invoke() → Rust extern "C" → these Swift @_cdecl functions
///
/// Threading: All functions are thread-safe. The internal manager uses an actor
/// for state isolation. Async work is dispatched to a background queue.
///
/// Memory: Strings returned by wp_llm_* functions are malloc'd C strings.
/// The caller MUST free them with wp_llm_free_string().

import Foundation

#if canImport(FoundationModels)
import FoundationModels
#endif

// MARK: - Internal State

/// Thread-safe storage for pending requests and completed results.
/// We use a simple lock-based approach since @_cdecl functions can't be async.
private final class LLMManager: @unchecked Sendable {
    static let shared = LLMManager()

    private let lock = NSLock()

    /// Completed results keyed by request ID
    private var results: [String: String] = [:]

    /// Active tasks that can be cancelled
    private var activeTasks: [String: Task<Void, Never>] = [:]

    /// Whether the model is available (cached after first check)
    private var cachedAvailability: Int32?

    private init() {}

    // MARK: - Availability

    func checkAvailability() -> Int32 {
        if let cached = cachedAvailability {
            return cached
        }

        #if canImport(FoundationModels)
        if #available(iOS 26.0, macOS 26.0, *) {
            let model = SystemLanguageModel.default
            let result: Int32
            switch model.availability {
            case .available:
                result = 0  // Available
            case .unavailable(.deviceNotEligible):
                result = 1  // Device not eligible
            case .unavailable(.appleIntelligenceNotEnabled):
                result = 2  // Apple Intelligence not enabled
            case .unavailable(.modelNotReady):
                result = 3  // Model not ready (downloading)
            case .unavailable(_):
                result = 4  // Unknown unavailable reason
            @unknown default:
                result = 4
            }
            cachedAvailability = result
            return result
        }
        #endif

        return 1  // Not available (OS too old or framework not present)
    }

    /// Reset cached availability (e.g., if user enables Apple Intelligence)
    func resetAvailabilityCache() {
        lock.lock()
        cachedAvailability = nil
        lock.unlock()
    }

    // MARK: - Request Management

    func submitRequest(requestId: String, prompt: String, instructions: String, toolsJson: String?) {
        lock.lock()
        // Cancel any existing request with the same ID
        activeTasks[requestId]?.cancel()
        results.removeValue(forKey: requestId)
        lock.unlock()

        let task = Task { [weak self] in
            guard let self = self else { return }
            let result = await self.executeGeneration(prompt: prompt, instructions: instructions, toolsJson: toolsJson)

            self.lock.lock()
            self.results[requestId] = result
            self.activeTasks.removeValue(forKey: requestId)
            self.lock.unlock()
        }

        lock.lock()
        activeTasks[requestId] = task
        lock.unlock()
    }

    func pollResult(requestId: String) -> String? {
        lock.lock()
        defer { lock.unlock() }
        // If we have a result, remove it from storage and return it
        return results.removeValue(forKey: requestId)
    }

    func cancelRequest(requestId: String) {
        lock.lock()
        activeTasks[requestId]?.cancel()
        activeTasks.removeValue(forKey: requestId)
        results.removeValue(forKey: requestId)
        lock.unlock()
    }

    // MARK: - Generation

    private func executeGeneration(prompt: String, instructions: String, toolsJson: String?) async -> String {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, macOS 26.0, *) {
            do {
                let session = LanguageModelSession(instructions: instructions)
                let response = try await session.respond(to: prompt)

                // Build JSON result
                let resultDict: [String: Any] = [
                    "success": true,
                    "text": response.content,
                    "error": NSNull()
                ]
                if let jsonData = try? JSONSerialization.data(withJSONObject: resultDict),
                   let jsonString = String(data: jsonData, encoding: .utf8) {
                    return jsonString
                }
                return "{\"success\":true,\"text\":\"\(escapeJSON(response.content))\",\"error\":null}"
            } catch {
                let errorMsg = escapeJSON(error.localizedDescription)
                return "{\"success\":false,\"text\":null,\"error\":\"\(errorMsg)\"}"
            }
        }
        #endif

        return "{\"success\":false,\"text\":null,\"error\":\"Foundation Models not available on this OS version\"}"
    }

    /// Escape a string for embedding in JSON
    private func escapeJSON(_ string: String) -> String {
        var result = string
        result = result.replacingOccurrences(of: "\\", with: "\\\\")
        result = result.replacingOccurrences(of: "\"", with: "\\\"")
        result = result.replacingOccurrences(of: "\n", with: "\\n")
        result = result.replacingOccurrences(of: "\r", with: "\\r")
        result = result.replacingOccurrences(of: "\t", with: "\\t")
        return result
    }
}

// MARK: - C FFI Functions (called from Rust via extern "C")

/// Check if the Foundation Models framework is available on this device.
///
/// Returns:
///   0 = available
///   1 = device not eligible
///   2 = Apple Intelligence not enabled
///   3 = model not ready (downloading)
///   4 = unavailable (unknown reason)
@_cdecl("wp_llm_check_availability")
func wpLlmCheckAvailability() -> Int32 {
    return LLMManager.shared.checkAvailability()
}

/// Reset the cached availability status.
/// Call this when the user might have toggled Apple Intelligence in Settings.
@_cdecl("wp_llm_reset_availability")
func wpLlmResetAvailability() {
    LLMManager.shared.resetAvailabilityCache()
}

/// Submit a text generation request. Non-blocking — returns immediately.
/// Poll for the result with wp_llm_poll_result().
///
/// Parameters:
///   - request_id: Unique ID for this request (caller-generated UUID)
///   - prompt: The user's text / question
///   - instructions: System instructions for the model session
///   - tools_json: JSON array of tool definitions (reserved for future use, can be NULL)
///
/// Returns: 0 on success (request queued), -1 on error
@_cdecl("wp_llm_submit_request")
func wpLlmSubmitRequest(
    _ requestId: UnsafePointer<CChar>,
    _ prompt: UnsafePointer<CChar>,
    _ instructions: UnsafePointer<CChar>,
    _ toolsJson: UnsafePointer<CChar>?
) -> Int32 {
    let reqId = String(cString: requestId)
    let promptStr = String(cString: prompt)
    let instructionsStr = String(cString: instructions)
    let toolsStr = toolsJson.map { String(cString: $0) }

    LLMManager.shared.submitRequest(
        requestId: reqId,
        prompt: promptStr,
        instructions: instructionsStr,
        toolsJson: toolsStr
    )

    return 0
}

/// Poll for a completed generation result.
///
/// Returns a malloc'd JSON string if the result is ready, or NULL if still processing.
/// Format: {"success":true,"text":"...","error":null}
///      or {"success":false,"text":null,"error":"..."}
///
/// Caller MUST free the returned string with wp_llm_free_string().
@_cdecl("wp_llm_poll_result")
func wpLlmPollResult(_ requestId: UnsafePointer<CChar>) -> UnsafeMutablePointer<CChar>? {
    let reqId = String(cString: requestId)

    guard let result = LLMManager.shared.pollResult(requestId: reqId) else {
        return nil  // Not ready yet
    }

    // Return a malloc'd copy of the result string
    return strdup(result)
}

/// Cancel a pending generation request.
@_cdecl("wp_llm_cancel_request")
func wpLlmCancelRequest(_ requestId: UnsafePointer<CChar>) {
    let reqId = String(cString: requestId)
    LLMManager.shared.cancelRequest(requestId: reqId)
}

/// Free a string previously returned by wp_llm_* functions.
/// Safe to call with NULL.
@_cdecl("wp_llm_free_string")
func wpLlmFreeString(_ str: UnsafeMutablePointer<CChar>?) {
    guard let str = str else { return }
    free(str)
}
