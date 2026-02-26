/**
 * MovementFilters — date range, movement type, and search for the log.
 */

import { Search } from 'lucide-react';
import { Input } from '../../../../components/ui/Input';
import { cn } from '../../../../lib/utils';

const TYPE_OPTIONS = [
  { label: 'All', value: '' },
  { label: 'Transfer', value: 'transfer' },
  { label: 'Consume', value: 'consume' },
  { label: 'Return', value: 'return' },
  { label: 'Adjust', value: 'adjust' },
  { label: 'Receive', value: 'receive' },
  { label: 'Write-off', value: 'write_off' },
];

interface MovementFiltersProps {
  movementType: string;
  onMovementTypeChange: (type: string) => void;
  dateFrom: string;
  onDateFromChange: (date: string) => void;
  dateTo: string;
  onDateToChange: (date: string) => void;
}

export function MovementFilters({
  movementType,
  onMovementTypeChange,
  dateFrom,
  onDateFromChange,
  dateTo,
  onDateToChange,
}: MovementFiltersProps) {
  return (
    <div className="space-y-4">
      {/* Type chips */}
      <div className="flex flex-wrap gap-2">
        {TYPE_OPTIONS.map((option) => (
          <button
            key={option.value}
            onClick={() => onMovementTypeChange(option.value)}
            className={cn(
              'px-3 py-1.5 rounded-full text-xs font-medium transition-colors',
              movementType === option.value
                ? 'bg-primary-500 text-white'
                : 'bg-gray-100 text-gray-600 hover:bg-gray-200 dark:bg-gray-700 dark:text-gray-300 dark:hover:bg-gray-600',
            )}
          >
            {option.label}
          </button>
        ))}
      </div>

      {/* Date range */}
      <div className="flex flex-wrap gap-3">
        <div>
          <label className="block text-xs text-gray-500 dark:text-gray-400 mb-1">From</label>
          <input
            type="date"
            value={dateFrom}
            onChange={(e) => onDateFromChange(e.target.value)}
            className="rounded-lg border border-gray-300 dark:border-gray-600 bg-white dark:bg-gray-800 px-3 py-1.5 text-sm text-gray-900 dark:text-gray-100 focus:outline-none focus:ring-2 focus:ring-primary-300"
          />
        </div>
        <div>
          <label className="block text-xs text-gray-500 dark:text-gray-400 mb-1">To</label>
          <input
            type="date"
            value={dateTo}
            onChange={(e) => onDateToChange(e.target.value)}
            className="rounded-lg border border-gray-300 dark:border-gray-600 bg-white dark:bg-gray-800 px-3 py-1.5 text-sm text-gray-900 dark:text-gray-100 focus:outline-none focus:ring-2 focus:ring-primary-300"
          />
        </div>
      </div>
    </div>
  );
}
