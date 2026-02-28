/**
 * TaskEntryCard — renders a task entry with interactive stage pipeline.
 *
 * Shows title, assigned user, due date, parts note (when parts_ordered),
 * and the interactive TaskStageSelector pipeline.
 */

import { useState } from 'react';
import { Calendar, Edit2, Trash2, User, Package } from 'lucide-react';
import { TaskStageSelector } from './TaskStageSelector';
import type { EntryResponse, TaskStatus } from '../../../lib/types';
import { TASK_STATUS_LABELS } from '../../../lib/types';

interface TaskEntryCardProps {
  entry: EntryResponse;
  onStatusChange?: (entryId: number, status: TaskStatus, partsNote?: string) => void;
  onUpdate?: (entryId: number, title: string, content: string) => void;
  onDelete?: (entryId: number) => void;
}

export function TaskEntryCard({
  entry,
  onStatusChange,
  onUpdate,
  onDelete,
}: TaskEntryCardProps) {
  const [editing, setEditing] = useState(false);
  const [title, setTitle] = useState(entry.title);
  const [content, setContent] = useState(entry.content ?? '');

  const isDone = entry.task_status === 'done';

  const handleSave = () => {
    if (title.trim() && onUpdate) {
      onUpdate(entry.id, title, content);
    }
    setEditing(false);
  };

  if (editing) {
    return (
      <div className="p-3 bg-surface border border-blue-300 dark:border-blue-600 rounded-lg space-y-2">
        <input
          type="text"
          value={title}
          onChange={(e) => setTitle(e.target.value)}
          className="w-full rounded-md border border-border bg-surface px-2 py-1 text-sm font-medium focus:ring-1 focus:ring-blue-500"
          placeholder="Task title"
          autoFocus
        />
        <textarea
          value={content}
          onChange={(e) => setContent(e.target.value)}
          className="w-full rounded-md border border-border bg-surface px-2 py-1.5 text-sm min-h-[60px] resize-none focus:ring-1 focus:ring-blue-500"
          placeholder="Task notes..."
        />
        <div className="flex justify-end gap-2">
          <button
            onClick={() => { setEditing(false); setTitle(entry.title); setContent(entry.content ?? ''); }}
            className="px-2 py-1 text-xs text-gray-500 hover:text-gray-700"
          >
            Cancel
          </button>
          <button
            onClick={handleSave}
            className="px-3 py-1 text-xs font-medium bg-blue-500 text-white rounded-md hover:bg-blue-600"
          >
            Save
          </button>
        </div>
      </div>
    );
  }

  return (
    <div
      className={`group p-3 bg-surface border border-border rounded-lg hover:border-gray-300 dark:hover:border-gray-600 transition-colors ${
        isDone ? 'opacity-70' : ''
      }`}
    >
      {/* Header — title + action buttons */}
      <div className="flex items-start justify-between gap-2 mb-2">
        <h4 className={`text-sm font-medium ${isDone ? 'line-through text-gray-400 dark:text-gray-500' : 'text-gray-900 dark:text-gray-100'}`}>
          {entry.title}
        </h4>

        {entry.can_edit && (
          <div className="flex items-center gap-1 opacity-0 group-hover:opacity-100 transition-opacity">
            <button
              onClick={() => setEditing(true)}
              className="p-1 rounded text-gray-400 hover:text-blue-500 hover:bg-blue-50 dark:hover:bg-blue-900/30"
              title="Edit task"
            >
              <Edit2 className="h-3.5 w-3.5" />
            </button>
            {onDelete && (
              <button
                onClick={() => onDelete(entry.id)}
                className="p-1 rounded text-gray-400 hover:text-red-500 hover:bg-red-50 dark:hover:bg-red-900/30"
                title="Delete task"
              >
                <Trash2 className="h-3.5 w-3.5" />
              </button>
            )}
          </div>
        )}
      </div>

      {/* Content / task notes */}
      {entry.content && (
        <p className="text-sm text-gray-600 dark:text-gray-400 mb-2 whitespace-pre-wrap">
          {entry.content}
        </p>
      )}

      {/* Stage pipeline */}
      <TaskStageSelector
        currentStatus={entry.task_status ?? 'planned'}
        onStatusChange={(status, partsNote) => onStatusChange?.(entry.id, status, partsNote)}
        disabled={!entry.can_edit && !onStatusChange}
      />

      {/* Parts note (shown when parts_ordered or later with a note) */}
      {entry.task_parts_note && (
        <div className="flex items-start gap-2 mt-2 p-2 bg-amber-50 dark:bg-amber-900/10 border border-amber-200 dark:border-amber-800 rounded-md">
          <Package className="h-3.5 w-3.5 text-amber-500 mt-0.5 shrink-0" />
          <p className="text-xs text-amber-700 dark:text-amber-300">{entry.task_parts_note}</p>
        </div>
      )}

      {/* Footer — assigned user, due date, creator */}
      <div className="flex items-center gap-3 mt-2 pt-2 border-t border-border text-[11px]">
        {entry.task_assigned_to_name && (
          <span className="flex items-center gap-1 text-gray-600 dark:text-gray-400">
            <User className="h-3 w-3" />
            {entry.task_assigned_to_name}
          </span>
        )}
        {entry.task_due_date && (
          <span className="flex items-center gap-1 text-gray-500 dark:text-gray-400">
            <Calendar className="h-3 w-3" />
            {new Date(entry.task_due_date).toLocaleDateString('en-US', {
              month: 'short', day: 'numeric',
            })}
          </span>
        )}
        <span className="text-gray-400 dark:text-gray-500 ml-auto">
          {entry.creator_name ?? 'Unknown'}
        </span>
      </div>
    </div>
  );
}
