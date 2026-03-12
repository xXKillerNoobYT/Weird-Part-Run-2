/**
 * UserPicker — user selection screen for login.
 *
 * Shows a grid of active users as cards. Each card displays:
 * - Avatar (or initial)
 * - Display name
 * - Hat/role badges
 *
 * Used on public devices and first-time setups.
 * On Capacitor with an empty local DB, shows a setup prompt
 * to connect to the shop server and sync users.
 */

import { useEffect, useState } from 'react';
import { Zap, UserCircle, Wifi } from 'lucide-react';
import { getUsers } from '../../api/auth';
import { isCapacitor } from '../../lib/environment';
import { runInitialSync } from '../../local/sync-engine';
import { getDeviceId } from '../../lib/device-identity';
import type { UserPickerItem } from '../../lib/types';
import { Badge } from '../ui/Badge';
import { Spinner } from '../ui/Spinner';

interface UserPickerProps {
  onSelect: (userId: number, displayName: string) => void;
}

export function UserPicker({ onSelect }: UserPickerProps) {
  const [users, setUsers] = useState<UserPickerItem[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    loadUsers();
  }, []);

  async function loadUsers() {
    setLoading(true);
    setError(null);
    try {
      const data = await getUsers();
      setUsers(data);
    } catch (err) {
      setError('Unable to load users.');
      console.error('Failed to load users:', err);
    } finally {
      setLoading(false);
    }
  }

  return (
    <div className="min-h-screen bg-surface-secondary flex flex-col items-center justify-center p-6">
      {/* Header */}
      <div className="flex items-center gap-3 mb-2">
        <div className="w-10 h-10 rounded-xl bg-primary-500 text-white flex items-center justify-center">
          <Zap className="h-6 w-6" />
        </div>
        <h1 className="text-2xl font-bold text-gray-900 dark:text-gray-100">
          Wired-Part
        </h1>
      </div>
      <p className="text-gray-500 dark:text-gray-400 mb-8">
        Select your name to sign in
      </p>

      {/* Error */}
      {error && (
        <div className="mb-6 px-4 py-3 rounded-lg bg-red-50 dark:bg-red-900/20 text-red-600 dark:text-red-400 text-sm max-w-md text-center">
          {error}
        </div>
      )}

      {/* Loading */}
      {loading && <Spinner size="lg" label="Loading users..." />}

      {/* User Grid */}
      {!loading && users.length > 0 && (
        <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 gap-4 max-w-3xl w-full">
          {users.map((user) => (
            <button
              key={user.id}
              onClick={() => onSelect(user.id, user.display_name)}
              className="flex items-center gap-4 p-4 bg-white dark:bg-gray-800 rounded-xl border border-gray-200 dark:border-gray-700 shadow-sm hover:shadow-md hover:border-primary-300 dark:hover:border-primary-600 transition-all duration-150 text-left"
            >
              {/* Avatar */}
              {user.avatar_url ? (
                <img
                  src={user.avatar_url}
                  alt={user.display_name}
                  className="w-12 h-12 rounded-full object-cover"
                />
              ) : (
                <div className="w-12 h-12 rounded-full bg-primary-100 dark:bg-primary-900 flex items-center justify-center">
                  <UserCircle className="w-8 h-8 text-primary-500" />
                </div>
              )}

              {/* Info */}
              <div className="flex-1 min-w-0">
                <p className="text-sm font-semibold text-gray-900 dark:text-gray-100 truncate">
                  {user.display_name}
                </p>
                <div className="flex flex-wrap gap-1 mt-1">
                  {user.hats.map((hat) => (
                    <Badge key={hat} variant="primary">
                      {hat}
                    </Badge>
                  ))}
                </div>
              </div>
            </button>
          ))}
        </div>
      )}

      {/* No users — Capacitor: show setup prompt, Browser: show generic message */}
      {!loading && users.length === 0 && !error && (
        isCapacitor() ? (
          <CapacitorSetupPrompt onSynced={() => loadUsers()} />
        ) : (
          <p className="text-gray-500 dark:text-gray-400">
            No users found. The database may need to be initialized.
          </p>
        )
      )}
    </div>
  );
}

// ── First-time setup for Capacitor devices ─────────────────────────

function CapacitorSetupPrompt({ onSynced }: { onSynced: () => void }) {
  const [url, setUrl] = useState('');
  const [checking, setChecking] = useState(false);
  const [syncing, setSyncing] = useState(false);
  const [status, setStatus] = useState<string | null>(null);
  const [promptError, setPromptError] = useState<string | null>(null);

  async function handleConnect() {
    if (!url.trim()) return;
    setChecking(true);
    setPromptError(null);
    setStatus(null);

    try {
      const { setShopUrl, isShopReachable } = await import('../../lib/shop-config');
      const cleanUrl = url.trim().replace(/\/+$/, '');
      await setShopUrl(cleanUrl);
      const reachable = await isShopReachable();

      if (!reachable) {
        setPromptError('Cannot reach that server. Check the URL and try again.');
        setChecking(false);
        return;
      }

      setStatus('Connected! Syncing data...');
      setChecking(false);
      setSyncing(true);

      const deviceId = await getDeviceId();
      const success = await runInitialSync(deviceId);

      if (success) {
        setStatus('Sync complete!');
        setSyncing(false);
        onSynced();
      } else {
        setPromptError('Sync failed. Check connection and try again.');
        setSyncing(false);
      }
    } catch (err) {
      console.error('Setup connection failed:', err);
      setPromptError('Connection failed. Please check the URL.');
      setChecking(false);
      setSyncing(false);
    }
  }

  return (
    <div className="max-w-sm w-full text-center space-y-4">
      <div className="flex justify-center mb-2">
        <div className="w-12 h-12 rounded-full bg-blue-50 dark:bg-blue-900/30 flex items-center justify-center">
          <Wifi className="w-6 h-6 text-blue-500" />
        </div>
      </div>
      <p className="text-gray-600 dark:text-gray-400 text-sm">
        No users on this device yet. Enter your shop server address to sync.
      </p>
      <input
        type="url"
        value={url}
        onChange={(e) => setUrl(e.target.value)}
        onKeyDown={(e) => e.key === 'Enter' && handleConnect()}
        placeholder="http://192.168.1.100:8000"
        className="w-full px-3 py-2.5 text-sm border border-gray-300 dark:border-gray-600 rounded-lg bg-white dark:bg-gray-800 text-gray-900 dark:text-gray-100 placeholder-gray-400 focus:ring-2 focus:ring-primary-500 focus:border-primary-500 outline-none"
      />
      <button
        onClick={handleConnect}
        disabled={!url.trim() || checking || syncing}
        className="w-full px-4 py-2.5 text-sm font-medium rounded-lg bg-primary-500 text-white hover:bg-primary-600 disabled:opacity-50 disabled:cursor-not-allowed transition-colors"
      >
        {checking ? 'Connecting...' : syncing ? 'Syncing...' : 'Connect to Shop'}
      </button>
      {status && (
        <p className="text-sm text-green-600 dark:text-green-400">{status}</p>
      )}
      {promptError && (
        <p className="text-sm text-red-600 dark:text-red-400">{promptError}</p>
      )}
    </div>
  );
}
