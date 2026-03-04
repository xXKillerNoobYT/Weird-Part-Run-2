/**
 * CategoriesPage — primary parts authoring hub with 6-level tree editor.
 *
 * Left pane:  Navigable tree (Category → Style → Type → Brand/General → Color = Part).
 * Right pane: Context-sensitive editor based on selected tree node.
 *
 * This is a slim shell that manages:
 *   - Selection state (which tree node is selected)
 *   - Create-target state (which level is being created)
 *   - Expand/collapse state for categories, styles, types
 *   - Delete confirmation modal
 *   - Right-panel routing based on selection type
 *
 * Global color management is now handled via the GlobalColorsModal,
 * accessible from the BrandColorPanel header (right panel).
 *
 * All tree node components and edit panels are extracted into `./categories/`.
 */

import { useState } from 'react';
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import {
  FolderTree, Plus, Edit2,
} from 'lucide-react';
import { Button } from '../../../components/ui/Button';
import { Modal } from '../../../components/ui/Modal';
import { Spinner } from '../../../components/ui/Spinner';
import { EmptyState } from '../../../components/ui/EmptyState';
import { useAuthStore } from '../../../stores/auth-store';
import { PERMISSIONS } from '../../../lib/constants';
import {
  listCategories, listColors,
  deleteCategory, deleteStyle, deleteType,
} from '../../../api/parts';
import type { SelectedCategoryNode } from '../../../lib/types';

// Tree components
import { CategoryNode } from './categories/CategoryNode';

// Right-panel components
import { CreateForm, type CreateTarget } from './categories/CreateForm';
import { EditCategoryPanel } from './categories/EditCategoryPanel';
import { EditStylePanel } from './categories/EditStylePanel';
import { EditTypePanel } from './categories/EditTypePanel';
import { BrandColorPanel } from './categories/BrandColorPanel';
import { PartDetailPanel } from './categories/PartDetailPanel';


