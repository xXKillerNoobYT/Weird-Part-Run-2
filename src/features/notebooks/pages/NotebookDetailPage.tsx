/**
 * NotebookDetailPage — full view of a notebook with sections and entries.
 *
 * Renders section panels (collapsible), handles all CRUD mutations
 * (create entry, update entry, delete entry, status change, field save,
 * add section), and floating action buttons.
 */

import { useState } from 'react';
import { useParams, useNavigate } from 'react-router-dom';
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import { ArrowLeft, BookOpen, FolderPlus, Archive, CheckCircle2, UserPlus } from 'lucide-react';
import { PageSpinner } from '../../../components/ui/Spinner';
import { EmptyState } from '../../../components/ui/EmptyState';
import {
  getNotebookFull,
  createEntry,
  updateEntry,
  updateTaskStatus,
  updateFieldValue,
  deleteEntry,
  createSection,
  archiveNotebook,
  reorderSections,
  reorderEntries,
  bulkUpdateTasks,
} from '../../../api/notebooks';
import { toast } from '../../../lib/toast';
import { SectionPanel } from '../components/SectionPanel';
import { CreateEntryModal } from '../components/CreateEntryModal';
import { AddSectionModal } from '../components/AddSectionModal';
import { useBulkSelection, BulkActionBar } from '../../orders/components/BulkActionBar';
import type {
  EntryCreate,
  SectionCreate,
  TaskStatus,
  SectionWithEntries,
  EntryResponse,
} from '../../../lib/types';

