/**
 * JobNotebookTemplatePage — Office module page for managing notebook templates.
 *
 * Layout: Template list (left) + Template editor (right).
 * Managers can add/edit/delete templates, sections, and entries.
 * Requires manage_notebooks permission.
 *
 * Features:
 * - Create / rename / delete templates
 * - Add / rename / reorder / delete sections (info, notes, tasks)
 * - Add / delete entries within sections
 * - Set a template as default (used when creating new job notebooks)
 * - Inline editing for template name + description
 */

import { useState, useEffect } from 'react';
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import {
  Plus, Trash2, Star, ChevronDown, ChevronRight,
  GripVertical, FileText, ListTodo, Info, BookOpen,
  Pencil, Check, X,
} from 'lucide-react';
import { PageSpinner } from '../../../components/ui/Spinner';
import { EmptyState } from '../../../components/ui/EmptyState';
import {
  listTemplates,
  getTemplateFull,
  createTemplate,
  updateTemplate,
  deleteTemplate,
  addTemplateSection,
  updateTemplateSection,
  deleteTemplateSection,
  addTemplateEntry,
  deleteTemplateEntry,
} from '../../../api/notebooks';
import type {
  TemplateResponse,
  TemplateSectionWithEntries,
  TemplateEntryResponse,
  SectionType,
  EntryType,
  FieldType,
} from '../../../lib/types';

const SECTION_TYPE_ICONS: Record<SectionType, typeof Info> = {
  info: Info,
  notes: FileText,
  tasks: ListTodo,
};

const SECTION_TYPE_LABELS: Record<SectionType, string> = {
  info: 'Info Fields',
  notes: 'Notes',
  tasks: 'Tasks',
};

