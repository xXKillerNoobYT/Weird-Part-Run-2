/**
 * InstallPrompt — Banner prompting users to install the PWA.
 *
 * Listens for the `beforeinstallprompt` event and shows a subtle
 * install banner at the bottom of the screen. Users can dismiss it
 * (stored in localStorage) or click to install.
 *
 * On iOS Safari, shows a manual instruction since there's no
 * beforeinstallprompt event.
 */

import { useState, useEffect, useCallback, useRef } from 'react';
import { Download, X } from 'lucide-react';

const DISMISS_KEY = 'pwa-install-dismissed';
const DISMISS_DURATION_MS = 7 * 24 * 60 * 60 * 1000; // 1 week

interface BeforeInstallPromptEvent extends Event {
    readonly platforms: string[];
    readonly userChoice: Promise<{ outcome: 'accepted' | 'dismissed' }>;
    prompt(): Promise<void>;
}

export function InstallPrompt() {
    const [deferredPrompt, setDeferredPrompt] = useState<BeforeInstallPromptEvent | null>(null);
    const [showBanner, setShowBanner] = useState(false);
    const [isIOS, setIsIOS] = useState(false);
    const promptRef = useRef<BeforeInstallPromptEvent | null>(null);

    useEffect(() => {
        // Check if already installed as PWA
        if (window.matchMedia('(display-mode: standalone)').matches) return;

        // Check dismissal
        const dismissed = localStorage.getItem(DISMISS_KEY);
        if (dismissed && Date.now() - parseInt(dismissed, 10) < DISMISS_DURATION_MS) return;

        // Detect iOS Safari (no beforeinstallprompt support)
        const ua = navigator.userAgent;
        const isiOS = /iPad|iPhone|iPod/.test(ua) && !(window as unknown as { MSStream: unknown }).MSStream;
        const isSafari = /Safari/.test(ua) && !/Chrome/.test(ua);

        if (isiOS && isSafari) {
            setIsIOS(true);
            setShowBanner(true);
            return;
        }

        // Listen for the install prompt event
        const handler = (e: Event) => {
            e.preventDefault();
            const prompt = e as BeforeInstallPromptEvent;
            promptRef.current = prompt;
            setDeferredPrompt(prompt);
            setShowBanner(true);
        };

        window.addEventListener('beforeinstallprompt', handler);
        return () => window.removeEventListener('beforeinstallprompt', handler);
    }, []);

    const handleInstall = useCallback(async () => {
        if (!deferredPrompt) return;
        try {
            await deferredPrompt.prompt();
            const { outcome } = await deferredPrompt.userChoice;
            if (outcome === 'accepted') {
                setShowBanner(false);
            }
        } catch {
            // Prompt failed — hide banner
        }
        setDeferredPrompt(null);
        promptRef.current = null;
    }, [deferredPrompt]);

    const handleDismiss = useCallback(() => {
        localStorage.setItem(DISMISS_KEY, String(Date.now()));
        setShowBanner(false);
    }, []);

    if (!showBanner) return null;

    return (
        <div className="fixed bottom-4 left-4 right-4 sm:left-auto sm:right-4 sm:w-96 z-50 animate-slide-up">
            <div className="flex items-center gap-3 rounded-xl border border-border bg-surface p-4 shadow-lg">
                <div className="flex-shrink-0 flex items-center justify-center w-10 h-10 rounded-lg bg-primary/10">
                    <Download className="h-5 w-5 text-primary" />
                </div>
                <div className="flex-1 min-w-0">
                    <p className="text-sm font-medium text-gray-900 dark:text-gray-100">
                        Install Wired Part
                    </p>
                    <p className="text-xs text-gray-500 dark:text-gray-400 mt-0.5">
                        {isIOS
                            ? 'Tap Share → "Add to Home Screen" for the best experience'
                            : 'Add to your desktop for quick access'}
                    </p>
                </div>
                {!isIOS && (
                    <button
                        onClick={handleInstall}
                        className="flex-shrink-0 rounded-lg bg-primary px-3 py-1.5 text-xs font-medium text-white hover:bg-primary/90 transition-colors min-h-[36px]"
                    >
                        Install
                    </button>
                )}
                <button
                    onClick={handleDismiss}
                    className="flex-shrink-0 p-1.5 rounded-lg text-gray-400 hover:text-gray-600 dark:hover:text-gray-300 hover:bg-gray-100 dark:hover:bg-gray-800 transition-colors min-h-[36px] min-w-[36px] flex items-center justify-center"
                    title="Dismiss"
                >
                    <X className="h-4 w-4" />
                </button>
            </div>
        </div>
    );
}
