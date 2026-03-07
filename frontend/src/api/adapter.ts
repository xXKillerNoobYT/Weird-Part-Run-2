/**
 * API Adapter — routes requests based on platform.
 *
 * Architecture:
 * - Browser (desktop at shop): requests go to FastAPI via HTTP (axios)
 * - Capacitor (mobile): requests go to local TS services + SQLite
 *
 * For V1.0, the adapter wraps the existing axios-based client for
 * browser mode and provides a stub for the local client that will
 * be implemented in the Lean TS Data Layer (Task 10).
 *
 * The existing api/*.ts files (jobs.ts, parts.ts, etc.) don't change.
 * They import from client.ts which uses this adapter under the hood.
 */

import { isCapacitor } from '../lib/environment';

export type ApiMode = 'http' | 'local';

/** Returns the current API routing mode */
export function getApiMode(): ApiMode {
  return isCapacitor() ? 'local' : 'http';
}

/**
 * Generic request handler that routes to the correct implementation.
 *
 * In browser mode: passes through to axios (existing behavior)
 * In Capacitor mode: delegates to local TS service layer
 *
 * This is used by the api client files when they need platform-aware
 * behavior. Most api/*.ts files can continue using apiClient directly
 * since browser mode is the default and Capacitor mode isn't active
 * until the local data layer is built (Task 10).
 */
export async function adaptedRequest<T>(
  httpFn: () => Promise<T>,
  localFn?: () => Promise<T>,
): Promise<T> {
  if (isCapacitor() && localFn) {
    return localFn();
  }
  return httpFn();
}

/**
 * Check if the current platform supports a feature locally.
 * Some features are shop-only (cost tracking, reports, approvals).
 * In Capacitor mode, these should show a "sync required" message.
 */
export function isFeatureAvailableLocally(feature: string): boolean {
  if (!isCapacitor()) return true; // Browser always has full access

  const localFeatures = new Set([
    'auth',
    'jobs',
    'labor',
    'movement',
    'orders',
    'notebooks',
    'warehouse-read',
    'tools',
    'parts-read',
    'fleet-read',
    'scheduling-read',
  ]);

  return localFeatures.has(feature);
}

/** Shop-only features that require sync to access */
export const SHOP_ONLY_FEATURES = [
  'cost-tracking',
  'approvals',
  'reports',
  'pdf-generation',
  'companions',
  'scheduler',
  'people-admin',
  'settings-admin',
] as const;