export function JobNotebookTemplatePage() {
  const queryClient = useQueryClient();
  const [selectedId, setSelectedId] = useState<number | null>(null);
  const [showCreateTemplate, setShowCreateTemplate] = useState(false);
  const [newTemplateName, setNewTemplateName] = useState('');
  const [showAddSection, setShowAddSection] = useState(false);
  const [newSectionName, setNewSectionName] = useState('');
  const [newSectionType, setNewSectionType] = useState<SectionType>('tasks');
  const [addingEntryToSection, setAddingEntryToSection] = useState<number | null>(null);
  const [newEntryTitle, setNewEntryTitle] = useState('');
  const [newEntryType, setNewEntryType] = useState<EntryType>('note');
  const [newFieldType, setNewFieldType] = useState<FieldType>('text');
  const [expandedSections, setExpandedSections] = useState<Set<number>>(new Set());

  // Inline editing state for template name + description
  const [editingName, setEditingName] = useState(false);
  const [editName, setEditName] = useState('');
  const [editingDesc, setEditingDesc] = useState(false);
  const [editDesc, setEditDesc] = useState('');

  // ── Queries ─────────────────────────────────────────────────────
  const { data: templates = [], isLoading: loadingList } = useQuery({
    queryKey: ['notebook-templates'],
    queryFn: listTemplates,
  });

  const { data: templateFull, isLoading: loadingDetail } = useQuery({
    queryKey: ['notebook-template-full', selectedId],
    queryFn: () => getTemplateFull(selectedId!),
    enabled: !!selectedId,
  });

  // Auto-expand all sections when template loads
  useEffect(() => {
    if (templateFull?.sections) {
      setExpandedSections(new Set(templateFull.sections.map((s) => s.id)));
    }
  }, [templateFull]);

  // ── Mutations ───────────────────────────────────────────────────
  const invalidateAll = () => {
    queryClient.invalidateQueries({ queryKey: ['notebook-templates'] });
    if (selectedId) queryClient.invalidateQueries({ queryKey: ['notebook-template-full', selectedId] });
  };

  const createTemplateMut = useMutation({
    mutationFn: () => createTemplate({ name: newTemplateName.trim() }),
    onSuccess: (t) => {
      invalidateAll();
      setSelectedId(t.id);
      setShowCreateTemplate(false);
      setNewTemplateName('');
    },
  });

  const updateTemplateMut = useMutation({
    mutationFn: (data: { name?: string; description?: string; is_default?: boolean }) =>
      updateTemplate(selectedId!, data),
    onSuccess: () => {
      invalidateAll();
      setEditingName(false);
      setEditingDesc(false);
    },
  });

  const deleteTemplateMut = useMutation({
    mutationFn: (id: number) => deleteTemplate(id),
    onSuccess: () => {
      invalidateAll();
      setSelectedId(null);
    },
  });

  const addSectionMut = useMutation({
    mutationFn: () =>
      addTemplateSection(selectedId!, {
        name: newSectionName.trim(),
        section_type: newSectionType,
      }),
    onSuccess: (sec) => {
      invalidateAll();
      setShowAddSection(false);
      setNewSectionName('');
      // Auto-expand the new section
      setExpandedSections((prev) => new Set([...prev, sec.id]));
    },
  });

  const updateSectionMut = useMutation({
    mutationFn: ({ sectionId, data }: { sectionId: number; data: { name?: string } }) =>
      updateTemplateSection(sectionId, data),
    onSuccess: invalidateAll,
  });

  const deleteSectionMut = useMutation({
    mutationFn: (sectionId: number) => deleteTemplateSection(sectionId),
    onSuccess: invalidateAll,
  });

  const addEntryMut = useMutation({
    mutationFn: (sectionId: number) =>
      addTemplateEntry(sectionId, {
        title: newEntryTitle.trim(),
        entry_type: newEntryType,
        field_type: newEntryType === 'field' ? newFieldType : undefined,
      }),
    onSuccess: () => {
      invalidateAll();
      setAddingEntryToSection(null);
      setNewEntryTitle('');
    },
  });

  const deleteEntryMut = useMutation({
    mutationFn: (entryId: number) => deleteTemplateEntry(entryId),
    onSuccess: invalidateAll,
  });

  // ── Helpers ─────────────────────────────────────────────────────
  const toggleSection = (id: number) => {
    setExpandedSections((prev) => {
      const next = new Set(prev);
      next.has(id) ? next.delete(id) : next.add(id);
      return next;
    });
  };

  const startEditingName = () => {
    if (templateFull) {
      setEditName(templateFull.name);
      setEditingName(true);
    }
  };

  const startEditingDesc = () => {
    if (templateFull) {
      setEditDesc(templateFull.description ?? '');
      setEditingDesc(true);
    }
  };

  const saveName = () => {
    if (editName.trim() && editName.trim() !== templateFull?.name) {
      updateTemplateMut.mutate({ name: editName.trim() });
    } else {
      setEditingName(false);
    }
  };

  const saveDesc = () => {
    const trimmed = editDesc.trim();
    if (trimmed !== (templateFull?.description ?? '')) {
      updateTemplateMut.mutate({ description: trimmed || undefined });
    } else {
      setEditingDesc(false);
    }
  };

  // ── Render ──────────────────────────────────────────────────────
  if (loadingList) return <PageSpinner />;

  return (
    <div className="flex gap-4 h-[calc(100vh-180px)]">
      {/* ─── Left sidebar: Template list ─── */}
      <div className="w-72 shrink-0 border border-border rounded-lg bg-surface overflow-hidden flex flex-col">
        <div className="flex items-center justify-between px-3 py-2.5 border-b border-border">
          <span className="text-xs font-semibold text-gray-700 dark:text-gray-300 uppercase tracking-wider">
            Templates
          </span>
          <button
            onClick={() => setShowCreateTemplate(true)}
            className="p-1.5 rounded hover:bg-surface-secondary text-gray-400 hover:text-blue-500 transition-colors"
            title="New template"
          >
            <Plus className="h-4 w-4" />
          </button>
        </div>

        <div className="flex-1 overflow-y-auto p-2 space-y-1">
          {templates.map((t: TemplateResponse) => (
            <button
              key={t.id}
              onClick={() => setSelectedId(t.id)}
              className={`w-full text-left px-3 py-2.5 rounded-lg text-sm transition-colors ${
                selectedId === t.id
                  ? 'bg-blue-50 dark:bg-blue-900/20 text-blue-700 dark:text-blue-300 border border-blue-200 dark:border-blue-800'
                  : 'hover:bg-surface-secondary text-gray-700 dark:text-gray-300'
              }`}
            >
              <div className="flex items-center gap-2">
                <span className="font-medium truncate flex-1">{t.name}</span>
                {t.is_default && <Star className="h-3 w-3 text-amber-500 fill-amber-500 shrink-0" />}
              </div>
              {t.job_type && (
                <span className="text-[10px] text-gray-400 dark:text-gray-500 mt-0.5 block">{t.job_type}</span>
              )}
            </button>
          ))}

          {templates.length === 0 && !showCreateTemplate && (
            <div className="text-center py-8">
              <BookOpen className="h-8 w-8 mx-auto mb-2 text-gray-300 dark:text-gray-600" />
              <p className="text-xs text-gray-400 dark:text-gray-500">
                No templates yet
              </p>
              <button
                onClick={() => setShowCreateTemplate(true)}
                className="mt-2 text-xs text-blue-500 hover:underline"
              >
                Create your first template
              </button>
            </div>
          )}
        </div>

        {/* Create template inline form */}
        {showCreateTemplate && (
          <div className="p-3 border-t border-border space-y-2">
            <label className="text-xs font-medium text-gray-600 dark:text-gray-400">
              New Template
            </label>
            <input
              type="text"
              value={newTemplateName}
              onChange={(e) => setNewTemplateName(e.target.value)}
              placeholder="Template name..."
              className="w-full rounded-md border border-border bg-surface px-2.5 py-1.5 text-sm"
              autoFocus
              onKeyDown={(e) => {
                if (e.key === 'Enter' && newTemplateName.trim()) createTemplateMut.mutate();
                if (e.key === 'Escape') { setShowCreateTemplate(false); setNewTemplateName(''); }
              }}
            />
            <div className="flex gap-1.5">
              <button
                onClick={() => { setShowCreateTemplate(false); setNewTemplateName(''); }}
                className="flex-1 px-2 py-1.5 text-xs text-gray-500 hover:text-gray-700 rounded-md hover:bg-surface-secondary transition-colors"
              >
                Cancel
              </button>
              <button
                onClick={() => createTemplateMut.mutate()}
                disabled={!newTemplateName.trim() || createTemplateMut.isPending}
                className="flex-1 px-2 py-1.5 text-xs font-medium bg-blue-500 text-white rounded-md hover:bg-blue-600 disabled:opacity-50 transition-colors"
              >
                {createTemplateMut.isPending ? 'Creating...' : 'Create'}
              </button>
            </div>
          </div>
        )}
      </div>

      {/* ─── Right panel: Template editor ─── */}
      <div className="flex-1 border border-border rounded-lg bg-surface overflow-y-auto">
        {!selectedId ? (
          <div className="h-full flex items-center justify-center">
            <EmptyState
              icon={<BookOpen className="h-10 w-10 text-gray-300 dark:text-gray-600" />}
              title="Select a template"
              description="Choose a template from the sidebar to view and edit its structure"
            />
          </div>
        ) : loadingDetail ? (
          <PageSpinner />
        ) : !templateFull ? (
          <EmptyState
            icon={<BookOpen className="h-10 w-10 text-gray-300 dark:text-gray-600" />}
            title="Template not found"
          />
        ) : (
          <div className="p-5 space-y-5">
            {/* ── Template header (editable) ── */}
            <div className="flex items-start justify-between gap-4">
              <div className="flex-1 min-w-0">
                {/* Editable name */}
                {editingName ? (
                  <div className="flex items-center gap-2">
                    <input
                      type="text"
                      value={editName}
                      onChange={(e) => setEditName(e.target.value)}
                      className="text-base font-semibold text-gray-900 dark:text-gray-100 bg-transparent border-b-2 border-blue-500 outline-none flex-1 py-0.5"
                      autoFocus
                      onKeyDown={(e) => {
                        if (e.key === 'Enter') saveName();
                        if (e.key === 'Escape') setEditingName(false);
                      }}
                    />
                    <button onClick={saveName} className="p-1.5 text-green-500 hover:text-green-600">
                      <Check className="h-4 w-4" />
                    </button>
                    <button onClick={() => setEditingName(false)} className="p-1.5 text-gray-400 hover:text-gray-600">
                      <X className="h-4 w-4" />
                    </button>
                  </div>
                ) : (
                  <div className="flex items-center gap-2 group">
                    <h2 className="text-base font-semibold text-gray-900 dark:text-gray-100">
                      {templateFull.name}
                    </h2>
                    {templateFull.is_default && (
                      <span className="inline-flex items-center gap-1 rounded-full bg-amber-100 dark:bg-amber-900/30 px-2 py-0.5 text-[10px] font-medium text-amber-700 dark:text-amber-400">
                        <Star className="h-3 w-3 fill-current" />
                        Default
                      </span>
                    )}
                    <button
                      onClick={startEditingName}
                      className="p-1.5 rounded text-gray-400 dark:text-gray-500 hover:text-gray-600 dark:hover:text-gray-300 hover:bg-gray-100 dark:hover:bg-gray-700 transition-colors"
                      title="Edit name"
                    >
                      <Pencil className="h-3.5 w-3.5" />
                    </button>
                  </div>
                )}

                {/* Editable description */}
                {editingDesc ? (
                  <div className="mt-1 flex items-start gap-2">
                    <textarea
                      value={editDesc}
                      onChange={(e) => setEditDesc(e.target.value)}
                      className="text-sm text-gray-500 dark:text-gray-400 bg-transparent border border-blue-300 dark:border-blue-600 rounded-md outline-none flex-1 py-1 px-2 min-h-[48px] resize-none"
                      placeholder="Template description..."
                      autoFocus
                      onKeyDown={(e) => {
                        if (e.key === 'Enter' && !e.shiftKey) { e.preventDefault(); saveDesc(); }
                        if (e.key === 'Escape') setEditingDesc(false);
                      }}
                    />
                    <div className="flex flex-col gap-1">
                      <button onClick={saveDesc} className="p-1.5 text-green-500 hover:text-green-600">
                        <Check className="h-3.5 w-3.5" />
                      </button>
                      <button onClick={() => setEditingDesc(false)} className="p-1.5 text-gray-400 hover:text-gray-600">
                        <X className="h-3.5 w-3.5" />
                      </button>
                    </div>
                  </div>
                ) : (
                  <div className="mt-1 group/desc flex items-center gap-1">
                    <p
                      className="text-sm text-gray-500 dark:text-gray-400 cursor-pointer hover:text-gray-600 dark:hover:text-gray-300"
                      onClick={startEditingDesc}
                    >
                      {templateFull.description || (
                        <span className="italic text-gray-400 dark:text-gray-600">
                          Click to add a description...
                        </span>
                      )}
                    </p>
                    <button
                      onClick={startEditingDesc}
                      className="p-1.5 rounded text-gray-400 dark:text-gray-500 hover:text-gray-600 dark:hover:text-gray-300 hover:bg-gray-100 dark:hover:bg-gray-700 transition-colors"
                      title="Edit description"
                    >
                      <Pencil className="h-3.5 w-3.5" />
                    </button>
                  </div>
                )}
              </div>

              {/* Action buttons */}
              <div className="flex items-center gap-1.5 shrink-0">
                {!templateFull.is_default && (
                  <button
                    onClick={() => updateTemplateMut.mutate({ is_default: true })}
                    className="flex items-center gap-1 px-2.5 py-1.5 text-xs font-medium text-amber-600 hover:bg-amber-50 dark:hover:bg-amber-900/20 rounded-md border border-amber-200 dark:border-amber-800 transition-colors"
                    title="Set as default template for new job notebooks"
                  >
                    <Star className="h-3.5 w-3.5" />
                    Set Default
                  </button>
                )}
                <button
                  onClick={() => {
                    if (window.confirm('Delete this template? This cannot be undone.')) {
                      deleteTemplateMut.mutate(selectedId!);
                    }
                  }}
                  className="p-1.5 rounded text-gray-400 hover:text-red-500 hover:bg-red-50 dark:hover:bg-red-900/20 transition-colors"
                  title="Delete template"
                >
                  <Trash2 className="h-4 w-4" />
                </button>
              </div>
            </div>

            {/* ── Section count summary ── */}
            <div className="flex items-center gap-4 text-xs text-gray-400 dark:text-gray-500 border-b border-border pb-3">
              <span>{templateFull.sections.length} section{templateFull.sections.length !== 1 ? 's' : ''}</span>
              <span>
                {templateFull.sections.reduce((n, s) => n + s.entries.length, 0)} total entries
              </span>
            </div>

            {/* ── Sections ── */}
            <div className="space-y-3">
              {templateFull.sections.map((section: TemplateSectionWithEntries) => (
                <TemplateSectionCard
                  key={section.id}
                  section={section}
                  isExpanded={expandedSections.has(section.id)}
                  onToggle={() => toggleSection(section.id)}
                  onDelete={() => {
                    if (window.confirm(`Delete section "${section.name}" and all its entries?`)) {
                      deleteSectionMut.mutate(section.id);
                    }
                  }}
                  onRename={(name) => updateSectionMut.mutate({ sectionId: section.id, data: { name } })}
                  addingEntry={addingEntryToSection === section.id}
                  onStartAddEntry={() => {
                    setAddingEntryToSection(section.id);
                    setNewEntryType(
                      section.section_type === 'info' ? 'field'
                      : section.section_type === 'tasks' ? 'task'
                      : 'note'
                    );
                    setNewEntryTitle('');
                  }}
                  onCancelAddEntry={() => { setAddingEntryToSection(null); setNewEntryTitle(''); }}
                  entryForm={{
                    title: newEntryTitle,
                    setTitle: setNewEntryTitle,
                    type: newEntryType,
                    setType: setNewEntryType,
                    fieldType: newFieldType,
                    setFieldType: setNewFieldType,
                    onSubmit: () => newEntryTitle.trim() && addEntryMut.mutate(section.id),
                    isPending: addEntryMut.isPending,
                  }}
                  onDeleteEntry={(entryId) => deleteEntryMut.mutate(entryId)}
                />
              ))}
            </div>

            {/* ── Add section ── */}
            {showAddSection ? (
              <div className="p-4 border border-blue-200 dark:border-blue-800 bg-blue-50/50 dark:bg-blue-900/10 rounded-lg space-y-3">
                <h4 className="text-xs font-semibold text-gray-700 dark:text-gray-300 uppercase">
                  New Section
                </h4>
                <input
                  type="text"
                  value={newSectionName}
                  onChange={(e) => setNewSectionName(e.target.value)}
                  placeholder="Section name..."
                  className="w-full rounded-md border border-border bg-surface px-3 py-2 text-sm"
                  autoFocus
                  onKeyDown={(e) => {
                    if (e.key === 'Enter' && newSectionName.trim()) addSectionMut.mutate();
                    if (e.key === 'Escape') { setShowAddSection(false); setNewSectionName(''); }
                  }}
                />
                <div className="flex gap-2">
                  {(['info', 'notes', 'tasks'] as SectionType[]).map((st) => {
                    const StIcon = SECTION_TYPE_ICONS[st];
                    return (
                      <button
                        key={st}
                        type="button"
                        onClick={() => setNewSectionType(st)}
                        className={`flex items-center gap-1.5 px-3 py-1.5 text-xs rounded-md border transition-colors ${
                          newSectionType === st
                            ? 'bg-blue-100 dark:bg-blue-900/30 border-blue-300 dark:border-blue-600 text-blue-700 dark:text-blue-300'
                            : 'border-border text-gray-500 hover:text-gray-700'
                        }`}
                      >
                        <StIcon className="h-3.5 w-3.5" />
                        {SECTION_TYPE_LABELS[st]}
                      </button>
                    );
                  })}
                </div>
                <div className="flex justify-end gap-2">
                  <button
                    onClick={() => { setShowAddSection(false); setNewSectionName(''); }}
                    className="px-3 py-1.5 text-xs text-gray-500 hover:text-gray-700 rounded-md hover:bg-surface-secondary transition-colors"
                  >
                    Cancel
                  </button>
                  <button
                    onClick={() => newSectionName.trim() && addSectionMut.mutate()}
                    disabled={!newSectionName.trim() || addSectionMut.isPending}
                    className="px-3 py-1.5 text-xs font-medium bg-blue-500 text-white rounded-md hover:bg-blue-600 disabled:opacity-50 transition-colors"
                  >
                    {addSectionMut.isPending ? 'Adding...' : 'Add Section'}
                  </button>
                </div>
              </div>
            ) : (
              <button
                onClick={() => setShowAddSection(true)}
                className="flex items-center gap-1.5 px-4 py-2.5 text-xs font-medium text-gray-500 hover:text-blue-500 border border-dashed border-border hover:border-blue-300 dark:hover:border-blue-600 rounded-lg transition-colors w-full justify-center"
              >
                <Plus className="h-4 w-4" />
                Add Section
              </button>
            )}
          </div>
        )}
      </div>
    </div>
  );
}


