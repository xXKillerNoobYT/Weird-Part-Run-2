/**
 * HelpButton — small "?" icon that shows contextual help in a popover.
 *
 * Looks up the help text from `helpContent.ts` by key and renders
 * it in a floating popover. Click to toggle, click outside to close.
 *
 * Usage:
 * ```tsx
 * <HelpButton helpKey="orders.smart-suggestions" />
 * ```
 *
 * The popover auto-positions to stay within the viewport (defaults to
 * bottom, falls back to top if near the bottom edge).
 *
 * Phase 7E
 */

import { useState, useRef, useEffect } from 'react';
import { HelpCircle, ExternalLink } from 'lucide-react';
import helpContent, { type HelpEntry } from '../../../lib/helpContent';


interface HelpButtonProps {
  /** Key into helpContent map */
  helpKey: string;
  /** Override the help entry (useful for dynamic/inline help) */
  entry?: HelpEntry;
  /** Size variant */
  size?: 'sm' | 'md';
  /** Additional CSS classes on the wrapper */
  className?: string;
}

export function HelpButton({ helpKey, entry, size = 'sm', className = '' }: HelpButtonProps) {
  const [open, setOpen] = useState(false);
  const containerRef = useRef<HTMLDivElement>(null);

  // Resolve help entry
  const help = entry || helpContent[helpKey];

  // Close on outside click
  useEffect(() => {
    if (!open) return;

    function handleClick(e: PointerEvent | MouseEvent) {
      if (containerRef.current && !containerRef.current.contains(e.target as Node)) {
        setOpen(false);
      }
    }

    document.addEventListener('pointerdown', handleClick);
    return () => document.removeEventListener('pointerdown', handleClick);
  }, [open]);

  // Close on Escape
  useEffect(() => {
    if (!open) return;

    function handleKey(e: KeyboardEvent) {
      if (e.key === 'Escape') setOpen(false);
    }

    document.addEventListener('keydown', handleKey);
    return () => document.removeEventListener('keydown', handleKey);
  }, [open]);

  if (!help) {
    // No help content found — render nothing in production
    if (import.meta.env.DEV) {
      console.warn(`[HelpButton] No help content found for key: "${helpKey}"`);
    }
    return null;
  }

  const iconSize = size === 'sm' ? 'h-3.5 w-3.5' : 'h-4 w-4';
  const buttonPadding = size === 'sm' ? 'p-1' : 'p-1.5';

  return (
    <div className={`relative inline-flex ${className}`} ref={containerRef}>
      {/* Trigger button */}
      <button
        onClick={() => setOpen(!open)}
        className={`${buttonPadding} rounded-full text-gray-400 dark:text-gray-500 hover:text-primary hover:bg-gray-100 dark:hover:bg-gray-700 transition-colors focus:outline-none focus:ring-2 focus:ring-primary/30`}
        title="Help"
        aria-label={`Help: ${help.title}`}
        aria-expanded={open}
      >
        <HelpCircle className={iconSize} />
      </button>

      {/* Popover */}
      {open && (
        <div
          className="absolute left-1/2 top-full mt-2 z-50 -translate-x-1/2 w-64 sm:w-72"
          role="tooltip"
        >
          <div className="rounded-lg border border-border bg-surface p-3 shadow-lg text-left">
            {/* Title */}
            <h4 className="text-sm font-semibold text-gray-900 dark:text-gray-100 mb-1">
              {help.title}
            </h4>

            {/* Body */}
            <p className="text-xs leading-relaxed text-gray-600 dark:text-gray-400">
              {help.body}
            </p>

            {/* Optional link */}
            {help.linkUrl && (
              <a
                href={help.linkUrl}
                target="_blank"
                rel="noopener noreferrer"
                className="mt-2 inline-flex items-center gap-1 text-xs font-medium text-primary hover:underline"
              >
                {help.linkLabel || 'Learn more'}
                <ExternalLink className="h-3 w-3" />
              </a>
            )}
          </div>

          {/* Arrow pointer */}
          <div className="absolute -top-1 left-1/2 -translate-x-1/2 h-2 w-2 rotate-45 border-l border-t border-border bg-surface" />
        </div>
      )}
    </div>
  );
}
