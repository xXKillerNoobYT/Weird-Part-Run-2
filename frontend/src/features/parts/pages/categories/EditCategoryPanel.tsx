/**
 * EditCategoryPanel — right-panel form for editing a selected category.
 *
 * Two sections:
 *   1. Category details: name, description, image URL, active toggle, delete
 *   2. Child styles management: list existing styles, inline add, click-to-navigate
 *
 * This follows the same "edit self + manage children" pattern used by
 * EditTypePanel (brand checkboxes + color links).
 */

import { useState } from 'react';
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import {
  Layers, Check, ToggleLeft, ToggleRight, Trash2,
  Plus, ChevronRight, Box,
} from 'lucide-react';
import { Button } from '../../../../components/ui/Button';
import { Input } from '../../../../components/ui/Input';
import { Badge } from '../../../../components/ui/Badge';
import { Spinner } from '../../../../components/ui/Spinner';
import {
  listCategories, updateCategory,
  listStylesByCategory, createStyle, deleteStyle,
} from '../../../../api/parts';
import type { PartCategoryUpdate, SelectedCategoryNode } from '../../../../lib/types';


export interface EditCategoryPanelProps {
  categoryId: number;
  canEdit: boolean;
  onDelete: () => void;
  onSelectChild: (node: SelectedCategoryNode) => void;
}

