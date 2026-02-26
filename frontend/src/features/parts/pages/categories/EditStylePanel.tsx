/**
 * EditStylePanel — right-panel form for editing a selected style.
 *
 * Two sections:
 *   1. Style details: name, description, image URL, active toggle, delete
 *   2. Child types management: list existing types, inline add, click-to-navigate
 *
 * Follows the same "edit self + manage children" pattern as EditCategoryPanel
 * and EditTypePanel.
 */

import { useState } from 'react';
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import {
  Box, Check, ToggleLeft, ToggleRight, Trash2,
  Plus, ChevronRight, Package,
} from 'lucide-react';
import { Button } from '../../../../components/ui/Button';
import { Input } from '../../../../components/ui/Input';
import { Badge } from '../../../../components/ui/Badge';
import { Spinner } from '../../../../components/ui/Spinner';
import {
  listCategories, listStylesByCategory, updateStyle,
  listTypesByStyle, createType, deleteType,
} from '../../../../api/parts';
import type { PartStyle, PartStyleUpdate, SelectedCategoryNode } from '../../../../lib/types';


export interface EditStylePanelProps {
  styleId: number;
  /** If provided, skip the expensive all-categories lookup */
  categoryId?: number;
  canEdit: boolean;
  onDelete: () => void;
  onSelectChild: (node: SelectedCategoryNode) => void;
}