export function NotebookDetailPage() {
  const { notebookId } = useParams<{ notebookId: string }>();
  const navigate = useNavigate();
  const queryClient = useQueryClient();

  const nbId = Number(notebookId);

  const [showCreateEntry, setShowCreateEntry] = useState<{
    sectionId: number;
    type: 'note' | 'task';
  } | null>(null);
  const [showAddSection, setShowAddSection] = useState(false);
  const [savingFieldId, setSavingFieldId] = useState<number | null>(null);

  // ── Queries ─────────────────────────────────────────────────────
  const { data, isLoading, error } = useQuery({
    queryKey: ['notebook-full', nbId],
    queryFn: () => getNotebookFull(nbId),
    enabled: !!notebookId && !isNaN(nbId),
  });

  // Collect all task entries across sections for bulk selection
  const allTasks: EntryResponse[] = (data?.sections ?? []).flatMap(
    (s: SectionWithEntries) =>
      s.entries.filter((e: EntryResponse) => e.entry_type === 'task' && !('is_deleted' in e && e.is_deleted))
  );
  const bulkSelection = useBulkSelection(allTasks);

  // ── Mutations ───────────────────────────────────────────────────
  const invalidate = () => queryClient.invalidateQueries({ queryKey: ['notebook-full', nbId] });

  const createEntryMut = useMutation({
    mutationFn: ({ sectionId, entry }: { sectionId: number; entry: EntryCreate }) =>
      createEntry(sectionId, entry),
    onSuccess: () => { invalidate(); setShowCreateEntry(null); },
  });

  const updateEntryMut = useMutation({
    mutationFn: ({ entryId, title, content }: { entryId: number; title: string; content: string }) =>
      updateEntry(entryId, { title, content }),
    onSuccess: invalidate,
  });

  const deleteEntryMut = useMutation({
    mutationFn: (entryId: number) => deleteEntry(entryId),
    onSuccess: invalidate,
  });

  const taskStatusMut = useMutation({
    mutationFn: ({ entryId, status, partsNote }: { entryId: number; status: TaskStatus; partsNote?: string }) =>
      updateTaskStatus(entryId, { status, parts_note: partsNote }),
    onSuccess: invalidate,
  });

  const fieldValueMut = useMutation({
    mutationFn: ({ entryId, value }: { entryId: number; value: string }) => {
      setSavingFieldId(entryId);
      return updateFieldValue(entryId, { value });
    },
    onSuccess: () => { invalidate(); setSavingFieldId(null); },
    onError: () => setSavingFieldId(null),
  });

  const addSectionMut = useMutation({
    mutationFn: ({ notebookId: nid, section }: { notebookId: number; section: SectionCreate }) =>
      createSection(nid, section),
    onSuccess: () => { invalidate(); setShowAddSection(false); },
  });

  const archiveMut = useMutation({
    mutationFn: () => archiveNotebook(nbId),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['notebooks'] });
      toast.success('Notebook archived');
      navigate(-1);
    },
    onError: () => toast.error('Failed to archive notebook'),
  });

  const reorderMut = useMutation({
    mutationFn: (orderedIds: number[]) => reorderSections(nbId, orderedIds),
    onSuccess: invalidate,
    onError: () => toast.error('Failed to reorder sections'),
  });

  const reorderEntriesMut = useMutation({
    mutationFn: ({ sectionId, orderedIds }: { sectionId: number; orderedIds: number[] }) =>
      reorderEntries(sectionId, orderedIds),
    onSuccess: invalidate,
    onError: () => toast.error('Failed to reorder entries'),
  });

  const bulkTaskMut = useMutation({
    mutationFn: ({ entryIds, taskStatus, taskAssignedTo }: {
      entryIds: number[];
      taskStatus?: string;
      taskAssignedTo?: number;
    }) => bulkUpdateTasks(entryIds, taskStatus, taskAssignedTo),
    onSuccess: (result) => {
      invalidate();
      bulkSelection.clear();
      toast.success(`Updated ${result.updated} tasks`);
    },
    onError: () => toast.error('Bulk update failed'),
  });

  // ── Handlers ────────────────────────────────────────────────────
  const handleAddEntry = (sectionId: number, type: 'note' | 'task') => {
    setShowCreateEntry({ sectionId, type });
  };

  const handleEntryUpdate = (entryId: number, title: string, content: string) => {
    updateEntryMut.mutate({ entryId, title, content });
  };

  const handleEntryDelete = (entryId: number) => {
    if (window.confirm('Delete this entry?')) {
      deleteEntryMut.mutate(entryId);
    }
  };

  const handleTaskStatusChange = (entryId: number, status: TaskStatus, partsNote?: string) => {
    taskStatusMut.mutate({ entryId, status, partsNote });
  };

  const handleFieldSave = (entryId: number, value: string) => {
    fieldValueMut.mutate({ entryId, value });
  };

  const handleArchive = () => {
    if (window.confirm('Archive this notebook? It will be hidden from the list but can be restored later.')) {
      archiveMut.mutate();
    }
  };

  const handleSectionMove = (sectionId: number, direction: 'up' | 'down') => {
    const ids = sections.map((s: SectionWithEntries) => s.id);
    const idx = ids.indexOf(sectionId);
    if (idx < 0) return;
    const targetIdx = direction === 'up' ? idx - 1 : idx + 1;
    if (targetIdx < 0 || targetIdx >= ids.length) return;
    [ids[idx], ids[targetIdx]] = [ids[targetIdx], ids[idx]];
    reorderMut.mutate(ids);
  };

  const handleEntryReorder = (sectionId: number, orderedIds: number[]) => {
    reorderEntriesMut.mutate({ sectionId, orderedIds });
  };

  // ── Render ──────────────────────────────────────────────────────
  if (isLoading) return <PageSpinner />;

  if (error || !data) {
    return (
      <EmptyState
        icon={<BookOpen className="h-10 w-10 text-gray-300 dark:text-gray-600" />}
        title="Notebook not found"
        description="This notebook may have been archived or deleted."
      />
    );
  }

  const { notebook, sections } = data;

  return (
    <div className="space-y-4">
      {/* Header */}
      <div className="flex items-center gap-3">
        <button
          onClick={() => navigate(-1)}
          className="p-2 rounded-lg hover:bg-surface-secondary transition-colors min-h-[44px] min-w-[44px] flex items-center justify-center"
        >
          <ArrowLeft className="h-5 w-5 text-gray-500 dark:text-gray-400" />
        </button>
        <div className="flex-1 min-w-0">
          <h1 className="text-lg font-bold text-gray-900 dark:text-gray-100 truncate">
            {notebook.title}
          </h1>
          {notebook.description && (
            <p className="text-sm text-gray-500 dark:text-gray-400 truncate">
              {notebook.description}
            </p>
          )}
        </div>
        <div className="flex items-center gap-1.5">
          <button
            onClick={() => setShowAddSection(true)}
            className="flex items-center gap-1.5 px-3 py-2 text-xs font-medium text-blue-500 hover:text-blue-600 hover:bg-blue-50 dark:hover:bg-blue-900/20 rounded-lg transition-colors min-h-[44px]"
          >
            <FolderPlus className="h-4 w-4" />
            <span className="hidden sm:inline">Add Section</span>
          </button>
          <button
            onClick={handleArchive}
            disabled={archiveMut.isPending}
            className="flex items-center gap-1.5 px-3 py-2 text-xs font-medium text-red-500 hover:text-red-600 hover:bg-red-50 dark:hover:bg-red-900/20 rounded-lg transition-colors min-h-[44px]"
            title="Archive notebook"
          >
            <Archive className="h-4 w-4" />
            <span className="hidden sm:inline">Archive</span>
          </button>
        </div>
      </div>

      {/* Sections */}
      {sections.length === 0 ? (
        <EmptyState
          icon={<BookOpen className="h-8 w-8 text-gray-300 dark:text-gray-600" />}
          title="No sections"
          description="Add a section to start organizing entries"
        />
      ) : (
        <div className="space-y-3">
          {sections.map((section: SectionWithEntries, idx: number) => (
            <SectionPanel
              key={section.id}
              section={section}
              onFieldSave={handleFieldSave}
              onEntryUpdate={handleEntryUpdate}
              onEntryDelete={handleEntryDelete}
              onTaskStatusChange={handleTaskStatusChange}
              onAddEntry={handleAddEntry}
              savingFieldId={savingFieldId}
              onMoveUp={idx > 0 ? () => handleSectionMove(section.id, 'up') : undefined}
              onMoveDown={idx < sections.length - 1 ? () => handleSectionMove(section.id, 'down') : undefined}
              onEntryReorder={handleEntryReorder}
              isTaskSelected={bulkSelection.isSelected}
              onToggleTask={bulkSelection.toggle}
            />
          ))}
        </div>
      )}

      {/* Create entry modal */}
      {showCreateEntry && (
        <CreateEntryModal
          defaultType={showCreateEntry.type}
          sectionId={showCreateEntry.sectionId}
          onSubmit={(sectionId, entry) =>
            createEntryMut.mutate({ sectionId, entry })
          }
          onClose={() => setShowCreateEntry(null)}
          loading={createEntryMut.isPending}
        />
      )}

      {/* Add section modal */}
      {showAddSection && (
        <AddSectionModal
          notebookId={nbId}
          onSubmit={(nid, section) =>
            addSectionMut.mutate({ notebookId: nid, section })
          }
          onClose={() => setShowAddSection(false)}
          loading={addSectionMut.isPending}
        />
      )}

      {/* Bulk task action bar */}
      <BulkActionBar
        count={bulkSelection.selectedIds.size}
        onClear={bulkSelection.clear}
        loading={bulkTaskMut.isPending}
        actions={[
          {
            label: 'Mark Complete',
            icon: CheckCircle2,
            variant: 'primary',
            onClick: () =>
              bulkTaskMut.mutate({
                entryIds: [...bulkSelection.selectedIds],
                taskStatus: 'done',
              }),
          },
          {
            label: 'Mark In Progress',
            icon: UserPlus,
            variant: 'default',
            onClick: () =>
              bulkTaskMut.mutate({
                entryIds: [...bulkSelection.selectedIds],
                taskStatus: 'in_progress',
              }),
          },
        ]}
      />
    </div>
  );
}
