/**
 * AuthGate — orchestrates the entire authentication flow.
 *
 * Flow:
 * 1. Generate device fingerprint
 * 2. POST /auth/device-login → check if auto-login possible
 * 3. If auto-login → store token, fetch user profile, render children
 * 4. If not → show UserPicker → PinLoginForm → store token, render children
 *
 * This component wraps the entire app. While auth is pending, it shows
 * a loading screen. Once authenticated, it renders the main app.
 */

import { useEffect, useState } from 'react';
import { Zap } from 'lucide-react';
import { useAuthStore } from '../../stores/auth-store';
import { deviceLogin } from '../../api/auth';
import { generateDeviceFingerprint, getDeviceName } from '../../lib/utils';
import { UserPicker } from './UserPicker';
import { PinLoginForm } from './PinLoginForm';
import { PageSpinner } from '../ui/Spinner';

type AuthStep = 'loading' | 'user-picker' | 'pin-entry' | 'authenticated';

interface AuthGateProps {
  children: React.ReactNode;
}

export function AuthGate({ children }: AuthGateProps) {
  const { isAuthenticated, isLoading, login, checkAuth } = useAuthStore();
  const [step, setStep] = useState<AuthStep>('loading');
  const [selectedUserId, setSelectedUserId] = useState<number | null>(null);
  const [selectedUserName, setSelectedUserName] = useState<string>('');
  const [deviceFp, setDeviceFp] = useState('');
  const [deviceName, setDeviceName] = useState('');
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    initAuth();
  }, []);

  async function initAuth() {
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
      </div>
    );
  }

  // User picker
  if (step === 'user-picker') {
    return <UserPicker onSelect={handleUserSelected} />;
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
