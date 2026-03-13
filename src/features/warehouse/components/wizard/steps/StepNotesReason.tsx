/**
 * Step 5: Notes & Reason — sub-categorized quick-pick reasons + free text.
 *
 * Displays reason categories as a grid of chips. Selecting a category
 * reveals sub-reasons. Free-text notes and reference number fields below.
 */

import { useState } from 'react';
import { useQuery } from '@tanstack/react-query';
import { cn } from '../../../../../lib/utils';
import { getMovementReasons } from '../../../../../api/warehouse';
import { useMovementWizardStore } from '../../../stores/movement-wizard-store';

export function StepNotesReason() {
  const {
    reason,
    reasonDetail,
    notes,
    referenceNumber,
    setReason,
    setReasonDetail,
    setNotes,
    setReferenceNumber,
    getMovementType,
  } = useMovementWizardStore();

  const { data: reasonCategories = {} } = useQuery({
    queryKey: ['warehouse', 'movement-reasons'],
    queryFn: getMovementReasons,
    staleTime: 300_000,
  });

  const [expandedCategory, setExpandedCategory] = useState<string | null>(
    reason ?? null
  );

  const movementType = getMovementType();

  const handleCategoryClick = (category: string) => {
    if (expandedCategory === category) {
      // Deselect
      setExpandedCategory(null);
      setReason(null);
      setReasonDetail(null);
    } else {
      setExpandedCategory(category);
      setReason(category);
      setReasonDetail(null);
    }
  };

  const handleSubReasonClick = (subReason: string) => {
    setReasonDetail(subReason);
  };

  return (
    <div className="space-y-6">
      {/* Reason quick-picks */}
      <div>
        <label className="block text-sm font-medium text-gray-700 dark:text-gray-300 mb-3">
          Reason for Movement
          <span className="text-gray-400 font-normal ml-1">(optional)</span>
        </label>

        <div className="grid grid-cols-2 sm:grid-cols-3 gap-2">
          {Object.entries(reasonCategories).map(([category, subReasons]) => (
            <div key={category}>
              <button
                onClick={() => handleCategoryClick(category)}
                className={cn(
                  'w-full px-3 py-2.5 rounded-lg text-sm font-medium text-left transition-colors border',
                  reason === category
                    ? 'border-primary-500 bg-primary-50 dark:bg-primary-900/30 text-primary-700 dark:text-primary-400'
                    : 'border-gray-200 dark:border-gray-700 text-gray-700 dark:text-gray-300 hover:bg-gray-50 dark:hover:bg-gray-900/50',
                )}
              >
                {category}
              </button>

              {/* Sub-reasons */}
              {expandedCategory === category &&
                (subReasons as string[]).length > 0 && (
                  <div className="mt-1 space-y-1 pl-2">
                    {(subReasons as string[]).map((sub) => (
                      <button
                        key={sub}
                        onClick={() => handleSubReasonClick(sub)}
                        className={cn(
                          'w-full px-2.5 py-1.5 rounded text-xs text-left transition-colors',
                          reasonDetail === sub
                            ? 'bg-primary-100 dark:bg-primary-900/40 text-primary-700 dark:text-primary-400 font-medium'
                            : 'text-gray-600 dark:text-gray-400 hover:bg-gray-100 dark:hover:bg-gray-800',
                        )}
                      >
                        {sub}
                      </button>
                    ))}
                  </div>
                )}
            </div>
          ))}
        </div>
      </div>

      {/* Reference Number */}
      {(movementType === 'return' || movementType === 'consume') && (
        <div>
          <label className="block text-sm font-medium text-gray-700 dark:text-gray-300 mb-2">
            Reference # <span className="text-gray-400 font-normal">(optional)</span>
          </label>
          <input
            type="text"
            value={referenceNumber ?? ''}
            onChange={(e) => setReferenceNumber(e.target.value || null)}
            placeholder="e.g. PO-2024-001, Job ticket #..."
            className="w-full px-3 py-2.5 rounded-lg border border-gray-300 dark:border-gray-600 bg-white dark:bg-gray-800 text-gray-900 dark:text-gray-100 text-sm"
          />
        </div>
      )}

      {/* Notes */}
      <div>
        <label className="block text-sm font-medium text-gray-700 dark:text-gray-300 mb-2">
          Notes <span className="text-gray-400 font-normal">(optional)</span>
        </label>
        <textarea
          value={notes ?? ''}
          onChange={(e) => setNotes(e.target.value || null)}
          placeholder="Add any additional notes about this movement..."
          rows={3}
          className="w-full px-3 py-2.5 rounded-lg border border-gray-300 dark:border-gray-600 bg-white dark:bg-gray-800 text-gray-900 dark:text-gray-100 text-sm resize-none"
        />
      </div>
    </div>
  );
}
