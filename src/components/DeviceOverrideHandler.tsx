/**
 * DeviceOverrideHandler — listens for device:override custom events dispatched
 * by the API client when the backend returns 403 / 423 with an X-Device-Override
 * header. Shows a full-screen overlay appropriate to the override action:
 *
 *   - force_logout → sign out the user immediately
 *   - force_wipe   → clear local data and redirect to setup
 *   - disabled      → locked screen explaining the device is disabled
 *
 * Render this once near the app root (inside AuthGate / AppShell).
 */

import { useEffect, useState, useCallback } from 'react';
import { ShieldOff, LogOut, Trash2, Lock } from 'lucide-react';
import { Button } from './ui/Button';

type OverrideType = 'force_logout' | 'force_wipe' | 'disabled' | null;

interface OverrideState {
    action: OverrideType;
    reason: string;
}

export function DeviceOverrideHandler() {
    const [override, setOverride] = useState<OverrideState>({ action: null, reason: '' });

    useEffect(() => {
        function handleOverride(e: Event) {
            const detail = (e as CustomEvent).detail as { action: string; reason?: string };
            const action = detail.action as OverrideType;
            if (action) {
                setOverride({ action, reason: detail.reason ?? '' });
            }
        }

        window.addEventListener('device:override', handleOverride);
        return () => window.removeEventListener('device:override', handleOverride);
    }, []);

    const handleLogout = useCallback(() => {
        localStorage.removeItem('wiredpart_token');
        window.dispatchEvent(new CustomEvent('auth:expired'));
        setOverride({ action: null, reason: '' });
    }, []);

    const handleWipe = useCallback(() => {
        // Clear all local storage
        localStorage.clear();
        // In Tauri, we'd also drop the local SQLite DB here.
        // For now, just redirect to login.
        window.dispatchEvent(new CustomEvent('auth:expired'));
        window.location.reload();
    }, []);

    if (!override.action) return null;

    return (
        <div className="fixed inset-0 z-[9999] flex items-center justify-center bg-black/70 backdrop-blur-sm p-4">
            <div className="bg-surface border border-border rounded-2xl shadow-2xl max-w-md w-full p-6 space-y-5 text-center">
                {override.action === 'force_logout' && (
                    <>
                        <div className="mx-auto w-14 h-14 rounded-full bg-amber-100 dark:bg-amber-900/30 flex items-center justify-center">
                            <LogOut className="h-7 w-7 text-amber-600 dark:text-amber-400" />
                        </div>
                        <h2 className="text-lg font-semibold text-gray-900 dark:text-gray-100">
                            Session Ended
                        </h2>
                        <p className="text-sm text-gray-600 dark:text-gray-400">
                            An administrator has remotely signed out this device. You'll need to sign in again.
                        </p>
                        <Button variant="primary" className="w-full" icon={<LogOut className="h-4 w-4" />}
                            onClick={handleLogout}>
                            Sign In Again
                        </Button>
                    </>
                )}

                {override.action === 'force_wipe' && (
                    <>
                        <div className="mx-auto w-14 h-14 rounded-full bg-red-100 dark:bg-red-900/30 flex items-center justify-center">
                            <Trash2 className="h-7 w-7 text-red-600 dark:text-red-400" />
                        </div>
                        <h2 className="text-lg font-semibold text-gray-900 dark:text-gray-100">
                            Device Wipe Required
                        </h2>
                        <p className="text-sm text-gray-600 dark:text-gray-400">
                            An administrator has issued a remote wipe for this device. All local data will be cleared and you'll need to set up this device again.
                        </p>
                        <Button variant="danger" className="w-full" icon={<Trash2 className="h-4 w-4" />}
                            onClick={handleWipe}>
                            Clear Data &amp; Restart
                        </Button>
                    </>
                )}

                {override.action === 'disabled' && (
                    <>
                        <div className="mx-auto w-14 h-14 rounded-full bg-red-100 dark:bg-red-900/30 flex items-center justify-center">
                            <Lock className="h-7 w-7 text-red-600 dark:text-red-400" />
                        </div>
                        <h2 className="text-lg font-semibold text-gray-900 dark:text-gray-100">
                            Device Disabled
                        </h2>
                        <p className="text-sm text-gray-600 dark:text-gray-400">
                            This device has been disabled by an administrator.
                            {override.reason && (
                                <> Reason: <strong>{override.reason}</strong></>
                            )}
                        </p>
                        <p className="text-xs text-gray-500 dark:text-gray-500">
                            Contact your supervisor or office to re-enable access.
                        </p>
                        <Button variant="secondary" className="w-full" icon={<ShieldOff className="h-4 w-4" />}
                            onClick={handleLogout}>
                            Return to Login
                        </Button>
                    </>
                )}
            </div>
        </div>
    );
}
