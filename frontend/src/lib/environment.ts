/**
 * Environment detection for the API adapter pattern.
 *
 * The frontend runs in two modes:
 * 1. **Browser** — desktop/laptop at the shop, hitting the FastAPI server over LAN HTTP
 * 2. **Capacitor** — mobile device with local SQLite, syncing with shop over LAN when available
 *
 * This module detects which mode we're in so the API adapter can route
 * requests to either HTTP (browser) or local TS services (Capacitor).
 */

/** True when running inside a Capacitor native shell (iOS/Android) */
export function isCapacitor(): boolean {
  return (
    typeof window !== 'undefined' &&
    window.hasOwnProperty('Capacitor') &&
    (window as any).Capacitor?.isNativePlatform?.() === true
  );
}

/** True when running in a regular browser (desktop or mobile Safari/Chrome) */
export function isBrowser(): boolean {
  return !isCapacitor();
}

/** Returns 'ios' | 'android' | 'web' */
export function getPlatform(): 'ios' | 'android' | 'web' {
  if (!isCapacitor()) return 'web';
  const platform = (window as any).Capacitor?.getPlatform?.();
  if (platform === 'ios') return 'ios';
  if (platform === 'android') return 'android';
  return 'web';
}

/**
 * Returns the base URL for API requests.
 *
 * - Browser mode: uses VITE_API_URL or defaults to current origin + /api
 * - Capacitor mode: returns null (use local TS services instead)
 */
export function getApiBaseUrl(): string | null {
  if (isCapacitor()) return null; // Local TS data layer handles it
  return import.meta.env.VITE_API_URL || `${window.location.origin}/api`;
}