export function CategoriesPage() {
  const queryClient = useQueryClient();
  const { hasPermission } = useAuthStore();
  const canEdit = hasPermission(PERMISSIONS.EDIT_PARTS_CATALOG);

  // ── State ─────────────────────────────────────────
  const [selected, setSelected] = useState<SelectedCategoryNode | null>(null);
  const [createTarget, setCreateTarget] = useState<CreateTarget | null>(null);
  const [expandedCategories, setExpandedCategories] = useState<Set<number>>(new Set());
  const [expandedStyles, setExpandedStyles] = useState<Set<number>>(new Set());
  const [expandedTypes, setExpandedTypes] = useState<Set<number>>(new Set());
  const [deleteConfirm, setDeleteConfirm] = useState<SelectedCategoryNode | null>(null);

  // ── Queries ────────────────────────────────────────
  const { data: categories, isLoading: catLoading } = useQuery({
    queryKey: ['categories'],
    queryFn: () => listCategories(),
  });

  const { data: allColors } = useQuery({
    queryKey: ['colors'],
    queryFn: () => listColors(),
  });

  // ── Toggle expand helpers ──────────────────────────
  const toggleCategory = (id: number) => {
    setExpandedCategories((prev) => {
      const next = new Set(prev);
      if (next.has(id)) next.delete(id);
      else next.add(id);
      return next;
    });
  };

  const toggleStyle = (id: number) => {
    setExpandedStyles((prev) => {
      const next = new Set(prev);
      if (next.has(id)) next.delete(id);
      else next.add(id);
      return next;
    });
  };

  const toggleType = (id: number) => {
    setExpandedTypes((prev) => {
      const next = new Set(prev);
      if (next.has(id)) next.delete(id);
      else next.add(id);
      return next;
    });
  };

  // ── Tree select handler ──────────────────────────
  // Auto-expands the clicked node (and its parent chain) so children are visible
  const handleTreeSelect = (node: SelectedCategoryNode) => {
    setSelected(node);
    if (node.type === 'category') {
      setExpandedCategories((prev) => new Set([...prev, node.id]));
    } else if (node.type === 'style') {
      setExpandedStyles((prev) => new Set([...prev, node.id]));
      if (node.categoryId) {
        setExpandedCategories((prev) => new Set([...prev, node.categoryId!]));
      }
    } else if (node.type === 'type') {
      // Expand the type itself so its brands/colors are immediately visible
      setExpandedTypes((prev) => new Set([...prev, node.id]));
      if (node.styleId) {
        setExpandedStyles((prev) => new Set([...prev, node.styleId!]));
      }
      if (node.categoryId) {
        setExpandedCategories((prev) => new Set([...prev, node.categoryId!]));
      }
    } else if (node.type === 'brand' || node.type === 'part') {
      // Expand the entire parent chain so the brand/part stays visible
      // (BrandNode handles its own local expand state via setIsExpanded)
      if (node.typeId) {
        setExpandedTypes((prev) => new Set([...prev, node.typeId!]));
      }
      if (node.styleId) {
        setExpandedStyles((prev) => new Set([...prev, node.styleId!]));
      }
      if (node.categoryId) {
        setExpandedCategories((prev) => new Set([...prev, node.categoryId!]));
      }
    }
  };

  // ── Delete mutations ───────────────────────────────
  const deleteCatMutation = useMutation({
    mutationFn: deleteCategory,
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['categories'] });
      setSelected(null);
      setDeleteConfirm(null);
    },
  });

  const deleteStyleMutation = useMutation({
    mutationFn: deleteStyle,
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['styles'] });
      queryClient.invalidateQueries({ queryKey: ['categories'] });
      setSelected(null);
      setDeleteConfirm(null);
    },
  });

  const deleteTypeMutation = useMutation({
    mutationFn: deleteType,
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['types'] });
      queryClient.invalidateQueries({ queryKey: ['styles'] });
      setSelected(null);
      setDeleteConfirm(null);
    },
  });

  const handleDelete = () => {
    if (!deleteConfirm) return;
    switch (deleteConfirm.type) {
      case 'category':
        deleteCatMutation.mutate(deleteConfirm.id);
        break;
      case 'style':
        deleteStyleMutation.mutate(deleteConfirm.id);
        break;
      case 'type':
        deleteTypeMutation.mutate(deleteConfirm.id);
        break;
    }
  };

  const isDeleting =
    deleteCatMutation.isPending ||
    deleteStyleMutation.isPending ||
    deleteTypeMutation.isPending;

  // ── Right panel routing ─────────────────────────────
  const renderRightPanel = () => {
    if (createTarget) {
      return (
        <CreateForm
          target={createTarget}
          allColors={allColors ?? []}
          onCancel={() => setCreateTarget(null)}
          onCreated={(type, id, parentId) => {
            setCreateTarget(null);
            setSelected({ type, id });
            if (type === 'style' && parentId) toggleCategory(parentId);
            if (type === 'type' && parentId) toggleStyle(parentId);
          }}
        />
      );
    }

    if (!selected) {
      return (
        <div className="flex-1 flex items-center justify-center p-8">
          <EmptyState
            icon={<Edit2 className="h-10 w-10" />}
            title="Select a node to edit"
            description="Click any item in the tree to view or edit its details. Use the + buttons to create new items."
          />
        </div>
      );
    }

    switch (selected.type) {
      case 'category':
        return (
          <EditCategoryPanel
            categoryId={selected.id}
            canEdit={canEdit}
            onDelete={() => setDeleteConfirm(selected)}
            onSelectChild={(node) => {
              handleTreeSelect(node);
            }}
          />
        );
      case 'style':
        return (
          <EditStylePanel
            styleId={selected.id}
            categoryId={selected.categoryId}
            canEdit={canEdit}
            onDelete={() => setDeleteConfirm(selected)}
            onSelectChild={(node) => {
              handleTreeSelect(node);
            }}
          />
        );
      case 'type':
        return (
          <EditTypePanel
            typeId={selected.id}
            canEdit={canEdit}
            onDelete={() => setDeleteConfirm(selected)}
          />
        );
      case 'brand':
        return (
          <BrandColorPanel
            typeId={selected.typeId!}
            brandId={selected.brandId ?? null}
            brandName={selected.brandId === null ? 'General' : 'Brand'}
            categoryId={selected.categoryId!}
            styleId={selected.styleId!}
            canEdit={canEdit}
            onSelectPart={handleTreeSelect}
          />
        );
      case 'part':
        return (
          <PartDetailPanel
            partId={selected.partId ?? selected.id}
            canEdit={canEdit}
            onDeleted={() => setSelected(null)}
          />
        );
      default:
        return null;
    }
  };

  return (
    <div className="flex flex-col lg:flex-row gap-4 h-[calc(100vh-10rem)]">
      {/* ════════════════════════════════════════════════════════
          LEFT PANE — Tree Navigator
          ════════════════════════════════════════════════════════ */}
      <div className="w-full lg:w-[380px] xl:w-[420px] flex-shrink-0 flex flex-col border border-gray-200 dark:border-gray-700 rounded-xl bg-white dark:bg-gray-800 overflow-hidden">
        {/* Tree header */}
        <div className="flex items-center justify-between px-4 py-3 border-b border-gray-200 dark:border-gray-700 bg-gray-50 dark:bg-gray-800/80">
          <h3 className="text-sm font-semibold text-gray-700 dark:text-gray-300 flex items-center gap-2">
            <FolderTree className="h-4 w-4" />
            Part Hierarchy
          </h3>
          {canEdit && (
            <Button
              size="sm"
              variant="ghost"
              icon={<Plus className="h-3.5 w-3.5" />}
              onClick={() => {
                setCreateTarget({ type: 'category' });
                setSelected(null);
              }}
              title="Add Category"
            >
              Category
            </Button>
          )}
        </div>

        {/* Tree body */}
        <div className="flex-1 overflow-y-auto px-2 py-2">
          {catLoading ? (
            <div className="flex justify-center py-8">
              <Spinner size="lg" />
            </div>
          ) : !categories || categories.length === 0 ? (
            <EmptyState
              icon={<FolderTree className="h-10 w-10" />}
              title="No categories yet"
              description={canEdit ? 'Click "+ Category" to create one.' : 'No categories have been created.'}
            />
          ) : (
            <div className="space-y-0.5">
              {categories.map((cat) => (
                <CategoryNode
                  key={cat.id}
                  category={cat}
                  isExpanded={expandedCategories.has(cat.id)}
                  onToggle={() => toggleCategory(cat.id)}
                  selected={selected}
                  onSelect={handleTreeSelect}
                  canEdit={canEdit}
                  onCreateChild={(parentId) => {
                    setCreateTarget({ type: 'style', parentId });
                    setSelected(null);
                  }}
                  expandedStyles={expandedStyles}
                  onToggleStyle={toggleStyle}
                  expandedTypes={expandedTypes}
                  onToggleType={toggleType}
                  onCreateType={(styleId, categoryId) => {
                    setCreateTarget({ type: 'type', parentId: styleId, grandparentId: categoryId });
                    setSelected(null);
                  }}
                />
              ))}
            </div>
          )}
        </div>
      </div>

      {/* ════════════════════════════════════════════════════════
          RIGHT PANE — Edit / Create Form
          ════════════════════════════════════════════════════════ */}
      <div className="flex-1 min-w-0 border border-gray-200 dark:border-gray-700 rounded-xl bg-white dark:bg-gray-800 overflow-hidden flex flex-col">
        {renderRightPanel()}
      </div>

      {/* ── Delete Confirmation Modal ──────────────── */}
      {deleteConfirm && (
        <Modal isOpen={true} onClose={() => setDeleteConfirm(null)} title={`Delete ${deleteConfirm.type}?`} size="sm">
          <p className="text-gray-600 dark:text-gray-300 mb-4">
            Are you sure you want to delete this {deleteConfirm.type}? This cannot be undone.
          </p>
          {(deleteCatMutation.isError || deleteStyleMutation.isError || deleteTypeMutation.isError) && (
            <p className="text-red-500 text-sm mb-4">
              Failed to delete. This item may have child items or parts linked to it.
            </p>
          )}
          <div className="flex justify-end gap-2">
            <Button variant="secondary" onClick={() => setDeleteConfirm(null)}>Cancel</Button>
            <Button variant="danger" isLoading={isDeleting} onClick={handleDelete}>
              Delete
            </Button>
          </div>
        </Modal>
      )}
    </div>
  );
}
