/**
 * AddSectionModal — modal for workers to add custom sections to a notebook.
 *
 * Workers can create 'notes' or 'tasks' sections (e.g., by room or area).
 * 'info' sections are template-only (Office-managed), not available here.
 */

import { useState } from 'react';
import { X, FileText, ListTodo } from 'lucide-react';
import type { SectionCreate, SectionType } from '../../../lib/types';

interface AddSectionModalProps {
  notebookId: number;
  onSubmit: (notebookId: number, section: SectionCreate) => void;
  onClose: () => void;
  loading?: boolean;
}

export function AddSectionModal({ notebookId, onSubmit, onClose, loading }: AddSectionModalProps) {
  const [name, setName] = useState('');
  const [sectionType, setSectionType] = useState<SectionType>('tasks');

  const handleSubmit = (e: React.FormEvent) => {
    e.preventDefault();
    if (!name.trim()) return;
    onSubmit(notebookId, { name: name.trim(), section_type: sectionType });
  };

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/50">
      <div className="bg-surface border border-border rounded-xl shadow-xl w-full max-w-sm mx-4">
        {/* Header */}
        <div className="flex items-center justify-between px-5 py-4 border-b border-border">
          <h2 className="text-base font-semibold text-gray-900 dark:text-gray-100">
            Add Section
          </h2>
          <button
            onClick={onClose}
            className="p-1 rounded-lg hover:bg-surface-secondary transition-colors"
          >
            <X className="h-4 w-4 text-gray-400" />
          </button>
        </div>

        <form onSubmit={handleSubmit} className="p-5 space-y-4">
          {/* Section name */}
          <div>
            <label className="block text-xs font-medium text-gray-700 dark:text-gray-300 mb-1">
              Section Name
            </label>
            <input
              type="text"
              value={name}
              onChange={(e) => setName(e.target.value)}
              placeholder="e.g., Kitchen, Living Room, Panel Room..."
              className="w-full rounded-lg border border-border bg-surface px-3 py-2 text-sm focus:ring-2 focus:ring-blue-500 focus:border-blue-500"
              autoFocus
              required
            />
          </div>

          {/* Section type */}
          <div>
            <label className="block text-xs font-medium text-gray-700 dark:text-gray-300 mb-2">
              Section Type
            </label>
            <div className="flex gap-2">
              <button
                type="button"
                onClick={() => setSectionType('tasks')}
                className={`flex-1 flex items-center justify-center gap-1.5 py-2 text-xs font-medium rounded-lg border transition-colors ${
                  sectionType === 'tasks'
                    ? 'bg-blue-50 dark:bg-blue-900/20 border-blue-300 dark:border-blue-600 text-blue-700 dark:text-blue-300'
                    : 'bg-surface border-border text-gray-500 hover:border-gray-300 dark:hover:border-gray-600'
                }`}
              >
                <ListTodo className="h-3.5 w-3.5" />
                Tasks
              </button>
              <button
                type="button"
                onClick={() => setSectionType('notes')}
                className={`flex-1 flex items-center justify-center gap-1.5 py-2 text-xs font-medium rounded-lg border transition-colors ${
                  sectionType === 'notes'
                    ? 'bg-blue-50 dark:bg-blue-900/20 border-blue-300 dark:border-blue-600 text-blue-700 dark:text-blue-300'
                    : 'bg-surface border-border text-gray-500 hover:border-gray-300 dark:hover:border-gray-600'
                }`}
              >
                <FileText className="h-3.5 w-3.5" />
                Notes
              </button>
            </div>
            <p className="text-[11px] text-gray-400 dark:text-gray-500 mt-1.5">
              {sectionType === 'tasks'
                ? 'Track tasks with stage pipeline (Planned → Done)'
                : 'Free-form notes and observations'}
            </p>
          </div>

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
              disabled={!name.trim() || loading}
              className="px-4 py-2 text-sm font-medium text-white bg-blue-500 hover:bg-blue-600 disabled:opacity-50 disabled:cursor-not-allowed rounded-lg transition-colors"
            >
              {loading ? 'Adding...' : 'Add Section'}
            </button>
          </div>
        </form>
      </div>
    </div>
  );
}
