/**
 * UserPicker — user selection screen for login.
 *
 * Shows a grid of active users as cards. Each card displays:
 * - Avatar (or initial)
 * - Display name
 * - Hat/role badges
 *
 * Used on public devices and first-time setups.
 * On native (Tauri) with an empty local DB, shows a setup prompt
 * offering two paths:
 *   1. "Set Up New Company" — creates first admin user locally
 *   2. "Sync from Another Device" — connects to an existing peer
 */

import { useEffect, useState } from 'react';
import { Zap, UserCircle, Wifi, Plus, ArrowLeft, ShieldCheck } from 'lucide-react';
import { getUsers } from '../../api/auth';
import { isNativeApp } from '../../lib/environment';
import { runInitialSync } from '../../local/sync-engine';
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

      // Sort last-logged-in user to the top for faster re-login.
      // Any user on any device — the device remembers who used it last.
      const lastUserId = localStorage.getItem('wiredpart_last_user');
      if (lastUserId) {
        const id = Number(lastUserId);
        data.sort((a, b) => {
          if (a.id === id) return -1;
          if (b.id === id) return 1;
          return 0; // preserve original order for everyone else
        });
      }

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

      {/* No users — Native: show setup prompt, Browser: show generic message */}
      {!loading && users.length === 0 && !error && (
        isNativeApp() ? (
          <NativeSetupPrompt onSynced={() => loadUsers()} />
        ) : (
          <p className="text-gray-500 dark:text-gray-400">
            No users found. The database may need to be initialized.
          </p>
        )
      )}
    </div>
  );
}

// ── First-time setup for native devices ─────────────────────────────
//
// Two paths:
//   "Set Up New Company"     → seedFirstAdmin() → creates hats, perms, first user
//   "Sync from Another Device" → runInitialSync() → pulls data from any peer

type SetupMode = 'choose' | 'new-company' | 'sync-device';

function NativeSetupPrompt({ onSynced }: { onSynced: () => void }) {
  const [mode, setMode] = useState<SetupMode>('choose');

  if (mode === 'new-company') {
    return <NewCompanyForm onComplete={onSynced} onBack={() => setMode('choose')} />;
  }
  if (mode === 'sync-device') {
    return <SyncFromDeviceForm onSynced={onSynced} onBack={() => setMode('choose')} />;
  }

  // ── Mode chooser ─────────────────────────────────────────────────
  return (
    <div className="max-w-sm w-full text-center space-y-5">
      <p className="text-gray-600 dark:text-gray-400 text-sm">
        Welcome! How would you like to get started?
      </p>

      {/* Option 1: Brand new company */}
      <button
        onClick={() => setMode('new-company')}
        className="w-full flex items-center gap-4 p-4 bg-white dark:bg-gray-800 rounded-xl border border-gray-200 dark:border-gray-700 shadow-sm hover:shadow-md hover:border-primary-300 dark:hover:border-primary-600 transition-all text-left"
      >
        <div className="w-10 h-10 rounded-full bg-primary-50 dark:bg-primary-900/30 flex items-center justify-center shrink-0">
          <Plus className="w-5 h-5 text-primary-500" />
        </div>
        <div>
          <p className="text-sm font-semibold text-gray-900 dark:text-gray-100">
            Set Up New Company
          </p>
          <p className="text-xs text-gray-500 dark:text-gray-400 mt-0.5">
            This is the first device — create your admin account
          </p>
        </div>
      </button>

      {/* Option 2: Join existing fleet */}
      <button
        onClick={() => setMode('sync-device')}
        className="w-full flex items-center gap-4 p-4 bg-white dark:bg-gray-800 rounded-xl border border-gray-200 dark:border-gray-700 shadow-sm hover:shadow-md hover:border-blue-300 dark:hover:border-blue-600 transition-all text-left"
      >
        <div className="w-10 h-10 rounded-full bg-blue-50 dark:bg-blue-900/30 flex items-center justify-center shrink-0">
          <Wifi className="w-5 h-5 text-blue-500" />
        </div>
        <div>
          <p className="text-sm font-semibold text-gray-900 dark:text-gray-100">
            Sync from Another Device
          </p>
          <p className="text-xs text-gray-500 dark:text-gray-400 mt-0.5">
            Join an existing team — connect to any device on your network
          </p>
        </div>
      </button>
    </div>
  );
}

