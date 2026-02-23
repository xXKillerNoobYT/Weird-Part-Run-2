/**
 * BrandsPage — manage part brands and manufacturers.
 *
 * Features:
 *  - Searchable list of brands with part counts
 *  - Add / edit / delete brand modals
 *  - Inline toggle for active/inactive status
 *  - Permission-gated edit actions
 */

import { useState } from 'react';
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import {
  Tag, Plus, Search, Edit2, Trash2, Globe,
  AlertTriangle, ToggleLeft, ToggleRight,
} from 'lucide-react';
import { Button } from '../../../components/ui/Button';
import { Input } from '../../../components/ui/Input';
import { Badge } from '../../../components/ui/Badge';
import { Modal } from '../../../components/ui/Modal';
import { Spinner } from '../../../components/ui/Spinner';
import { EmptyState } from '../../../components/ui/EmptyState';
import { useAuthStore } from '../../../stores/auth-store';
import { PERMISSIONS } from '../../../lib/constants';
import { listBrands, createBrand, updateBrand, deleteBrand } from '../../../api/parts';
import type { Brand, BrandCreate, BrandUpdate } from '../../../lib/types';


export function BrandsPage() {
  const queryClient = useQueryClient();
  const { hasPermission } = useAuthStore();
  const canEdit = hasPermission(PERMISSIONS.EDIT_PARTS_CATALOG);

  // ── State ─────────────────────────────────────────
  const [searchText, setSearchText] = useState('');
  const [isCreateOpen, setIsCreateOpen] = useState(false);
  const [editingBrand, setEditingBrand] = useState<Brand | null>(null);
  const [deleteConfirm, setDeleteConfirm] = useState<Brand | null>(null);

  // ── Query ─────────────────────────────────────────
  const { data: brands, isLoading, error } = useQuery({
    queryKey: ['brands', { search: searchText || undefined }],
    queryFn: () => listBrands({ search: searchText || undefined }),
  });

  // ── Mutations ─────────────────────────────────────
  const createMutation = useMutation({
    mutationFn: createBrand,
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['brands'] });
      setIsCreateOpen(false);
    },
  });

  const updateMutation = useMutation({
    mutationFn: ({ id, data }: { id: number; data: BrandUpdate }) => updateBrand(id, data),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['brands'] });
      setEditingBrand(null);
    },
  });

  const deleteMutation = useMutation({
    mutationFn: deleteBrand,
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['brands'] });
      setDeleteConfirm(null);
    },
  });

  const toggleActiveMutation = useMutation({
    mutationFn: ({ id, is_active }: { id: number; is_active: boolean }) =>
      updateBrand(id, { is_active }),
    onSuccess: () => queryClient.invalidateQueries({ queryKey: ['brands'] }),
  });

  const items = brands ?? [];

  return (
    <div className="space-y-4">
      {/* ── Header ───────────────────────────────── */}
      <div className="flex flex-col sm:flex-row gap-3 items-start sm:items-center justify-between">
        <div className="flex-1 w-full sm:max-w-md">
          <Input
            placeholder="Search brands..."
            icon={<Search className="h-4 w-4" />}
            value={searchText}
            onChange={(e) => setSearchText(e.target.value)}
          />
        </div>
        {canEdit && (
          <Button
            size="sm"
            icon={<Plus className="h-4 w-4" />}
            onClick={() => setIsCreateOpen(true)}
          >
            Add Brand
          </Button>
        )}
      </div>

      {/* ── Results summary ──────────────────────── */}
      <div className="text-sm text-gray-500 dark:text-gray-400">
        {isLoading ? 'Loading...' : `${items.length} brand${items.length !== 1 ? 's' : ''}`}
      </div>

      {/* ── Table ────────────────────────────────── */}
      {isLoading ? (
        <div className="flex justify-center py-12">
          <Spinner size="lg" />
        </div>
      ) : error ? (
        <EmptyState
          icon={<AlertTriangle className="h-12 w-12 text-red-400" />}
          title="Error loading brands"
          description={String(error)}
        />
      ) : items.length === 0 ? (
        <EmptyState
          icon={<Tag className="h-12 w-12" />}
          title="No brands found"
          description={searchText ? 'Try a different search term.' : 'Add your first brand to get started.'}
        />
      ) : (
        <div className="overflow-x-auto border border-gray-200 dark:border-gray-700 rounded-xl">
          <table className="w-full text-sm">
            <thead>
              <tr className="bg-gray-50 dark:bg-gray-800/80 border-b border-gray-200 dark:border-gray-700">
                <th className="text-left px-4 py-3 font-medium text-gray-600 dark:text-gray-400">Brand</th>
                <th className="text-left px-4 py-3 font-medium text-gray-600 dark:text-gray-400">Website</th>
                <th className="text-right px-4 py-3 font-medium text-gray-600 dark:text-gray-400">Parts</th>
                <th className="text-center px-4 py-3 font-medium text-gray-600 dark:text-gray-400">Status</th>
                <th className="text-left px-4 py-3 font-medium text-gray-600 dark:text-gray-400">Notes</th>
                {canEdit && (
                  <th className="text-right px-4 py-3 font-medium text-gray-600 dark:text-gray-400">Actions</th>
                )}
              </tr>
            </thead>
            <tbody>
              {items.map((brand) => (
                <tr
                  key={brand.id}
                  className="border-b border-gray-100 dark:border-gray-700/50 hover:bg-gray-50 dark:hover:bg-gray-800/30 transition-colors"
                >
                  <td className="px-4 py-3 font-medium text-gray-900 dark:text-gray-100">
                    {brand.name}
                  </td>
                  <td className="px-4 py-3">
                    {brand.website ? (
                      <a
                        href={brand.website}
                        target="_blank"
                        rel="noopener noreferrer"
                        className="inline-flex items-center gap-1 text-primary-500 hover:text-primary-600 hover:underline"
                        onClick={(e) => e.stopPropagation()}
                      >
                        <Globe className="h-3.5 w-3.5" />
                        <span className="truncate max-w-[200px]">
                          {brand.website.replace(/^https?:\/\/(www\.)?/, '')}
                        </span>
                      </a>
                    ) : (
                      <span className="text-gray-400">—</span>
                    )}
                  </td>
                  <td className="px-4 py-3 text-right font-medium text-gray-700 dark:text-gray-300">
                    {brand.part_count}
                  </td>
                  <td className="px-4 py-3 text-center">
                    {canEdit ? (
                      <button
                        className="inline-flex items-center gap-1 text-sm transition-colors"
                        onClick={() => toggleActiveMutation.mutate({
                          id: brand.id,
                          is_active: !brand.is_active,
                        })}
                        title={brand.is_active ? 'Click to deactivate' : 'Click to activate'}
                      >
                        {brand.is_active ? (
                          <ToggleRight className="h-5 w-5 text-green-500" />
                        ) : (
                          <ToggleLeft className="h-5 w-5 text-gray-400" />
                        )}
                      </button>
                    ) : (
                      <Badge variant={brand.is_active ? 'success' : 'default'}>
                        {brand.is_active ? 'Active' : 'Inactive'}
                      </Badge>
                    )}
                  </td>
                  <td className="px-4 py-3 text-gray-500 dark:text-gray-400 truncate max-w-[250px]">
                    {brand.notes ?? '—'}
                  </td>
                  {canEdit && (
                    <td className="px-4 py-3 text-right">
                      <div className="flex justify-end gap-1">
                        <button
                          className="p-1 rounded hover:bg-gray-200 dark:hover:bg-gray-700"
                          onClick={() => setEditingBrand(brand)}
                          title="Edit"
                        >
                          <Edit2 className="h-4 w-4 text-gray-500" />
                        </button>
                        <button
                          className="p-1 rounded hover:bg-red-100 dark:hover:bg-red-900/30"
                          onClick={() => setDeleteConfirm(brand)}
                          title="Delete"
                        >
                          <Trash2 className="h-4 w-4 text-red-400" />
                        </button>
                      </div>
                    </td>
                  )}
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      )}

      {/* ── Create Modal ─────────────────────────── */}
      <BrandFormModal
        isOpen={isCreateOpen}
        onClose={() => setIsCreateOpen(false)}
        onSubmit={(data) => createMutation.mutate(data as BrandCreate)}
        isLoading={createMutation.isPending}
        title="Add Brand"
      />

      {/* ── Edit Modal ───────────────────────────── */}
      {editingBrand && (
        <BrandFormModal
          isOpen={true}
          onClose={() => setEditingBrand(null)}
          onSubmit={(data) => updateMutation.mutate({ id: editingBrand.id, data: data as BrandUpdate })}
          isLoading={updateMutation.isPending}
          title={`Edit: ${editingBrand.name}`}
          initial={editingBrand}
        />
      )}

      {/* ── Delete Confirmation ──────────────────── */}
      {deleteConfirm && (
        <Modal isOpen={true} onClose={() => setDeleteConfirm(null)} title="Delete Brand?" size="sm">
          <p className="text-gray-600 dark:text-gray-300 mb-2">
            Are you sure you want to delete <strong>{deleteConfirm.name}</strong>?
          </p>
          {deleteConfirm.part_count > 0 && (
            <p className="text-amber-600 dark:text-amber-400 text-sm mb-4">
              This brand has {deleteConfirm.part_count} part{deleteConfirm.part_count !== 1 ? 's' : ''} linked to it.
              You must reassign or remove those parts before deleting.
            </p>
          )}
          {deleteMutation.isError && (
            <p className="text-red-500 text-sm mb-4">
              {(deleteMutation.error as any)?.response?.data?.detail ?? 'Failed to delete brand.'}
            </p>
          )}
          <div className="flex justify-end gap-2">
            <Button variant="secondary" onClick={() => setDeleteConfirm(null)}>Cancel</Button>
            <Button
              variant="danger"
              isLoading={deleteMutation.isPending}
              onClick={() => deleteMutation.mutate(deleteConfirm.id)}
            >
              Delete
            </Button>
          </div>
        </Modal>
      )}
    </div>
  );
}


// ═══════════════════════════════════════════════════════════════
// Brand Form Modal (shared by Create + Edit)
// ═══════════════════════════════════════════════════════════════

interface BrandFormModalProps {
  isOpen: boolean;
  onClose: () => void;
  onSubmit: (data: BrandCreate | BrandUpdate) => void;
  isLoading: boolean;
  title: string;
  initial?: Brand | null;
}

function BrandFormModal({ isOpen, onClose, onSubmit, isLoading, title, initial }: BrandFormModalProps) {
  const [form, setForm] = useState({
    name: initial?.name ?? '',
    website: initial?.website ?? '',
    notes: initial?.notes ?? '',
  });

  const handleSubmit = (e: React.FormEvent) => {
    e.preventDefault();
    onSubmit({
      name: form.name,
      website: form.website || undefined,
      notes: form.notes || undefined,
    });
  };

  const update = (field: string, value: string) =>
    setForm(prev => ({ ...prev, [field]: value }));

  return (
    <Modal isOpen={isOpen} onClose={onClose} title={title} size="md">
      <form onSubmit={handleSubmit} className="space-y-4">
        <Input
          label="Brand Name *"
          value={form.name}
          onChange={(e) => update('name', e.target.value)}
          placeholder="e.g. Southwire"
          required
        />

        <Input
          label="Website"
          value={form.website}
          onChange={(e) => update('website', e.target.value)}
          placeholder="https://www.southwire.com"
          type="url"
        />

        <div className="space-y-1.5">
          <label className="block text-sm font-medium text-gray-700 dark:text-gray-300">Notes</label>
          <textarea
            className="w-full rounded-lg border border-gray-300 dark:border-gray-600 bg-white dark:bg-gray-800 px-3 py-2 text-sm min-h-[80px]"
            value={form.notes}
            onChange={(e) => update('notes', e.target.value)}
            placeholder="Optional notes about this brand..."
          />
        </div>

        <div className="flex justify-end gap-2 pt-2 border-t border-gray-200 dark:border-gray-700">
          <Button variant="secondary" type="button" onClick={onClose}>Cancel</Button>
          <Button type="submit" isLoading={isLoading}>
            {initial ? 'Save Changes' : 'Create Brand'}
          </Button>
        </div>
      </form>
    </Modal>
  );
}
