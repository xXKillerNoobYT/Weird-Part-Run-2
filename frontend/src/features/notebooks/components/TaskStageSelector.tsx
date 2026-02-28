/**
 * TaskStageSelector — interactive pipeline showing task stage transitions.
 *
 * Renders 5 stages as a horizontal pipeline. The current stage is highlighted.
 * Clicking a stage triggers a status update. When selecting "Parts Ordered",
 * shows a text area for the parts note.
 */

import { useState } from 'react';
import { Check } from 'lucide-react';
import {
  TASK_STATUS_LABELS,
  TASK_STATUS_ORDER,
  type TaskStatus,
} from '../../../lib/types';

interface TaskStageSelectorProps {
  currentStatus: TaskStatus;
  onStatusChange: (status: TaskStatus, partsNote?: string) => void;
  disabled?: boolean;
}

const STAGE_COLORS: Record<TaskStatus, { bg: string; border: string; text: string; dot: string }> = {
  planned:         { bg: 'bg-gray-100 dark:bg-gray-800',   border: 'border-gray-300 dark:border-gray-600',   text: 'text-gray-600 dark:text-gray-400',   dot: 'bg-gray-400' },
  parts_ordered:   { bg: 'bg-amber-50 dark:bg-amber-900/20', border: 'border-amber-300 dark:border-amber-600', text: 'text-amber-700 dark:text-amber-300', dot: 'bg-amber-500' },
  parts_delivered:  { bg: 'bg-blue-50 dark:bg-blue-900/20',  border: 'border-blue-300 dark:border-blue-600',  text: 'text-blue-700 dark:text-blue-300',  dot: 'bg-blue-500' },
  in_progress:     { bg: 'bg-sky-50 dark:bg-sky-900/20',    border: 'border-sky-300 dark:border-sky-600',    text: 'text-sky-700 dark:text-sky-300',    dot: 'bg-sky-500' },
  done:            { bg: 'bg-green-50 dark:bg-green-900/20', border: 'border-green-300 dark:border-green-600', text: 'text-green-700 dark:text-green-300', dot: 'bg-green-500' },
};

export function TaskStageSelector({ currentStatus, onStatusChange, disabled }: TaskStageSelectorProps) {
  const [pendingStatus, setPendingStatus] = useState<TaskStatus | null>(null);
  const [partsNote, setPartsNote] = useState('');

  const currentIndex = TASK_STATUS_ORDER.indexOf(currentStatus);

  const handleStageClick = (status: TaskStatus) => {
    if (disabled || status === currentStatus) return;

    // When transitioning to parts_ordered, prompt for parts note
    if (status === 'parts_ordered') {
      setPendingStatus(status);
      return;
    }

    onStatusChange(status);
  };

  const confirmPartsOrdered = () => {
    if (pendingStatus) {
      onStatusChange(pendingStatus, partsNote || undefined);
      setPendingStatus(null);
      setPartsNote('');
    }
  };

  return (
    <div className="space-y-2">
      <div className="flex items-center gap-0.5">
        {TASK_STATUS_ORDER.map((status, index) => {
          const isActive = status === currentStatus;
          const isPast = index < currentIndex;
          const colors = STAGE_COLORS[status];

          return (
            <button
              key={status}
              onClick={() => handleStageClick(status)}
              disabled={disabled}
              className={`
                flex items-center gap-1 px-2 py-1 text-[10px] font-medium rounded-md
                border transition-all
                ${isActive
                  ? `${colors.bg} ${colors.border} ${colors.text} ring-1 ring-offset-1 ring-offset-surface`
                  : isPast
                    ? 'bg-green-50 dark:bg-green-900/10 border-green-200 dark:border-green-800 text-green-600 dark:text-green-400'
                    : 'bg-surface border-border text-gray-400 dark:text-gray-500 hover:bg-surface-secondary'
                }
                ${disabled ? 'cursor-not-allowed opacity-60' : 'cursor-pointer'}
              `}
              title={TASK_STATUS_LABELS[status]}
            >
              {isPast ? (
                <Check className="h-3 w-3" />
              ) : isActive ? (
                <div className={`w-2 h-2 rounded-full ${colors.dot}`} />
              ) : null}
              <span className="hidden sm:inline">{TASK_STATUS_LABELS[status]}</span>
            </button>
          );
        })}
      </div>

      {/* Parts note prompt */}
      {pendingStatus === 'parts_ordered' && (
        <div className="p-3 bg-amber-50 dark:bg-amber-900/20 border border-amber-200 dark:border-amber-800 rounded-lg space-y-2">
          <label className="text-xs font-medium text-amber-700 dark:text-amber-300">
            What parts are needed?
          </label>
          <textarea
            value={partsNote}
            onChange={(e) => setPartsNote(e.target.value)}
            placeholder="Describe the parts needed..."
            className="w-full rounded-md border border-amber-300 dark:border-amber-700 bg-surface px-3 py-2 text-sm min-h-[60px] resize-none"
            autoFocus
          />
          <div className="flex justify-end gap-2">
            <button
              onClick={() => { setPendingStatus(null); setPartsNote(''); }}
              className="px-2 py-1 text-xs text-gray-500 hover:text-gray-700"
            >
              Cancel
            </button>
            <button
              onClick={confirmPartsOrdered}
              className="px-3 py-1 text-xs font-medium bg-amber-500 text-white rounded-md hover:bg-amber-600 transition-colors"
            >
              Confirm
            </button>
          </div>
        </div>
      )}
    </div>
  );
}
