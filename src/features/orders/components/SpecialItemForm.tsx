/**
 * SpecialItemForm — inline form section for adding non-catalog items.
 *
 * Used inside UnifiedOrderPage. Special items are flagged for office review
 * and shown in the order line list with a ⚠️ badge.
 *
 * The form collects: description (required), quantity, unit, part number,
 * estimated cost, and optional notes.
 */

import { useState } from 'react';
import {
  AlertTriangle,
  Plus,
  X,
  Trash2,
} from 'lucide-react';
import type { SpecialItemCreate } from '../../../lib/types';

interface SpecialItemFormProps {
  /** Current list of special items in the order */
  items: SpecialItemCreate[];
  /** Called when items change (add/update/remove) */
  onChange: (items: SpecialItemCreate[]) => void;
  /** Whether the form is in read-only mode (e.g. after submission) */
  readOnly?: boolean;
}

const BLANK_ITEM: SpecialItemCreate = {
  description: '',
  quantity: 1,
  unit: 'each',
  part_number: '',
  estimated_cost: null,
  notes: '',
};

export function SpecialItemForm({ items, onChange, readOnly }: SpecialItemFormProps) {
  const [showAddForm, setShowAddForm] = useState(false);
  const [draft, setDraft] = useState<SpecialItemCreate>({ ...BLANK_ITEM });
  const [error, setError] = useState('');

  // ── Add the current draft to the items list ─────────────────────
  const handleAdd = () => {
    if (!draft.description.trim()) {
      setError('Description is required.');
      return;
    }
    if ((draft.quantity ?? 1) < 1) {
      setError('Quantity must be at least 1.');
      return;
    }

    setError('');
    onChange([
      ...items,
      {
        ...draft,
        description: draft.description.trim(),
        part_number: draft.part_number?.trim() || undefined,
        notes: draft.notes?.trim() || undefined,
        estimated_cost: draft.estimated_cost || undefined,
      },
    ]);
    setDraft({ ...BLANK_ITEM });
    setShowAddForm(false);
  };

  // ── Remove a special item by index ──────────────────────────────
  const handleRemove = (index: number) => {
    onChange(items.filter((_, i) => i !== index));
  };

  return (
    <div className="space-y-3">
      {/* ── Section header ────────────────────────────────────── */}
      <div className="flex items-center justify-between">
        <div className="flex items-center gap-2">
          <AlertTriangle className="h-4 w-4 text-amber-500" />
          <h3 className="text-sm font-semibold text-gray-900 dark:text-gray-100">
            Special Items ({items.length})
          </h3>
        </div>
        {!readOnly && !showAddForm && (
          <button
            type="button"
            onClick={() => setShowAddForm(true)}
            className="inline-flex items-center gap-1.5 rounded-lg bg-amber-50 dark:bg-amber-900/20 border border-amber-200 dark:border-amber-800 px-3 py-1.5 text-sm font-medium text-amber-700 dark:text-amber-300 hover:bg-amber-100 dark:hover:bg-amber-900/30 transition-colors min-h-[36px]"
          >
            <Plus className="h-4 w-4" />
            <span className="hidden sm:inline">Add Special Item</span>
            <span className="sm:hidden">Add</span>
          </button>
        )}
      </div>

      {/* ── Existing special items list ───────────────────────── */}
      {items.length > 0 && (
        <div className="space-y-2">
          {items.map((item, idx) => (
            <div
              key={idx}
              className="flex items-start gap-3 p-3 rounded-lg border border-amber-200 dark:border-amber-800 bg-amber-50/50 dark:bg-amber-900/10"
            >
              <AlertTriangle className="h-4 w-4 text-amber-500 flex-shrink-0 mt-0.5" />
              <div className="flex-1 min-w-0">
                <p className="text-sm font-medium text-gray-900 dark:text-gray-100">
                  {item.description}
                </p>
                <p className="text-xs text-gray-500 dark:text-gray-400 mt-0.5">
                  Qty: {item.quantity ?? 1} {item.unit ?? 'each'}
                  {item.part_number && ` · P/N: ${item.part_number}`}
                  {item.estimated_cost != null && ` · ~$${item.estimated_cost.toFixed(2)}`}
                </p>
                {item.notes && (
                  <p className="text-xs text-gray-500 dark:text-gray-400 mt-1 italic">
                    {item.notes}
                  </p>
                )}
              </div>
              {!readOnly && (
                <button
                  type="button"
                  onClick={() => handleRemove(idx)}
                  className="flex-shrink-0 p-2 text-gray-400 dark:text-gray-500 hover:text-red-500 transition-colors min-h-[36px] min-w-[36px] flex items-center justify-center"
                  aria-label="Remove special item"
                >
                  <Trash2 className="h-4 w-4" />
                </button>
              )}
            </div>
          ))}
        </div>
      )}

      {/* ── Add-item inline form ──────────────────────────────── */}
      {showAddForm && (
        <div className="rounded-lg border border-amber-200 dark:border-amber-800 bg-amber-50/30 dark:bg-amber-900/10 p-4 space-y-3">
          <div className="flex items-center justify-between">
            <h4 className="text-sm font-medium text-gray-900 dark:text-gray-100">
              Add Non-Catalog Item
            </h4>
            <button
              type="button"
              onClick={() => { setShowAddForm(false); setError(''); }}
              className="p-2 text-gray-400 dark:text-gray-500 hover:text-gray-600 dark:hover:text-gray-300 min-h-[36px] min-w-[36px] flex items-center justify-center"
              aria-label="Cancel"
            >
              <X className="h-4 w-4" />
            </button>
          </div>

          {error && (
            <p className="text-xs text-red-600 dark:text-red-400">{error}</p>
          )}

          {/* Description (required) */}
          <div className="space-y-1">
            <label className="block text-xs font-medium text-gray-600 dark:text-gray-400">
              Description <span className="text-red-500">*</span>
            </label>
            <input
              type="text"
              value={draft.description}
              onChange={(e) => setDraft({ ...draft, description: e.target.value })}
              placeholder="e.g. Custom junction box with 6 knockouts"
              className="w-full rounded-lg border border-gray-300 dark:border-gray-600 bg-white dark:bg-gray-800 px-3 py-2 text-sm text-gray-900 dark:text-gray-100 placeholder:text-gray-400 dark:placeholder:text-gray-500 focus:ring-2 focus:ring-primary-300 focus:border-primary-500 min-h-[44px]"
              autoFocus
            />
          </div>

          {/* Row: Quantity + Unit + Part Number */}
          <div className="grid grid-cols-2 sm:grid-cols-3 gap-3">
            <div className="space-y-1">
              <label className="block text-xs font-medium text-gray-600 dark:text-gray-400">
                Qty
              </label>
              <input
                type="number"
                min="1"
                value={draft.quantity ?? 1}
                onChange={(e) => setDraft({ ...draft, quantity: parseInt(e.target.value) || 1 })}
                className="w-full rounded-lg border border-gray-300 dark:border-gray-600 bg-white dark:bg-gray-800 px-3 py-2 text-sm text-gray-900 dark:text-gray-100 focus:ring-2 focus:ring-primary-300 focus:border-primary-500 min-h-[44px]"
              />
            </div>

            <div className="space-y-1">
              <label className="block text-xs font-medium text-gray-600 dark:text-gray-400">
                Unit
              </label>
              <select
                value={draft.unit ?? 'each'}
                onChange={(e) => setDraft({ ...draft, unit: e.target.value })}
                className="w-full rounded-lg border border-gray-300 dark:border-gray-600 bg-white dark:bg-gray-800 px-3 py-2 text-sm text-gray-900 dark:text-gray-100 focus:ring-2 focus:ring-primary-300 focus:border-primary-500 min-h-[44px]"
              >
                <option value="each">Each</option>
                <option value="box">Box</option>
                <option value="roll">Roll</option>
                <option value="ft">Feet</option>
                <option value="m">Meters</option>
                <option value="pair">Pair</option>
                <option value="set">Set</option>
                <option value="lb">Pounds</option>
              </select>
            </div>

            <div className="space-y-1 col-span-2 sm:col-span-1">
              <label className="block text-xs font-medium text-gray-600 dark:text-gray-400">
                Part #
              </label>
              <input
                type="text"
                value={draft.part_number ?? ''}
                onChange={(e) => setDraft({ ...draft, part_number: e.target.value })}
                placeholder="Optional"
                className="w-full rounded-lg border border-gray-300 dark:border-gray-600 bg-white dark:bg-gray-800 px-3 py-2 text-sm text-gray-900 dark:text-gray-100 placeholder:text-gray-400 dark:placeholder:text-gray-500 focus:ring-2 focus:ring-primary-300 focus:border-primary-500 min-h-[44px]"
              />
            </div>
          </div>

          {/* Estimated cost + Notes */}
          <div className="grid grid-cols-1 sm:grid-cols-2 gap-3">
            <div className="space-y-1">
              <label className="block text-xs font-medium text-gray-600 dark:text-gray-400">
                Estimated Cost
              </label>
              <input
                type="number"
                min="0"
                step="0.01"
                value={draft.estimated_cost ?? ''}
                onChange={(e) =>
                  setDraft({
                    ...draft,
                    estimated_cost: e.target.value ? parseFloat(e.target.value) : null,
                  })
                }
                placeholder="$0.00"
                className="w-full rounded-lg border border-gray-300 dark:border-gray-600 bg-white dark:bg-gray-800 px-3 py-2 text-sm text-gray-900 dark:text-gray-100 placeholder:text-gray-400 dark:placeholder:text-gray-500 focus:ring-2 focus:ring-primary-300 focus:border-primary-500 min-h-[44px]"
              />
            </div>

            <div className="space-y-1">
              <label className="block text-xs font-medium text-gray-600 dark:text-gray-400">
                Notes
              </label>
              <input
                type="text"
                value={draft.notes ?? ''}
                onChange={(e) => setDraft({ ...draft, notes: e.target.value })}
                placeholder="Optional notes"
                className="w-full rounded-lg border border-gray-300 dark:border-gray-600 bg-white dark:bg-gray-800 px-3 py-2 text-sm text-gray-900 dark:text-gray-100 placeholder:text-gray-400 dark:placeholder:text-gray-500 focus:ring-2 focus:ring-primary-300 focus:border-primary-500 min-h-[44px]"
              />
            </div>
          </div>

          {/* Action buttons */}
          <div className="flex justify-end gap-2 pt-1">
            <button
              type="button"
              onClick={() => { setShowAddForm(false); setError(''); }}
              className="px-3 py-1.5 text-sm text-gray-600 dark:text-gray-400 hover:text-gray-900 dark:hover:text-gray-200 transition-colors min-h-[36px]"
            >
              Cancel
            </button>
            <button
              type="button"
              onClick={handleAdd}
              className="inline-flex items-center gap-1.5 rounded-lg bg-amber-500 hover:bg-amber-600 px-4 py-1.5 text-sm font-medium text-white shadow-sm transition-colors min-h-[36px]"
            >
              <Plus className="h-4 w-4" />
              Add Item
            </button>
          </div>
        </div>
      )}

      {/* ── Hint text ─────────────────────────────────────────── */}
      {items.length === 0 && !showAddForm && (
        <p className="text-xs text-gray-500 dark:text-gray-400">
          Need something not in the catalog? Add a special item — it will be flagged for office review.
        </p>
      )}
    </div>
  );
}
