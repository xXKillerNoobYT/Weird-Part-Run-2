/**
 * Auto-Updater Service — desktop-only self-update mechanism.
 *
 * On desktop (Mac/Windows), checks for new versions from a configured
 * update endpoint. Uses Tauri's updater plugin which handles download,
 * verification (Ed25519 signature), and installation.
 *
 * On mobile (iOS/Android), this service is a no-op — updates go through
 * the App Store / TestFlight.
 *
 * On web (browser), this service is a no-op — the shop server serves
 * the latest frontend build.
 *
 * Usage:
 *   import { checkForUpdate, installUpdate } from './updater-service';
 *   const update = await checkForUpdate();
 *   if (update) {
 *     console.log(`New version: ${update.version}`);
 *     await installUpdate(update); // Downloads, installs, and restarts
 *   }
 */

import { isTauri, isDesktop } from '../../lib/environment';

// ── Types ──────────────────────────────────────────────────────────

export interface UpdateInfo {
  version: string;
  date: string | null;
  body: string | null;  // Release notes (Markdown)
}

export interface UpdateCheckResult {
  available: boolean;
  update: UpdateInfo | null;
  /** The raw Tauri Update object — pass this to installUpdate() */
  _raw: any;
}

// ── Public API ─────────────────────────────────────────────────────

/**
 * Check if a new version is available.
 *
 * Returns null on non-desktop platforms or if no update endpoint is configured.
 * Returns { available: false } if already on the latest version.
 * Returns { available: true, update: { version, date, body } } if a new version exists.
 */
export async function checkForUpdate(): Promise<UpdateCheckResult | null> {
  if (!isDesktop()) return null;

  try {
    const { check } = await import('@tauri-apps/plugin-updater');
    const update = await check();

    if (!update) {
      return { available: false, update: null, _raw: null };
    }

    return {
      available: true,
      update: {
        version: update.version,
        date: update.date ?? null,
        body: update.body ?? null,
      },
      _raw: update,
    };
  } catch (err) {
    console.error('[Updater] Check failed:', err);
    return null;
  }
}

/**
 * Download and install an available update.
 *
 * This will download the update, verify its signature, and restart the app.
 * The user should be prompted before calling this — it's disruptive.
 *
 * @param result — The result from checkForUpdate() (must have available: true)
 */
export async function installUpdate(result: UpdateCheckResult): Promise<void> {
  if (!result.available || !result._raw) {
    console.warn('[Updater] No update available to install');
    return;
  }

  try {
    // downloadAndInstall() handles download → verify → extract → relaunch
    await result._raw.downloadAndInstall();
    // The app will restart after installation — this line may not execute
  } catch (err) {
    console.error('[Updater] Install failed:', err);
    throw err;
  }
}

/**
 * Get the current app version from Tauri config.
 */
export async function getCurrentVersion(): Promise<string> {
  if (!isTauri()) return '0.0.0';

  try {
    const { getVersion } = await import('@tauri-apps/api/app');
    return await getVersion();
  } catch {
    return '0.0.0';
  }
}
