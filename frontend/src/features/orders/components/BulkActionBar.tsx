/**
 * BulkActionBar — shared component for multi-select + floating action bar.
 *
 * Provides:
 * 1. `useBulkSelection(items)` hook — manages selected IDs, toggle, select-all
 * 2. `<BulkCheckbox>` — table header checkbox (select all) + row checkbox
 * 3. `<BulkActionBar>` — floating bar that appears when items are selected
 *
 * Usage in a list page:
 * ```tsx
 * const { selectedIds, toggle, toggleAll, isSelected, allSelected, clear } = useBulkSelection(items);
 *
 * // In <thead>:
 * <BulkCheckbox checked={allSelected} onChange={toggleAll} isHeader />
 *
 * // In <tbody> row:
 * <BulkCheckbox checked={isSelected(item.id)} onChange={() => toggle(item.id)} />
 *
 * // After the table:
 * <BulkActionBar count={selectedIds.size} onClear={clear} actions={[
 *   { label: 'Approve', icon: Check, onClick: handleBulkApprove, variant: 'primary' },
 *   { label: 'Reject', icon: X, onClick: handleBulkReject, variant: 'danger' },
 * ]} />
 * ```
 *
 * Smart filtering: when the list page filters its data, the selection
 * naturally stays correct because `useBulkSelection` only tracks IDs,
 * and the `toggleAll` function uses the current items array.
 *
 * Phase 7E
 */

import { useState, useCallback, useMemo } from 'react';
import { X, type LucideIcon } from 'lucide-react';


// ─── Hook: useBulkSelection ──────────────────────────────────────────

interface BulkSelectionResult<T extends { id: number }> {
  /** Set of currently selected item IDs */
  selectedIds: Set<number>;
  /** Toggle a single item's selection */
  toggle: (id: number) => void;
  /** Toggle all items (select all if not all selected, otherwise deselect all) */
  toggleAll: () => void;
  /** Check if a specific item is selected */
  isSelected: (id: number) => boolean;
  /** Whether ALL current items are selected */
  allSelected: boolean;
  /** Whether SOME (but not all) items are selected */
  someSelected: boolean;
  /** Clear all selections */
  clear: () => void;
  /** Get the selected items (not just IDs) */
  selectedItems: T[];
}

/**
 * Hook that manages bulk selection state for a list of items.
 *
 * @param items - The currently displayed (possibly filtered) items.
 *   When items change (e.g. filter applied), stale selections are
 *   automatically pruned — only IDs still present in `items` remain.
 */
export function useBulkSelection<T extends { id: number }>(
  items: T[]
): BulkSelectionResult<T> {
  const [selectedIds, setSelectedIds] = useState<Set<number>>(new Set());

  // Build a set of current item IDs for quick lookup
  const currentIds = useMemo(() => new Set(items.map((i) => i.id)), [items]);

  // Prune stale selections (items that are no longer in the current list)
  const activeSelection = useMemo(() => {
    const pruned = new Set<number>();
    for (const id of selectedIds) {
      if (currentIds.has(id)) pruned.add(id);
    }
    return pruned;
  }, [selectedIds, currentIds]);

  const allSelected = items.length > 0 && activeSelection.size === items.length;
  const someSelected = activeSelection.size > 0 && !allSelected;

  const toggle = useCallback((id: number) => {
    setSelectedIds((prev) => {
      const next = new Set(prev);
      if (next.has(id)) {
        next.delete(id);
      } else {
        next.add(id);
      }
      return next;
    });
  }, []);

  const toggleAll = useCallback(() => {
    if (allSelected) {
      // Deselect all
      setSelectedIds(new Set());
    } else {
      // Select all current items
      setSelectedIds(new Set(items.map((i) => i.id)));
    }
  }, [allSelected, items]);

  const isSelected = useCallback(
    (id: number) => activeSelection.has(id),
    [activeSelection]
  );

  const clear = useCallback(() => {
    setSelectedIds(new Set());
  }, []);

  const selectedItems = useMemo(
    () => items.filter((i) => activeSelection.has(i.id)),
    [items, activeSelection]
  );

  return {
    selectedIds: activeSelection,
    toggle,
    toggleAll,
    isSelected,
    allSelected,
    someSelected,
    clear,
    selectedItems,
  };
}


// ─── Component: BulkCheckbox ─────────────────────────────────────────

interface BulkCheckboxProps {
  checked: boolean;
  /** For header checkbox — shows indeterminate state */
  indeterminate?: boolean;
  onChange: () => void;
  /** Renders as <th> instead of <td> */
  isHeader?: boolean;
}

/**
 * Checkbox cell for bulk selection — used in both <thead> and <tbody>.
 *
 * Wraps in <th> or <td> to match the table structure, with proper
 * padding and 44px touch targets.
 */
