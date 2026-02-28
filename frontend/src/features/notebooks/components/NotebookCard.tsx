/**
 * NotebookCard — card for notebook list views.
 *
 * Shows title, description, job badge (if job notebook), task counts,
 * creator, and last-updated timestamp.
 */

import { BookOpen, Briefcase, CheckCircle2, ListTodo } from 'lucide-react';
import type { NotebookListItem } from '../../../lib/types';

interface NotebookCardProps {
  notebook: NotebookListItem;
  onClick?: () => void;
}

export function NotebookCard({ notebook, onClick }: NotebookCardProps) {
  const hasOpenTasks = notebook.open_task_count > 0;
  const allDone = notebook.total_task_count > 0 && notebook.open_task_count === 0;

  return (
    <div
      onClick={onClick}
      className="p-4 bg-surface border border-border rounded-lg hover:border-gray-300 dark:hover:border-gray-600 transition-colors cursor-pointer"
    >
      {/* Header — icon + title */}
      <div className="flex items-start gap-3">
        <div className="p-2 bg-blue-50 dark:bg-blue-900/20 rounded-lg shrink-0">
          <BookOpen className="h-4 w-4 text-blue-500" />
        </div>
        <div className="flex-1 min-w-0">
          <h3 className="text-sm font-semibold text-gray-900 dark:text-gray-100 truncate">
            {notebook.title}
          </h3>
          {notebook.description && (
            <p className="text-xs text-gray-500 dark:text-gray-400 mt-0.5 line-clamp-2">
              {notebook.description}
            </p>
          )}
        </div>
      </div>

      {/* Badges row */}
      <div className="flex items-center gap-2 mt-3 flex-wrap">
        {/* Job badge */}
        {notebook.job_id && (
          <span className="inline-flex items-center gap-1 px-2 py-0.5 text-[10px] font-medium bg-indigo-50 dark:bg-indigo-900/20 text-indigo-600 dark:text-indigo-400 border border-indigo-200 dark:border-indigo-800 rounded-full">
            <Briefcase className="h-3 w-3" />
            {notebook.job_number ?? `Job #${notebook.job_id}`}
          </span>
        )}

        {/* Task count badges */}
        {hasOpenTasks && (
          <span className="inline-flex items-center gap-1 px-2 py-0.5 text-[10px] font-medium bg-amber-50 dark:bg-amber-900/20 text-amber-600 dark:text-amber-400 border border-amber-200 dark:border-amber-800 rounded-full">
            <ListTodo className="h-3 w-3" />
            {notebook.open_task_count} open
          </span>
        )}
        {allDone && (
          <span className="inline-flex items-center gap-1 px-2 py-0.5 text-[10px] font-medium bg-green-50 dark:bg-green-900/20 text-green-600 dark:text-green-400 border border-green-200 dark:border-green-800 rounded-full">
            <CheckCircle2 className="h-3 w-3" />
            All done
          </span>
        )}
      </div>

      {/* Footer — creator + timestamp */}
      <div className="flex items-center justify-between mt-3 pt-2 border-t border-border text-[11px] text-gray-400 dark:text-gray-500">
        <span>{notebook.creator_name ?? 'Unknown'}</span>
        {notebook.updated_at && (
          <span>
            {new Date(notebook.updated_at + 'Z').toLocaleDateString('en-US', {
              month: 'short', day: 'numeric',
            })}
          </span>
        )}
      </div>
    </div>
  );
}
