/**
 * QRScannerBubble — compact camera preview that scans QR codes.
 *
 * Renders as a small bubble above the search bar on Step 2 of the
 * movement wizard. Toggle open/closed with a button. When a valid
 * WiredPart QR code is detected, fires onScan() and pauses for 2s
 * to prevent duplicate reads.
 *
 * Camera switching (front ↔ rear) is supported.
 */

import { useState, useRef, useCallback, useEffect, useId } from 'react';
import { Html5Qrcode, Html5QrcodeSupportedFormats } from 'html5-qrcode';
import { Camera, SwitchCamera, X, AlertCircle, CheckCircle2 } from 'lucide-react';
import { cn } from '../../../../lib/utils';
import { decodeQRData, type WiredPartQRData } from '../../../../lib/qr-utils';

interface QRScannerBubbleProps {
  /** Called when a valid WiredPart QR code is decoded. */
  onScan: (data: WiredPartQRData) => void;
  /** Disable the toggle button (e.g. during processing). */
  disabled?: boolean;
}

export function QRScannerBubble({ onScan, disabled }: QRScannerBubbleProps) {
  const uniqueId = useId();
  const elementId = `qr-reader-${uniqueId.replace(/:/g, '')}`;

  const [isOpen, setIsOpen] = useState(false);
  const [facingMode, setFacingMode] = useState<'user' | 'environment'>('environment');
  const [error, setError] = useState<string | null>(null);
  const [isStarting, setIsStarting] = useState(false);
  const [lastScanFeedback, setLastScanFeedback] = useState<string | null>(null);

  const qrRef = useRef<Html5Qrcode | null>(null);
  const isStoppingRef = useRef(false);

  // ── Start camera ─────────────────────────────────────────────
  const startCamera = useCallback(
    async (facing: 'user' | 'environment') => {
      // Wait for the DOM element to be available
      await new Promise((r) => setTimeout(r, 50));

      const el = document.getElementById(elementId);
      if (!el) return;

      setIsStarting(true);
      setError(null);

      try {
        const qr = new Html5Qrcode(elementId, {
          formatsToSupport: [Html5QrcodeSupportedFormats.QR_CODE],
          verbose: false,
        });
        qrRef.current = qr;

        await qr.start(
          { facingMode: facing },
          { fps: 10, qrbox: { width: 120, height: 120 }, disableFlip: false },
          (decodedText) => {
            const data = decodeQRData(decodedText);
            if (data) {
              // Pause scanning to prevent rapid-fire duplicates
              qr.pause(/* shouldPauseVideo= */ false);
              setLastScanFeedback(data.code || `Part #${data.part_id}`);
              onScan(data);

              // Resume after 2 seconds
              setTimeout(() => {
                try {
                  qr.resume();
                } catch {
                  // Scanner may have been stopped/closed
                }
                setLastScanFeedback(null);
              }, 2000);
            }
            // Ignore non-WiredPart QR codes silently
          },
          () => {
            // onScanError fires continuously when no QR in frame — ignore
          },
        );
      } catch (err: unknown) {
        const msg =
          err instanceof Error ? err.message : 'Camera not available';
        if (msg.includes('Permission')) {
          setError('Camera permission denied. Check your browser settings.');
        } else {
          setError(msg);
        }
      } finally {
        setIsStarting(false);
      }
    },
    [elementId, onScan],
  );

  // ── Stop camera ──────────────────────────────────────────────
  const stopCamera = useCallback(async () => {
    if (isStoppingRef.current) return;
    isStoppingRef.current = true;
    try {
      if (qrRef.current) {
        await qrRef.current.stop();
        qrRef.current.clear();
        qrRef.current = null;
      }
    } catch {
      // Already stopped or cleared
    } finally {
      isStoppingRef.current = false;
    }
  }, []);

  // ── Toggle open/close ────────────────────────────────────────
  const handleToggle = useCallback(() => {
    if (isOpen) {
      stopCamera();
      setIsOpen(false);
      setError(null);
      setLastScanFeedback(null);
    } else {
      setIsOpen(true);
      // startCamera is triggered by the useEffect below
    }
  }, [isOpen, stopCamera]);

  // Start camera when bubble opens or facing mode changes
  useEffect(() => {
    if (isOpen) {
      startCamera(facingMode);
    }
    return () => {
      stopCamera();
    };
  }, [isOpen, facingMode]); // eslint-disable-line react-hooks/exhaustive-deps

  // ── Switch camera ────────────────────────────────────────────
  const handleSwitchCamera = useCallback(async () => {
    await stopCamera();
    setFacingMode((prev) => (prev === 'user' ? 'environment' : 'user'));
  }, [stopCamera]);

  // ── Close on unmount ─────────────────────────────────────────
  useEffect(() => {
    return () => {
      stopCamera();
    };
  }, []); // eslint-disable-line react-hooks/exhaustive-deps

  return (
    <div className="space-y-2">
      {/* Toggle button */}
      <button
        type="button"
        onClick={handleToggle}
        disabled={disabled}
        className={cn(
          'inline-flex items-center gap-2 px-3 py-1.5 rounded-lg text-sm font-medium transition-all',
          isOpen
            ? 'bg-primary-100 dark:bg-primary-900/40 text-primary-700 dark:text-primary-300 ring-1 ring-primary-300 dark:ring-primary-700'
            : 'bg-gray-100 dark:bg-gray-800 text-gray-600 dark:text-gray-400 hover:bg-gray-200 dark:hover:bg-gray-700',
          disabled && 'opacity-50 cursor-not-allowed',
        )}
      >
        <Camera className="h-4 w-4" />
        {isOpen ? 'Close Scanner' : 'Scan QR'}
      </button>

      {/* Camera bubble */}
      {isOpen && (
        <div className="relative inline-block">
          {/* Camera feed container */}
          <div
            className={cn(
              'relative w-[180px] h-[180px] rounded-xl overflow-hidden',
              'border-2 border-primary-300 dark:border-primary-700',
              'bg-black shadow-lg',
            )}
          >
            <div id={elementId} className="w-full h-full" />

            {/* Loading overlay */}
            {isStarting && (
              <div className="absolute inset-0 flex items-center justify-center bg-black/60">
                <div className="flex flex-col items-center gap-2">
                  <div className="h-5 w-5 border-2 border-white/40 border-t-white rounded-full animate-spin" />
                  <span className="text-xs text-white/80">Starting camera...</span>
                </div>
              </div>
            )}

            {/* Scan success flash */}
            {lastScanFeedback && (
              <div className="absolute inset-0 flex items-center justify-center bg-green-500/20 pointer-events-none">
                <div className="flex items-center gap-1.5 px-2 py-1 rounded-md bg-green-600/90 text-white text-xs font-medium">
                  <CheckCircle2 className="h-3.5 w-3.5" />
                  {lastScanFeedback}
                </div>
              </div>
            )}

            {/* Controls bar at bottom */}
            <div className="absolute bottom-0 left-0 right-0 flex items-center justify-between px-2 py-1.5 bg-black/50 backdrop-blur-sm">
              <button
                type="button"
                onClick={handleSwitchCamera}
                className="p-1 rounded-md text-white/80 hover:text-white hover:bg-white/20 transition-colors"
                title="Switch camera"
              >
                <SwitchCamera className="h-4 w-4" />
              </button>
              <span className="text-[10px] text-white/60">
                {facingMode === 'environment' ? 'Rear' : 'Front'}
              </span>
              <button
                type="button"
                onClick={handleToggle}
                className="p-1 rounded-md text-white/80 hover:text-white hover:bg-white/20 transition-colors"
                title="Close scanner"
              >
                <X className="h-4 w-4" />
              </button>
            </div>
          </div>

          {/* Error message */}
          {error && (
            <div className="mt-2 flex items-start gap-2 px-3 py-2 rounded-lg bg-red-50 dark:bg-red-900/20 border border-red-200 dark:border-red-800 max-w-[240px]">
              <AlertCircle className="h-4 w-4 text-red-500 flex-shrink-0 mt-0.5" />
              <p className="text-xs text-red-600 dark:text-red-400">{error}</p>
            </div>
          )}
        </div>
      )}
    </div>
  );
}
