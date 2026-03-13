/**
 * GlobalColorsModal — popup for managing the global color palette.
 *
 * Self-contained modal that combines color list, edit form, and add-new
 * into one place. Triggered from BrandColorPanel's "Global Colors" button.
 *
 * The [NULL] color (name === '[NULL]') is a system color for "color unknown
 * or unimportant." It's pinned at the top and cannot be edited or deleted.
 */

import { useState, useEffect } from 'react';
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import {
  PaintBucket, Plus, Check, Trash2, ToggleLeft, ToggleRight,
} from 'lucide-react';
import { Modal } from '../../../../components/ui/Modal';
import { Button } from '../../../../components/ui/Button';
import { Input } from '../../../../components/ui/Input';
import { Badge } from '../../../../components/ui/Badge';
import { Spinner } from '../../../../components/ui/Spinner';
import {
  listColors, createColor, updateColor, deleteColor,
} from '../../../../api/parts';
import type { PartColor, PartColorCreate, PartColorUpdate } from '../../../../lib/types';


export interface GlobalColorsModalProps {
  isOpen: boolean;
  onClose: () => void;
  canEdit: boolean;
}

/** Check if a color is the special [NULL] system color */
function isNullColor(color: PartColor): boolean {
  return color.name === '[NULL]';
}


