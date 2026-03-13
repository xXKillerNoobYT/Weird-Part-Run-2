/**
 * TriggerItemRow — a single category + style + qty input row
 * for the manual trigger form.
 */

import { Trash2 } from 'lucide-react';
import type { PartCategory, PartStyle } from '../../../../lib/types';

interface TriggerItemRowProps {
  index: number;
  categoryId: number | '';
  styleId: number | '' | null;
  qty: number;
  categories: PartCategory[];
  styles: PartStyle[];
  canRemove: boolean;
  onChange: (index: number, field: string, value: any) => void;
  onRemove: (index: number) => void;
}

export function TriggerItemRow({
  index,
  categoryId,
  styleId,
  qty,
  categories,
  styles,
  canRemove,
  onChange,
  onRemove,
}: TriggerItemRowProps) {
  return (
    <div className="flex flex-col sm:flex-row gap-2 items-start sm:items-end">
      {/* Category */}
      <div className="flex-1 min-w-0 w-full sm:w-auto">
        {index === 0 && (
          <label className="block text-xs font-medium text-gray-500 dark:text-gray-400 mb-1">
            Category
          </label>
        )}
        <select
          value={categoryId}
          onChange={(e) =>
            onChange(index, 'category_id', e.target.value ? Number(e.target.value) : '')
          }
          className="w-full h-9 px-2 text-sm rounded-lg border border-gray-300 dark:border-gray-600 bg-white dark:bg-gray-800 text-gray-900 dark:text-gray-100 focus:outline-none focus:ring-2 focus:ring-primary-300"
        >
          <option value="">Select category...</option>
          {categories.map((c) => (
            <option key={c.id} value={c.id}>
              {c.name}
            </option>
          ))}
        </select>
      </div>

      {/* Style */}
      <div className="flex-1 min-w-0 w-full sm:w-auto">
        {index === 0 && (
          <label className="block text-xs font-medium text-gray-500 dark:text-gray-400 mb-1">
            Style (optional)
          </label>
        )}
        <select
          value={styleId ?? ''}
          onChange={(e) =>
            onChange(index, 'style_id', e.target.value ? Number(e.target.value) : null)
          }
          disabled={!categoryId || styles.length === 0}
          className="w-full h-9 px-2 text-sm rounded-lg border border-gray-300 dark:border-gray-600 bg-white dark:bg-gray-800 text-gray-900 dark:text-gray-100 disabled:opacity-50 focus:outline-none focus:ring-2 focus:ring-primary-300"
        >
          <option value="">Any style</option>
          {styles.map((s) => (
            <option key={s.id} value={s.id}>
              {s.name}
            </option>
          ))}
        </select>
      </div>

      {/* Qty */}
      <div className="w-full sm:w-24">
        {index === 0 && (
          <label className="block text-xs font-medium text-gray-500 dark:text-gray-400 mb-1">
            Qty
          </label>
        )}
        <input
          type="number"
          min={1}
          value={qty}
          onChange={(e) =>
            onChange(index, 'qty', Math.max(1, parseInt(e.target.value) || 1))
          }
          className="w-full h-9 px-2 text-sm rounded-lg border border-gray-300 dark:border-gray-600 bg-white dark:bg-gray-800 text-gray-900 dark:text-gray-100 focus:outline-none focus:ring-2 focus:ring-primary-300"
        />
      </div>

      {/* Remove */}
      <button
        onClick={() => onRemove(index)}
        disabled={!canRemove}
        className="p-2 text-gray-400 hover:text-red-500 disabled:opacity-30 transition-colors shrink-0"
      >
        <Trash2 className="h-4 w-4" />
      </button>
    </div>
  );
}
