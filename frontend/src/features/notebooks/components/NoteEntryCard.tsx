/**
 * NoteEntryCard — renders a free-form note entry.
 *
 * Shows title, content, creator name, and timestamp.
 * Editable if the user has permission (creator, manager, or delegated).
 */

import { useState } from 'react';
import { Edit2, Trash2, User } from 'lucide-react';
import type { EntryResponse } from '../../../lib/types';

interface NoteEntryCardProps {
  entry: EntryResponse;
  onUpdate?: (entryId: number, title: string, content: string) => void;
  onDelete?: (entryId: number) => void;
}

export function NoteEntryCard({ entry, onUpdate, onDelete }: NoteEntryCardProps) {
  const [editing, setEditing] = useState(false);
  const [title, setTitle] = useState(entry.title);
  const [content, setContent] = useState(entry.content ?? '');

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
          placeholder="Note title"
          autoFocus
        />
        <textarea
          value={content}
          onChange={(e) => setContent(e.target.value)}
          className="w-full rounded-md border border-border bg-surface px-2 py-1.5 text-sm min-h-[80px] resize-none focus:ring-1 focus:ring-blue-500"
          placeholder="Note content..."
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
    <div className="group p-3 bg-surface border border-border rounded-lg hover:border-gray-300 dark:hover:border-gray-600 transition-colors">
      <div className="flex items-start justify-between gap-2">
        <div className="flex-1 min-w-0">
          <h4 className="text-sm font-medium text-gray-900 dark:text-gray-100">{entry.title}</h4>
          {entry.content && (
            <p className="text-sm text-gray-600 dark:text-gray-400 mt-1 whitespace-pre-wrap">
              {entry.content}
            </p>
          )}
        </div>

        {entry.can_edit && (
          <div className="flex items-center gap-1 opacity-0 group-hover:opacity-100 transition-opacity">
            <button
              onClick={() => setEditing(true)}
              className="p-1 rounded text-gray-400 hover:text-blue-500 hover:bg-blue-50 dark:hover:bg-blue-900/30"
              title="Edit note"
            >
              <Edit2 className="h-3.5 w-3.5" />
            </button>
            {onDelete && (
              <button
                onClick={() => onDelete(entry.id)}
                className="p-1 rounded text-gray-400 hover:text-red-500 hover:bg-red-50 dark:hover:bg-red-900/30"
                title="Delete note"
              >
                <Trash2 className="h-3.5 w-3.5" />
              </button>
            )}
          </div>
        )}
      </div>

      {/* Footer — creator + timestamp */}
      <div className="flex items-center gap-2 mt-2 pt-2 border-t border-border">
        <User className="h-3 w-3 text-gray-400" />
        <span className="text-[11px] text-gray-500 dark:text-gray-400">
          {entry.creator_name ?? 'Unknown'}
        </span>
        {entry.created_at && (
          <span className="text-[11px] text-gray-400 dark:text-gray-500 ml-auto">
            {new Date(entry.created_at + 'Z').toLocaleDateString('en-US', {
              month: 'short', day: 'numeric', hour: '2-digit', minute: '2-digit',
            })}
          </span>
        )}
      </div>
    </div>
  );
}
