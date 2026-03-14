/**
 * Database Path Configuration
 *
 * Solves the "chicken-and-egg" problem: the DB path preference can't be
 * stored inside the database — we need to know the path before opening it.
 *
 * Solution: a small JSON sidecar file (`db-config.json`) in the guaranteed
 * per-user Tauri app data directory. This file always lives in a predictable
 * location; it just *points* to where the real database lives.
 *
 * ## Storage Modes
 *
 * **Private (default):**
 * - macOS:   ~/Library/Application Support/com.wiredpart.app/wiredpart.db
 * - Windows: C:\Users\{user}\AppData\Local\wiredpart\wiredpart.db
 * - iOS:     App sandbox (managed by OS)
 *
 * **Public (desktop only):**
 * - macOS:   /Users/Shared/WiredPart/wiredpart.db
 * - Windows: C:\Users\Public\WiredPart\wiredpart.db
 *
 * Public mode lets multiple OS-level user accounts on the same computer
 * share one WiredPart database — important for shop computers where
 * different employees log in to different OS accounts.
 *
 * ## Config File Location (always per-user)
 *
 * - macOS:   ~/Library/Application Support/com.wiredpart.app/db-config.json
 * - Windows: C:\Users\{user}\AppData\Local\wiredpart\db-config.json
 */

import { isDesktop, isTauri, getPlatform } from '../lib/environment';

// ── Types ──────────────────────────────────────────────────────────

export interface DbConfig {
  /** Storage mode: 'private' uses Tauri's app data dir, 'public' uses a shared dir */
  mode: 'private' | 'public';
  /** Absolute path to the DB file when mode === 'public'. Ignored in private mode. */
  customPath?: string;
}

// ── Constants ──────────────────────────────────────────────────────

const CONFIG_FILENAME = 'db-config.json';

const DEFAULT_CONFIG: DbConfig = { mode: 'private' };

/**
 * Well-known public DB paths per platform.
 * These are the recommended default locations for shared access.
 */
export const PUBLIC_DB_PATHS = {
  macos: '/Users/Shared/WiredPart/wiredpart.db',
  windows: 'C:\\Users\\Public\\WiredPart\\wiredpart.db',
} as const;

// ── In-memory cache ────────────────────────────────────────────────

let _cachedConfig: DbConfig | null = null;

// ── Public API ─────────────────────────────────────────────────────

/**
 * Read the current DB path configuration.
 *
 * Returns the default (private mode) if:
 * - Not running in Tauri
 * - Config file doesn't exist yet (first launch)
 * - Config file is corrupted/unreadable
 *
 * Results are cached in memory — the config file is only read once
 * per app session since the DB path can't change without a restart.
 */
export async function getDbConfig(): Promise<DbConfig> {
  if (_cachedConfig) return _cachedConfig;

  if (!isTauri()) {
    _cachedConfig = DEFAULT_CONFIG;
    return _cachedConfig;
  }

  try {
    const { readTextFile, BaseDirectory } = await import('@tauri-apps/plugin-fs');
    const raw = await readTextFile(CONFIG_FILENAME, {
      baseDir: BaseDirectory.AppData,
    });
    const parsed = JSON.parse(raw) as Partial<DbConfig>;

    // Validate shape — don't trust arbitrary JSON
    if (parsed.mode === 'public' && typeof parsed.customPath === 'string') {
      _cachedConfig = { mode: 'public', customPath: parsed.customPath };
    } else {
      _cachedConfig = DEFAULT_CONFIG;
    }
  } catch {
    // File doesn't exist (first launch) or is unreadable — use default
    _cachedConfig = DEFAULT_CONFIG;
  }

  return _cachedConfig;
}

/**
 * Save a new DB path configuration.
 *
 * This writes the config file and updates the in-memory cache.
 * The actual DB connection does NOT change — the user must restart
 * the app for the new path to take effect.
 *
 * @param config - The new configuration to save
 */
export async function saveDbConfig(config: DbConfig): Promise<void> {
  if (!isTauri()) {
    console.warn('[db-config] Cannot save config outside Tauri');
    return;
  }

  try {
    const { writeTextFile, BaseDirectory } = await import('@tauri-apps/plugin-fs');
    const json = JSON.stringify(config, null, 2);
    await writeTextFile(CONFIG_FILENAME, json, {
      baseDir: BaseDirectory.AppData,
    });
    _cachedConfig = config;
    console.log('[db-config] Saved:', config);
  } catch (err) {
    console.error('[db-config] Failed to save config:', err);
    throw err;
  }
}

/**
 * Get the default public DB path for the current platform.
 *
 * Returns null on non-desktop platforms (iOS doesn't support public dirs).
 */
export function getDefaultPublicPath(): string | null {
  if (!isDesktop()) return null;

  const platform = getPlatform();

  if (platform === 'macos') return PUBLIC_DB_PATHS.macos;
  if (platform === 'windows') return PUBLIC_DB_PATHS.windows;
  return null;
}

/**
 * Get the Tauri SQL plugin connection string for the current configuration.
 *
 * - Private mode: `sqlite:wiredpart.db` (relative → Tauri app data dir)
 * - Public mode: `sqlite:/Users/Shared/WiredPart/wiredpart.db` (absolute)
 *
 * The Tauri SQL plugin interprets paths starting with `/` or drive letter
 * as absolute paths, and relative paths as relative to the app data dir.
 */
export async function getDbConnectionString(): Promise<string> {
  const config = await getDbConfig();

  if (config.mode === 'public' && config.customPath) {
    return `sqlite:${config.customPath}`;
  }

  // Default: relative path → Tauri resolves to app data dir
  return 'sqlite:wiredpart.db';
}

/**
 * Clear the cached config. Used during testing or when
 * the config file is known to have changed externally.
 */
export function clearConfigCache(): void {
  _cachedConfig = null;
}
