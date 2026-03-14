/**
 * DataStorageSection — Desktop-only settings for DB storage location.
 *
 * Allows users to switch between:
 * - **Private**: Database in per-user app data (default)
 * - **Public**: Database in a shared directory accessible to all OS users
 *
 * This is only relevant on desktop (macOS/Windows) where multiple OS-level
 * user accounts might share one computer at a shop. On mobile/web, this
 * component renders nothing.
 *
 * Switching storage mode:
 * 1. Creates the public directory (Rust IPC → OS-level permissions)
 * 2. Copies the existing DB to the new location
 * 3. Updates db-config.json to point to the new path
 * 4. Prompts for app restart (DB connection is initialized once at startup)
 */

import { useState, useEffect } from 'react';
import { HardDrive, FolderOpen, AlertTriangle, RefreshCw } from 'lucide-react';
import { Card, CardHeader } from '../../../components/ui/Card';
import { Button } from '../../../components/ui/Button';
import { isDesktop, getPlatform, isTauri } from '../../../lib/environment';
import {
  getDbConfig,
  saveDbConfig,
  getDefaultPublicPath,
  type DbConfig,
} from '../../../local/db-config';

/** Render nothing on non-desktop platforms */
export function DataStorageSection() {
  if (!isDesktop()) return null;
  return <DataStorageSectionInner />;
}

