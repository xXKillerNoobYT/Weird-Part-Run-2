/**
 * MultipeerBridge.h — C-compatible interface for Apple Multipeer Connectivity.
 *
 * This header defines the FFI boundary between Rust (Tauri) and ObjC.
 * All functions use C types only — no ObjC or C++ types exposed.
 *
 * Thread safety: All functions are thread-safe. The ObjC implementation
 * uses a serial dispatch queue for internal state mutations.
 *
 * Memory: Strings returned by wp_multipeer_* functions are malloc'd.
 * The caller MUST free them with wp_multipeer_free_string().
 */

#ifndef MULTIPEER_BRIDGE_H
#define MULTIPEER_BRIDGE_H

#include <stdint.h>
#include <stdbool.h>

#ifdef __cplusplus
extern "C" {
#endif

/**
 * Initialize the Multipeer manager with device identity.
 *
 * @param device_id   UUID string identifying this device
 * @param device_name Human-readable name (e.g. "Shop Computer")
 * @param company_id  Company identifier for same-company filtering
 * @return 0 on success, -1 on failure
 */
int wp_multipeer_init(const char *device_id,
                      const char *device_name,
                      const char *company_id);

/**
 * Start advertising and browsing for peers.
 * Must call wp_multipeer_init() first.
 *
 * @return 0 on success, -1 if not initialized or already running
 */
int wp_multipeer_start(void);

/**
 * Stop advertising and browsing. Disconnects all peers.
 */
void wp_multipeer_stop(void);

/**
 * Clean up all resources. Call on app shutdown.
 */
void wp_multipeer_cleanup(void);

/**
 * Get JSON array of discovered peers.
 *
 * Returns a malloc'd JSON string. Caller must free with wp_multipeer_free_string().
 * Format: [{"device_id":"...","device_name":"...","company_id":"...","state":"found|connecting|connected"}]
 *
 * @return JSON string (never NULL — returns "[]" if no peers)
 */
char *wp_multipeer_get_peers_json(void);

/**
 * Send data to a specific connected peer.
 *
 * @param peer_device_id The device_id of the target peer
 * @param data           Raw bytes to send
 * @param len            Length of data in bytes
 * @return 0 on success, -1 on failure (peer not connected, send error)
 */
int wp_multipeer_send(const char *peer_device_id,
                      const uint8_t *data,
                      uint32_t len);

/**
 * Pop the next received message from the queue.
 *
 * Returns a malloc'd JSON string with the message, or NULL if queue is empty.
 * Format: {"from_device_id":"...","data":"<base64-encoded>","received_at":"<ISO8601>"}
 *
 * Caller must free with wp_multipeer_free_string().
 *
 * @return JSON string or NULL
 */
char *wp_multipeer_pop_received(void);

/**
 * Get the number of messages waiting in the receive queue.
 *
 * @return Number of pending messages
 */
uint32_t wp_multipeer_receive_count(void);

/**
 * Check if the Multipeer manager is currently running (advertising + browsing).
 *
 * @return true if running, false otherwise
 */
bool wp_multipeer_is_running(void);

/**
 * Free a string previously returned by wp_multipeer_* functions.
 * Safe to call with NULL.
 *
 * @param str String to free
 */
void wp_multipeer_free_string(char *str);

#ifdef __cplusplus
}
#endif

#endif /* MULTIPEER_BRIDGE_H */
