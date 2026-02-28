/**
 * CreateEntryModal — modal for creating a note or task entry.
 *
 * Type tabs switch between Note and Task creation forms.
 * Tasks get additional fields: status, due date, parts note.
 */

import { useState } from 'react';
import { X, FileText, ListTodo } from 'lucide-react';
import type { EntryCreate, TaskStatus } from '../../../lib/types';

interface CreateEntryModalProps {
  /** Which type to default to (based on which section the user clicked "Add") */
  defaultType: 'note' | 'task';
  sectionId: number;
  onSubmit: (sectionId: number, entry: EntryCreate) => void;
  onClose: () => void;
  loading?: boolean;
}

export function CreateEntryModal({
  defaultType,
  sectionId,
  onSubmit,
  onClose,
  loading,
}: CreateEntryModalProps) {
  const [type, setType] = useState<'note' | 'task'>(defaultType);
  const [title, setTitle] = useState('');
  const [content, setContent] = useState('');
  const [taskStatus, setTaskStatus] = useState<TaskStatus>('planned');
  const [dueDate, setDueDate] = useState('');

  const handleSubmit = (e: React.FormEvent) => {
    e.preventDefault();
    if (!title.trim()) return;

    const entry: EntryCreate = {
      title: title.trim(),
      content: content.trim() || undefined,
      entry_type: type,
    };

    if (type === 'task') {
      entry.task_status = taskStatus;
      if (dueDate) entry.task_due_date = dueDate;
    }

    onSubmit(sectionId, entry);
  };

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/50">
      <div className="bg-surface border border-border rounded-xl shadow-xl w-full max-w-md mx-4">
        {/* Header */}
        <div className="flex items-center justify-between px-5 py-4 border-b border-border">
          <h2 className="text-base font-semibold text-gray-900 dark:text-gray-100">
            Add Entry
          </h2>
          <button
            onClick={onClose}
            className="p-1 rounded-lg hover:bg-surface-secondary transition-colors"
          >
            <X className="h-4 w-4 text-gray-400" />
          </button>
        </div>

        <form onSubmit={handleSubmit} className="p-5 space-y-4">
          {/* Type tabs */}
          <div className="flex gap-1 p-1 bg-surface-secondary rounded-lg">
            <button
              type="button"
              onClick={() => setType('note')}
              className={`flex-1 flex items-center justify-center gap-1.5 py-1.5 text-xs font-medium rounded-md transition-colors ${
                type === 'note'
                  ? 'bg-surface text-gray-900 dark:text-gray-100 shadow-sm'
                  : 'text-gray-500 dark:text-gray-400 hover:text-gray-700 dark:hover:text-gray-300'
              }`}
            >
              <FileText className="h-3.5 w-3.5" />
              Note
            </button>
            <button
              type="button"
              onClick={() => setType('task')}
              className={`flex-1 flex items-center justify-center gap-1.5 py-1.5 text-xs font-medium rounded-md transition-colors ${
                type === 'task'
                  ? 'bg-surface text-gray-900 dark:text-gray-100 shadow-sm'
                  : 'text-gray-500 dark:text-gray-400 hover:text-gray-700 dark:hover:text-gray-300'
              }`}
            >
              <ListTodo className="h-3.5 w-3.5" />
              Task
            </button>
          </div>

          {/* Title */}
          <div>
            <label className="block text-xs font-medium text-gray-700 dark:text-gray-300 mb-1">
              Title
            </label>
            <input
              type="text"
              value={title}
              onChange={(e) => setTitle(e.target.value)}
              placeholder={type === 'task' ? 'Task title...' : 'Note title...'}
              className="w-full rounded-lg border border-border bg-surface px-3 py-2 text-sm focus:ring-2 focus:ring-blue-500 focus:border-blue-500"
              autoFocus
              required
            />
          </div>

          {/* Content */}
          <div>
            <label className="block text-xs font-medium text-gray-700 dark:text-gray-300 mb-1">
              {type === 'task' ? 'Notes (optional)' : 'Content'}
            </label>
            <textarea
              value={content}
              onChange={(e) => setContent(e.target.value)}
              placeholder={type === 'task' ? 'Additional details...' : 'Note content...'}
              className="w-full rounded-lg border border-border bg-surface px-3 py-2 text-sm min-h-[80px] resize-none focus:ring-2 focus:ring-blue-500 focus:border-blue-500"
            />
          </div>

          {/* Task-specific fields */}
          {type === 'task' && (
            <div className="grid grid-cols-2 gap-3">
              <div>
                <label className="block text-xs font-medium text-gray-700 dark:text-gray-300 mb-1">
                  Initial Status
                </label>
                <select
                  value={taskStatus}
                  onChange={(e) => setTaskStatus(e.target.value as TaskStatus)}
                  className="w-full rounded-lg border border-border bg-surface px-3 py-2 text-sm"
                >
                  <option value="planned">Planned</option>
                  <option value="in_progress">In Progress</option>
                </select>
              </div>
              <div>
                <label className="block text-xs font-medium text-gray-700 dark:text-gray-300 mb-1">
                  Due Date
                </label>
                <input
                  type="date"
                  value={dueDate}
                  onChange={(e) => setDueDate(e.target.value)}
                  className="w-full rounded-lg border border-border bg-surface px-3 py-2 text-sm"
                />
              </div>
            </div>
          )}

          {/* Actions */}
          <div className="flex justify-end gap-2 pt-2">
            <button
              type="button"
              onClick={onClose}
              className="px-4 py-2 text-sm font-medium text-gray-600 dark:text-gray-400 hover:text-gray-800 dark:hover:text-gray-200 rounded-lg hover:bg-surface-secondary transition-colors"
            >
              Cancel
            </button>
            <button
              type="submit"
              disabled={!title.trim() || loading}
              className="px-4 py-2 text-sm font-medium text-white bg-blue-500 hover:bg-blue-600 disabled:opacity-50 disabled:cursor-not-allowed rounded-lg transition-colors"
            >
              {loading ? 'Creating...' : `Add ${type === 'task' ? 'Task' : 'Note'}`}
            </button>
          </div>
        </form>
      </div>
    </div>
  );
}
