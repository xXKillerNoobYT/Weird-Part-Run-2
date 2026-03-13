/**
 * API Adapter — routes requests based on platform.
 *
 * Architecture:
 * - Browser (desktop at shop): requests go to FastAPI via HTTP (axios)
 * - Tauri (native app): requests go to local TS services + SQLite
 *
 * The existing api/*.ts files (jobs.ts, parts.ts, etc.) don't change.
 * They import from client.ts which uses this adapter under the hood.
 *
 * In Tauri mode, ALL features are available locally — the full data layer
 * runs on every device. There are no "shop-only" features in Tauri mode.
 */

import { isNativeApp } from '../lib/environment';

export type ApiMode = 'http' | 'local';

/** Returns the current API routing mode */
export function getApiMode(): ApiMode {
  return isNativeApp() ? 'local' : 'http';
}

/**
 * Generic request handler that routes to the correct implementation.
 *
 * In browser mode: passes through to axios (existing behavior)
 * In native mode (Tauri): delegates to local TS service layer
 */
export async function adaptedRequest<T>(
  httpFn: () => Promise<T>,
  localFn?: () => Promise<T>,
): Promise<T> {
  if (isNativeApp() && localFn) {
    return localFn();
  }
  return httpFn();
}

/**
 * Check if the current platform supports a feature locally.
 * Both Tauri and Browser have full access to all features.
 */
export function isFeatureAvailableLocally(_feature: string): boolean {
  return true; // Tauri has full local data layer, browser has full HTTP access
}

/**
 * Features that require sync for up-to-date data.
 * In Tauri mode these all work locally, but data may be stale
 * if the device hasn't synced recently.
 */
export const SYNC_DEPENDENT_FEATURES = [
  'cost-tracking',
  'approvals',
  'reports',
  'pdf-generation',
  'companions',
  'scheduler',
  'people-admin',
  'settings-admin',
] as const;
