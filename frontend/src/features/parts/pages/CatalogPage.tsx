/**
 * CatalogPage — browse, search, and manage the parts catalog.
 *
 * Features:
 *  - Searchable, sortable, paginated data table
 *  - Filter bar (type, brand, deprecated, low stock)
 *  - Click row to expand detail panel
 *  - Add/edit part dialog
 *  - Permission-gated pricing columns
 */

import { useState, useCallback } from 'react';
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import {
  Package, Plus, Search, Filter, ChevronDown, ChevronUp,
  Edit2, Trash2, AlertTriangle, QrCode, X, ChevronLeft,
  ChevronRight, Tag,
} from 'lucide-react';
import { Button } from '../../../components/ui/Button';
import { Input } from '../../../components/ui/Input';
import { Badge } from '../../../components/ui/Badge';
import { Modal } from '../../../components/ui/Modal';
import { Spinner } from '../../../components/ui/Spinner';
import { EmptyState } from '../../../components/ui/EmptyState';
import { useAuthStore } from '../../../stores/auth-store';
import { PERMISSIONS } from '../../../lib/constants';
import { listParts, createPart, updatePart, deletePart, listBrands } from '../../../api/parts';
import type { PartListItem, PartCreate, PartUpdate, PartSearchParams, Brand } from '../../../lib/types';


