/**
 * Device Identity — persistent UUID for each physical device.
 *
 * Every device (shop computer, iPad, iPhone, Windows PC) gets a
 * unique ID on first launch. This ID is used for:
 * - Change tracking (who made this edit)
 * - Sync protocol (which changes are mine vs. remote)
 * - Conflict resolution (device_id + timestamp = unique change ID)
 *
 * Storage: localStorage (persists in Tauri's WebView data directory,
 * tied to browser profile in browser mode).
 */

const DEVICE_ID_KEY = 'wiredpart_device_id';

/** Generate a UUID v4 */
function generateUUID(): string {
  if (typeof crypto !== 'undefined' && crypto.randomUUID) {
    return crypto.randomUUID();
  }
  // Fallback for older browsers
  return 'xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx'.replace(/[xy]/g, (c) => {
    const r = (Math.random() * 16) | 0;
    const v = c === 'x' ? r : (r & 0x3) | 0x8;
    return v.toString(16);
  });
}

/** Get or create a persistent device ID */
export async function getDeviceId(): Promise<string> {
  let id = localStorage.getItem(DEVICE_ID_KEY);
  if (!id) {
    id = generateUUID();
    localStorage.setItem(DEVICE_ID_KEY, id);
  }
  return id;
}
