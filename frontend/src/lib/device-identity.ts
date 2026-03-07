/**
 * Device Identity — persistent UUID for each physical device.
 *
 * Every device (shop computer, iPad, iPhone, Android phone) gets a
 * unique ID on first launch. This ID is used for:
 * - Change tracking (who made this edit)
 * - Sync protocol (which changes are mine vs. remote)
 * - Conflict resolution (device_id + timestamp = unique change ID)
 *
 * On Capacitor: stored via @capacitor/preferences (survives app updates)
 * On browser: stored in localStorage (tied to browser profile)
 */

import { isCapacitor } from './environment';

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
  if (isCapacitor()) {
    const { Preferences } = await import(/* @vite-ignore */ '@capacitor/preferences');
    const result = await Preferences.get({ key: DEVICE_ID_KEY });
    if (result.value) return result.value;

    const id = generateUUID();
    await Preferences.set({ key: DEVICE_ID_KEY, value: id });
    return id;
  }

  // Browser mode
  let id = localStorage.getItem(DEVICE_ID_KEY);
  if (!id) {
    id = generateUUID();
    localStorage.setItem(DEVICE_ID_KEY, id);
  }
  return id;
}
