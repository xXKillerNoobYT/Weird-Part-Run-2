/**
 * BrandsPage — manage part brands and manufacturers.
 *
 * Features:
 *  - Searchable list of brands with part + supplier counts
 *  - Add / edit / delete brand modals
 *  - Inline toggle for active/inactive status
 *  - Expandable supplier links section per brand
 *  - "Link Supplier" to create brand-supplier relationships
 *  - Permission-gated edit actions
 */

import { useState } from 'react';
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import {
  Tag, Plus, Search, Edit2, Trash2, Globe,
  AlertTriangle, ToggleLeft, ToggleRight,
  ChevronDown, ChevronRight, Building2, Link2, Unlink, X,
} from 'lucide-react';
import { Button } from '../../../components/ui/Button';
import { Input } from '../../../components/ui/Input';
import { Badge } from '../../../components/ui/Badge';
import { Modal } from '../../../components/ui/Modal';
import { Spinner } from '../../../components/ui/Spinner';
import { EmptyState } from '../../../components/ui/EmptyState';
import { useAuthStore } from '../../../stores/auth-store';
import { PERMISSIONS } from '../../../lib/constants';
import {
  listBrands, createBrand, updateBrand, deleteBrand,
  getBrandSuppliers, listSuppliers,
  createBrandSupplierLink, deleteBrandSupplierLink,
} from '../../../api/parts';
import type {
  Brand, BrandCreate, BrandUpdate,
  BrandSupplierLink, Supplier,
} from '../../../lib/types';