export function GlobalColorsModal({ isOpen, onClose, canEdit }: GlobalColorsModalProps) {
  const queryClient = useQueryClient();

  // ── State ──────────────────────────────────────
  const [selectedId, setSelectedId] = useState<number | null>(null);
  const [showAddForm, setShowAddForm] = useState(false);

  // Edit form state
  const [editName, setEditName] = useState('');
  const [editHex, setEditHex] = useState('#FFFFFF');

  // Add form state
  const [newName, setNewName] = useState('');
  const [newHex, setNewHex] = useState('#4F46E5');

  // ── Query ──────────────────────────────────────
  const { data: colors = [], isLoading } = useQuery({
    queryKey: ['colors'],
    queryFn: () => listColors(),
    enabled: isOpen,
  });

  // Sort: [NULL] first (sort_order -1), then by sort_order asc, then by name
  const sortedColors = [...colors].sort((a, b) => {
    if (a.sort_order !== b.sort_order) return a.sort_order - b.sort_order;
    return a.name.localeCompare(b.name);
  });

  const selectedColor = colors.find((c) => c.id === selectedId) ?? null;
  const isSelectedNull = selectedColor ? isNullColor(selectedColor) : false;

  // Sync edit form when selection changes
  useEffect(() => {
    if (selectedColor) {
      setEditName(selectedColor.name);
      setEditHex(selectedColor.hex_code ?? '#FFFFFF');
    }
  }, [selectedColor?.id, selectedColor?.name, selectedColor?.hex_code]);

  // Reset state when modal closes
  useEffect(() => {
    if (!isOpen) {
      setSelectedId(null);
      setShowAddForm(false);
      setNewName('');
      setNewHex('#4F46E5');
    }
  }, [isOpen]);

  // ── Mutations ──────────────────────────────────
  const updateMutation = useMutation({
    mutationFn: (data: PartColorUpdate) => updateColor(selectedId!, data),
    onSuccess: () => queryClient.invalidateQueries({ queryKey: ['colors'] }),
  });

  const toggleMutation = useMutation({
    mutationFn: ({ id, is_active }: { id: number; is_active: boolean }) =>
      updateColor(id, { is_active }),
    onSuccess: () => queryClient.invalidateQueries({ queryKey: ['colors'] }),
  });

  const createMutation = useMutation({
    mutationFn: (data: PartColorCreate) => createColor(data),
    onSuccess: (newColor) => {
      queryClient.invalidateQueries({ queryKey: ['colors'] });
      setShowAddForm(false);
      setNewName('');
      setNewHex('#4F46E5');
      // Select the newly created color
      if (newColor?.id) setSelectedId(newColor.id);
    },
  });

  const deleteMutation = useMutation({
    mutationFn: deleteColor,
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['colors'] });
      setSelectedId(null);
    },
  });

  // ── Handlers ───────────────────────────────────
  const handleSaveEdit = (e: React.FormEvent) => {
    e.preventDefault();
    if (!selectedId || isSelectedNull) return;
    updateMutation.mutate({ name: editName, hex_code: editHex || undefined });
  };

  const handleCreate = (e: React.FormEvent) => {
    e.preventDefault();
    if (!newName.trim()) return;
    createMutation.mutate({ name: newName.trim(), hex_code: newHex || undefined });
  };

  const handleDelete = () => {
    if (!selectedId || isSelectedNull) return;
    if (window.confirm(`Delete color "${selectedColor?.name}"? This cannot be undone.`)) {
      deleteMutation.mutate(selectedId);
    }
  };

  // ── Render ─────────────────────────────────────
  return (
    <Modal isOpen={isOpen} onClose={onClose} title="Global Colors" size="lg">
      <div className="flex flex-col sm:flex-row gap-4 min-h-[340px]">
        {/* ═══ Left: Color List ═══════════════════════ */}
        <div className="sm:w-56 flex-shrink-0 flex flex-col">
          {/* Add button */}
          {canEdit && (
            <button
              className="flex items-center gap-2 w-full px-3 py-2 mb-2 rounded-lg border border-dashed border-gray-300 dark:border-gray-600 text-sm text-primary-600 dark:text-primary-400 hover:bg-primary-50 dark:hover:bg-primary-900/20 transition-colors min-h-[44px]"
              onClick={() => {
                setShowAddForm(true);
                setSelectedId(null);
              }}
            >
              <Plus className="h-4 w-4" />
              Add Color
            </button>
          )}

          {/* Color entries */}
          <div className="flex-1 overflow-y-auto space-y-0.5 max-h-[50vh]">
            {isLoading ? (
              <div className="flex justify-center py-8">
                <Spinner size="md" />
              </div>
            ) : sortedColors.length === 0 ? (
              <p className="text-sm text-gray-400 italic text-center py-4">No colors defined</p>
            ) : (
              sortedColors.map((color) => {
                const isSelected = selectedId === color.id && !showAddForm;
                const isNull = isNullColor(color);

                return (
                  <button
                    key={color.id}
                    className={`flex items-center gap-2 w-full px-2.5 py-2 rounded-lg text-left transition-colors min-h-[44px] ${
                      isSelected
                        ? 'bg-primary-50 dark:bg-primary-900/30 text-primary-700 dark:text-primary-300'
                        : 'hover:bg-gray-100 dark:hover:bg-gray-700/50'
                    }`}
                    onClick={() => {
                      setSelectedId(color.id);
                      setShowAddForm(false);
                    }}
                  >
                    {/* Swatch */}
                    {isNull ? (
                      <span className="inline-flex items-center justify-center w-5 h-5 rounded-full bg-black border border-gray-500 flex-shrink-0">
                        <span className="text-white text-[7px] font-bold leading-none">NULL</span>
                      </span>
                    ) : (
                      <span
                        className="inline-block w-5 h-5 rounded-full border border-gray-300 dark:border-gray-500 flex-shrink-0"
                        style={{ backgroundColor: color.hex_code ?? '#ccc' }}
                      />
                    )}

                    {/* Name + badges */}
                    <span className="text-sm truncate flex-1">{color.name}</span>
                    {!color.is_active && (
                      <Badge variant="default" className="text-[10px] px-1.5 py-0">Off</Badge>
                    )}
                    <span className="text-[10px] text-gray-400 flex-shrink-0">{color.part_count}p</span>
                  </button>
                );
              })
            )}
          </div>
        </div>

        {/* ═══ Right: Edit / Add Form ════════════════ */}
        <div className="flex-1 min-w-0 border-l border-gray-200 dark:border-gray-700 pl-4">
          {showAddForm ? (
            /* ── Add New Color Form ──────────── */
            <form onSubmit={handleCreate} className="space-y-4">
              <h4 className="text-sm font-semibold text-gray-700 dark:text-gray-300 flex items-center gap-2">
                <Plus className="h-4 w-4" />
                New Color
              </h4>

              <Input
                label="Color Name"
                value={newName}
                onChange={(e) => setNewName(e.target.value)}
                placeholder="e.g. Navy Blue"
                required
                maxLength={50}
              />

              <div className="space-y-1.5">
                <label className="block text-sm font-medium text-gray-700 dark:text-gray-300">
                  Hex Color
                </label>
                <div className="flex items-center gap-3">
                  <input
                    type="color"
                    value={newHex}
                    onChange={(e) => setNewHex(e.target.value)}
                    className="w-10 h-10 rounded-lg border border-gray-300 dark:border-gray-600 cursor-pointer"
                  />
                  <Input
                    value={newHex}
                    onChange={(e) => setNewHex(e.target.value)}
                    className="font-mono"
                    placeholder="#000000"
                  />
                </div>
              </div>

              {createMutation.isError && (
                <p className="text-red-500 text-sm">
                  {(createMutation.error as any)?.response?.data?.detail ?? 'Failed to create color.'}
                </p>
              )}

              <div className="flex gap-2 pt-2">
                <Button type="submit" isLoading={createMutation.isPending}>
                  Create Color
                </Button>
                <Button
                  type="button"
                  variant="ghost"
                  onClick={() => {
                    setShowAddForm(false);
                    setNewName('');
                    setNewHex('#4F46E5');
                  }}
                >
                  Cancel
                </Button>
              </div>
            </form>
          ) : selectedColor ? (
            /* ── Edit Existing Color ─────────── */
            <div className="space-y-4">
              {/* Header with status + actions */}
              <div className="flex items-center justify-between">
                <div className="flex items-center gap-2">
                  {isSelectedNull ? (
                    <span className="inline-flex items-center justify-center w-6 h-6 rounded-full bg-black border-2 border-gray-500">
                      <span className="text-white text-[8px] font-bold leading-none">NULL</span>
                    </span>
                  ) : (
                    <span
                      className="inline-block w-6 h-6 rounded-full border-2 border-gray-300 dark:border-gray-500"
                      style={{ backgroundColor: selectedColor.hex_code ?? '#ccc' }}
                    />
                  )}
                  <h4 className="text-sm font-semibold text-gray-700 dark:text-gray-300">
                    {selectedColor.name}
                  </h4>
                  <Badge variant={selectedColor.is_active ? 'success' : 'default'}>
                    {selectedColor.is_active ? 'Active' : 'Inactive'}
                  </Badge>
                </div>

                {canEdit && !isSelectedNull && (
                  <div className="flex items-center gap-1">
                    <button
                      className="p-2 rounded-lg hover:bg-gray-100 dark:hover:bg-gray-700 transition-colors min-h-[44px] min-w-[44px] flex items-center justify-center"
                      onClick={() => toggleMutation.mutate({ id: selectedColor.id, is_active: !selectedColor.is_active })}
                      title={selectedColor.is_active ? 'Deactivate' : 'Activate'}
                    >
                      {selectedColor.is_active ? (
                        <ToggleRight className="h-5 w-5 text-green-500" />
                      ) : (
                        <ToggleLeft className="h-5 w-5 text-gray-400" />
                      )}
                    </button>
                    <button
                      className="p-2 rounded-lg hover:bg-red-50 dark:hover:bg-red-900/20 transition-colors min-h-[44px] min-w-[44px] flex items-center justify-center"
                      onClick={handleDelete}
                      title="Delete color"
                    >
                      <Trash2 className="h-4 w-4 text-red-400" />
                    </button>
                  </div>
                )}
              </div>

              {/* Info line */}
              <p className="text-xs text-gray-500 dark:text-gray-400">
                {selectedColor.part_count} part{selectedColor.part_count !== 1 ? 's' : ''} using this color
                {isSelectedNull && ' \u00B7 System color (read-only)'}
              </p>

              {/* Edit form — disabled for [NULL] */}
              {isSelectedNull ? (
                <div className="rounded-lg border border-gray-200 dark:border-gray-700 bg-gray-50 dark:bg-gray-800/50 p-4 text-sm text-gray-500 dark:text-gray-400">
                  The <span className="font-mono font-medium">[NULL]</span> color is a system default for parts where color is unknown or unimportant. It cannot be edited or deleted.
                </div>
              ) : (
                <form onSubmit={handleSaveEdit} className="space-y-4">
                  <Input
                    label="Name"
                    value={editName}
                    onChange={(e) => setEditName(e.target.value)}
                    disabled={!canEdit}
                    required
                    maxLength={50}
                  />

                  <div className="space-y-1.5">
                    <label className="block text-sm font-medium text-gray-700 dark:text-gray-300">
                      Hex Color Code
                    </label>
                    <div className="flex items-center gap-3">
                      <input
                        type="color"
                        value={editHex}
                        onChange={(e) => setEditHex(e.target.value)}
                        disabled={!canEdit}
                        className="w-10 h-10 rounded-lg border border-gray-300 dark:border-gray-600 cursor-pointer disabled:opacity-50"
                      />
                      <Input
                        value={editHex}
                        onChange={(e) => setEditHex(e.target.value)}
                        disabled={!canEdit}
                        className="font-mono"
                      />
                    </div>
                  </div>

                  {updateMutation.isSuccess && (
                    <p className="text-green-600 text-sm flex items-center gap-1">
                      <Check className="h-4 w-4" /> Saved
                    </p>
                  )}
                  {updateMutation.isError && (
                    <p className="text-red-500 text-sm">
                      {(updateMutation.error as any)?.response?.data?.detail ?? 'Failed to save.'}
                    </p>
                  )}

                  {canEdit && (
                    <div className="pt-2">
                      <Button type="submit" isLoading={updateMutation.isPending}>
                        Save Changes
                      </Button>
                    </div>
                  )}
                </form>
              )}
            </div>
          ) : (
            /* ── Empty state ─────────────────── */
            <div className="flex flex-col items-center justify-center h-full text-center py-8">
              <PaintBucket className="h-10 w-10 text-gray-300 dark:text-gray-600 mb-3" />
              <p className="text-sm text-gray-500 dark:text-gray-400">
                Select a color to view or edit
              </p>
              <p className="text-xs text-gray-400 dark:text-gray-500 mt-1">
                {sortedColors.length} color{sortedColors.length !== 1 ? 's' : ''} defined
              </p>
            </div>
          )}
        </div>
      </div>
    </Modal>
  );
}
