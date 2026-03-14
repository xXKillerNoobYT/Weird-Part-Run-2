/**
 * Environment detection for the API adapter pattern.
 *
 * The frontend runs in two modes:
 * 1. **Browser** — desktop/laptop at the shop, hitting the FastAPI server over LAN HTTP
 * 2. **Tauri** — native desktop/mobile app with local SQLite via Tauri SQL plugin
 *
 * This module detects which mode we're in so the API adapter can route
 * requests to either HTTP (browser) or local TS services (Tauri).
 */

/** True when running inside a Tauri native shell (Mac, Windows, iOS, Android) */
export function isTauri(): boolean {
  return typeof window !== 'undefined' && '__TAURI__' in window;
}

/** True when running in native mode — uses local data layer */
export function isNativeApp(): boolean {
  return isTauri();
}

/** True when running in a regular browser (desktop or mobile Safari/Chrome) */
export function isBrowser(): boolean {
  return !isNativeApp();
}

/** True when running on a desktop OS (macOS or Windows) — supports public data dir */
export function isDesktop(): boolean {
  if (!isTauri()) return false;
  const platform = getPlatform();
  return platform === 'macos' || platform === 'windows';
}

/** True when running on a mobile OS (iOS or Android) — single-user sandbox storage */
export function isMobile(): boolean {
  if (!isTauri()) return false;
  const platform = getPlatform();
  return platform === 'ios' || platform === 'android';
}

/** Returns the current platform identifier */
export function getPlatform(): 'macos' | 'windows' | 'ios' | 'android' | 'web' {
  if (isTauri()) {
    // Tauri sets __TAURI_ENV_PLATFORM__ at build time
    const tauriPlatform = (window as any).__TAURI_ENV_PLATFORM__;
    if (tauriPlatform === 'macos' || tauriPlatform === 'darwin') return 'macos';
    if (tauriPlatform === 'windows') return 'windows';
    if (tauriPlatform === 'ios') return 'ios';
    if (tauriPlatform === 'android') return 'android';
    // Fallback: detect from user agent
    if (navigator.userAgent.includes('Macintosh')) return 'macos';
    if (navigator.userAgent.includes('Windows')) return 'windows';
    return 'macos'; // Default for Tauri
  }

  return 'web';
}

/**
 * Returns the base URL for API requests.
 *
 * - Browser mode: uses VITE_API_URL or defaults to current origin + /api
 * - Native mode (Tauri): returns null (use local TS services instead)
 */
export function getApiBaseUrl(): string | null {
  if (isNativeApp()) return null; // Local TS data layer handles it
  return import.meta.env.VITE_API_URL || `${window.location.origin}/api`;
}
