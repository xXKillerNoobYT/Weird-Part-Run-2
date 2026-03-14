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
    // Wait for Tauri to inject __TAURI__ (up to 2s in 100ms increments).
    // Tauri injects the IPC bridge asynchronously after the WebView loads,
    // so isNativeApp() may return false on the first tick in production too.
    if (!('__TAURI__' in window)) {
      for (let i = 0; i < 20; i++) {
        await new Promise((r) => setTimeout(r, 100));
        if ('__TAURI__' in window) break;
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
