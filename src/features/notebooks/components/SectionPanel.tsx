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
import { ChevronDown, ChevronRight, Lock, Plus, FileText, ListTodo, Info, ArrowUp, ArrowDown } from 'lucide-react';
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
  onMoveUp?: () => void;
  onMoveDown?: () => void;
  /** Entry reorder — receives the full new ordered ID array */
  onEntryReorder?: (sectionId: number, orderedIds: number[]) => void;
  /** Bulk task selection — passed through to TaskEntryCard */
  isTaskSelected?: (entryId: number) => boolean;
  onToggleTask?: (entryId: number) => void;
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
  onMoveUp,
  onMoveDown,
  onEntryReorder,
  isTaskSelected,
  onToggleTask,
}: SectionPanelProps) {
  const [expanded, setExpanded] = useState(true);

  const Icon = SECTION_TYPE_ICONS[section.section_type] ?? FileText;
  const activeEntries = section.entries.filter((e: EntryResponse) => !('is_deleted' in e && e.is_deleted));

  // Count open tasks for the section header badge
  const openTaskCount = activeEntries.filter(
    (e: EntryResponse) => e.entry_type === 'task' && e.task_status !== 'done'
  ).length;

  // ── Entry reorder helper ─────────────────────────────────────
  const handleEntryMove = (entryId: number, direction: 'up' | 'down') => {
    if (!onEntryReorder) return;
    const ids = activeEntries.map((e: EntryResponse) => e.id);
    const idx = ids.indexOf(entryId);
    if (idx < 0) return;
    const targetIdx = direction === 'up' ? idx - 1 : idx + 1;
    if (targetIdx < 0 || targetIdx >= ids.length) return;
    [ids[idx], ids[targetIdx]] = [ids[targetIdx], ids[idx]];
    onEntryReorder(section.id, ids);
  };

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

        {/* Reorder buttons */}
        {(onMoveUp || onMoveDown) && (
          <span className="flex gap-0.5" onClick={(e) => e.stopPropagation()}>
            <button
              onClick={(e) => { e.stopPropagation(); onMoveUp?.(); }}
              disabled={!onMoveUp}
              className="p-0.5 rounded hover:bg-gray-200 dark:hover:bg-gray-700 disabled:opacity-30 disabled:cursor-not-allowed transition-colors"
              title="Move section up"
            >
              <ArrowUp className="h-3.5 w-3.5 text-gray-400 dark:text-gray-500" />
            </button>
            <button
              onClick={(e) => { e.stopPropagation(); onMoveDown?.(); }}
              disabled={!onMoveDown}
              className="p-0.5 rounded hover:bg-gray-200 dark:hover:bg-gray-700 disabled:opacity-30 disabled:cursor-not-allowed transition-colors"
              title="Move section down"
            >
              <ArrowDown className="h-3.5 w-3.5 text-gray-400 dark:text-gray-500" />
            </button>
          </span>
        )}
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
                  onSave={onFieldSave ?? (() => { })}
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
              {activeEntries.map((entry: EntryResponse, idx: number) => (
                <div key={entry.id} className="flex gap-1.5 items-start">
                  {/* Entry reorder buttons */}
                  {onEntryReorder && activeEntries.length > 1 && (
                    <div className="flex flex-col gap-0.5 pt-2.5 shrink-0">
                      <button
                        onClick={() => handleEntryMove(entry.id, 'up')}
                        disabled={idx === 0}
                        className="p-0.5 rounded hover:bg-gray-200 dark:hover:bg-gray-700 disabled:opacity-20 disabled:cursor-not-allowed transition-colors"
                        title="Move up"
                      >
                        <ArrowUp className="h-3 w-3 text-gray-400" />
                      </button>
                      <button
                        onClick={() => handleEntryMove(entry.id, 'down')}
                        disabled={idx === activeEntries.length - 1}
                        className="p-0.5 rounded hover:bg-gray-200 dark:hover:bg-gray-700 disabled:opacity-20 disabled:cursor-not-allowed transition-colors"
                        title="Move down"
                      >
                        <ArrowDown className="h-3 w-3 text-gray-400" />
                      </button>
                    </div>
                  )}
                  <div className="flex-1 min-w-0">
                    <NoteEntryCard
                      entry={entry}
                      onUpdate={onEntryUpdate}
                      onDelete={onEntryDelete}
                    />
                  </div>
                </div>
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
              {activeEntries.map((entry: EntryResponse, idx: number) => (
                <div key={entry.id} className="flex gap-1.5 items-start">
                  {/* Entry reorder buttons */}
                  {onEntryReorder && activeEntries.length > 1 && (
                    <div className="flex flex-col gap-0.5 pt-2.5 shrink-0">
                      <button
                        onClick={() => handleEntryMove(entry.id, 'up')}
                        disabled={idx === 0}
                        className="p-0.5 rounded hover:bg-gray-200 dark:hover:bg-gray-700 disabled:opacity-20 disabled:cursor-not-allowed transition-colors"
                        title="Move up"
                      >
                        <ArrowUp className="h-3 w-3 text-gray-400" />
                      </button>
                      <button
                        onClick={() => handleEntryMove(entry.id, 'down')}
                        disabled={idx === activeEntries.length - 1}
                        className="p-0.5 rounded hover:bg-gray-200 dark:hover:bg-gray-700 disabled:opacity-20 disabled:cursor-not-allowed transition-colors"
                        title="Move down"
                      >
                        <ArrowDown className="h-3 w-3 text-gray-400" />
                      </button>
                    </div>
                  )}
                  <div className="flex-1 min-w-0">
                    <TaskEntryCard
                      entry={entry}
                      onStatusChange={onTaskStatusChange}
                      onUpdate={onEntryUpdate}
                      onDelete={onEntryDelete}
                      isSelected={isTaskSelected?.(entry.id)}
                      onToggle={onToggleTask ? () => onToggleTask(entry.id) : undefined}
                    />
                  </div>
                </div>
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
