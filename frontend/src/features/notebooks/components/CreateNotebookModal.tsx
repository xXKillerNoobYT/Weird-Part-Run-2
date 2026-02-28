/**
 * CreateNotebookModal — modal for creating a standalone (general) notebook.
 *
 * Simple form: title + description. Job notebooks are auto-created,
 * so this modal is only for general-purpose notebooks.
 */

import { useState } from 'react';
import { X, BookOpen } from 'lucide-react';
import type { NotebookCreate } from '../../../lib/types';

interface CreateNotebookModalProps {
  onSubmit: (data: NotebookCreate) => void;
  onClose: () => void;
  loading?: boolean;
}

export function CreateNotebookModal({ onSubmit, onClose, loading }: CreateNotebookModalProps) {
  const [title, setTitle] = useState('');
  const [description, setDescription] = useState('');

  const handleSubmit = (e: React.FormEvent) => {
    e.preventDefault();
    if (!title.trim()) return;
    onSubmit({ title: title.trim(), description: description.trim() || undefined });
  };

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/50">
      <div className="bg-surface border border-border rounded-xl shadow-xl w-full max-w-md mx-4">
        {/* Header */}
        <div className="flex items-center gap-3 px-5 py-4 border-b border-border">
          <div className="p-2 bg-blue-50 dark:bg-blue-900/20 rounded-lg">
            <BookOpen className="h-4 w-4 text-blue-500" />
          </div>
          <h2 className="text-base font-semibold text-gray-900 dark:text-gray-100 flex-1">
            New Notebook
          </h2>
          <button
            onClick={onClose}
            className="p-1 rounded-lg hover:bg-surface-secondary transition-colors"
          >
            <X className="h-4 w-4 text-gray-400" />
          </button>
        </div>

        <form onSubmit={handleSubmit} className="p-5 space-y-4">
          <div>
            <label className="block text-xs font-medium text-gray-700 dark:text-gray-300 mb-1">
              Title
            </label>
            <input
              type="text"
              value={title}
              onChange={(e) => setTitle(e.target.value)}
              placeholder="Notebook title..."
              className="w-full rounded-lg border border-border bg-surface px-3 py-2 text-sm focus:ring-2 focus:ring-blue-500 focus:border-blue-500"
              autoFocus
              required
            />
          </div>

          <div>
            <label className="block text-xs font-medium text-gray-700 dark:text-gray-300 mb-1">
              Description (optional)
            </label>
            <textarea
              value={description}
              onChange={(e) => setDescription(e.target.value)}
              placeholder="What is this notebook for?"
              className="w-full rounded-lg border border-border bg-surface px-3 py-2 text-sm min-h-[80px] resize-none focus:ring-2 focus:ring-blue-500 focus:border-blue-500"
            />
          </div>

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
              {loading ? 'Creating...' : 'Create Notebook'}
            </button>
          </div>
        </form>
      </div>
    </div>
  );
}
