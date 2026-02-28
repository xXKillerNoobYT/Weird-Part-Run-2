/**
 * SectionPanel — collapsible section that renders entries by section_type.
 *
 * - 'info'  → InfoFieldRenderer for each field entry
 * - 'notes' → NoteEntryCard list + "Add Note" button
 * - 'tasks' → TaskEntryCard list + "Add Task" button
 *
 * Sections can be collapsed/expanded. Locked sections show a lock icon.
 */

import { useState } from 'react';
import { ChevronDown, ChevronRight, Lock, Plus, FileText, ListTodo, Info } from 'lucide-react';
import { InfoFieldRenderer } from './InfoFieldRenderer';
import { NoteEntryCard } from './NoteEntryCard';
import { TaskEntryCard } from './TaskEntryCard';
import type { SectionWithEntries, EntryResponse, TaskStatus } from '../../../lib/types';

interface SectionPanelProps {
  section: SectionWithEntries;
  onFieldSave?: (entryId: number, value: string) => void;
  onEntryUpdate?: (entryId: number, title: string, content: string) => void;
  onEntryDelete?: (entryId: number) => void;
  onTaskStatusChange?: (entryId: number, status: TaskStatus, partsNote?: string) => void;
  onAddEntry?: (sectionId: number, type: 'note' | 'task') => void;
  /** Whether a field save is in progress (for InfoFieldRenderer spinner) */
  savingFieldId?: number | null;
}

const SECTION_TYPE_ICONS = {
  info: Info,
  notes: FileText,
  tasks: ListTodo,
} as const;

export function SectionPanel({
  section,
  onFieldSave,
  onEntryUpdate,
  onEntryDelete,
  onTaskStatusChange,
  onAddEntry,
  savingFieldId,
}: SectionPanelProps) {
  const [expanded, setExpanded] = useState(true);

  const Icon = SECTION_TYPE_ICONS[section.section_type] ?? FileText;
  const activeEntries = section.entries.filter((e: EntryResponse) => !('is_deleted' in e && e.is_deleted));

  // Count open tasks for the section header badge
  const openTaskCount = activeEntries.filter(
    (e: EntryResponse) => e.entry_type === 'task' && e.task_status !== 'done'
  ).length;

  return (
    <div className="border border-border rounded-lg overflow-hidden">
      {/* Section header */}
      <button
        onClick={() => setExpanded(!expanded)}
        className="w-full flex items-center gap-2 px-4 py-2.5 bg-surface-secondary hover:bg-gray-100 dark:hover:bg-gray-800 transition-colors text-left"
      >
        {expanded ? (
          <ChevronDown className="h-4 w-4 text-gray-400 shrink-0" />
        ) : (
          <ChevronRight className="h-4 w-4 text-gray-400 shrink-0" />
        )}
        <Icon className="h-4 w-4 text-gray-500 dark:text-gray-400 shrink-0" />
        <span className="text-sm font-semibold text-gray-800 dark:text-gray-200 flex-1">
          {section.name}
        </span>

        {/* Open task count badge */}
        {section.section_type === 'tasks' && openTaskCount > 0 && (
          <span className="px-1.5 py-0.5 text-[10px] font-medium bg-amber-100 dark:bg-amber-900/30 text-amber-700 dark:text-amber-300 rounded-full">
            {openTaskCount}
          </span>
        )}

        {/* Locked indicator */}
        {section.is_locked && (
          <Lock className="h-3 w-3 text-gray-400 dark:text-gray-500" />
        )}

        {/* Entry count */}
        <span className="text-[11px] text-gray-400 dark:text-gray-500">
          {activeEntries.length}
        </span>
      </button>

      {/* Section body */}
      {expanded && (
        <div className="px-4 py-3 space-y-2">
          {/* Render entries based on section_type */}
          {section.section_type === 'info' && (
            <div className="space-y-1.5">
              {activeEntries.map((entry: EntryResponse) => (
                <InfoFieldRenderer
                  key={entry.id}
                  entry={entry}
                  onSave={onFieldSave ? (id, val) => onFieldSave(id, val) : undefined}
                  saving={savingFieldId === entry.id}
                />
              ))}
              {activeEntries.length === 0 && (
                <p className="text-xs text-gray-400 dark:text-gray-500 italic py-2">
                  No fields configured
                </p>
              )}
            </div>
          )}

          {section.section_type === 'notes' && (
            <div className="space-y-2">
              {activeEntries.map((entry: EntryResponse) => (
                <NoteEntryCard
                  key={entry.id}
                  entry={entry}
                  onUpdate={onEntryUpdate}
                  onDelete={onEntryDelete}
                />
              ))}
              {activeEntries.length === 0 && (
                <p className="text-xs text-gray-400 dark:text-gray-500 italic py-2">
                  No notes yet
                </p>
              )}
              {onAddEntry && (
                <button
                  onClick={() => onAddEntry(section.id, 'note')}
                  className="flex items-center gap-1.5 px-3 py-1.5 text-xs font-medium text-blue-500 hover:text-blue-600 hover:bg-blue-50 dark:hover:bg-blue-900/20 rounded-md transition-colors"
                >
                  <Plus className="h-3.5 w-3.5" />
                  Add Note
                </button>
              )}
            </div>
          )}

          {section.section_type === 'tasks' && (
            <div className="space-y-2">
              {activeEntries.map((entry: EntryResponse) => (
                <TaskEntryCard
                  key={entry.id}
                  entry={entry}
                  onStatusChange={onTaskStatusChange}
                  onUpdate={onEntryUpdate}
                  onDelete={onEntryDelete}
                />
              ))}
              {activeEntries.length === 0 && (
                <p className="text-xs text-gray-400 dark:text-gray-500 italic py-2">
                  No tasks yet
                </p>
              )}
              {onAddEntry && (
                <button
                  onClick={() => onAddEntry(section.id, 'task')}
                  className="flex items-center gap-1.5 px-3 py-1.5 text-xs font-medium text-blue-500 hover:text-blue-600 hover:bg-blue-50 dark:hover:bg-blue-900/20 rounded-md transition-colors"
                >
                  <Plus className="h-3.5 w-3.5" />
                  Add Task
                </button>
              )}
            </div>
          )}
        </div>
      )}
    </div>
  );
}
