/**
 * useKeyboardShortcuts — Global keyboard shortcut system.
 *
 * Registers global keyboard listeners for common actions.
 * Skips shortcuts when user is typing in an input/textarea/contentEditable.
 *
 * Shortcuts:
 *   Ctrl+K  → Open command palette (global search)
 *   Ctrl+/  → Open command palette (alias)
 *   Escape  → Close command palette / close modal
 *
 * Usage:
 *   const { isPaletteOpen, setIsPaletteOpen } = useKeyboardShortcuts();
 */

import { useEffect, useState, useCallback } from 'react';

/** Check if the event target is an input field where shortcuts should be suppressed */
function isEditableTarget(target: EventTarget | null): boolean {
  if (!target || !(target instanceof HTMLElement)) return false;
  const tag = target.tagName.toLowerCase();
  if (tag === 'input' || tag === 'textarea' || tag === 'select') return true;
  if (target.isContentEditable) return true;
  return false;
}

export function useKeyboardShortcuts() {
  const [isPaletteOpen, setIsPaletteOpen] = useState(false);

  const handleKeyDown = useCallback(
    (e: KeyboardEvent) => {
      const meta = e.metaKey || e.ctrlKey;

      // Ctrl+K or Ctrl+/ → Toggle command palette
      if (meta && (e.key === 'k' || e.key === '/')) {
        e.preventDefault();
        e.stopPropagation();
        setIsPaletteOpen((prev) => !prev);
        return;
      }

      // Escape → Close command palette (only when open, not in inputs)
      if (e.key === 'Escape' && isPaletteOpen) {
        e.preventDefault();
        setIsPaletteOpen(false);
        return;
      }

      // Skip remaining shortcuts if user is typing
      if (isEditableTarget(e.target)) return;

      // Future: Add more shortcuts here
      // e.g. Ctrl+N for new item, arrow keys for list navigation
    },
    [isPaletteOpen]
  );

  useEffect(() => {
    document.addEventListener('keydown', handleKeyDown, { capture: true });
    return () => document.removeEventListener('keydown', handleKeyDown, { capture: true });
  }, [handleKeyDown]);

  return { isPaletteOpen, setIsPaletteOpen };
}
