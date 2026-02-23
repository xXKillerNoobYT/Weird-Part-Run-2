/**
 * Utility functions used throughout the app.
 *
 * The `cn()` function is the most important — it merges Tailwind classes
 * intelligently (last class wins for conflicts like "p-2 p-4" → "p-4").
 */

import { type ClassValue, clsx } from 'clsx';
import { twMerge } from 'tailwind-merge';

/**
 * Merge Tailwind CSS classes with conflict resolution.
 *
 * Combines clsx (conditional classes) with tailwind-merge (deduplication).
 * This is the standard pattern used by shadcn/ui and most modern React+Tailwind apps.
 *
 * @example
 *   cn('p-2 text-red-500', isActive && 'bg-blue-500', 'p-4')
 *   // → 'text-red-500 bg-blue-500 p-4'  (p-4 wins over p-2)
 */
export function cn(...inputs: ClassValue[]): string {
  return twMerge(clsx(inputs));
}

/**
 * Generate a simple device fingerprint from browser characteristics.
 *
 * This is NOT cryptographically secure — it's a convenience for auto-login.
 * For production, consider FingerprintJS or WebAuthn.
 */
export function generateDeviceFingerprint(): string {
  const components = [
    navigator.userAgent,
    navigator.language,
    screen.width + 'x' + screen.height,
    screen.colorDepth.toString(),
    Intl.DateTimeFormat().resolvedOptions().timeZone,
    navigator.hardwareConcurrency?.toString() ?? '0',
  ];

  // Simple hash from components
  const str = components.join('|');
  let hash = 0;
  for (let i = 0; i < str.length; i++) {
    const char = str.charCodeAt(i);
    hash = ((hash << 5) - hash) + char;
    hash |= 0; // Convert to 32-bit integer
  }

  // Combine with a stored random suffix for uniqueness
  let storedId = localStorage.getItem('wiredpart_device_id');
  if (!storedId) {
    storedId = Math.random().toString(36).substring(2, 15);
    localStorage.setItem('wiredpart_device_id', storedId);
  }

  return `wp-${Math.abs(hash).toString(36)}-${storedId}`;
}

/**
 * Get a friendly device name from the browser's user agent.
 */
export function getDeviceName(): string {
  const ua = navigator.userAgent;

  if (ua.includes('Chrome') && !ua.includes('Edg')) return 'Chrome';
  if (ua.includes('Edg')) return 'Edge';
  if (ua.includes('Firefox')) return 'Firefox';
  if (ua.includes('Safari') && !ua.includes('Chrome')) return 'Safari';

  return 'Browser';
}

/**
 * Format a date string for display.
 */
export function formatDate(date: string | null | undefined): string {
  if (!date) return '—';
  try {
    return new Date(date).toLocaleDateString();
  } catch {
    return date;
  }
}

/**
 * Format a date+time string for display.
 */
export function formatDateTime(date: string | null | undefined): string {
  if (!date) return '—';
  try {
    return new Date(date).toLocaleString();
  } catch {
    return date;
  }
}
