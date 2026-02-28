/**
 * JobNotebookTemplatePage — Office module page for managing notebook templates.
 *
 * Layout: Template list (left) + Template editor (right).
 * Managers can add/edit/delete templates, sections, and entries.
 * Requires manage_notebooks permission.
 */

import { useState } from 'react';
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import {
  Plus, Trash2, Edit2, Star, ChevronDown, ChevronRight,
  GripVertical, FileText, ListTodo, Info, BookOpen,
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
  TemplateFull,
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

  const deleteTemplateMut = useMutation({
    mutationFn: (id: number) => deleteTemplate(id),
    onSuccess: () => {
      invalidateAll();
      setSelectedId(null);
    },
  });

  const setDefaultMut = useMutation({
    mutationFn: (id: number) => updateTemplate(id, { is_default: true }),
    onSuccess: invalidateAll,
  });

  const addSectionMut = useMutation({
    mutationFn: () =>
      addTemplateSection(selectedId!, {
        name: newSectionName.trim(),
        section_type: newSectionType,
      }),
    onSuccess: () => {
      invalidateAll();
      setShowAddSection(false);
      setNewSectionName('');
    },
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

  // ── Render ──────────────────────────────────────────────────────
  if (loadingList) return <PageSpinner />;

  return (
    <div className="flex gap-4 h-[calc(100vh-180px)]">
      {/* ─── Left sidebar: Template list ─── */}
      <div className="w-64 shrink-0 border border-border rounded-lg bg-surface overflow-hidden flex flex-col">
        <div className="flex items-center justify-between px-3 py-2.5 border-b border-border">
          <span className="text-xs font-semibold text-gray-700 dark:text-gray-300 uppercase tracking-wider">
            Templates
          </span>
          <button
            onClick={() => setShowCreateTemplate(true)}
            className="p-1 rounded hover:bg-surface-secondary text-gray-400 hover:text-blue-500 transition-colors"
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
              className={`w-full text-left px-3 py-2 rounded-lg text-sm transition-colors ${
                selectedId === t.id
                  ? 'bg-blue-50 dark:bg-blue-900/20 text-blue-700 dark:text-blue-300 border border-blue-200 dark:border-blue-800'
                  : 'hover:bg-surface-secondary text-gray-700 dark:text-gray-300'
              }`}
            >
              <div className="flex items-center gap-2">
                <span className="font-medium truncate flex-1">{t.name}</span>
                {t.is_default && <Star className="h-3 w-3 text-amber-500 shrink-0" />}
              </div>
              {t.job_type && (
                <span className="text-[10px] text-gray-400 dark:text-gray-500">{t.job_type}</span>
              )}
            </button>
          ))}

          {templates.length === 0 && (
            <p className="text-xs text-gray-400 dark:text-gray-500 italic text-center py-4">
              No templates yet
            </p>
          )}
        </div>

        {/* Create template inline form */}
        {showCreateTemplate && (
          <div className="p-2 border-t border-border">
            <input
              type="text"
              value={newTemplateName}
              onChange={(e) => setNewTemplateName(e.target.value)}
              placeholder="Template name..."
              className="w-full rounded-md border border-border bg-surface px-2 py-1.5 text-sm mb-2"
              autoFocus
              onKeyDown={(e) => {
                if (e.key === 'Enter' && newTemplateName.trim()) createTemplateMut.mutate();
                if (e.key === 'Escape') setShowCreateTemplate(false);
              }}
            />
            <div className="flex gap-1">
              <button
                onClick={() => setShowCreateTemplate(false)}
                className="flex-1 px-2 py-1 text-xs text-gray-500 hover:text-gray-700 rounded"
              >
                Cancel
              </button>
              <button
                onClick={() => createTemplateMut.mutate()}
                disabled={!newTemplateName.trim()}
                className="flex-1 px-2 py-1 text-xs font-medium bg-blue-500 text-white rounded hover:bg-blue-600 disabled:opacity-50"
              >
                Create
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
              description="Choose a template from the sidebar to view and edit"
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
          <div className="p-4 space-y-4">
            {/* Template header */}
            <div className="flex items-center justify-between">
              <div>
                <h2 className="text-base font-semibold text-gray-900 dark:text-gray-100">
                  {templateFull.template.name}
                </h2>
                {templateFull.template.description && (
                  <p className="text-sm text-gray-500 dark:text-gray-400">
                    {templateFull.template.description}
                  </p>
                )}
              </div>
              <div className="flex items-center gap-2">
                {!templateFull.template.is_default && (
                  <button
                    onClick={() => setDefaultMut.mutate(selectedId!)}
                    className="flex items-center gap-1 px-2.5 py-1 text-xs font-medium text-amber-600 hover:bg-amber-50 dark:hover:bg-amber-900/20 rounded-md transition-colors"
                    title="Set as default template"
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

            {/* Sections */}
            <div className="space-y-2">
              {templateFull.sections.map((section: TemplateSectionWithEntries) => {
                const SectionIcon = SECTION_TYPE_ICONS[section.section_type] ?? FileText;
                const isExpanded = expandedSections.has(section.id);

                return (
                  <div key={section.id} className="border border-border rounded-lg overflow-hidden">
                    {/* Section header */}
                    <div className="flex items-center gap-2 px-3 py-2 bg-surface-secondary">
                      <button onClick={() => toggleSection(section.id)} className="shrink-0">
                        {isExpanded ? (
                          <ChevronDown className="h-4 w-4 text-gray-400" />
                        ) : (
                          <ChevronRight className="h-4 w-4 text-gray-400" />
                        )}
                      </button>
                      <GripVertical className="h-3.5 w-3.5 text-gray-300 dark:text-gray-600 shrink-0" />
                      <SectionIcon className="h-4 w-4 text-gray-500 dark:text-gray-400 shrink-0" />
                      <span className="text-sm font-medium text-gray-800 dark:text-gray-200 flex-1">
                        {section.name}
                      </span>
                      <span className="text-[10px] text-gray-400 dark:text-gray-500 uppercase">
                        {section.section_type}
                      </span>
                      <span className="text-[11px] text-gray-400">{section.entries.length}</span>
                      <button
                        onClick={() => {
                          if (window.confirm(`Delete section "${section.name}"?`)) {
                            deleteSectionMut.mutate(section.id);
                          }
                        }}
                        className="p-0.5 rounded text-gray-300 hover:text-red-500 transition-colors"
                      >
                        <Trash2 className="h-3.5 w-3.5" />
                      </button>
                    </div>

                    {/* Section entries */}
                    {isExpanded && (
                      <div className="px-3 py-2 space-y-1">
                        {section.entries.map((entry: TemplateEntryResponse) => (
                          <div
                            key={entry.id}
                            className="flex items-center gap-2 px-2 py-1.5 rounded hover:bg-surface-secondary group"
                          >
                            <GripVertical className="h-3 w-3 text-gray-300 dark:text-gray-600" />
                            <span className="text-sm text-gray-700 dark:text-gray-300 flex-1">
                              {entry.title}
                            </span>
                            <span className="text-[10px] text-gray-400 dark:text-gray-500">
                              {entry.entry_type}
                              {entry.field_type && ` · ${entry.field_type}`}
                            </span>
                            <button
                              onClick={() => deleteEntryMut.mutate(entry.id)}
                              className="p-0.5 rounded text-gray-300 hover:text-red-500 opacity-0 group-hover:opacity-100 transition-all"
                            >
                              <Trash2 className="h-3 w-3" />
                            </button>
                          </div>
                        ))}

                        {/* Add entry inline form */}
                        {addingEntryToSection === section.id ? (
                          <div className="p-2 bg-surface-secondary rounded-md space-y-2">
                            <input
                              type="text"
                              value={newEntryTitle}
                              onChange={(e) => setNewEntryTitle(e.target.value)}
                              placeholder="Entry title..."
                              className="w-full rounded border border-border bg-surface px-2 py-1 text-sm"
                              autoFocus
                            />
                            <div className="flex gap-2">
                              <select
                                value={newEntryType}
                                onChange={(e) => setNewEntryType(e.target.value as EntryType)}
                                className="rounded border border-border bg-surface px-2 py-1 text-xs"
                              >
                                <option value="note">Note</option>
                                <option value="task">Task</option>
                                <option value="field">Field</option>
                              </select>
                              {newEntryType === 'field' && (
                                <select
                                  value={newFieldType}
                                  onChange={(e) => setNewFieldType(e.target.value as FieldType)}
                                  className="rounded border border-border bg-surface px-2 py-1 text-xs"
                                >
                                  <option value="text">Text</option>
                                  <option value="checkbox">Checkbox</option>
                                  <option value="textarea">Textarea</option>
                                </select>
                              )}
                            </div>
                            <div className="flex justify-end gap-1">
                              <button
                                onClick={() => { setAddingEntryToSection(null); setNewEntryTitle(''); }}
                                className="px-2 py-1 text-xs text-gray-500"
                              >
                                Cancel
                              </button>
                              <button
                                onClick={() => newEntryTitle.trim() && addEntryMut.mutate(section.id)}
                                disabled={!newEntryTitle.trim()}
                                className="px-2 py-1 text-xs font-medium bg-blue-500 text-white rounded hover:bg-blue-600 disabled:opacity-50"
                              >
                                Add
                              </button>
                            </div>
                          </div>
                        ) : (
                          <button
                            onClick={() => {
                              setAddingEntryToSection(section.id);
                              // Default entry type based on section type
                              setNewEntryType(
                                section.section_type === 'info' ? 'field'
                                : section.section_type === 'tasks' ? 'task'
                                : 'note'
                              );
                            }}
                            className="flex items-center gap-1 px-2 py-1 text-xs text-gray-400 hover:text-blue-500 transition-colors"
                          >
                            <Plus className="h-3 w-3" />
                            Add entry
                          </button>
                        )}
                      </div>
                    )}
                  </div>
                );
              })}
            </div>

            {/* Add section */}
            {showAddSection ? (
              <div className="p-3 border border-border rounded-lg space-y-2">
                <input
                  type="text"
                  value={newSectionName}
                  onChange={(e) => setNewSectionName(e.target.value)}
                  placeholder="Section name..."
                  className="w-full rounded-md border border-border bg-surface px-2 py-1.5 text-sm"
                  autoFocus
                />
                <div className="flex gap-2">
                  {(['info', 'notes', 'tasks'] as SectionType[]).map((st) => {
                    const StIcon = SECTION_TYPE_ICONS[st];
                    return (
                      <button
                        key={st}
                        type="button"
                        onClick={() => setNewSectionType(st)}
                        className={`flex items-center gap-1 px-2 py-1 text-xs rounded-md border transition-colors ${
                          newSectionType === st
                            ? 'bg-blue-50 dark:bg-blue-900/20 border-blue-300 dark:border-blue-600 text-blue-700 dark:text-blue-300'
                            : 'border-border text-gray-500'
                        }`}
                      >
                        <StIcon className="h-3 w-3" />
                        {st}
                      </button>
                    );
                  })}
                </div>
                <div className="flex justify-end gap-1">
                  <button
                    onClick={() => { setShowAddSection(false); setNewSectionName(''); }}
                    className="px-2 py-1 text-xs text-gray-500"
                  >
                    Cancel
                  </button>
                  <button
                    onClick={() => newSectionName.trim() && addSectionMut.mutate()}
                    disabled={!newSectionName.trim()}
                    className="px-2 py-1 text-xs font-medium bg-blue-500 text-white rounded hover:bg-blue-600 disabled:opacity-50"
                  >
                    Add Section
                  </button>
                </div>
              </div>
            ) : (
              <button
                onClick={() => setShowAddSection(true)}
                className="flex items-center gap-1.5 px-3 py-2 text-xs font-medium text-gray-500 hover:text-blue-500 border border-dashed border-border hover:border-blue-300 rounded-lg transition-colors w-full justify-center"
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
