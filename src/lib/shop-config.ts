/**
 * Shop server URL configuration for native devices.
 *
 * Native devices need to know where the shop server is for sync.
 * This is configured once (scan QR or enter IP) and stored persistently.
 * The URL is only used for sync — all daily operations use local SQLite.
 *
 * In browser mode, this module is unused (browser hits the server directly).
 *
 * Storage: localStorage (persists in Tauri's WebView data directory).
 */

const SHOP_URL_KEY = 'shop_url';

/** Get the stored shop server URL, or null if not configured */
export async function getShopUrl(): Promise<string | null> {
  return localStorage.getItem(SHOP_URL_KEY);
}

/** Store the shop server URL */
export async function setShopUrl(url: string): Promise<void> {
  const cleanUrl = url.replace(/\/$/, '');
  localStorage.setItem(SHOP_URL_KEY, cleanUrl);
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