function DataStorageSectionInner() {
  const [config, setConfig] = useState<DbConfig | null>(null);
  const [loading, setLoading] = useState(true);
  const [switching, setSwitching] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [needsRestart, setNeedsRestart] = useState(false);

  const platform = getPlatform();
  const publicPath = getDefaultPublicPath();

  // Load current config on mount
  useEffect(() => {
    getDbConfig()
      .then((cfg) => {
        setConfig(cfg);
        setLoading(false);
      })
      .catch((err) => {
        console.error('[DataStorage] Failed to load config:', err);
        setError('Failed to load storage configuration');
        setLoading(false);
      });
  }, []);

  const isPublic = config?.mode === 'public';

  /** Get the display path for the current storage mode */
  function getCurrentPath(): string {
    if (isPublic && config?.customPath) {
      return config.customPath;
    }
    // Private mode — show the platform-specific default
    if (platform === 'macos') {
      return '~/Library/Application Support/com.wiredpart.app/wiredpart.db';
    }
    if (platform === 'windows') {
      return 'C:\\Users\\{user}\\AppData\\Local\\wiredpart\\wiredpart.db';
    }
    return 'App data directory';
  }

  /** Switch between private and public storage */
  async function handleSwitch() {
    if (!isTauri() || !publicPath) return;
    setSwitching(true);
    setError(null);

    try {
      const { invoke } = await import('@tauri-apps/api/core');
      const { appDataDir, join } = await import('@tauri-apps/api/path');

      if (!isPublic) {
        // ── Switching to Public ──────────────────────────────────
        // 1. Create the public directory with correct permissions
        await invoke('create_public_data_dir');

        // 2. Copy existing DB from private → public
        const appData = await appDataDir();
        const privatePath = await join(appData, 'wiredpart.db');
        await invoke('copy_database_file', {
          source: privatePath,
          destination: publicPath,
        });

        // 3. Update config
        const newConfig: DbConfig = { mode: 'public', customPath: publicPath };
        await saveDbConfig(newConfig);
        setConfig(newConfig);
      } else {
        // ── Switching to Private ─────────────────────────────────
        // 1. Copy DB back from public → private (in case edits happened there)
        const appData = await appDataDir();
        const privatePath = await join(appData, 'wiredpart.db');
        if (config?.customPath) {
          await invoke('copy_database_file', {
            source: config.customPath,
            destination: privatePath,
          });
        }

        // 2. Update config
        const newConfig: DbConfig = { mode: 'private' };
        await saveDbConfig(newConfig);
        setConfig(newConfig);
      }

      setNeedsRestart(true);
    } catch (err: any) {
      console.error('[DataStorage] Switch failed:', err);
      setError(String(err?.message || err || 'Switch failed'));
    } finally {
      setSwitching(false);
    }
  }

  /** Prompt user to restart — no programmatic relaunch without the process plugin */
  function handleRestart() {
    // We don't have @tauri-apps/plugin-process installed,
    // so we can't programmatically restart. Just reinforce the message.
    window.alert(
      'Please close and reopen WiredPart for the new database location to take effect.'
    );
  }

  if (loading) {
    return (
      <Card>
        <CardHeader title="Data Storage" />
        <div className="px-4 pb-4">
          <p className="text-sm text-gray-500">Loading...</p>
        </div>
      </Card>
    );
  }

  return (
    <Card>
      <CardHeader title="Data Storage" />
      <div className="px-4 pb-4 space-y-4">
        <p className="text-sm text-gray-500 dark:text-gray-400">
          Choose where the WiredPart database is stored on this computer.
          Public mode lets all user accounts on this machine share the same data.
        </p>

        {/* Current mode indicator */}
        <div className="flex flex-col gap-3">
          {/* Private option */}
          <label
            className={`flex items-start gap-3 p-3 rounded-lg border cursor-pointer transition-colors ${
              !isPublic
                ? 'border-sky-300 bg-sky-50/50 dark:bg-sky-900/10'
                : 'border-border bg-surface hover:bg-surface-secondary'
            }`}
            onClick={() => !switching && isPublic && handleSwitch()}
          >
            <div className={`mt-0.5 ${!isPublic ? 'text-sky-600 dark:text-sky-400' : 'text-gray-400'}`}>
              <HardDrive className="h-5 w-5" />
            </div>
            <div className="flex-1 min-w-0">
              <div className="flex items-center gap-2">
                <span className="font-medium text-sm">Private</span>
                <span className="text-xs text-gray-500">(this user only)</span>
                {!isPublic && (
                  <span className="text-xs bg-sky-100 dark:bg-sky-900/30 text-sky-700 dark:text-sky-300 px-1.5 py-0.5 rounded">
                    Active
                  </span>
                )}
              </div>
              <p className="text-xs text-gray-500 dark:text-gray-400 mt-1 font-mono break-all">
                {platform === 'macos'
                  ? '~/Library/Application Support/com.wiredpart.app/'
                  : 'C:\\Users\\{user}\\AppData\\Local\\wiredpart\\'}
              </p>
            </div>
          </label>

          {/* Public option */}
          <label
            className={`flex items-start gap-3 p-3 rounded-lg border cursor-pointer transition-colors ${
              isPublic
                ? 'border-sky-300 bg-sky-50/50 dark:bg-sky-900/10'
                : 'border-border bg-surface hover:bg-surface-secondary'
            }`}
            onClick={() => !switching && !isPublic && handleSwitch()}
          >
            <div className={`mt-0.5 ${isPublic ? 'text-sky-600 dark:text-sky-400' : 'text-gray-400'}`}>
              <FolderOpen className="h-5 w-5" />
            </div>
            <div className="flex-1 min-w-0">
              <div className="flex items-center gap-2">
                <span className="font-medium text-sm">Public</span>
                <span className="text-xs text-gray-500">(all users on this computer)</span>
                {isPublic && (
                  <span className="text-xs bg-sky-100 dark:bg-sky-900/30 text-sky-700 dark:text-sky-300 px-1.5 py-0.5 rounded">
                    Active
                  </span>
                )}
              </div>
              <p className="text-xs text-gray-500 dark:text-gray-400 mt-1 font-mono break-all">
                {publicPath ?? 'Not available'}
              </p>
            </div>
          </label>
        </div>

        {/* Current path display */}
        <div className="text-xs text-gray-500 dark:text-gray-400">
          <span className="font-medium">Current database:</span>{' '}
          <span className="font-mono break-all">{getCurrentPath()}</span>
        </div>

        {/* Error display */}
        {error && (
          <div className="flex items-start gap-2 p-3 rounded-lg bg-red-50 dark:bg-red-900/10 border border-red-200 dark:border-red-800 text-sm text-red-700 dark:text-red-300">
            <AlertTriangle className="h-4 w-4 mt-0.5 shrink-0" />
            <span>{error}</span>
          </div>
        )}

        {/* Restart prompt */}
        {needsRestart && (
          <div className="flex items-center gap-3 p-3 rounded-lg bg-amber-50 dark:bg-amber-900/10 border border-amber-200 dark:border-amber-800">
            <AlertTriangle className="h-4 w-4 text-amber-600 dark:text-amber-400 shrink-0" />
            <div className="flex-1">
              <p className="text-sm font-medium text-amber-800 dark:text-amber-200">
                Restart required
              </p>
              <p className="text-xs text-amber-600 dark:text-amber-400 mt-0.5">
                The database location has changed. Restart the app to use the new location.
              </p>
            </div>
            <Button size="sm" onClick={handleRestart}>
              <RefreshCw className="h-3.5 w-3.5 mr-1" />
              Restart
            </Button>
          </div>
        )}

        {/* Switching indicator */}
        {switching && (
          <div className="flex items-center gap-2 text-sm text-gray-500">
            <RefreshCw className="h-4 w-4 animate-spin" />
            <span>Copying database...</span>
          </div>
        )}
      </div>
    </Card>
  );
}
