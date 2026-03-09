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
import { ArrowLeft, BookOpen, FolderPlus, Archive } from 'lucide-react';
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
} from '../../../api/notebooks';
import { toast } from '../../../lib/toast';
import { SectionPanel } from '../components/SectionPanel';
import { CreateEntryModal } from '../components/CreateEntryModal';
import { AddSectionModal } from '../components/AddSectionModal';
import type {
  EntryCreate,
  SectionCreate,
  TaskStatus,
  SectionWithEntries,
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
    enabled: !!nbId,
  });

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
          className="p-1.5 rounded-lg hover:bg-surface-secondary transition-colors"
        >
          <ArrowLeft className="h-4 w-4 text-gray-500 dark:text-gray-400" />
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
            className="flex items-center gap-1.5 px-3 py-1.5 text-xs font-medium text-blue-500 hover:text-blue-600 hover:bg-blue-50 dark:hover:bg-blue-900/20 rounded-lg transition-colors"
          >
            <FolderPlus className="h-4 w-4" />
            <span className="hidden sm:inline">Add Section</span>
          </button>
          <button
            onClick={handleArchive}
            disabled={archiveMut.isPending}
            className="flex items-center gap-1.5 px-3 py-1.5 text-xs font-medium text-red-500 hover:text-red-600 hover:bg-red-50 dark:hover:bg-red-900/20 rounded-lg transition-colors"
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
    </div>
  );
}