export function EditCategoryPanel({ categoryId, canEdit, onDelete, onSelectChild }: EditCategoryPanelProps) {
  const queryClient = useQueryClient();
  const { data: categories } = useQuery({ queryKey: ['categories'], queryFn: () => listCategories() });
  const category = categories?.find((c) => c.id === categoryId);

  // ── Category detail form state ─────────────────
  const [name, setName] = useState('');
  const [description, setDescription] = useState('');
  const [imageUrl, setImageUrl] = useState('');
  const [initialized, setInitialized] = useState(false);
  const [prevId, setPrevId] = useState(categoryId);

  // ── Inline "Add Style" form state ──────────────
  const [showAddStyle, setShowAddStyle] = useState(false);
  const [newStyleName, setNewStyleName] = useState('');

  // Populate form when category loads or changes
  if (category && (!initialized || categoryId !== prevId)) {
    setName(category.name);
    setDescription(category.description ?? '');
    setImageUrl(category.image_url ?? '');
    setInitialized(true);
    setPrevId(categoryId);
  }

  // ── Queries ─────────────────────────────────────
  const { data: styles, isLoading: stylesLoading } = useQuery({
    queryKey: ['styles', categoryId],
    queryFn: () => listStylesByCategory(categoryId),
    enabled: !!category,
  });

  // ── Mutations ───────────────────────────────────
  const updateMutation = useMutation({
    mutationFn: (data: PartCategoryUpdate) => updateCategory(categoryId, data),
    onSuccess: () => queryClient.invalidateQueries({ queryKey: ['categories'] }),
  });

  const toggleMutation = useMutation({
    mutationFn: (is_active: boolean) => updateCategory(categoryId, { is_active }),
    onSuccess: () => queryClient.invalidateQueries({ queryKey: ['categories'] }),
  });

  const createStyleMutation = useMutation({
    mutationFn: (styleName: string) => createStyle({ category_id: categoryId, name: styleName }),
    onSuccess: (created) => {
      queryClient.invalidateQueries({ queryKey: ['styles', categoryId] });
      queryClient.invalidateQueries({ queryKey: ['categories'] });
      setNewStyleName('');
      setShowAddStyle(false);
      // Navigate to the newly created style
      onSelectChild({ type: 'style', id: created.id, categoryId });
    },
  });

  const deleteStyleMutation = useMutation({
    mutationFn: deleteStyle,
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['styles', categoryId] });
      queryClient.invalidateQueries({ queryKey: ['categories'] });
    },
  });

  if (!category) {
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

  const handleAddStyle = (e: React.FormEvent) => {
    e.preventDefault();
    if (!newStyleName.trim()) return;
    createStyleMutation.mutate(newStyleName.trim());
  };

  return (
    <div className="flex flex-col h-full">
      {/* ── Header ──────────────────────────────── */}
      <div className="px-6 py-4 border-b border-gray-200 dark:border-gray-700 bg-gray-50 dark:bg-gray-800/80 flex items-center justify-between">
        <div>
          <div className="flex items-center gap-2">
            <Layers className="h-5 w-5 text-primary-500" />
            <h3 className="text-lg font-semibold text-gray-900 dark:text-gray-100">
              {category.name}
            </h3>
            <Badge variant={category.is_active ? 'success' : 'default'}>
              {category.is_active ? 'Active' : 'Inactive'}
            </Badge>
          </div>
          <p className="text-sm text-gray-500 dark:text-gray-400 mt-0.5">
            Category &middot; {category.style_count} styles &middot; {category.part_count} parts
          </p>
        </div>
        {canEdit && (
          <div className="flex items-center gap-2">
            <button
              className="p-2 rounded-lg hover:bg-gray-100 dark:hover:bg-gray-700 transition-colors"
              onClick={() => toggleMutation.mutate(!category.is_active)}
              title={category.is_active ? 'Deactivate' : 'Activate'}
            >
              {category.is_active ? (
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
        {/* Section 1: Category Details */}
        <form onSubmit={handleSubmit} className="p-6 space-y-4">
          <Input
            label="Name"
            value={name}
            onChange={(e) => setName(e.target.value)}
            disabled={!canEdit}
            required
          />

          <div className="space-y-1.5">
            <label className="block text-sm font-medium text-gray-700 dark:text-gray-300">
              Description
            </label>
            <textarea
              className="w-full rounded-lg border border-gray-300 dark:border-gray-600 bg-white dark:bg-gray-800 px-3 py-2 text-sm min-h-[60px] disabled:opacity-50"
              value={description}
              onChange={(e) => setDescription(e.target.value)}
              disabled={!canEdit}
              placeholder="Optional description..."
            />
          </div>

          <Input
            label="Image URL"
            value={imageUrl}
            onChange={(e) => setImageUrl(e.target.value)}
            disabled={!canEdit}
            placeholder="https://..."
            type="url"
          />

          {updateMutation.isSuccess && (
            <p className="text-green-600 text-sm flex items-center gap-1">
              <Check className="h-4 w-4" /> Saved successfully
            </p>
          )}
          {updateMutation.isError && (
            <p className="text-red-500 text-sm">
              {(updateMutation.error as any)?.response?.data?.detail ?? 'Failed to save.'}
            </p>
          )}

          {canEdit && (
            <div className="flex justify-end">
              <Button type="submit" isLoading={updateMutation.isPending}>
                Save Changes
              </Button>
            </div>
          )}
        </form>

        {/* Section 2: Child Styles Management */}
        <div className="border-t border-gray-200 dark:border-gray-700 p-6">
          <div className="flex items-center justify-between mb-3">
            <h4 className="text-sm font-semibold text-gray-700 dark:text-gray-300 flex items-center gap-2">
              <Box className="h-4 w-4 text-indigo-500" />
              Styles
              {styles && (
                <span className="text-xs text-gray-400 font-normal">({styles.length})</span>
              )}
            </h4>
            {canEdit && (
              <button
                className="flex items-center gap-1 text-xs text-primary-600 hover:text-primary-700 dark:text-primary-400 font-medium"
                onClick={() => setShowAddStyle(!showAddStyle)}
              >
                <Plus className="h-3.5 w-3.5" />
                Add Style
              </button>
            )}
          </div>

          {/* Inline add style form */}
          {showAddStyle && (
            <form onSubmit={handleAddStyle} className="flex items-center gap-2 mb-3">
              <input
                className="flex-1 rounded-lg border border-gray-300 dark:border-gray-600 bg-white dark:bg-gray-800 px-3 py-1.5 text-sm focus:ring-2 focus:ring-primary-500 focus:border-primary-500"
                placeholder="New style name..."
                value={newStyleName}
                onChange={(e) => setNewStyleName(e.target.value)}
                autoFocus
              />
              <Button
                type="submit"
                size="sm"
                isLoading={createStyleMutation.isPending}
                disabled={!newStyleName.trim()}
              >
                Add
              </Button>
              <Button
                type="button"
                size="sm"
                variant="ghost"
                onClick={() => { setShowAddStyle(false); setNewStyleName(''); }}
              >
                Cancel
              </Button>
            </form>
          )}
          {createStyleMutation.isError && (
            <p className="text-red-500 text-xs mb-2">
              {(createStyleMutation.error as any)?.response?.data?.detail ?? 'Failed to create style.'}
            </p>
          )}

          {/* Styles list */}
          {stylesLoading ? (
            <div className="flex items-center gap-2 py-3 text-sm text-gray-400">
              <Spinner size="sm" /> Loading styles...
            </div>
          ) : !styles || styles.length === 0 ? (
            <p className="text-sm text-gray-400 italic py-2">
              {canEdit ? 'No styles yet. Click "Add Style" to create one.' : 'No styles in this category.'}
            </p>
          ) : (
            <div className="space-y-1">
              {styles.map((s) => (
                <div
                  key={s.id}
                  className="flex items-center gap-2 px-3 py-2 rounded-lg hover:bg-gray-50 dark:hover:bg-gray-700/50 cursor-pointer group transition-colors"
                  onClick={() => onSelectChild({ type: 'style', id: s.id, categoryId })}
                >
                  <Box className="h-3.5 w-3.5 text-indigo-400 flex-shrink-0" />
                  <span className="flex-1 text-sm text-gray-700 dark:text-gray-300 truncate">
                    {s.name}
                  </span>
                  {!s.is_active && (
                    <Badge variant="default" className="text-[10px] px-1.5 py-0">Off</Badge>
                  )}
                  <span className="text-[10px] text-gray-400">
                    {s.type_count}t &middot; {s.part_count}p
                  </span>
                  {canEdit && (
                    <button
                      className="p-1 rounded opacity-0 group-hover:opacity-100 hover:bg-red-50 dark:hover:bg-red-900/20 transition-all"
                      onClick={(e) => {
                        e.stopPropagation();
                        if (confirm(`Delete style "${s.name}"?`)) {
                          deleteStyleMutation.mutate(s.id);
                        }
                      }}
                      title="Delete style"
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