export function BrandsPage() {
  const queryClient = useQueryClient();
  const { hasPermission } = useAuthStore();
  const canEdit = hasPermission(PERMISSIONS.EDIT_PARTS_CATALOG);

  // ── State ─────────────────────────────────────────
  const [searchText, setSearchText] = useState('');
  const [expandedBrandId, setExpandedBrandId] = useState<number | null>(null);
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
                <th className="w-8 px-3 py-3" />
                <th className="text-left px-4 py-3 font-medium text-gray-600 dark:text-gray-400">Brand</th>
                <th className="text-left px-4 py-3 font-medium text-gray-600 dark:text-gray-400">Website</th>
                <th className="text-right px-4 py-3 font-medium text-gray-600 dark:text-gray-400">Parts</th>
                <th className="text-right px-4 py-3 font-medium text-gray-600 dark:text-gray-400">Suppliers</th>
                <th className="text-center px-4 py-3 font-medium text-gray-600 dark:text-gray-400">Status</th>
                <th className="text-left px-4 py-3 font-medium text-gray-600 dark:text-gray-400">Notes</th>
                {canEdit && (
                  <th className="text-right px-4 py-3 font-medium text-gray-600 dark:text-gray-400">Actions</th>
                )}
              </tr>
            </thead>
            <tbody>
              {items.map((brand) => {
                const isExpanded = expandedBrandId === brand.id;
                return (
                  <BrandRow
                    key={brand.id}
                    brand={brand}
                    isExpanded={isExpanded}
                    onToggleExpand={() =>
                      setExpandedBrandId(isExpanded ? null : brand.id)
                    }
                    canEdit={canEdit}
                    onEdit={() => setEditingBrand(brand)}
                    onDelete={() => setDeleteConfirm(brand)}
                    onToggleActive={() =>
                      toggleActiveMutation.mutate({
                        id: brand.id,
                        is_active: !brand.is_active,
                      })
                    }
                  />
                );
              })}
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
// Brand Row — table row with expandable supplier links
// ═══════════════════════════════════════════════════════════════

interface BrandRowProps {
  brand: Brand;
  isExpanded: boolean;
  onToggleExpand: () => void;
  canEdit: boolean;
  onEdit: () => void;
  onDelete: () => void;
  onToggleActive: () => void;
}

function BrandRow({
  brand,
  isExpanded,
  onToggleExpand,
  canEdit,
  onEdit,
  onDelete,
  onToggleActive,
}: BrandRowProps) {
  return (
    <>
      {/* Main row */}
      <tr
        className="border-b border-gray-100 dark:border-gray-700/50 hover:bg-gray-50 dark:hover:bg-gray-800/30 transition-colors cursor-pointer"
        onClick={onToggleExpand}
      >
        <td className="px-3 py-3 text-gray-400">
          {isExpanded ? (
            <ChevronDown className="h-4 w-4" />
          ) : (
            <ChevronRight className="h-4 w-4" />
          )}
        </td>
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
        <td className="px-4 py-3 text-right font-medium text-gray-700 dark:text-gray-300">
          {brand.supplier_count}
        </td>
        <td className="px-4 py-3 text-center" onClick={(e) => e.stopPropagation()}>
          {canEdit ? (
            <button
              className="inline-flex items-center gap-1 text-sm transition-colors"
              onClick={onToggleActive}
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
          <td className="px-4 py-3 text-right" onClick={(e) => e.stopPropagation()}>
            <div className="flex justify-end gap-1">
              <button
                className="p-1 rounded hover:bg-gray-200 dark:hover:bg-gray-700"
                onClick={onEdit}
                title="Edit"
              >
                <Edit2 className="h-4 w-4 text-gray-500" />
              </button>
              <button
                className="p-1 rounded hover:bg-red-100 dark:hover:bg-red-900/30"
                onClick={onDelete}
                title="Delete"
              >
                <Trash2 className="h-4 w-4 text-red-400" />
              </button>
            </div>
          </td>
        )}
      </tr>

      {/* Expanded supplier links section */}
      {isExpanded && (
        <tr>
          <td colSpan={canEdit ? 8 : 7} className="px-0 py-0">
            <BrandSupplierSection brandId={brand.id} brandName={brand.name} canEdit={canEdit} />
          </td>
        </tr>
      )}
    </>
  );
}


// ═══════════════════════════════════════════════════════════════
// Brand-Supplier Links Section (shown when brand row is expanded)
// ═══════════════════════════════════════════════════════════════

function BrandSupplierSection({
  brandId,
  brandName,
  canEdit,
}: {
  brandId: number;
  brandName: string;
  canEdit: boolean;
}) {
  const queryClient = useQueryClient();
  const [showLinkForm, setShowLinkForm] = useState(false);
  const [linkSupplierId, setLinkSupplierId] = useState<number | null>(null);
  const [linkAccountNumber, setLinkAccountNumber] = useState('');
  const [linkNotes, setLinkNotes] = useState('');

  // Fetch supplier links for this brand
  const { data: links, isLoading: linksLoading } = useQuery({
    queryKey: ['brand-suppliers', brandId],
    queryFn: () => getBrandSuppliers(brandId),
  });

  // Fetch all suppliers (for the link dropdown — only when form is open)
  const { data: allSuppliers } = useQuery({
    queryKey: ['suppliers'],
    queryFn: () => listSuppliers(),
    enabled: showLinkForm,
  });

  // Filter out suppliers already linked
  const linkedSupplierIds = new Set((links ?? []).map((l) => l.supplier_id));
  const availableSuppliers = (allSuppliers ?? []).filter(
    (s) => !linkedSupplierIds.has(s.id) && s.is_active,
  );

  // Create link mutation
  const createLinkMutation = useMutation({
    mutationFn: createBrandSupplierLink,
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['brand-suppliers', brandId] });
      queryClient.invalidateQueries({ queryKey: ['brands'] });
      setShowLinkForm(false);
      setLinkSupplierId(null);
      setLinkAccountNumber('');
      setLinkNotes('');
    },
  });

  // Delete link mutation
  const deleteLinkMutation = useMutation({
    mutationFn: deleteBrandSupplierLink,
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['brand-suppliers', brandId] });
      queryClient.invalidateQueries({ queryKey: ['brands'] });
    },
  });

  const handleCreateLink = () => {
    if (!linkSupplierId) return;
    createLinkMutation.mutate({
      brand_id: brandId,
      supplier_id: linkSupplierId,
      account_number: linkAccountNumber || undefined,
      notes: linkNotes || undefined,
    });
  };

  return (
    <div className="bg-gray-50 dark:bg-gray-800/30 border-t border-gray-200 dark:border-gray-700 px-6 py-4">
      <div className="flex items-center justify-between mb-3">
        <h4 className="text-xs font-semibold uppercase tracking-wider text-gray-500 dark:text-gray-400 flex items-center gap-1.5">
          <Building2 className="h-3.5 w-3.5" />
          Suppliers carrying {brandName}
        </h4>
        {canEdit && !showLinkForm && (
          <Button
            size="sm"
            variant="secondary"
            icon={<Link2 className="h-3.5 w-3.5" />}
            onClick={() => setShowLinkForm(true)}
          >
            Link Supplier
          </Button>
        )}
      </div>

      {/* Existing links */}
      {linksLoading ? (
        <div className="flex items-center gap-2 py-2 text-sm text-gray-500">
          <Spinner size="sm" /> Loading suppliers...
        </div>
      ) : (links ?? []).length === 0 && !showLinkForm ? (
        <p className="text-sm text-gray-400 italic py-1">
          No suppliers linked yet.{' '}
          {canEdit && (
            <button
              className="text-primary-500 hover:text-primary-600 hover:underline not-italic"
              onClick={() => setShowLinkForm(true)}
            >
              Link one now
            </button>
          )}
        </p>
      ) : (
        <div className="space-y-2">
          {(links ?? []).map((link) => (
            <div
              key={link.id}
              className="flex items-center justify-between py-2 px-3 bg-white dark:bg-gray-800 rounded-lg border border-gray-200 dark:border-gray-700"
            >
              <div className="flex items-center gap-3">
                <Building2 className="h-4 w-4 text-gray-400" />
                <div>
                  <span className="text-sm font-medium text-gray-900 dark:text-gray-100">
                    {link.supplier_name}
                  </span>
                  {link.account_number && (
                    <span className="ml-2 text-xs text-gray-500 dark:text-gray-400">
                      Acct: {link.account_number}
                    </span>
                  )}
                  {link.notes && (
                    <span className="ml-2 text-xs text-gray-400 italic">
                      — {link.notes}
                    </span>
                  )}
                </div>
              </div>
              {canEdit && (
                <button
                  className="p-1 rounded hover:bg-red-100 dark:hover:bg-red-900/30 transition-colors"
                  onClick={() => deleteLinkMutation.mutate(link.id)}
                  title="Remove supplier link"
                >
                  <Unlink className="h-3.5 w-3.5 text-red-400" />
                </button>
              )}
            </div>
          ))}
        </div>
      )}

      {/* Link Supplier form (inline) */}
      {showLinkForm && (
        <div className="mt-3 p-3 bg-white dark:bg-gray-800 rounded-lg border border-primary-200 dark:border-primary-800 space-y-3">
          <div className="flex items-center justify-between">
            <span className="text-sm font-medium text-gray-700 dark:text-gray-300 flex items-center gap-1.5">
              <Link2 className="h-3.5 w-3.5 text-primary-500" />
              Link a supplier to {brandName}
            </span>
            <button
              className="p-1 rounded hover:bg-gray-100 dark:hover:bg-gray-700"
              onClick={() => setShowLinkForm(false)}
            >
              <X className="h-4 w-4 text-gray-400" />
            </button>
          </div>

          <div className="grid grid-cols-1 sm:grid-cols-3 gap-3">
            <div className="space-y-1">
              <label className="block text-xs font-medium text-gray-600 dark:text-gray-400">
                Supplier *
              </label>
              <select
                className="w-full rounded-lg border border-gray-300 dark:border-gray-600 bg-white dark:bg-gray-800 px-3 py-2 text-sm"
                value={linkSupplierId ?? ''}
                onChange={(e) => setLinkSupplierId(e.target.value ? Number(e.target.value) : null)}
              >
                <option value="">Select supplier...</option>
                {availableSuppliers.map((s) => (
                  <option key={s.id} value={s.id}>
                    {s.name}
                  </option>
                ))}
              </select>
              {availableSuppliers.length === 0 && (
                <p className="text-xs text-gray-400 italic">All active suppliers are already linked</p>
              )}
            </div>

            <div className="space-y-1">
              <label className="block text-xs font-medium text-gray-600 dark:text-gray-400">
                Account Number
              </label>
              <input
                className="w-full rounded-lg border border-gray-300 dark:border-gray-600 bg-white dark:bg-gray-800 px-3 py-2 text-sm"
                value={linkAccountNumber}
                onChange={(e) => setLinkAccountNumber(e.target.value)}
                placeholder="e.g. CED-12345"
              />
            </div>

            <div className="space-y-1">
              <label className="block text-xs font-medium text-gray-600 dark:text-gray-400">
                Notes
              </label>
              <input
                className="w-full rounded-lg border border-gray-300 dark:border-gray-600 bg-white dark:bg-gray-800 px-3 py-2 text-sm"
                value={linkNotes}
                onChange={(e) => setLinkNotes(e.target.value)}
                placeholder="Optional notes..."
              />
            </div>
          </div>

          <div className="flex justify-end gap-2">
            <Button
              variant="secondary"
              size="sm"
              onClick={() => setShowLinkForm(false)}
            >
              Cancel
            </Button>
            <Button
              size="sm"
              disabled={!linkSupplierId}
              isLoading={createLinkMutation.isPending}
              onClick={handleCreateLink}
              icon={<Link2 className="h-3.5 w-3.5" />}
            >
              Link Supplier
            </Button>
          </div>

          {createLinkMutation.isError && (
            <p className="text-red-500 text-sm">
              {(createLinkMutation.error as any)?.response?.data?.detail ?? 'Failed to create link.'}
            </p>
          )}
        </div>
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
