/**
 * Auto-Start Service — manage launch-on-boot for the shop computer role.
 *
 * Wraps `tauri-plugin-autostart` to let the office/shop computer
 * automatically start WiredPart on system boot. This ensures the sync
 * server is always available for field devices on the LAN.
 *
 * On non-Tauri platforms this is a no-op (all methods return safe defaults).
 */

import { isTauri } from '../../lib/environment';

/**
 * Check if auto-start is currently enabled.
 */
export async function isAutoStartEnabled(): Promise<boolean> {
  if (!isTauri()) return false;

  try {
    const { isEnabled } = await import('@tauri-apps/plugin-autostart');
    return await isEnabled();
  } catch {
    return false;
  }
}

/**
 * Enable auto-start (launch WiredPart on system boot).
 */
export async function enableAutoStart(): Promise<boolean> {
  if (!isTauri()) return false;

  try {
    const { enable } = await import('@tauri-apps/plugin-autostart');
    await enable();
    console.log('[autostart] Enabled — app will launch on boot');
    return true;
  } catch (err) {
    console.error('[autostart] Failed to enable:', err);
    return false;
  }
}

/**
 * Disable auto-start.
 */
export async function disableAutoStart(): Promise<boolean> {
  if (!isTauri()) return false;

  try {
    const { disable } = await import('@tauri-apps/plugin-autostart');
    await disable();
    console.log('[autostart] Disabled — app will not launch on boot');
    return true;
  } catch (err) {
    console.error('[autostart] Failed to disable:', err);
    return false;
  }
}

/**
 * Toggle auto-start on/off. Returns the new state.
 */
export async function toggleAutoStart(): Promise<boolean> {
  const current = await isAutoStartEnabled();
  if (current) {
    await disableAutoStart();
    return false;
  } else {
    await enableAutoStart();
    return true;
  }
}
