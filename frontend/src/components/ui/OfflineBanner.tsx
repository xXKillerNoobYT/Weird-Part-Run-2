/**
 * OfflineBanner — Subtle banner shown when the shop server is unreachable.
 *
 * Listens to browser online/offline events and also pings the API periodically.
 * When offline, displays a non-intrusive banner above the main content.
 *
 * Mount this inside AppShell, above <Outlet />.
 */

import { useState, useEffect, useCallback, useRef } from 'react';
import { WifiOff, Wifi } from 'lucide-react';

/** How often to check connectivity when offline (ms) */
const OFFLINE_CHECK_INTERVAL = 10_000;
/** How often to check connectivity when online (ms) */
const ONLINE_CHECK_INTERVAL = 60_000;

export function OfflineBanner() {
    const [isOffline, setIsOffline] = useState(!navigator.onLine);
    const [wasOffline, setWasOffline] = useState(false);
    const reconnectTimer = useRef<ReturnType<typeof setTimeout> | null>(null);

    // Ping the API to check real connectivity (not just navigator.onLine)
    const checkConnectivity = useCallback(async () => {
        try {
            const response = await fetch('/api/health', {
                method: 'HEAD',
                cache: 'no-store',
                signal: AbortSignal.timeout(5000),
            });
            if (response.ok) {
                setIsOffline(false);
            } else {
                setIsOffline(true);
            }
        } catch {
            setIsOffline(true);
        }
    }, []);

    // Listen for browser online/offline events
    useEffect(() => {
        const goOnline = () => {
            // Verify with a real ping before declaring online
            checkConnectivity();
        };
        const goOffline = () => setIsOffline(true);

        window.addEventListener('online', goOnline);
        window.addEventListener('offline', goOffline);
        return () => {
            window.removeEventListener('online', goOnline);
            window.removeEventListener('offline', goOffline);
        };
    }, [checkConnectivity]);

    // Periodic connectivity check
    useEffect(() => {
        const interval = isOffline ? OFFLINE_CHECK_INTERVAL : ONLINE_CHECK_INTERVAL;
        const id = setInterval(checkConnectivity, interval);
        return () => clearInterval(id);
    }, [isOffline, checkConnectivity]);

    // Show "reconnected" message briefly after coming back online
    useEffect(() => {
        if (isOffline) {
            setWasOffline(true);
        } else if (wasOffline) {
            // Clear the reconnect message after 3 seconds
            reconnectTimer.current = setTimeout(() => {
                setWasOffline(false);
            }, 3000);
        }
        return () => {
            if (reconnectTimer.current) clearTimeout(reconnectTimer.current);
        };
    }, [isOffline, wasOffline]);

    // Don't render if fully online and no recent reconnection
    if (!isOffline && !wasOffline) return null;

    return (
        <div
            role="status"
            aria-live="polite"
            className={`flex items-center justify-center gap-2 px-4 py-2 text-sm font-medium transition-colors duration-300 ${isOffline
                    ? 'bg-amber-500/10 text-amber-700 dark:bg-amber-500/20 dark:text-amber-300 border-b border-amber-300/30 dark:border-amber-600/30'
                    : 'bg-green-500/10 text-green-700 dark:bg-green-500/20 dark:text-green-300 border-b border-green-300/30 dark:border-green-600/30'
                }`}
        >
            {isOffline ? (
                <>
                    <WifiOff className="h-4 w-4 flex-shrink-0" />
                    <span>Working offline — changes will sync when connected</span>
                </>
            ) : (
                <>
                    <Wifi className="h-4 w-4 flex-shrink-0" />
                    <span>Reconnected to shop server</span>
                </>
            )}
        </div>
    );
}
