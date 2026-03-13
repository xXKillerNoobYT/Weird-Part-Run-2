/**
 * AuditProgressBar — X/Y items counted with percentage and color bar.
 */

import { cn } from '../../../../lib/utils';
import type { AuditProgress } from '../../../../lib/types';

interface AuditProgressBarProps {
  progress: AuditProgress;
}

export function AuditProgressBar({ progress }: AuditProgressBarProps) {
  const pct = progress.pct_complete;
  const barColor = pct === 100 ? 'bg-green-500' : 'bg-primary-500';

  return (
    <div className="space-y-1.5">
      <div className="flex items-center justify-between text-sm">
        <span className="text-gray-700 dark:text-gray-300 font-medium">
          {progress.counted}/{progress.total_items} items
        </span>
        <span className="text-gray-500 dark:text-gray-400">
          {pct}%
        </span>
      </div>
      <div className="w-full h-2.5 bg-gray-200 dark:bg-gray-700 rounded-full overflow-hidden">
        <div
          className={cn('h-full rounded-full transition-all duration-300', barColor)}
          style={{ width: `${pct}%` }}
        />
      </div>
      <div className="flex gap-4 text-xs text-gray-500 dark:text-gray-400">
        <span className="text-green-600 dark:text-green-400">
          {progress.matched} matched
        </span>
        <span className="text-red-600 dark:text-red-400">
          {progress.discrepancies} discrepancies
        </span>
        <span>{progress.skipped} skipped</span>
      </div>
    </div>
  );
}