export function EditStylePanel({ styleId, categoryId, canEdit, onDelete, onSelectChild }: EditStylePanelProps) {
  const queryClient = useQueryClient();
  const { data: categories } = useQuery({ queryKey: ['categories'], queryFn: () => listCategories() });

  // ── Style detail form state ────────────────────
  const [style, setStyle] = useState<PartStyle | null>(null);
  const [name, setName] = useState('');
  const [description, setDescription] = useState('');
  const [imageUrl, setImageUrl] = useState('');
  const [initialized, setInitialized] = useState(false);
  const [prevId, setPrevId] = useState(styleId);

  // ── Inline "Add Type" form state ───────────────
  const [showAddType, setShowAddType] = useState(false);
  const [newTypeName, setNewTypeName] = useState('');

  // Resolve the category to query — prefer explicit prop from tree selection
  const resolvedCategoryId = categoryId ?? undefined;

  // Fast path: direct lookup when categoryId is known
  const directStyleQuery = useQuery({
    queryKey: ['styles', resolvedCategoryId],
    queryFn: () => listStylesByCategory(resolvedCategoryId!),
    enabled: !!resolvedCategoryId,
    select: (styles) => styles.find((s) => s.id === styleId) ?? null,
  });

  // Slow fallback: scan all categories only if categoryId is unknown
  const fallbackStyleQuery = useQuery({
    queryKey: ['style-lookup-fallback', styleId],
    queryFn: async () => {
      if (!categories) return null;
      for (const cat of categories) {
        const styles = await listStylesByCategory(cat.id);
        const found = styles.find((s) => s.id === styleId);
        if (found) return found;
      }
      return null;
    },
    enabled: !resolvedCategoryId && !!categories && categories.length > 0,
  });

  // Use whichever query resolved
  const resolvedStyle = directStyleQuery.data ?? fallbackStyleQuery.data ?? null;

  if (resolvedStyle && (!initialized || styleId !== prevId)) {
    setStyle(resolvedStyle);
    setName(resolvedStyle.name);
    setDescription(resolvedStyle.description ?? '');
    setImageUrl(resolvedStyle.image_url ?? '');
    setInitialized(true);
    setPrevId(styleId);
  }

  // ── Fetch child types ──────────────────────────
  const { data: types, isLoading: typesLoading } = useQuery({
    queryKey: ['types', styleId],
    queryFn: () => listTypesByStyle(styleId),
    enabled: !!style,
  });

  // ── Mutations ──────────────────────────────────
  const updateMutation = useMutation({
    mutationFn: (data: PartStyleUpdate) => updateStyle(styleId, data),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['styles'] });
      queryClient.invalidateQueries({ queryKey: ['style-lookup-fallback', styleId] });
      queryClient.invalidateQueries({ queryKey: ['categories'] });
    },
  });

  const toggleMutation = useMutation({
    mutationFn: (is_active: boolean) => updateStyle(styleId, { is_active }),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['styles'] });
      queryClient.invalidateQueries({ queryKey: ['style-lookup-fallback', styleId] });
    },
  });

  const createTypeMutation = useMutation({
    mutationFn: (typeName: string) => createType({ style_id: styleId, name: typeName }),
    onSuccess: (created) => {
      queryClient.invalidateQueries({ queryKey: ['types', styleId] });
      queryClient.invalidateQueries({ queryKey: ['styles'] });
      queryClient.invalidateQueries({ queryKey: ['style-lookup-fallback', styleId] });
      queryClient.invalidateQueries({ queryKey: ['categories'] });
      setNewTypeName('');
      setShowAddType(false);
      // Navigate to the newly created type
      onSelectChild({
        type: 'type',
        id: created.id,
        styleId,
        categoryId: style?.category_id,
      });
    },
  });

  const deleteTypeMutation = useMutation({
    mutationFn: deleteType,
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['types', styleId] });
      queryClient.invalidateQueries({ queryKey: ['styles'] });
      queryClient.invalidateQueries({ queryKey: ['style-lookup-fallback', styleId] });
      queryClient.invalidateQueries({ queryKey: ['categories'] });
    },
  });

  if (!style) {
    return (
      <div className="flex-1 flex items-center justify-center">
        <Spinner size="lg" />
      </div>
    );
  }

  const handleSubmit = (e: React.FormEvent) => {
    e.preventDefault();
    updateMutation.mutate({
      name,
      description: description || undefined,
      image_url: imageUrl || undefined,
    });
  };

  const handleAddType = (e: React.FormEvent) => {
    e.preventDefault();
    if (!newTypeName.trim()) return;
    createTypeMutation.mutate(newTypeName.trim());
  };

  return (
    <div className="flex flex-col h-full">
      {/* ── Header ──────────────────────────────── */}
      <div className="px-6 py-4 border-b border-gray-200 dark:border-gray-700 bg-gray-50 dark:bg-gray-800/80 flex items-center justify-between">
        <div>
          <div className="flex items-center gap-2">
            <Box className="h-5 w-5 text-indigo-500" />
            <h3 className="text-lg font-semibold text-gray-900 dark:text-gray-100">
              {style.name}
            </h3>
            <Badge variant={style.is_active ? 'success' : 'default'}>
              {style.is_active ? 'Active' : 'Inactive'}
            </Badge>
          </div>
          <p className="text-sm text-gray-500 dark:text-gray-400 mt-0.5">
            Style in {style.category_name} &middot; {style.type_count} types &middot; {style.part_count} parts
          </p>
        </div>
        {canEdit && (
          <div className="flex items-center gap-2">
            <button
              className="p-2 rounded-lg hover:bg-gray-100 dark:hover:bg-gray-700 transition-colors"
              onClick={() => toggleMutation.mutate(!style.is_active)}
              title={style.is_active ? 'Deactivate' : 'Activate'}
            >
              {style.is_active ? (
                <ToggleRight className="h-5 w-5 text-green-500" />
              ) : (
                <ToggleLeft className="h-5 w-5 text-gray-400" />
              )}
            </button>
            <button
              className="p-2 rounded-lg hover:bg-red-50 dark:hover:bg-red-900/20 transition-colors"
              onClick={onDelete}
              title="Delete"
            >
              <Trash2 className="h-4 w-4 text-red-400" />
            </button>
          </div>
        )}
      </div>

      {/* ── Scrollable content ──────────────────── */}
      <div className="flex-1 overflow-y-auto">
        {/* Section 1: Style Details */}
        <form onSubmit={handleSubmit} className="p-6 space-y-4">
          <Input label="Name" value={name} onChange={(e) => setName(e.target.value)} disabled={!canEdit} required />

          <div className="space-y-1.5">
            <label className="block text-sm font-medium text-gray-700 dark:text-gray-300">Description</label>
            <textarea
              className="w-full rounded-lg border border-gray-300 dark:border-gray-600 bg-white dark:bg-gray-800 px-3 py-2 text-sm min-h-[60px] disabled:opacity-50"
              value={description}
              onChange={(e) => setDescription(e.target.value)}
              disabled={!canEdit}
            />
          </div>

          <Input label="Image URL" value={imageUrl} onChange={(e) => setImageUrl(e.target.value)} disabled={!canEdit} type="url" />

          {updateMutation.isSuccess && (
            <p className="text-green-600 text-sm flex items-center gap-1"><Check className="h-4 w-4" /> Saved</p>
          )}
          {updateMutation.isError && (
            <p className="text-red-500 text-sm">{(updateMutation.error as any)?.response?.data?.detail ?? 'Failed to save.'}</p>
          )}

          {canEdit && (
            <div className="flex justify-end">
              <Button type="submit" isLoading={updateMutation.isPending}>Save Changes</Button>
            </div>
          )}
        </form>

        {/* Section 2: Child Types Management */}
        <div className="border-t border-gray-200 dark:border-gray-700 p-6">
          <div className="flex items-center justify-between mb-3">
            <h4 className="text-sm font-semibold text-gray-700 dark:text-gray-300 flex items-center gap-2">
              <Package className="h-4 w-4 text-teal-500" />
              Types
              {types && (
                <span className="text-xs text-gray-400 font-normal">({types.length})</span>
              )}
            </h4>
            {canEdit && (
              <button
                className="flex items-center gap-1 text-xs text-primary-600 hover:text-primary-700 dark:text-primary-400 font-medium"
                onClick={() => setShowAddType(!showAddType)}
              >
                <Plus className="h-3.5 w-3.5" />
                Add Type
              </button>
            )}
          </div>

          {/* Inline add type form */}
          {showAddType && (
            <form onSubmit={handleAddType} className="flex items-center gap-2 mb-3">
              <input
                className="flex-1 rounded-lg border border-gray-300 dark:border-gray-600 bg-white dark:bg-gray-800 px-3 py-1.5 text-sm focus:ring-2 focus:ring-primary-500 focus:border-primary-500"
                placeholder="New type name..."
                value={newTypeName}
                onChange={(e) => setNewTypeName(e.target.value)}
                autoFocus
              />
              <Button
                type="submit"
                size="sm"
                isLoading={createTypeMutation.isPending}
                disabled={!newTypeName.trim()}
              >
                Add
              </Button>
              <Button
                type="button"
                size="sm"
                variant="ghost"
                onClick={() => { setShowAddType(false); setNewTypeName(''); }}
              >
                Cancel
              </Button>
            </form>
          )}
          {createTypeMutation.isError && (
            <p className="text-red-500 text-xs mb-2">
              {(createTypeMutation.error as any)?.response?.data?.detail ?? 'Failed to create type.'}
            </p>
          )}

          {/* Types list */}
          {typesLoading ? (
            <div className="flex items-center gap-2 py-3 text-sm text-gray-400">
              <Spinner size="sm" /> Loading types...
            </div>
          ) : !types || types.length === 0 ? (
            <p className="text-sm text-gray-400 italic py-2">
              {canEdit ? 'No types yet. Click "Add Type" to create one.' : 'No types in this style.'}
            </p>
          ) : (
            <div className="space-y-1">
              {types.map((t) => (
                <div
                  key={t.id}
                  className="flex items-center gap-2 px-3 py-2 rounded-lg hover:bg-gray-50 dark:hover:bg-gray-700/50 cursor-pointer group transition-colors"
                  onClick={() => onSelectChild({
                    type: 'type',
                    id: t.id,
                    styleId,
                    categoryId: style.category_id,
                  })}
                >
                  <Package className="h-3.5 w-3.5 text-teal-400 flex-shrink-0" />
                  <span className="flex-1 text-sm text-gray-700 dark:text-gray-300 truncate">
                    {t.name}
                  </span>
                  {!t.is_active && (
                    <Badge variant="default" className="text-[10px] px-1.5 py-0">Off</Badge>
                  )}
                  <span className="text-[10px] text-gray-400">
                    {t.color_count}c &middot; {t.part_count}p
                  </span>
                  {canEdit && (
                    <button
                      className="p-1 rounded opacity-0 group-hover:opacity-100 hover:bg-red-50 dark:hover:bg-red-900/20 transition-all"
                      onClick={(e) => {
                        e.stopPropagation();
                        if (confirm(`Delete type "${t.name}"?`)) {
                          deleteTypeMutation.mutate(t.id);
                        }
                      }}
                      title="Delete type"
                    >
                      <Trash2 className="h-3 w-3 text-red-400" />
                    </button>
                  )}
                  <ChevronRight className="h-3.5 w-3.5 text-gray-400 dark:text-gray-500 flex-shrink-0" />
                </div>
              ))}
            </div>
          )}
        </div>
      </div>
    </div>
  );
}
