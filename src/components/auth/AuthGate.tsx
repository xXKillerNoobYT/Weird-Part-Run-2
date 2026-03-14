/**
 * AuthGate — orchestrates the entire authentication flow.
 *
 * Flow:
 * 1. On native (Tauri): initialize local SQLite database
 * 2. Generate device fingerprint
 * 3. POST /auth/device-login → check if auto-login possible (or local fallback)
 * 4. If auto-login → store token, fetch user profile, render children
 * 5. If not → show UserPicker → PinLoginForm → store token, render children
 *
 * This component wraps the entire app. While auth is pending, it shows
 * a loading screen. Once authenticated, it renders the main app.
 */

import { useEffect, useState } from 'react';
import { Zap } from 'lucide-react';
import { useAuthStore } from '../../stores/auth-store';
import { deviceLogin } from '../../api/auth';
import { generateDeviceFingerprint, getDeviceName } from '../../lib/utils';
import { isNativeApp } from '../../lib/environment';
import { UserPicker } from './UserPicker';
import { PinLoginForm } from './PinLoginForm';
import { PageSpinner } from '../ui/Spinner';

type AuthStep = 'loading' | 'user-picker' | 'pin-entry' | 'authenticated';

interface AuthGateProps {
  children: React.ReactNode;
}

// Guard against React StrictMode double-mounting in DEV
let _initRunning = false;

