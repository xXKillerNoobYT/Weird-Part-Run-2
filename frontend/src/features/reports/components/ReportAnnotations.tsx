/**
 * ReportAnnotations — collapsible annotations panel for any report.
 *
 * Shows existing notes on a report and lets the user add, edit, or delete them.
 * Renders below report content, styled like NoteEntryCard.
 */

import { useState } from 'react';
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import {
  getAnnotations,
  createAnnotation,
  updateAnnotation,
  deleteAnnotation,
  type ReportAnnotation,
} from '../../../api/reports';


interface Props {
  reportType: string;
  contextKey: string;
}

export default function ReportAnnotations({ reportType, contextKey }: Props) {
  const qc = useQueryClient();
  const queryKey = ['report-annotations', reportType, contextKey];

  const { data: annotations = [], isLoading } = useQuery({
    queryKey,
    queryFn: () => getAnnotations(reportType, contextKey),
    enabled: !!contextKey,
  });

  const [isOpen, setIsOpen] = useState(false);
  const [newContent, setNewContent] = useState('');
  const [editingId, setEditingId] = useState<number | null>(null);
  const [editContent, setEditContent] = useState('');

  const createMut = useMutation({
    mutationFn: () => createAnnotation({ report_type: reportType, context_key: contextKey, content: newContent }),
    onSuccess: () => { qc.invalidateQueries({ queryKey }); setNewContent(''); },
  });

  const updateMut = useMutation({
    mutationFn: (a: { id: number; content: string }) => updateAnnotation(a.id, a.content),
    onSuccess: () => { qc.invalidateQueries({ queryKey }); setEditingId(null); },
  });

  const deleteMut = useMutation({
    mutationFn: (id: number) => deleteAnnotation(id),
    onSuccess: () => qc.invalidateQueries({ queryKey }),
  });

  const startEdit = (a: ReportAnnotation) => {
    setEditingId(a.id);
    setEditContent(a.content);
  };

  return (
    <div className="mt-6 border border-gray-200 dark:border-gray-700 rounded-lg no-print">
      {/* Header Toggle */}
      <button
        onClick={() => setIsOpen(!isOpen)}
        className="w-full flex items-center justify-between px-4 py-3 text-left text-sm font-medium
                   text-gray-700 dark:text-gray-300 hover:bg-gray-50 dark:hover:bg-gray-800 rounded-lg"
      >
        <span className="flex items-center gap-2">
          📝 Notes & Annotations
          {annotations.length > 0 && (
            <span className="bg-blue-100 text-blue-700 dark:bg-blue-900 dark:text-blue-300 text-xs px-2 py-0.5 rounded-full">
              {annotations.length}
            </span>
          )}
        </span>
        <span className="text-gray-400">{isOpen ? '▲' : '▼'}</span>
      </button>

      {isOpen && (
        <div className="px-4 pb-4 space-y-3">
          {/* Existing annotations */}
          {isLoading ? (
            <p className="text-sm text-gray-500">Loading…</p>
          ) : annotations.length === 0 ? (
            <p className="text-sm text-gray-400 italic">No notes yet. Add one below.</p>
          ) : (
            <div className="space-y-2">
              {annotations.map((a) => (
                <div key={a.id} className="bg-gray-50 dark:bg-gray-800 rounded-lg p-3">
                  {editingId === a.id ? (
                    <div className="space-y-2">
                      <textarea
                        value={editContent}
                        onChange={(e) => setEditContent(e.target.value)}
                        className="w-full rounded border border-gray-300 dark:border-gray-600 bg-white
                                   dark:bg-gray-700 text-sm p-2 min-h-16"
                        rows={3}
                      />
                      <div className="flex gap-2">
                        <button
                          onClick={() => updateMut.mutate({ id: a.id, content: editContent })}
                          disabled={updateMut.isPending || !editContent.trim()}
                          className="px-3 py-1 text-xs bg-blue-600 text-white rounded hover:bg-blue-700
                                     disabled:opacity-50"
                        >
                          Save
                        </button>
                        <button
                          onClick={() => setEditingId(null)}
                          className="px-3 py-1 text-xs bg-gray-200 dark:bg-gray-600 rounded hover:bg-gray-300"
                        >
                          Cancel
                        </button>
                      </div>
                    </div>
                  ) : (
                    <>
                      <p className="text-sm text-gray-800 dark:text-gray-200 whitespace-pre-wrap">
                        {a.content}
                      </p>
                      <div className="mt-1 flex items-center justify-between text-xs text-gray-500">
                        <span>
                          {a.author_name} · {new Date(a.created_at).toLocaleDateString()}
                          {a.updated_at !== a.created_at && ' (edited)'}
                        </span>
                        <div className="flex gap-2">
                          <button
                            onClick={() => startEdit(a)}
                            className="hover:text-blue-600 dark:hover:text-blue-400"
                          >
                            Edit
                          </button>
                          <button
                            onClick={() => {
                              if (confirm('Delete this note?')) deleteMut.mutate(a.id);
                            }}
                            className="hover:text-red-600 dark:hover:text-red-400"
                          >
                            Delete
                          </button>
                        </div>
                      </div>
                    </>
                  )}
                </div>
              ))}
            </div>
          )}

          {/* Add new annotation */}
          <div className="pt-2 border-t border-gray-200 dark:border-gray-700">
            <textarea
              value={newContent}
              onChange={(e) => setNewContent(e.target.value)}
              placeholder="Add a note…"
              className="w-full rounded border border-gray-300 dark:border-gray-600 bg-white
                         dark:bg-gray-700 text-sm p-2 min-h-16"
              rows={2}
            />
            <button
              onClick={() => createMut.mutate()}
              disabled={createMut.isPending || !newContent.trim()}
              className="mt-2 px-4 py-1.5 text-xs bg-blue-600 text-white rounded hover:bg-blue-700
                         disabled:opacity-50"
            >
              {createMut.isPending ? 'Adding…' : 'Add Note'}
            </button>
          </div>
        </div>
      )}
    </div>
  );
}