// ── Sub-components ──────────────────────────────────────────────────

interface TemplateSectionCardProps {
  section: TemplateSectionWithEntries;
  isExpanded: boolean;
  onToggle: () => void;
  onDelete: () => void;
  onRename: (name: string) => void;
  addingEntry: boolean;
  onStartAddEntry: () => void;
  onCancelAddEntry: () => void;
  entryForm: {
    title: string;
    setTitle: (v: string) => void;
    type: EntryType;
    setType: (v: EntryType) => void;
    fieldType: FieldType;
    setFieldType: (v: FieldType) => void;
    onSubmit: () => void;
    isPending: boolean;
  };
  onDeleteEntry: (id: number) => void;
}

function TemplateSectionCard({
  section, isExpanded, onToggle, onDelete, onRename,
  addingEntry, onStartAddEntry, onCancelAddEntry,
  entryForm, onDeleteEntry,
}: TemplateSectionCardProps) {
  const SectionIcon = SECTION_TYPE_ICONS[section.section_type] ?? FileText;
  const [editingSectionName, setEditingSectionName] = useState(false);
  const [sectionNameDraft, setSectionNameDraft] = useState('');

  const startEditName = () => {
    setSectionNameDraft(section.name);
    setEditingSectionName(true);
  };

  const saveEditName = () => {
    const trimmed = sectionNameDraft.trim();
    if (trimmed && trimmed !== section.name) {
      onRename(trimmed);
    }
    setEditingSectionName(false);
  };

  return (
    <div className="border border-border rounded-lg overflow-hidden">
      {/* Section header */}
      <div className="flex items-center gap-2 px-3 py-2.5 bg-surface-secondary group">
        <button onClick={onToggle} className="shrink-0 p-1.5 rounded hover:bg-gray-200 dark:hover:bg-gray-600 transition-colors">
          {isExpanded ? (
            <ChevronDown className="h-4 w-4 text-gray-400" />
          ) : (
            <ChevronRight className="h-4 w-4 text-gray-400" />
          )}
        </button>
        <SectionIcon className="h-4 w-4 text-gray-500 dark:text-gray-400 shrink-0" />

        {/* Editable section name */}
        {editingSectionName ? (
          <div className="flex items-center gap-1 flex-1">
            <input
              type="text"
              value={sectionNameDraft}
              onChange={(e) => setSectionNameDraft(e.target.value)}
              className="text-sm font-medium bg-surface border border-blue-300 dark:border-blue-600 rounded px-2 py-0.5 flex-1 outline-none"
              autoFocus
              onKeyDown={(e) => {
                if (e.key === 'Enter') saveEditName();
                if (e.key === 'Escape') setEditingSectionName(false);
              }}
              onBlur={saveEditName}
            />
          </div>
        ) : (
          <>
            <span
              className="text-sm font-medium text-gray-800 dark:text-gray-200 flex-1 cursor-pointer hover:text-blue-500 transition-colors"
              onDoubleClick={startEditName}
              title="Double-click to rename"
            >
              {section.name}
            </span>
            <button
              onClick={startEditName}
              className="p-1.5 rounded text-gray-400 dark:text-gray-500 hover:text-gray-600 dark:hover:text-gray-300 hover:bg-gray-200 dark:hover:bg-gray-600 transition-colors shrink-0"
              title="Rename section"
            >
              <Pencil className="h-3 w-3" />
            </button>
          </>
        )}

        <span className="text-[10px] text-gray-400 dark:text-gray-500 uppercase tracking-wider">
          {SECTION_TYPE_LABELS[section.section_type] ?? section.section_type}
        </span>
        <span className="text-[11px] text-gray-400 bg-gray-100 dark:bg-gray-700 px-1.5 py-0.5 rounded-full">
          {section.entries.length}
        </span>
        {section.is_locked && (
          <span className="text-[10px] text-gray-400" title="Locked section (cannot be removed by field workers)">
            🔒
          </span>
        )}
        <button
          onClick={onDelete}
          className="p-1.5 rounded text-gray-400 dark:text-gray-500 hover:text-red-500 hover:bg-red-50 dark:hover:bg-red-900/20 transition-colors shrink-0"
          title="Delete section"
        >
          <Trash2 className="h-3.5 w-3.5" />
        </button>
      </div>

      {/* Section entries */}
      {isExpanded && (
        <div className="px-3 py-2 space-y-1">
          {section.entries.length === 0 && !addingEntry && (
            <p className="text-xs text-gray-400 dark:text-gray-500 italic py-2 text-center">
              No entries yet — add one below
            </p>
          )}

          {section.entries.map((entry: TemplateEntryResponse) => (
            <div
              key={entry.id}
              className="flex items-center gap-2 px-2.5 py-2 rounded-md hover:bg-surface-secondary/80 group/entry transition-colors"
            >
              <GripVertical className="h-3 w-3 text-gray-300 dark:text-gray-600 shrink-0" />
              <EntryTypeIcon entryType={entry.entry_type} />
              <span className="text-sm text-gray-700 dark:text-gray-300 flex-1">
                {entry.title}
              </span>
              {entry.default_content && (
                <span className="text-[10px] text-gray-400 dark:text-gray-500 italic truncate max-w-[100px]">
                  {entry.default_content}
                </span>
              )}
              <span className="text-[10px] text-gray-400 dark:text-gray-500 bg-gray-50 dark:bg-gray-800 px-1.5 py-0.5 rounded">
                {entry.entry_type}
                {entry.field_type && ` · ${entry.field_type}`}
              </span>
              <button
                onClick={() => onDeleteEntry(entry.id)}
                className="p-1.5 rounded text-gray-400 dark:text-gray-500 hover:text-red-500 hover:bg-red-50 dark:hover:bg-red-900/20 transition-colors shrink-0"
                title="Remove entry"
              >
                <Trash2 className="h-3.5 w-3.5" />
              </button>
            </div>
          ))}

          {/* Add entry inline form */}
          {addingEntry ? (
            <div className="p-3 bg-surface-secondary/50 rounded-md space-y-2 mt-2 border border-border">
              <input
                type="text"
                value={entryForm.title}
                onChange={(e) => entryForm.setTitle(e.target.value)}
                placeholder="Entry title..."
                className="w-full rounded-md border border-border bg-surface px-2.5 py-1.5 text-sm"
                autoFocus
                onKeyDown={(e) => {
                  if (e.key === 'Enter' && entryForm.title.trim()) entryForm.onSubmit();
                  if (e.key === 'Escape') onCancelAddEntry();
                }}
              />
              <div className="flex gap-2 flex-wrap">
                {(['note', 'task', 'field'] as EntryType[]).map((et) => (
                  <button
                    key={et}
                    onClick={() => entryForm.setType(et)}
                    className={`flex items-center gap-1 px-2 py-1 text-xs rounded-md border transition-colors ${
                      entryForm.type === et
                        ? 'bg-blue-50 dark:bg-blue-900/20 border-blue-300 dark:border-blue-600 text-blue-700 dark:text-blue-300'
                        : 'border-border text-gray-500 hover:text-gray-700'
                    }`}
                  >
                    <EntryTypeIcon entryType={et} />
                    {et.charAt(0).toUpperCase() + et.slice(1)}
                  </button>
                ))}
                {entryForm.type === 'field' && (
                  <select
                    value={entryForm.fieldType}
                    onChange={(e) => entryForm.setFieldType(e.target.value as FieldType)}
                    className="rounded-md border border-border bg-surface px-2 py-1 text-xs"
                  >
                    <option value="text">Text</option>
                    <option value="checkbox">Checkbox</option>
                    <option value="textarea">Textarea</option>
                  </select>
                )}
              </div>
              <div className="flex justify-end gap-1.5">
                <button
                  onClick={onCancelAddEntry}
                  className="px-2.5 py-1 text-xs text-gray-500 hover:text-gray-700 rounded-md hover:bg-surface-secondary"
                >
                  Cancel
                </button>
                <button
                  onClick={entryForm.onSubmit}
                  disabled={!entryForm.title.trim() || entryForm.isPending}
                  className="px-2.5 py-1 text-xs font-medium bg-blue-500 text-white rounded-md hover:bg-blue-600 disabled:opacity-50 transition-colors"
                >
                  {entryForm.isPending ? 'Adding...' : 'Add Entry'}
                </button>
              </div>
            </div>
          ) : (
            <button
              onClick={onStartAddEntry}
              className="flex items-center gap-1 px-2 py-1.5 text-xs text-gray-400 hover:text-blue-500 transition-colors w-full mt-1"
            >
              <Plus className="h-3 w-3" />
              Add entry
            </button>
          )}
        </div>
      )}
    </div>
  );
}


/** Small icon for entry types */
function EntryTypeIcon({ entryType }: { entryType: string }) {
  switch (entryType) {
    case 'task':
      return <ListTodo className="h-3 w-3 text-blue-400 shrink-0" />;
    case 'field':
      return <Info className="h-3 w-3 text-green-400 shrink-0" />;
    default:
      return <FileText className="h-3 w-3 text-gray-400 shrink-0" />;
  }
}