export function AuthGate({ children }: AuthGateProps) {
  const { isAuthenticated, isLoading, login, checkAuth } = useAuthStore();
  const [step, setStep] = useState<AuthStep>('loading');
  const [selectedUserId, setSelectedUserId] = useState<number | null>(null);
  const [selectedUserName, setSelectedUserName] = useState<string>('');
  const [deviceFp, setDeviceFp] = useState('');
  const [deviceName, setDeviceName] = useState('');
  const [_error, setError] = useState<string | null>(null);
  const [_devDebug, _setDevDebug] = useState<string[]>([]);

  useEffect(() => {
    if (_initRunning) return;
    _initRunning = true;
    initAuth().finally(() => { _initRunning = false; });
  }, []);

  async function initAuth() {
    // Direct DOM debug — bypasses React state batching (DEV only).
    // Hidden state persists in localStorage so it survives refreshes.
    const dbg = import.meta.env.DEV
      ? (() => {
          // Respect user preference to hide the dev overlay
          if (localStorage.getItem('__dev_debug_hidden') === '1') {
            return (msg: string) => { console.log('[DEV]', msg); };
          }

          void (document.getElementById('__dev_debug') || (() => {
            // === Outer wrapper: fixed to bottom, NOT scrollable ===
            // Uses a CSS variable (--dev-overlay-h) so the AppShell can shrink
            // its h-screen to make room. This prevents content being hidden.
            const el = document.createElement('div');
            el.id = '__dev_debug';
            el.style.cssText = 'position:fixed;bottom:0;left:0;right:0;z-index:99999;background:rgba(0,0,0,0.95);border-top:2px solid #0f0;border-left:1px solid #0f0;border-right:1px solid #0f0;display:flex;flex-direction:column;max-height:120px';

            // Set CSS variable so AppShell shrinks to fit
            document.documentElement.style.setProperty('--dev-overlay-h', '120px');

            // === Header bar: label + close button (never scrolls) ===
            const header = document.createElement('div');
            header.style.cssText = 'display:flex;justify-content:space-between;align-items:center;padding:2px 4px;flex-shrink:0;border-bottom:1px solid rgba(0,255,0,0.2)';

            const label = document.createElement('span');
            label.textContent = 'DEV OVERLAY';
            label.style.cssText = 'color:#0f0;font:bold 9px monospace;opacity:0.6;letter-spacing:1px';
            header.appendChild(label);

            const closeBtn = document.createElement('button');
            closeBtn.textContent = '✕';
            closeBtn.style.cssText = 'color:#0f0;background:none;border:1px solid rgba(0,255,0,0.3);font:bold 11px monospace;cursor:pointer;padding:1px 6px;opacity:0.7;border-radius:2px;line-height:1';
            closeBtn.title = 'Hide dev overlay (re-enable in Settings → App Config)';
            closeBtn.onmouseenter = () => { closeBtn.style.opacity = '1'; closeBtn.style.borderColor = '#0f0'; };
            closeBtn.onmouseleave = () => { closeBtn.style.opacity = '0.7'; closeBtn.style.borderColor = 'rgba(0,255,0,0.3)'; };
            closeBtn.onclick = (e) => {
              e.stopPropagation();
              localStorage.setItem('__dev_debug_hidden', '1');
              document.documentElement.style.removeProperty('--dev-overlay-h');
              el.remove();
            };
            header.appendChild(closeBtn);
            el.appendChild(header);

            // === Log container: scrollable area for messages ===
            const logContainer = document.createElement('div');
            logContainer.id = '__dev_debug_log';
            logContainer.style.cssText = 'flex:1;overflow-y:auto;padding:2px 4px;color:#0f0;font:10px monospace';
            el.appendChild(logContainer);

            document.body.appendChild(el);
            return el;
          })());
          return (msg: string) => {
            console.log('[DEV]', msg);
            const logContainer = document.getElementById('__dev_debug_log');
            if (logContainer) {
              const line = document.createElement('div');
              line.textContent = msg;
              logContainer.appendChild(line);
              logContainer.scrollTop = logContainer.scrollHeight;
            }
          };
        })()
      : (_msg: string) => {}; // no-op in production

    // DEV ONLY: auto-login via URL param ?devlogin=<userId>, localStorage flag,
    // or automatic first-user login on native (iOS Simulator keyboard is broken).
    //
    // TIMING NOTE: Tauri injects __TAURI__ asynchronously, so isNativeApp() may
    // return false on first tick. We wait up to 2s for it to appear.
    if (import.meta.env.DEV) {
      dbg('DEV block entered');
      const params = new URLSearchParams(window.location.search);
      let devUserId = params.get('devlogin') || localStorage.getItem('__dev_autologin');
      localStorage.removeItem('__dev_autologin');

      dbg(`__TAURI__ in window: ${'__TAURI__' in window}`);

      // Wait for Tauri to inject __TAURI__ (up to 2s in 100ms increments)
      if (!('__TAURI__' in window)) {
        dbg('Waiting for __TAURI__...');
        for (let i = 0; i < 20; i++) {
          await new Promise((r) => setTimeout(r, 100));
          if ('__TAURI__' in window) {
            dbg(`__TAURI__ appeared after ${(i + 1) * 100}ms`);
            break;
          }
        }
        if (!('__TAURI__' in window)) {
          dbg('__TAURI__ NOT found after 2s wait');
        }
      } else {
        dbg('__TAURI__ was already present');
      }

      dbg(`isNativeApp(): ${isNativeApp()}`);

      // On native DEV builds, auto-login as user 1 if no explicit override
      if (!devUserId && isNativeApp()) {
        devUserId = '1';
        dbg('Native mode — will auto-login as user 1');
      }

      if (devUserId) {
        dbg(`Auto-login for user ${devUserId}`);
        // Wait for native init
        if (isNativeApp()) {
          try {
            const { initLocalSystem } = await import('../../local/init');
            dbg('Calling initLocalSystem...');
            await initLocalSystem();
            dbg('initLocalSystem OK');
          } catch (err) {
            dbg(`initLocalSystem FAILED: ${err}`);
            console.error('[DEV] Failed to initialize local system:', err);
          }
        }
        // Use devAutoLogin which skips PIN verification
        try {
          const { devAutoLogin, getLocalUserProfile } = await import('../../local/services/auth-service');
          dbg('Calling devAutoLogin...');
          const result = await devAutoLogin(Number(devUserId));
          dbg(`devAutoLogin: ${result.success} — ${result.message}`);
          console.log('[DEV] devAutoLogin result:', result.success, result.message);
          if (result.success && result.token) {
            try {
              await login(result.token);
              console.log('[DEV] login() succeeded');
            } catch (loginErr) {
              // login() calls getMe() which might fail — set state directly
              console.warn('[DEV] login() threw, setting auth state directly:', loginErr);
              localStorage.setItem('wiredpart_token', result.token);
              try {
                const profile = await getLocalUserProfile(result.token);
                useAuthStore.setState({
                  user: profile as any,
                  isAuthenticated: true,
                  isLoading: false,
                });
                console.log('[DEV] Forced auth state for', profile.display_name);
              } catch (profileErr) {
                console.error('[DEV] Even direct profile fetch failed:', profileErr);
                // Last resort: set minimal auth state so app renders
                useAuthStore.setState({
                  user: { id: result.user!.id, display_name: result.user!.display_name, permissions: [], hats: [] } as any,
                  isAuthenticated: true,
                  isLoading: false,
                });
              }
            }
            setStep('authenticated');
            window.history.replaceState({}, '', window.location.pathname);
            return;
          }
          console.warn('[DEV] Auto-login returned failure:', result.message);

          // DEV: If no users exist (fresh DB), auto-seed first admin for testing
          if (isNativeApp() && result.message?.includes('No active users')) {
            dbg('No users found — auto-seeding first admin for DEV...');
            try {
              const { seedFirstAdmin } = await import('../../local/services/auth-service');
              const seedResult = await seedFirstAdmin('Admin', '1234');
              dbg(`seedFirstAdmin: ${seedResult.success} — ${seedResult.message}`);
              if (seedResult.success && seedResult.token) {
                localStorage.setItem('wiredpart_token', seedResult.token);
                // Re-attempt auto-login now that a user exists
                const { devAutoLogin: retryLogin, getLocalUserProfile: retryProfile } = await import('../../local/services/auth-service');
                const retry = await retryLogin(1);
                dbg(`Retry auto-login: ${retry.success}`);
                if (retry.success && retry.token) {
                  try {
                    await login(retry.token);
                  } catch {
                    localStorage.setItem('wiredpart_token', retry.token);
                    const profile = await retryProfile(retry.token);
                    useAuthStore.setState({
                      user: profile as any,
                      isAuthenticated: true,
                      isLoading: false,
                    });
                  }
                  setStep('authenticated');
                  return;
                }
              }
            } catch (seedErr) {
              dbg(`Auto-seed failed: ${seedErr}`);
              console.error('[DEV] Auto-seed failed:', seedErr);
            }
          }
        } catch (err) {
          dbg(`Auto-login FAILED: ${err}`);
          console.error('[DEV] Auto-login failed:', err);
        }
      }
    }
    // On native (Tauri), initialize the local SQLite database before any auth calls
    if (isNativeApp()) {
      try {
        const { initLocalSystem } = await import('../../local/init');
        await initLocalSystem();
      } catch (err) {
        console.error('Failed to initialize local system:', err);
        setStep('user-picker');
        return;
      }
    }

    // First, check if we already have a valid token in localStorage
    const existingToken = localStorage.getItem('wiredpart_token');
    if (existingToken) {
      await checkAuth();
      const state = useAuthStore.getState();
      if (state.isAuthenticated) {
        setStep('authenticated');
        return;
      }
    }

    // No valid token — try device auto-login
    const fp = generateDeviceFingerprint();
    const name = getDeviceName();
    setDeviceFp(fp);
    setDeviceName(name);

    try {
      const result = await deviceLogin(fp, name);

      if (result.auto_login && result.token) {
        // Auto-login success!
        await login(result.token.access_token);
        setStep('authenticated');
      } else {
        // Need manual login
        setStep('user-picker');
      }
    } catch (err) {
      // API not available — show user picker anyway
      console.error('Device login failed:', err);
      setStep('user-picker');
    }
  }

  // Handle user selection from picker
  function handleUserSelected(userId: number, displayName: string) {
    setSelectedUserId(userId);
    setSelectedUserName(displayName);
    setError(null);
    setStep('pin-entry');
  }

  // Handle successful PIN login
  async function handlePinSuccess(token: string) {
    await login(token);
    // Remember who logged in so the UserPicker can show them first next time
    if (selectedUserId) {
      localStorage.setItem('wiredpart_last_user', String(selectedUserId));
    }
    setStep('authenticated');
  }

  // Handle back from PIN to user picker
  function handleBackToPicker() {
    setSelectedUserId(null);
    setSelectedUserName('');
    setError(null);
    setStep('user-picker');
  }

  // Watch for auth state changes (login AND logout)
  useEffect(() => {
    if (isAuthenticated && step !== 'authenticated') {
      setStep('authenticated');
    } else if (!isAuthenticated && step === 'authenticated') {
      // User logged out — reset back to user picker
      setSelectedUserId(null);
      setSelectedUserName('');
      setStep('user-picker');
    }
  }, [isAuthenticated, step]);

  // Safety: if step is 'authenticated' but store says not authenticated,
  // the login() call failed (e.g. getMe() threw). Reset to user-picker.
  useEffect(() => {
    if (step === 'authenticated' && !isAuthenticated && !isLoading) {
      console.warn('[AuthGate] Step=authenticated but store says not auth. Resetting.');
      setStep('user-picker');
    }
  }, [step, isAuthenticated, isLoading]);

  // Loading state
  if (step === 'loading' || isLoading) {
    return (
      <div className="min-h-screen bg-surface-secondary flex flex-col items-center justify-center gap-6">
        <div className="flex items-center gap-3">
          <div className="w-12 h-12 rounded-xl bg-primary-500 text-white flex items-center justify-center">
            <Zap className="h-7 w-7" />
          </div>
          <h1 className="text-3xl font-bold text-gray-900 dark:text-gray-100">
            Wired-Part
          </h1>
        </div>
        <PageSpinner label="Connecting..." />
        {import.meta.env.DEV && _devDebug.length > 0 && (
          <div className="fixed bottom-0 left-0 right-0 bg-black/90 text-green-400 text-[10px] font-mono p-2 max-h-32 overflow-y-auto z-[9999]">
            {_devDebug.map((msg, i) => <div key={i}>{msg}</div>)}
          </div>
        )}
      </div>
    );
  }

  // User picker
  if (step === 'user-picker') {
    return (
      <>
        <UserPicker onSelect={handleUserSelected} />
        {import.meta.env.DEV && _devDebug.length > 0 && (
          <div className="fixed bottom-0 left-0 right-0 bg-black/90 text-green-400 text-[10px] font-mono p-2 max-h-32 overflow-y-auto z-[9999]">
            {_devDebug.map((msg, i) => <div key={i}>{msg}</div>)}
          </div>
        )}
      </>
    );
  }

  // PIN entry
  if (step === 'pin-entry' && selectedUserId !== null) {
    return (
      <PinLoginForm
        userId={selectedUserId}
        userName={selectedUserName}
        deviceFingerprint={deviceFp}
        deviceName={deviceName}
        onSuccess={handlePinSuccess}
        onBack={handleBackToPicker}
      />
    );
  }

  // Authenticated — render the app
  return <>{children}</>;
}