// ── New Company Setup Form ───────────────────────────────────────────

function NewCompanyForm({
  onComplete,
  onBack,
}: {
  onComplete: () => void;
  onBack: () => void;
}) {
  const [name, setName] = useState('');
  const [pin, setPin] = useState('');
  const [pinConfirm, setPinConfirm] = useState('');
  const [creating, setCreating] = useState(false);
  const [formError, setFormError] = useState<string | null>(null);

  async function handleCreate() {
    // Validate
    if (!name.trim()) {
      setFormError('Enter your name.');
      return;
    }
    if (pin.length < 4) {
      setFormError('PIN must be at least 4 digits.');
      return;
    }
    if (pin !== pinConfirm) {
      setFormError('PINs do not match.');
      return;
    }

    setCreating(true);
    setFormError(null);

    try {
      const { seedFirstAdmin } = await import('../../local/services/auth-service');
      const result = await seedFirstAdmin(name.trim(), pin);

      if (!result.success) {
        setFormError(result.message);
        setCreating(false);
        return;
      }

      // Store the token so the user is immediately logged in
      if (result.token) {
        localStorage.setItem('wiredpart_token', result.token);
      }

      setCreating(false);
      onComplete();
    } catch (err) {
      console.error('First admin setup failed:', err);
      setFormError('Setup failed. Please try again.');
      setCreating(false);
    }
  }

  return (
    <div className="max-w-sm w-full space-y-4">
      <button
        onClick={onBack}
        className="flex items-center gap-1 text-sm text-gray-500 dark:text-gray-400 hover:text-gray-700 dark:hover:text-gray-200 transition-colors"
      >
        <ArrowLeft className="w-4 h-4" /> Back
      </button>

      <div className="text-center">
        <div className="flex justify-center mb-2">
          <div className="w-12 h-12 rounded-full bg-primary-50 dark:bg-primary-900/30 flex items-center justify-center">
            <Plus className="w-6 h-6 text-primary-500" />
          </div>
        </div>
        <h2 className="text-lg font-semibold text-gray-900 dark:text-gray-100">
          Create Admin Account
        </h2>
        <p className="text-sm text-gray-500 dark:text-gray-400 mt-1">
          You'll be the first user. Add more people later from the People page.
        </p>
      </div>

      <div className="space-y-3">
        <input
          type="text"
          value={name}
          onChange={(e) => setName(e.target.value)}
          placeholder="Your name"
          autoFocus
          className="w-full px-3 py-2.5 text-sm border border-gray-300 dark:border-gray-600 rounded-lg bg-white dark:bg-gray-800 text-gray-900 dark:text-gray-100 placeholder-gray-400 focus:ring-2 focus:ring-primary-500 focus:border-primary-500 outline-none"
        />
        <input
          type="password"
          inputMode="numeric"
          value={pin}
          onChange={(e) => setPin(e.target.value.replace(/\D/g, ''))}
          placeholder="Choose a PIN (4+ digits)"
          maxLength={8}
          className="w-full px-3 py-2.5 text-sm border border-gray-300 dark:border-gray-600 rounded-lg bg-white dark:bg-gray-800 text-gray-900 dark:text-gray-100 placeholder-gray-400 focus:ring-2 focus:ring-primary-500 focus:border-primary-500 outline-none"
        />
        <input
          type="password"
          inputMode="numeric"
          value={pinConfirm}
          onChange={(e) => setPinConfirm(e.target.value.replace(/\D/g, ''))}
          onKeyDown={(e) => e.key === 'Enter' && handleCreate()}
          placeholder="Confirm PIN"
          maxLength={8}
          className="w-full px-3 py-2.5 text-sm border border-gray-300 dark:border-gray-600 rounded-lg bg-white dark:bg-gray-800 text-gray-900 dark:text-gray-100 placeholder-gray-400 focus:ring-2 focus:ring-primary-500 focus:border-primary-500 outline-none"
        />
      </div>

      <button
        onClick={handleCreate}
        disabled={creating}
        className="w-full px-4 py-2.5 text-sm font-medium rounded-lg bg-primary-500 text-white hover:bg-primary-600 disabled:opacity-50 disabled:cursor-not-allowed transition-colors"
      >
        {creating ? 'Setting up...' : 'Create Account'}
      </button>

      {formError && (
        <p className="text-sm text-red-600 dark:text-red-400 text-center">{formError}</p>
      )}
    </div>
  );
}