export function CatalogPage() {
  const queryClient = useQueryClient();
  const { hasPermission } = useAuthStore();
  const canEdit = hasPermission(PERMISSIONS.EDIT_PARTS_CATALOG);
  const canSeePricing = hasPermission(PERMISSIONS.SHOW_DOLLAR_VALUES);

  // ── Search & filter state ─────────────────────────────
  const [searchText, setSearchText] = useState('');
  const [filters, setFilters] = useState<PartSearchParams>({
    page: 1,
    page_size: 25,
    sort_by: 'name',
    sort_dir: 'asc',
  });
  const [showFilters, setShowFilters] = useState(false);

  // ── Detail / edit state ───────────────────────────────
  const [selectedPartId, setSelectedPartId] = useState<number | null>(null);
  const [editingPart, setEditingPart] = useState<PartListItem | null>(null);
  const [isCreateOpen, setIsCreateOpen] = useState(false);
  const [deleteConfirm, setDeleteConfirm] = useState<PartListItem | null>(null);

  // ── Query: list parts ─────────────────────────────────
  const searchParams: PartSearchParams = {
    ...filters,
    search: searchText || undefined,
  };

  const { data: partsData, isLoading, error } = useQuery({
    queryKey: ['parts', searchParams],
    queryFn: () => listParts(searchParams),
  });

  // ── Query: brands for filter dropdown ─────────────────
  const { data: brands } = useQuery({
    queryKey: ['brands'],
    queryFn: () => listBrands(),
  });

  // ── Mutations ─────────────────────────────────────────
  const createMutation = useMutation({
    mutationFn: createPart,
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['parts'] });
      setIsCreateOpen(false);
    },
  });

  const updateMutation = useMutation({
    mutationFn: ({ id, data }: { id: number; data: PartUpdate }) => updatePart(id, data),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['parts'] });
      setEditingPart(null);
    },
  });

  const deleteMutation = useMutation({
    mutationFn: deletePart,
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['parts'] });
      setDeleteConfirm(null);
    },
  });

  // ── Sorting ───────────────────────────────────────────
  const handleSort = useCallback((column: string) => {
    setFilters(prev => ({
      ...prev,
      sort_by: column,
      sort_dir: prev.sort_by === column && prev.sort_dir === 'asc' ? 'desc' : 'asc',
      page: 1,
    }));
  }, []);

  const SortIcon = ({ column }: { column: string }) => {
    if (filters.sort_by !== column) return null;
    return filters.sort_dir === 'asc'
      ? <ChevronUp className="inline h-3.5 w-3.5 ml-0.5" />
      : <ChevronDown className="inline h-3.5 w-3.5 ml-0.5" />;
  };

  // ── Format helpers ────────────────────────────────────
  const formatDollars = (value: number | null) =>
    value != null ? `$${value.toFixed(2)}` : '•••';

  const formatPercent = (value: number | null) =>
    value != null ? `${value.toFixed(1)}%` : '•••';

  const items = partsData?.items ?? [];
  const total = partsData?.total ?? 0;
  const totalPages = partsData?.total_pages ?? 0;
  const currentPage = filters.page ?? 1;

  return (
    <div className="space-y-4">
      {/* ── Header with search + actions ─────────────── */}
      <div className="flex flex-col sm:flex-row gap-3 items-start sm:items-center justify-between">
        <div className="flex-1 w-full sm:max-w-md">
          <Input
            placeholder="Search parts by code, name, or description..."
            icon={<Search className="h-4 w-4" />}
            value={searchText}
            onChange={(e) => {
              setSearchText(e.target.value);
              setFilters(prev => ({ ...prev, page: 1 }));
            }}
          />
        </div>
        <div className="flex gap-2">
          <Button
            variant="secondary"
            size="sm"
            icon={<Filter className="h-4 w-4" />}
            onClick={() => setShowFilters(!showFilters)}
          >
            Filters
          </Button>
          {canEdit && (
            <Button
              size="sm"
              icon={<Plus className="h-4 w-4" />}
              onClick={() => setIsCreateOpen(true)}
            >
              Add Part
            </Button>
          )}
        </div>
      </div>

      {/* ── Filters bar ──────────────────────────────── */}
      {showFilters && (
        <div className="flex flex-wrap gap-3 p-3 bg-gray-50 dark:bg-gray-800/50 rounded-lg border border-gray-200 dark:border-gray-700">
          <select
            className="rounded-lg border border-gray-300 dark:border-gray-600 bg-white dark:bg-gray-800 px-3 py-1.5 text-sm"
            value={filters.part_type ?? ''}
            onChange={(e) => setFilters(prev => ({ ...prev, part_type: e.target.value || undefined, page: 1 }))}
          >
            <option value="">All Types</option>
            <option value="general">General</option>
            <option value="specific">Specific</option>
          </select>

          <select
            className="rounded-lg border border-gray-300 dark:border-gray-600 bg-white dark:bg-gray-800 px-3 py-1.5 text-sm"
            value={filters.brand_id ?? ''}
            onChange={(e) => setFilters(prev => ({
              ...prev,
              brand_id: e.target.value ? Number(e.target.value) : undefined,
              page: 1,
            }))}
          >
            <option value="">All Brands</option>
            {brands?.map((b: Brand) => (
              <option key={b.id} value={b.id}>{b.name}</option>
            ))}
          </select>

          <label className="flex items-center gap-1.5 text-sm text-gray-600 dark:text-gray-400">
            <input
              type="checkbox"
              className="rounded"
              checked={filters.low_stock ?? false}
              onChange={(e) => setFilters(prev => ({
                ...prev,
                low_stock: e.target.checked || undefined,
                page: 1,
              }))}
            />
            Low Stock Only
          </label>

          <label className="flex items-center gap-1.5 text-sm text-gray-600 dark:text-gray-400">
            <input
              type="checkbox"
              className="rounded"
              checked={filters.is_deprecated === true}
              onChange={(e) => setFilters(prev => ({
                ...prev,
                is_deprecated: e.target.checked || undefined,
                page: 1,
              }))}
            />
            Show Deprecated
          </label>

          <Button
            variant="ghost"
            size="sm"
            onClick={() => {
              setFilters({ page: 1, page_size: 25, sort_by: 'name', sort_dir: 'asc' });
              setSearchText('');
            }}
          >
            Clear All
          </Button>
        </div>
      )}

      {/* ── Results summary ──────────────────────────── */}
      <div className="text-sm text-gray-500 dark:text-gray-400">
        {total > 0 ? (
          <>Showing {(currentPage - 1) * (filters.page_size ?? 25) + 1}–{Math.min(currentPage * (filters.page_size ?? 25), total)} of {total} parts</>
        ) : isLoading ? (
          'Loading...'
        ) : (
          'No parts found'
        )}
      </div>

      {/* ── Data Table ───────────────────────────────── */}
      {isLoading ? (
        <div className="flex justify-center py-12">
          <Spinner size="lg" />
        </div>
      ) : error ? (
        <EmptyState
          icon={<AlertTriangle className="h-12 w-12 text-red-400" />}
          title="Error loading parts"
          description={String(error)}
        />
      ) : items.length === 0 ? (
        <EmptyState
          icon={<Package className="h-12 w-12" />}
          title="No parts found"
          description={searchText ? "Try adjusting your search or filters." : "Add your first part to get started."}
        />
      ) : (
        <div className="overflow-x-auto border border-gray-200 dark:border-gray-700 rounded-xl">
          <table className="w-full text-sm">
            <thead>
              <tr className="bg-gray-50 dark:bg-gray-800/80 border-b border-gray-200 dark:border-gray-700">
                <th className="text-left px-4 py-3 font-medium text-gray-600 dark:text-gray-400 cursor-pointer hover:text-gray-900 dark:hover:text-gray-200" onClick={() => handleSort('code')}>
                  Code <SortIcon column="code" />
                </th>
                <th className="text-left px-4 py-3 font-medium text-gray-600 dark:text-gray-400 cursor-pointer hover:text-gray-900 dark:hover:text-gray-200" onClick={() => handleSort('name')}>
                  Name <SortIcon column="name" />
                </th>
                <th className="text-left px-4 py-3 font-medium text-gray-600 dark:text-gray-400">
                  Type
                </th>
                <th className="text-left px-4 py-3 font-medium text-gray-600 dark:text-gray-400 cursor-pointer hover:text-gray-900 dark:hover:text-gray-200" onClick={() => handleSort('brand_name')}>
                  Brand <SortIcon column="brand_name" />
                </th>
                <th className="text-right px-4 py-3 font-medium text-gray-600 dark:text-gray-400 cursor-pointer hover:text-gray-900 dark:hover:text-gray-200" onClick={() => handleSort('total_stock')}>
                  Stock <SortIcon column="total_stock" />
                </th>
                {canSeePricing && (
                  <>
                    <th className="text-right px-4 py-3 font-medium text-gray-600 dark:text-gray-400 cursor-pointer hover:text-gray-900 dark:hover:text-gray-200" onClick={() => handleSort('company_cost_price')}>
                      Cost <SortIcon column="company_cost_price" />
                    </th>
                    <th className="text-right px-4 py-3 font-medium text-gray-600 dark:text-gray-400 cursor-pointer hover:text-gray-900 dark:hover:text-gray-200" onClick={() => handleSort('company_sell_price')}>
                      Sell <SortIcon column="company_sell_price" />
                    </th>
                  </>
                )}
                <th className="text-right px-4 py-3 font-medium text-gray-600 dark:text-gray-400">
                  ADU
                </th>
                <th className="px-4 py-3 font-medium text-gray-600 dark:text-gray-400 text-center">
                  Status
                </th>
                {canEdit && (
                  <th className="px-4 py-3 font-medium text-gray-600 dark:text-gray-400 text-right">
                    Actions
                  </th>
                )}
              </tr>
            </thead>
            <tbody>
              {items.map((part) => (
                <tr
                  key={part.id}
                  className="border-b border-gray-100 dark:border-gray-700/50 hover:bg-primary-50/50 dark:hover:bg-primary-900/10 cursor-pointer transition-colors"
                  onClick={() => setSelectedPartId(selectedPartId === part.id ? null : part.id)}
                >
                  <td className="px-4 py-3 font-mono text-xs text-primary-600 dark:text-primary-400">
                    {part.code}
                  </td>
                  <td className="px-4 py-3 font-medium text-gray-900 dark:text-gray-100">
                    {part.name}
                  </td>
                  <td className="px-4 py-3">
                    <Badge variant={part.part_type === 'specific' ? 'primary' : 'default'}>
                      {part.part_type}
                    </Badge>
                  </td>
                  <td className="px-4 py-3 text-gray-600 dark:text-gray-400">
                    {part.brand_name ?? '—'}
                  </td>
                  <td className="px-4 py-3 text-right font-medium">
                    <span className={part.total_stock <= 0 ? 'text-red-500' : 'text-gray-900 dark:text-gray-100'}>
                      {part.total_stock}
                    </span>
                  </td>
                  {canSeePricing && (
                    <>
                      <td className="px-4 py-3 text-right text-gray-600 dark:text-gray-400">
                        {formatDollars(part.company_cost_price)}
                      </td>
                      <td className="px-4 py-3 text-right text-gray-600 dark:text-gray-400">
                        {formatDollars(part.company_sell_price)}
                      </td>
                    </>
                  )}
                  <td className="px-4 py-3 text-right text-gray-600 dark:text-gray-400">
                    {part.forecast_adu_30 != null ? part.forecast_adu_30.toFixed(1) : '—'}
                  </td>
                  <td className="px-4 py-3 text-center">
                    <div className="flex justify-center gap-1">
                      {part.is_deprecated && (
                        <Badge variant="warning">deprecated</Badge>
                      )}
                      {part.is_qr_tagged && (
                        <QrCode className="h-4 w-4 text-green-500" />
                      )}
                      {part.forecast_days_until_low != null && part.forecast_days_until_low < 14 && part.forecast_days_until_low >= 0 && (
                        <Badge variant="danger">{part.forecast_days_until_low}d</Badge>
                      )}
                    </div>
                  </td>
                  {canEdit && (
                    <td className="px-4 py-3 text-right">
                      <div className="flex justify-end gap-1" onClick={(e) => e.stopPropagation()}>
                        <button
                          className="p-1 rounded hover:bg-gray-200 dark:hover:bg-gray-700"
                          onClick={() => setEditingPart(part)}
                          title="Edit"
                        >
                          <Edit2 className="h-4 w-4 text-gray-500" />
                        </button>
                        <button
                          className="p-1 rounded hover:bg-red-100 dark:hover:bg-red-900/30"
                          onClick={() => setDeleteConfirm(part)}
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

      {/* ── Pagination ───────────────────────────────── */}
      {totalPages > 1 && (
        <div className="flex items-center justify-between">
          <Button
            variant="secondary"
            size="sm"
            icon={<ChevronLeft className="h-4 w-4" />}
            disabled={currentPage <= 1}
            onClick={() => setFilters(prev => ({ ...prev, page: (prev.page ?? 1) - 1 }))}
          >
            Previous
          </Button>
          <span className="text-sm text-gray-500">
            Page {currentPage} of {totalPages}
          </span>
          <Button
            variant="secondary"
            size="sm"
            iconRight={<ChevronRight className="h-4 w-4" />}
            disabled={currentPage >= totalPages}
            onClick={() => setFilters(prev => ({ ...prev, page: (prev.page ?? 1) + 1 }))}
          >
            Next
          </Button>
        </div>
      )}

      {/* ── Create Part Modal ────────────────────────── */}
      <PartFormModal
        isOpen={isCreateOpen}
        onClose={() => setIsCreateOpen(false)}
        onSubmit={(data) => createMutation.mutate(data as PartCreate)}
        isLoading={createMutation.isPending}
        title="Add New Part"
        brands={brands ?? []}
      />

      {/* ── Edit Part Modal ──────────────────────────── */}
      {editingPart && (
        <PartFormModal
          isOpen={true}
          onClose={() => setEditingPart(null)}
          onSubmit={(data) => updateMutation.mutate({ id: editingPart.id, data: data as PartUpdate })}
          isLoading={updateMutation.isPending}
          title={`Edit: ${editingPart.name}`}
          initial={editingPart}
          brands={brands ?? []}
        />
      )}

      {/* ── Delete Confirmation ──────────────────────── */}
      {deleteConfirm && (
        <Modal isOpen={true} onClose={() => setDeleteConfirm(null)} title="Delete Part?" size="sm">
          <p className="text-gray-600 dark:text-gray-300 mb-4">
            Are you sure you want to delete <strong>{deleteConfirm.name}</strong> ({deleteConfirm.code})?
            This cannot be undone.
          </p>
          {deleteMutation.isError && (
            <p className="text-red-500 text-sm mb-4">
              {(deleteMutation.error as any)?.response?.data?.detail ?? 'Failed to delete part.'}
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
// Part Form Modal (Create + Edit)
// ═══════════════════════════════════════════════════════════════

interface PartFormModalProps {
  isOpen: boolean;
  onClose: () => void;
  onSubmit: (data: PartCreate | PartUpdate) => void;
  isLoading: boolean;
  title: string;
  initial?: PartListItem | null;
  brands: Brand[];
}

function PartFormModal({ isOpen, onClose, onSubmit, isLoading, title, initial, brands }: PartFormModalProps) {
  const [form, setForm] = useState<Record<string, any>>(() => ({
    code: initial?.code ?? '',
    name: initial?.name ?? '',
    description: '',
    part_type: initial?.part_type ?? 'general',
    brand_id: '',
    manufacturer_part_number: '',
    unit_of_measure: initial?.unit_of_measure ?? 'each',
    company_cost_price: initial?.company_cost_price ?? 0,
    company_markup_percent: initial?.company_markup_percent ?? 0,
    min_stock_level: 0,
    max_stock_level: 0,
    target_stock_level: 0,
    notes: '',
  }));

  const handleSubmit = (e: React.FormEvent) => {
    e.preventDefault();
    const data: Record<string, any> = { ...form };
    // Clean up empty strings
    Object.keys(data).forEach(k => {
      if (data[k] === '') data[k] = undefined;
    });
    if (data.brand_id) data.brand_id = Number(data.brand_id);
    if (data.company_cost_price) data.company_cost_price = Number(data.company_cost_price);
    if (data.company_markup_percent) data.company_markup_percent = Number(data.company_markup_percent);
    if (data.min_stock_level) data.min_stock_level = Number(data.min_stock_level);
    if (data.max_stock_level) data.max_stock_level = Number(data.max_stock_level);
    if (data.target_stock_level) data.target_stock_level = Number(data.target_stock_level);
    onSubmit(data);
  };

  const update = (field: string, value: any) =>
    setForm(prev => ({ ...prev, [field]: value }));

  const sellPrice = (Number(form.company_cost_price) || 0) *
    (1 + (Number(form.company_markup_percent) || 0) / 100);

  return (
    <Modal isOpen={isOpen} onClose={onClose} title={title} size="lg">
      <form onSubmit={handleSubmit} className="space-y-4">
        <div className="grid grid-cols-2 gap-4">
          <Input
            label="Part Code *"
            value={form.code}
            onChange={(e) => update('code', e.target.value)}
            placeholder="e.g. WR-12-2-250"
            required
          />
          <Input
            label="Name *"
            value={form.name}
            onChange={(e) => update('name', e.target.value)}
            placeholder="12/2 Romex 250ft"
            required
          />
        </div>

        <div className="grid grid-cols-3 gap-4">
          <div className="space-y-1.5">
            <label className="block text-sm font-medium text-gray-700 dark:text-gray-300">Type</label>
            <select
              className="w-full rounded-lg border border-gray-300 dark:border-gray-600 bg-white dark:bg-gray-800 px-3 py-2 text-sm"
              value={form.part_type}
              onChange={(e) => update('part_type', e.target.value)}
            >
              <option value="general">General (commodity)</option>
              <option value="specific">Specific (branded)</option>
            </select>
          </div>
          <div className="space-y-1.5">
            <label className="block text-sm font-medium text-gray-700 dark:text-gray-300">Brand</label>
            <select
              className="w-full rounded-lg border border-gray-300 dark:border-gray-600 bg-white dark:bg-gray-800 px-3 py-2 text-sm"
              value={form.brand_id}
              onChange={(e) => update('brand_id', e.target.value)}
            >
              <option value="">None</option>
              {brands.map(b => (
                <option key={b.id} value={b.id}>{b.name}</option>
              ))}
            </select>
          </div>
          <Input
            label="Unit of Measure"
            value={form.unit_of_measure}
            onChange={(e) => update('unit_of_measure', e.target.value)}
            placeholder="each, ft, box"
          />
        </div>

        {/* Pricing */}
        <div className="grid grid-cols-3 gap-4">
          <Input
            label="Cost Price ($)"
            type="number"
            min="0"
            step="0.01"
            value={form.company_cost_price}
            onChange={(e) => update('company_cost_price', e.target.value)}
          />
          <Input
            label="Markup (%)"
            type="number"
            min="0"
            step="0.1"
            value={form.company_markup_percent}
            onChange={(e) => update('company_markup_percent', e.target.value)}
          />
          <div className="space-y-1.5">
            <label className="block text-sm font-medium text-gray-700 dark:text-gray-300">Sell Price</label>
            <div className="h-10 flex items-center px-3 rounded-lg bg-gray-100 dark:bg-gray-700 text-sm font-medium">
              ${sellPrice.toFixed(2)}
            </div>
          </div>
        </div>

        {/* Stock Levels */}
        <div className="grid grid-cols-3 gap-4">
          <Input
            label="Min Stock"
            type="number"
            min="0"
            value={form.min_stock_level}
            onChange={(e) => update('min_stock_level', e.target.value)}
          />
          <Input
            label="Target Stock"
            type="number"
            min="0"
            value={form.target_stock_level}
            onChange={(e) => update('target_stock_level', e.target.value)}
          />
          <Input
            label="Max Stock"
            type="number"
            min="0"
            value={form.max_stock_level}
            onChange={(e) => update('max_stock_level', e.target.value)}
          />
        </div>

        {/* Notes */}
        <div className="space-y-1.5">
          <label className="block text-sm font-medium text-gray-700 dark:text-gray-300">Notes</label>
          <textarea
            className="w-full rounded-lg border border-gray-300 dark:border-gray-600 bg-white dark:bg-gray-800 px-3 py-2 text-sm min-h-[60px]"
            value={form.notes}
            onChange={(e) => update('notes', e.target.value)}
            placeholder="Optional notes..."
          />
        </div>

        <div className="flex justify-end gap-2 pt-2 border-t border-gray-200 dark:border-gray-700">
          <Button variant="secondary" type="button" onClick={onClose}>Cancel</Button>
          <Button type="submit" isLoading={isLoading}>
            {initial ? 'Save Changes' : 'Create Part'}
          </Button>
        </div>
      </form>
    </Modal>
  );
}
