/**
 * InfoFieldRenderer — renders 'field' type entries as form inputs.
 *
 * Handles text, checkbox, and textarea field types.
 * Empty fields are editable by anyone. Once filled, only managers can change them.
 * Shows a lock icon and "filled by" indicator on locked fields.
 */

import { useState } from 'react';
import { Lock, Check } from 'lucide-react';
import type { EntryResponse } from '../../../lib/types';

interface InfoFieldRendererProps {
  entry: EntryResponse;
  onSave: (entryId: number, value: string) => void;
  saving?: boolean;
}

export function InfoFieldRenderer({ entry, onSave, saving }: InfoFieldRendererProps) {
  const [editing, setEditing] = useState(false);
  const [value, setValue] = useState(entry.content ?? '');

  const isLocked = !entry.can_edit && !!entry.content;
  const isEmpty = !entry.content;

  const handleSave = () => {
    if (value !== (entry.content ?? '')) {
      onSave(entry.id, value);
    }
    setEditing(false);
  };

  // Checkbox field
  if (entry.field_type === 'checkbox') {
    const checked = entry.content === 'true' || entry.content === '1';
    return (
      <div className="flex items-center justify-between py-1.5">
        <span className="text-sm text-gray-700 dark:text-gray-300">{entry.title}</span>
        <div className="flex items-center gap-2">
          {isLocked && <Lock className="h-3 w-3 text-gray-400" />}
          <button
            onClick={() => {
              if (!isLocked) {
                onSave(entry.id, checked ? 'false' : 'true');
              }
            }}
            disabled={isLocked || saving}
            className={`w-5 h-5 rounded border-2 flex items-center justify-center transition-colors ${
              checked
                ? 'bg-blue-500 border-blue-500 text-white'
                : 'border-gray-300 dark:border-gray-600 hover:border-blue-400'
            } ${isLocked ? 'cursor-not-allowed opacity-60' : 'cursor-pointer'}`}
          >
            {checked && <Check className="h-3.5 w-3.5" />}
          </button>
        </div>
      </div>
    );
  }

  // Textarea field
  if (entry.field_type === 'textarea') {
    if (isLocked && !editing) {
      return (
        <div className="py-1.5">
          <div className="flex items-center gap-1.5 mb-1">
            <span className="text-sm font-medium text-gray-700 dark:text-gray-300">{entry.title}</span>
            <Lock className="h-3 w-3 text-gray-400" />
          </div>
          <p className="text-sm text-gray-900 dark:text-gray-100 whitespace-pre-wrap bg-surface-secondary rounded px-2 py-1.5">
            {entry.content}
          </p>
        </div>
      );
    }

    if (editing || isEmpty) {
      return (
        <div className="py-1.5">
          <label className="text-sm font-medium text-gray-700 dark:text-gray-300 mb-1 block">
            {entry.title}
            {entry.field_required && <span className="text-red-500 ml-0.5">*</span>}
          </label>
          <textarea
            value={value}
            onChange={(e) => setValue(e.target.value)}
            onBlur={handleSave}
            placeholder={`Enter ${entry.title.toLowerCase()}...`}
            className="w-full rounded-md border border-border bg-surface px-3 py-2 text-sm min-h-[60px] resize-none focus:ring-1 focus:ring-blue-500 focus:border-blue-500"
            autoFocus={editing}
          />
        </div>
      );
    }

    return (
      <div className="py-1.5 cursor-pointer" onClick={() => entry.can_edit && setEditing(true)}>
        <span className="text-sm font-medium text-gray-700 dark:text-gray-300">{entry.title}</span>
        <p className="text-sm text-gray-900 dark:text-gray-100 mt-0.5">{entry.content}</p>
      </div>
    );
  }

  // Text field (default)
  if (isLocked && !editing) {
    return (
      <div className="flex items-center justify-between py-1.5">
        <span className="text-sm text-gray-700 dark:text-gray-300">{entry.title}</span>
        <div className="flex items-center gap-1.5">
          <Lock className="h-3 w-3 text-gray-400" />
          <span className="text-sm font-medium text-gray-900 dark:text-gray-100">{entry.content}</span>
        </div>
      </div>
    );
  }

  if (editing || isEmpty) {
    return (
      <div className="flex items-center justify-between gap-3 py-1.5">
        <label className="text-sm text-gray-700 dark:text-gray-300 whitespace-nowrap">
          {entry.title}
          {entry.field_required && <span className="text-red-500 ml-0.5">*</span>}
        </label>
        <input
          type="text"
          value={value}
          onChange={(e) => setValue(e.target.value)}
          onBlur={handleSave}
          onKeyDown={(e) => e.key === 'Enter' && handleSave()}
          placeholder={`Enter ${entry.title.toLowerCase()}`}
          className="flex-1 max-w-[250px] rounded-md border border-border bg-surface px-2 py-1 text-sm text-right focus:ring-1 focus:ring-blue-500 focus:border-blue-500"
          autoFocus={editing}
        />
      </div>
    );
  }

  return (
    <div
      className="flex items-center justify-between py-1.5 cursor-pointer hover:bg-surface-secondary/50 rounded -mx-1 px-1 transition-colors"
      onClick={() => entry.can_edit && setEditing(true)}
    >
      <span className="text-sm text-gray-700 dark:text-gray-300">{entry.title}</span>
      <span className="text-sm font-medium text-gray-900 dark:text-gray-100">{entry.content}</span>
    </div>
  );
}