// ── Sync From Another Device Form ────────────────────────────────────
//
// Three-step flow:
//   Step 1 — Enter shop URL, verify reachable
//   Step 2 — Pick an admin user + enter PIN (authenticates against remote shop)
//   Step 3 — Run initial sync using the admin's token
//
// Why admin auth? The shop's /api/sync/initial endpoint requires the
// `manage_devices` permission. Only Admins have this by default. A random
// worker can't add devices to the fleet — only someone with the right hat.

type SyncStep = 'url' | 'auth' | 'syncing';

function SyncFromDeviceForm({
  onSynced,
  onBack,
}: {
  onSynced: () => void;
  onBack: () => void;
}) {
  const [step, setStep] = useState<SyncStep>('url');
  const [shopUrl, setShopUrl] = useState('');
  const [checking, setChecking] = useState(false);
  const [syncing, setSyncing] = useState(false);
  const [status, setStatus] = useState<string | null>(null);
  const [promptError, setPromptError] = useState<string | null>(null);

  // Remote user picker
  const [remoteUsers, setRemoteUsers] = useState<UserPickerItem[]>([]);
  const [loadingUsers, setLoadingUsers] = useState(false);
  const [selectedUserId, setSelectedUserId] = useState<number | null>(null);
  const [selectedUserName, setSelectedUserName] = useState('');
  const [pin, setPin] = useState('');
  const [authError, setAuthError] = useState<string | null>(null);
  const [authenticating, setAuthenticating] = useState(false);

  // ── Step 1: Connect to shop ──────────────────────────────────────

  async function handleConnect() {
    if (!shopUrl.trim()) return;
    setChecking(true);
    setPromptError(null);

    try {
      const { setShopUrl: saveShopUrl, isShopReachable } = await import('../../lib/shop-config');
      const cleanUrl = shopUrl.trim().replace(/\/+$/, '');
      await saveShopUrl(cleanUrl);
      const reachable = await isShopReachable();

      if (!reachable) {
        setPromptError('Cannot reach that device. Make sure you\'re on the same network and try again.');
        setChecking(false);
        return;
      }

      // Fetch user list from the remote shop
      setLoadingUsers(true);
      setChecking(false);

      try {
        const resp = await fetch(`${cleanUrl}/api/auth/users`);
        if (!resp.ok) throw new Error('Failed to fetch users');
        const json = await resp.json();
        const users: UserPickerItem[] = json.data ?? [];
        setRemoteUsers(users);
        setStep('auth');
      } catch (err) {
        console.error('Failed to fetch remote users:', err);
        setPromptError('Connected but couldn\'t load user list. Check the server.');
      } finally {
        setLoadingUsers(false);
      }
    } catch (err) {
      console.error('Connection check failed:', err);
      setPromptError('Connection failed. Please check the address.');
      setChecking(false);
    }
  }

  // ── Step 2: Authenticate as admin ────────────────────────────────

  async function handleAdminAuth() {
    if (!selectedUserId || pin.length < 4) return;
    setAuthenticating(true);
    setAuthError(null);

    const cleanUrl = shopUrl.trim().replace(/\/+$/, '');
    const { generateDeviceFingerprint, getDeviceName } = await import('../../lib/utils');
    const fp = generateDeviceFingerprint();
    const name = getDeviceName();

    try {
      // Authenticate against the remote shop
      const resp = await fetch(`${cleanUrl}/api/auth/pin-login`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          user_id: selectedUserId,
          pin,
          device_fingerprint: fp,
          device_name: name,
        }),
      });

      if (!resp.ok) {
        const errData = await resp.json().catch(() => ({}));
        const detail = errData.detail ?? 'Invalid PIN. Try again.';
        setAuthError(detail);
        setPin('');
        setAuthenticating(false);
        return;
      }

      const json = await resp.json();
      const token = json.data?.access_token;
      if (!token) {
        setAuthError('Authentication succeeded but no token received.');
        setAuthenticating(false);
        return;
      }

      // Store token so runInitialSync can use it
      localStorage.setItem('wiredpart_token', token);
      setAuthenticating(false);

      // ── Step 3: Run initial sync ─────────────────────────────────

      setStep('syncing');
      setSyncing(true);
      setStatus('Authenticated! Syncing data from shop...');

      const deviceId = await (await import('../../lib/device-identity')).getDeviceId();
      const success = await runInitialSync(deviceId);

      if (success) {
        setStatus('Sync complete! All data loaded.');
        setSyncing(false);
        onSynced();
      } else {
        // Check if it was a permission error
        setPromptError(
          'Sync failed. This user may not have permission to add devices. ' +
          'Make sure you sign in with an Admin account.'
        );
        setSyncing(false);
        setStep('auth');
        localStorage.removeItem('wiredpart_token');
      }
    } catch (err) {
      console.error('Admin auth failed:', err);
      setAuthError('Authentication failed. Check credentials and try again.');
      setAuthenticating(false);
    }
  }

  // ── Step 1 UI: Enter shop URL ────────────────────────────────────

  if (step === 'url') {
    return (
      <div className="max-w-sm w-full space-y-4">
        <button
          onClick={onBack}
          className="flex items-center gap-1 text-sm text-gray-500 dark:text-gray-400 hover:text-gray-700 dark:hover:text-gray-200 transition-colors"
        >
          <ArrowLeft className="w-4 h-4" /> Back
        </button>

        <div className="text-center">
          <div className="flex justify-center mb-2">
            <div className="w-12 h-12 rounded-full bg-blue-50 dark:bg-blue-900/30 flex items-center justify-center">
              <Wifi className="w-6 h-6 text-blue-500" />
            </div>
          </div>
          <h2 className="text-lg font-semibold text-gray-900 dark:text-gray-100">
            Sync from Another Device
          </h2>
          <p className="text-sm text-gray-500 dark:text-gray-400 mt-1">
            Enter the address of any device already running Wired-Part on your network.
          </p>
        </div>

        <input
          type="url"
          value={shopUrl}
          onChange={(e) => setShopUrl(e.target.value)}
          onKeyDown={(e) => e.key === 'Enter' && handleConnect()}
          placeholder="http://192.168.1.100:8000"
          autoFocus
          className="w-full px-3 py-2.5 text-sm border border-gray-300 dark:border-gray-600 rounded-lg bg-white dark:bg-gray-800 text-gray-900 dark:text-gray-100 placeholder-gray-400 focus:ring-2 focus:ring-primary-500 focus:border-primary-500 outline-none"
        />

        <button
          onClick={handleConnect}
          disabled={!shopUrl.trim() || checking || loadingUsers}
          className="w-full px-4 py-2.5 text-sm font-medium rounded-lg bg-blue-500 text-white hover:bg-blue-600 disabled:opacity-50 disabled:cursor-not-allowed transition-colors"
        >
          {checking ? 'Connecting...' : loadingUsers ? 'Loading users...' : 'Connect'}
        </button>

        {promptError && (
          <p className="text-sm text-red-600 dark:text-red-400 text-center">{promptError}</p>
        )}
      </div>
    );
  }

  // ── Step 2 UI: Admin auth ────────────────────────────────────────

  if (step === 'auth') {
    return (
      <div className="max-w-sm w-full space-y-4">
        <button
          onClick={() => { setStep('url'); setSelectedUserId(null); setPin(''); setAuthError(null); }}
          className="flex items-center gap-1 text-sm text-gray-500 dark:text-gray-400 hover:text-gray-700 dark:hover:text-gray-200 transition-colors"
        >
          <ArrowLeft className="w-4 h-4" /> Change device
        </button>

        <div className="text-center">
          <div className="flex justify-center mb-2">
            <div className="w-12 h-12 rounded-full bg-amber-50 dark:bg-amber-900/30 flex items-center justify-center">
              <ShieldCheck className="w-6 h-6 text-amber-600" />
            </div>
          </div>
          <h2 className="text-lg font-semibold text-gray-900 dark:text-gray-100">
            Admin Authorization Required
          </h2>
          <p className="text-sm text-gray-500 dark:text-gray-400 mt-1">
            Sign in with an <strong>Admin</strong> account from the existing device to authorize this new device.
          </p>
        </div>

        {/* Remote user selection */}
        {!selectedUserId ? (
          <div className="space-y-2 max-h-64 overflow-y-auto">
            {remoteUsers.length === 0 ? (
              <p className="text-sm text-gray-500 text-center py-4">
                No users found on the remote device.
              </p>
            ) : (
              remoteUsers.map((user) => (
                <button
                  key={user.id}
                  onClick={() => {
                    setSelectedUserId(user.id);
                    setSelectedUserName(user.display_name);
                    setAuthError(null);
                    setPin('');
                  }}
                  className="w-full flex items-center gap-3 p-3 bg-white dark:bg-gray-800 rounded-lg border border-gray-200 dark:border-gray-700 hover:border-primary-300 dark:hover:border-primary-600 transition-all text-left"
                >
                  <div className="w-10 h-10 rounded-full bg-primary-100 dark:bg-primary-900 flex items-center justify-center shrink-0">
                    <UserCircle className="w-6 h-6 text-primary-500" />
                  </div>
                  <div className="flex-1 min-w-0">
                    <p className="text-sm font-semibold text-gray-900 dark:text-gray-100 truncate">
                      {user.display_name}
                    </p>
                    <div className="flex flex-wrap gap-1 mt-0.5">
                      {user.hats.map((hat) => (
                        <Badge key={hat} variant={hat === 'Admin' ? 'warning' : 'primary'}>
                          {hat}
                        </Badge>
                      ))}
                    </div>
                  </div>
                </button>
              ))
            )}
          </div>
        ) : (
          /* PIN entry for selected user */
          <div className="space-y-3">
            <div className="flex items-center gap-3 p-3 bg-primary-50 dark:bg-primary-900/20 rounded-lg border border-primary-200 dark:border-primary-800">
              <div className="w-10 h-10 rounded-full bg-primary-100 dark:bg-primary-900 flex items-center justify-center shrink-0">
                <UserCircle className="w-6 h-6 text-primary-500" />
              </div>
              <div className="flex-1">
                <p className="text-sm font-semibold text-gray-900 dark:text-gray-100">{selectedUserName}</p>
                <button
                  onClick={() => { setSelectedUserId(null); setPin(''); setAuthError(null); }}
                  className="text-xs text-primary-600 dark:text-primary-400 hover:underline"
                >
                  Switch user
                </button>
              </div>
            </div>

            <input
              type="password"
              inputMode="numeric"
              value={pin}
              onChange={(e) => { setPin(e.target.value.replace(/\D/g, '')); setAuthError(null); }}
              onKeyDown={(e) => e.key === 'Enter' && handleAdminAuth()}
              placeholder="Enter PIN"
              maxLength={8}
              autoFocus
              className="w-full px-3 py-2.5 text-sm text-center tracking-[0.3em] border border-gray-300 dark:border-gray-600 rounded-lg bg-white dark:bg-gray-800 text-gray-900 dark:text-gray-100 placeholder-gray-400 focus:ring-2 focus:ring-primary-500 focus:border-primary-500 outline-none"
            />

            <button
              onClick={handleAdminAuth}
              disabled={pin.length < 4 || authenticating}
              className="w-full px-4 py-2.5 text-sm font-medium rounded-lg bg-amber-500 text-white hover:bg-amber-600 disabled:opacity-50 disabled:cursor-not-allowed transition-colors"
            >
              {authenticating ? 'Authorizing...' : 'Authorize & Sync'}
            </button>

            {authError && (
              <p className="text-sm text-red-600 dark:text-red-400 text-center">{authError}</p>
            )}
            {promptError && (
              <p className="text-sm text-red-600 dark:text-red-400 text-center">{promptError}</p>
            )}
          </div>
        )}
      </div>
    );
  }

  // ── Step 3 UI: Syncing ───────────────────────────────────────────

  return (
    <div className="max-w-sm w-full space-y-4 text-center">
      <div className="flex justify-center mb-2">
        <div className="w-12 h-12 rounded-full bg-blue-50 dark:bg-blue-900/30 flex items-center justify-center">
          <Wifi className="w-6 h-6 text-blue-500 animate-pulse" />
        </div>
      </div>
      <h2 className="text-lg font-semibold text-gray-900 dark:text-gray-100">
        Syncing Data...
      </h2>
      {status && (
        <p className="text-sm text-green-600 dark:text-green-400">{status}</p>
      )}
      {syncing && <Spinner size="lg" />}
      {promptError && (
        <p className="text-sm text-red-600 dark:text-red-400">{promptError}</p>
      )}
    </div>
  );
}
