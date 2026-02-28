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
import { ArrowLeft, Plus, BookOpen, FolderPlus } from 'lucide-react';
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
} from '../../../api/notebooks';
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
      updateTaskStatus(entryId, { task_status: status, task_parts_note: partsNote }),
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
        <button
          onClick={() => setShowAddSection(true)}
          className="flex items-center gap-1.5 px-3 py-1.5 text-xs font-medium text-blue-500 hover:text-blue-600 hover:bg-blue-50 dark:hover:bg-blue-900/20 rounded-lg transition-colors"
        >
          <FolderPlus className="h-4 w-4" />
          Add Section
        </button>
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
          {sections.map((section: SectionWithEntries) => (
            <SectionPanel
              key={section.id}
              section={section}
              onFieldSave={handleFieldSave}
              onEntryUpdate={handleEntryUpdate}
              onEntryDelete={handleEntryDelete}
              onTaskStatusChange={handleTaskStatusChange}
              onAddEntry={handleAddEntry}
              savingFieldId={savingFieldId}
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
