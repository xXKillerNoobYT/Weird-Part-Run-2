/**
 * Shop server URL configuration for mobile devices.
 *
 * Mobile devices need to know where the shop server is for sync.
 * This is configured once (scan QR or enter IP) and stored persistently.
 * The URL is only used for sync — all daily operations use local SQLite.
 *
 * In browser mode, this module is unused (browser hits the server directly).
 */

import { isCapacitor } from './environment';

const SHOP_URL_KEY = 'shop_url';

/** Get the stored shop server URL, or null if not configured */
export async function getShopUrl(): Promise<string | null> {
  if (isCapacitor()) {
    // Use Capacitor Preferences for persistent storage
    const { Preferences } = await import(/* @vite-ignore */ '@capacitor/preferences');
    const result = await Preferences.get({ key: SHOP_URL_KEY });
    return result.value;
  }
  // Browser fallback — use localStorage
  return localStorage.getItem(SHOP_URL_KEY);
}

/** Store the shop server URL */
export async function setShopUrl(url: string): Promise<void> {
  const cleanUrl = url.replace(/\/$/, '');
  if (isCapacitor()) {
    const { Preferences } = await import(/* @vite-ignore */ '@capacitor/preferences');
    await Preferences.set({ key: SHOP_URL_KEY, value: cleanUrl });
  } else {
    localStorage.setItem(SHOP_URL_KEY, cleanUrl);
  }
}

/** Check if the shop server is reachable (for sync) */
export async function isShopReachable(): Promise<boolean> {
  const url = await getShopUrl();
  if (!url) return false;
  try {
    const response = await fetch(`${url}/api/health`, {
      signal: AbortSignal.timeout(3000),
    });
    return response.ok;
  } catch {
    return false;
  }
}

/** Fetch server info from shop (hostname, version, etc.) */
export async function getShopInfo(): Promise<{
  hostname: string;
  local_ip: string;
  port: number;
  url: string;
  version: string;
  app: string;
} | null> {
  const url = await getShopUrl();
  if (!url) return null;
  try {
    const response = await fetch(`${url}/api/server-info`, {
      signal: AbortSignal.timeout(3000),
    });
    if (!response.ok) return null;
    return response.json();
  } catch {
    return null;
  }
}