export function BulkCheckbox({ checked, indeterminate, onChange, isHeader }: BulkCheckboxProps) {
  const Cell = isHeader ? 'th' : 'td';

  return (
    <Cell className={`w-10 px-3 ${isHeader ? 'py-3' : 'py-3'}`}>
      <label className="flex items-center justify-center min-w-[44px] min-h-[44px] -m-2 cursor-pointer">
        <input
          type="checkbox"
          checked={checked}
          ref={(el) => {
            if (el) el.indeterminate = indeterminate ?? false;
          }}
          onChange={(e) => {
            e.stopPropagation();
            onChange();
          }}
          className="h-4 w-4 rounded border-gray-300 dark:border-gray-600 text-primary focus:ring-primary cursor-pointer"
        />
      </label>
    </Cell>
  );
}


// ─── Component: BulkActionBar ────────────────────────────────────────

export interface BulkAction {
  label: string;
  icon?: LucideIcon;
  onClick: () => void;
  variant?: 'primary' | 'danger' | 'default';
  /** Disable this action while loading */
  loading?: boolean;
  /** Optional: only show if this condition is true */
  show?: boolean;
}

interface BulkActionBarProps {
  /** Number of selected items */
  count: number;
  /** Clear selection callback */
  onClear: () => void;
  /** Available bulk actions */
  actions: BulkAction[];
  /** Optional loading state for the whole bar */
  loading?: boolean;
}

/**
 * Floating action bar — appears at the bottom of the viewport when
 * items are selected. Shows selection count + action buttons.
 *
 * Uses `fixed` positioning so it stays visible while scrolling.
 * The bar animates in from below (translate-y transition).
 */
export function BulkActionBar({ count, onClear, actions, loading }: BulkActionBarProps) {
  // Filter actions to only those that should be shown
  const visibleActions = actions.filter((a) => a.show !== false);

  if (count === 0 || visibleActions.length === 0) return null;

  return (
    <div
      className="fixed bottom-4 left-1/2 z-50 -translate-x-1/2 animate-slide-up"
      role="toolbar"
      aria-label={`Bulk actions for ${count} selected items`}
    >
      <div className="flex items-center gap-3 rounded-xl border border-border bg-surface px-4 py-3 shadow-xl dark:shadow-2xl">
        {/* Count badge */}
        <span className="inline-flex items-center gap-1.5 text-sm font-medium text-gray-700 dark:text-gray-200 whitespace-nowrap">
          <span className="flex h-6 min-w-[24px] items-center justify-center rounded-full bg-primary px-1.5 text-xs font-bold text-white">
            {count}
          </span>
          selected
        </span>

        {/* Divider */}
        <div className="h-6 w-px bg-border" />

        {/* Action buttons */}
        <div className="flex items-center gap-2">
          {visibleActions.map((action) => (
            <BulkActionButton
              key={action.label}
              action={action}
              disabled={loading}
            />
          ))}
        </div>

        {/* Clear button */}
        <button
          onClick={onClear}
          className="ml-1 flex items-center justify-center rounded-lg p-1.5 text-gray-400 hover:text-gray-600 dark:text-gray-500 dark:hover:text-gray-300 hover:bg-gray-100 dark:hover:bg-gray-700 transition-colors"
          title="Clear selection"
        >
          <X className="h-4 w-4" />
        </button>
      </div>
    </div>
  );
}


// ─── Internal: BulkActionButton ──────────────────────────────────────

function BulkActionButton({
  action,
  disabled,
}: {
  action: BulkAction;
  disabled?: boolean;
}) {
  const Icon = action.icon;
  const isDisabled = disabled || action.loading;

  const variantClasses: Record<string, string> = {
    primary:
      'bg-primary text-white hover:bg-primary/90 focus:ring-primary',
    danger:
      'bg-red-500 text-white hover:bg-red-600 focus:ring-red-500',
    default:
      'bg-gray-100 dark:bg-gray-700 text-gray-700 dark:text-gray-200 hover:bg-gray-200 dark:hover:bg-gray-600 focus:ring-gray-400',
  };

  const classes = variantClasses[action.variant || 'default'];

  return (
    <button
      onClick={action.onClick}
      disabled={isDisabled}
      className={`inline-flex items-center gap-1.5 rounded-lg px-3 py-1.5 text-sm font-medium transition-colors focus:outline-none focus:ring-2 focus:ring-offset-1 disabled:opacity-50 disabled:cursor-not-allowed ${classes}`}
    >
      {action.loading ? (
        <div className="h-3.5 w-3.5 animate-spin rounded-full border-2 border-current border-t-transparent" />
      ) : Icon ? (
        <Icon className="h-3.5 w-3.5" />
      ) : null}
      <span className="hidden sm:inline">{action.label}</span>
    </button>
  );
}
