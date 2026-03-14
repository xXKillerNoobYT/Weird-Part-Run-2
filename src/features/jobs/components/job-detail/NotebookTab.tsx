/**
 * NotebookTab — Job notebook with sections, entries, tasks, and fields.
 * Extracted from JobDetailPage.
 */

import { useState } from 'react';
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query';
import { BookOpen, AlertTriangle, RotateCcw } from 'lucide-react';
import { PageSpinner } from '../../../../components/ui/Spinner';
import { EmptyState } from '../../../../components/ui/EmptyState';
import type { EntryCreate, SectionCreate, TaskStatus, SectionWithEntries } from '../../../../lib/types';
import {
  getJobNotebook, createEntry, updateEntry, updateTaskStatus,
  updateFieldValue, deleteEntry, createSection,
} from '../../../../api/notebooks';
import { SectionPanel } from '../../../notebooks/components/SectionPanel';
import { CreateEntryModal } from '../../../notebooks/components/CreateEntryModal';
import { AddSectionModal } from '../../../notebooks/components/AddSectionModal';

export function NotebookTab({ jobId }: { jobId: number }) {
  const queryClient = useQueryClient();

  const [showCreateEntry, setShowCreateEntry] = useState<{
    sectionId: number;
    type: 'note' | 'task';
  } | null>(null);
  const [showAddSection, setShowAddSection] = useState(false);
  const [savingFieldId, setSavingFieldId] = useState<number | null>(null);

  const { data, isLoading, error, refetch, isFetching } = useQuery({
    queryKey: ['job-notebook', jobId],
    queryFn: () => getJobNotebook(jobId),
    staleTime: 15_000,
    retry: 1, // one automatic retry before showing error
  });

  const invalidate = () => queryClient.invalidateQueries({ queryKey: ['job-notebook', jobId] });

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
    mutationFn: ({ notebookId, section }: { notebookId: number; section: SectionCreate }) =>
      createSection(notebookId, section),
    onSuccess: () => { invalidate(); setShowAddSection(false); },
  });

  if (isLoading) return <PageSpinner label="Loading notebook..." />;

  // ── Error / empty state with actionable recovery ──
  if (error || !data) {
    const errMsg = error instanceof Error ? error.message : '';
    const isNetworkError = errMsg.includes('Network') || errMsg.includes('ECONNREFUSED') || errMsg.includes('fetch');

    return (
      <div className="rounded-lg border border-border bg-surface p-6 text-center space-y-4">
        <div className="flex justify-center">
          <div className="h-12 w-12 rounded-full bg-amber-100 dark:bg-amber-900/30 flex items-center justify-center">
            <AlertTriangle className="h-6 w-6 text-amber-500" />
          </div>
        </div>
        <div>
          <h3 className="text-sm font-semibold text-gray-900 dark:text-gray-100">
            Notebook Unavailable
          </h3>
          <p className="text-xs text-gray-500 dark:text-gray-400 mt-1 max-w-sm mx-auto">
            {isNetworkError
              ? 'Could not reach the server. Check your connection and try again.'
              : 'Could not load or create the notebook for this job. This usually resolves by retrying.'}
          </p>
          {errMsg && !isNetworkError && (
            <p className="text-xs text-red-400 mt-2 font-mono max-w-sm mx-auto truncate">
              {errMsg}
            </p>
          )}
        </div>
        <button
          onClick={() => refetch()}
          disabled={isFetching}
          className="inline-flex items-center gap-2 rounded-lg bg-primary px-4 py-2 text-sm font-medium text-white shadow-sm hover:bg-primary/90 transition-colors disabled:opacity-50"
        >
          <RotateCcw className={`h-4 w-4 ${isFetching ? 'animate-spin' : ''}`} />
          {isFetching ? 'Retrying...' : 'Try Again'}
        </button>
      </div>
    );
  }

  const { notebook, sections } = data;

  return (
    <div className="space-y-3">
      {/* Section panels */}
      {sections.map((section: SectionWithEntries) => (
        <SectionPanel
          key={section.id}
          section={section}
          onFieldSave={(id, val) => fieldValueMut.mutate({ entryId: id, value: val })}
          onEntryUpdate={(id, title, content) => updateEntryMut.mutate({ entryId: id, title, content })}
          onEntryDelete={(id) => {
            if (window.confirm('Delete this entry?')) deleteEntryMut.mutate(id);
          }}
          onTaskStatusChange={(id, status, partsNote) =>
            taskStatusMut.mutate({ entryId: id, status, partsNote })
          }
          onAddEntry={(sectionId, type) => setShowCreateEntry({ sectionId, type })}
          savingFieldId={savingFieldId}
        />
      ))}

      {/* Empty notebook state (notebook exists but no sections) */}
      {sections.length === 0 && (
        <EmptyState
          icon={<BookOpen className="h-10 w-10 text-gray-300 dark:text-gray-600" />}
          title="Empty Notebook"
          description="This notebook has no sections yet. Add a section to start organizing your job info, notes, and tasks."
        />
      )}

      {/* Add section button */}
      <button
        onClick={() => setShowAddSection(true)}
        className="flex items-center gap-1.5 px-3 py-2 text-xs font-medium text-gray-500 hover:text-blue-500 border border-dashed border-border hover:border-blue-300 rounded-lg transition-colors w-full justify-center"
      >
        <BookOpen className="h-4 w-4" />
        Add Section
      </button>

      {/* Modals */}
      {showCreateEntry && (
        <CreateEntryModal
          defaultType={showCreateEntry.type}
          sectionId={showCreateEntry.sectionId}
          onSubmit={(sectionId, entry) => createEntryMut.mutate({ sectionId, entry })}
          onClose={() => setShowCreateEntry(null)}
          loading={createEntryMut.isPending}
        />
      )}

      {showAddSection && (
        <AddSectionModal
          notebookId={notebook.id}
          onSubmit={(nid, section) => addSectionMut.mutate({ notebookId: nid, section })}
          onClose={() => setShowAddSection(false)}
          loading={addSectionMut.isPending}
        />
      )}
    </div>
  );
}
