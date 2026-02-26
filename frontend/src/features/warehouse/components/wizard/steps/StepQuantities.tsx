/**
 * Step 3: Quantities — set qty per part with live validation.
 *
 * Shows each selected part with an editable quantity input.
 * Red border if qty exceeds available stock. Running total at bottom.
 */

import { Minus, Plus } from 'lucide-react';
import { cn } from '../../../../../lib/utils';
import { useMovementWizardStore } from '../../../stores/movement-wizard-store';
import { useAuthStore } from '../../../../../stores/auth-store';
import { PERMISSIONS } from '../../../../../lib/constants';

export function StepQuantities() {
  const { selectedParts, updatePartQty, getTotalQty } =
    useMovementWizardStore();
  const { hasPermission } = useAuthStore();
  const showDollars = hasPermission(PERMISSIONS.SHOW_DOLLAR_VALUES);
  const totalQty = getTotalQty();

  return (
    <div className="space-y-4">
      <p className="text-sm text-gray-500 dark:text-gray-400">
        Set the quantity for each part. Quantities must not exceed available stock.
      </p>

      {/* Part list with qty inputs */}
      <div className="space-y-2">
        {selectedParts.map((part) => {
          const isOverQty = part.qty > part.available_qty;
          const isZero = part.qty <= 0;
          const hasError = isOverQty || isZero;

          return (
            <div
              key={part.part_id}
              className={cn(
                'flex items-center gap-4 px-4 py-3 rounded-lg border',
                hasError
                  ? 'border-red-300 dark:border-red-700 bg-red-50 dark:bg-red-900/20'
                  : 'border-gray-200 dark:border-gray-700 bg-white dark:bg-gray-800',
              )}
            >
              {/* Part info */}
              <div className="flex-1 min-w-0">
                <div className="text-sm font-medium text-gray-900 dark:text-gray-100 truncate">
                  {part.part_name}
                </div>
                <div className="flex items-center gap-3 mt-0.5">
                  {part.part_code && (
                    <span className="text-xs text-gray-400">{part.part_code}</span>
                  )}
                  <span className="text-xs text-gray-400">
                    Available: {part.available_qty}
                  </span>
                  {part.supplier_name && (
                    <span className="text-xs text-gray-400">
                      via {part.supplier_name}
                    </span>
                  )}
                </div>
              </div>

              {/* Qty input with +/- buttons */}
              <div className="flex items-center gap-1 flex-shrink-0">
                <button
                  onClick={() => updatePartQty(part.part_id, part.qty - 1)}
                  disabled={part.qty <= 1}
                  className="p-1.5 rounded-lg border border-gray-300 dark:border-gray-600 text-gray-500 hover:bg-gray-50 dark:hover:bg-gray-700 disabled:opacity-30 disabled:cursor-not-allowed transition-colors"
                >
                  <Minus className="h-3.5 w-3.5" />
                </button>

                <input
                  type="number"
                  min={1}
                  max={part.available_qty}
                  value={part.qty}
                  onChange={(e) =>
                    updatePartQty(part.part_id, parseInt(e.target.value) || 0)
                  }
                  className={cn(
                    'w-16 text-center px-2 py-1.5 rounded-lg border text-sm font-medium outline-none',
                    hasError
                      ? 'border-red-400 text-red-600 dark:text-red-400 bg-red-50 dark:bg-red-900/20'
                      : 'border-gray-300 dark:border-gray-600 text-gray-900 dark:text-gray-100 bg-white dark:bg-gray-800',
                  )}
                />

                <button
                  onClick={() => updatePartQty(part.part_id, part.qty + 1)}
                  disabled={part.qty >= part.available_qty}
                  className="p-1.5 rounded-lg border border-gray-300 dark:border-gray-600 text-gray-500 hover:bg-gray-50 dark:hover:bg-gray-700 disabled:opacity-30 disabled:cursor-not-allowed transition-colors"
                >
                  <Plus className="h-3.5 w-3.5" />
                </button>
              </div>

              {/* Error hint */}
              {isOverQty && (
                <span className="text-xs text-red-500 flex-shrink-0">
                  Max: {part.available_qty}
                </span>
              )}
            </div>
          );
        })}
      </div>

      {/* Running total */}
      <div className="flex items-center justify-between px-4 py-3 rounded-lg bg-gray-50 dark:bg-gray-900/50 border border-gray-200 dark:border-gray-700">
        <span className="text-sm font-medium text-gray-700 dark:text-gray-300">
          Total
        </span>
        <div className="text-right">
          <span className="text-lg font-semibold text-gray-900 dark:text-gray-100">
            {totalQty} units
          </span>
          <span className="text-sm text-gray-400 ml-1">
            across {selectedParts.length} part{selectedParts.length !== 1 ? 's' : ''}
          </span>
        </div>
      </div>
    </div>
  );
}
