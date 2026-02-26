/**
 * CatalogPage — browse, search, and view the parts catalog.
 *
 * Two view modes (user toggleable):
 *  1. Card Grid — grouped product cards (category × brand), expandable variants
 *  2. Table    — flat sortable/paginated data table
 *
 * Features:
 *  - Hierarchy cascading filters (Category → Style → Type → Color)
 *  - Pending Part Numbers badge + quick filter
 *  - View/edit part dialog (edit fields, no creation — use Categories for that)
 *  - Permission-gated pricing columns
 *
 * Part creation has been moved to the Categories page tree editor where
 * hierarchy context (Category → Style → Type → Brand → Color) is implicit
 * in the tree path, making it much easier to create parts.
 */

import { useState, useCallback, useMemo } from 'react';
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import {
  Package, Search, Filter, ChevronDown, ChevronUp,
  Edit2, Trash2, AlertTriangle, QrCode, ChevronLeft,
  ChevronRight, AlertCircle, Clock, LayoutGrid, List, Box,
  FolderTree,
} from 'lucide-react';
import { useNavigate } from 'react-router-dom';
import { Button } from '../../../components/ui/Button';
import { Input } from '../../../components/ui/Input';
import { Badge } from '../../../components/ui/Badge';
import { Modal } from '../../../components/ui/Modal';
import { Spinner } from '../../../components/ui/Spinner';
import { EmptyState } from '../../../components/ui/EmptyState';
import { useAuthStore } from '../../../stores/auth-store';
import { PERMISSIONS } from '../../../lib/constants';
import {
  listParts, updatePart, deletePart,
  listBrands, getHierarchy, getPendingPartNumbersCount,
  getCatalogGroups,
} from '../../../api/parts';
import { AlternativesSection } from '../components/alternatives/AlternativesSection';
import type {
  PartListItem, PartUpdate, PartSearchParams,
  Brand, CatalogGroup,
} from '../../../lib/types';


type ViewMode = 'cards' | 'table';

export function CatalogPage() {
  const queryClient = useQueryClient();
  const navigate = useNavigate();
  const { hasPermission } = useAuthStore();
  const canEdit = hasPermission(PERMISSIONS.EDIT_PARTS_CATALOG);
  const canSeePricing = hasPermission(PERMISSIONS.SHOW_DOLLAR_VALUES);

  // ── View mode ───────────────────────────────────────
  const [viewMode, setViewMode] = useState<ViewMode>('cards');

  // ── Search & filter state ───────────────────────────
  const [searchText, setSearchText] = useState('');
  const [filters, setFilters] = useState<PartSearchParams>({
    page: 1,
    page_size: 25,
    sort_by: 'name',
    sort_dir: 'asc',
  });
  const [showFilters, setShowFilters] = useState(false);

  // ── Detail / edit state ─────────────────────────────
  const [editingPart, setEditingPart] = useState<PartListItem | null>(null);
  const [deleteConfirm, setDeleteConfirm] = useState<PartListItem | null>(null);

  // ── Query: hierarchy tree for dropdowns ──────────────
  const { data: hierarchy } = useQuery({
    queryKey: ['hierarchy'],
    queryFn: getHierarchy,
    staleTime: 5 * 60 * 1000,
  });

  // ── Query: brands ───────────────────────────────────
  const { data: brands } = useQuery({
    queryKey: ['brands'],
    queryFn: () => listBrands(),
  });

  // ── Query: pending part numbers count (badge) ────────
  const { data: pendingCount } = useQuery({
    queryKey: ['pendingPartNumbersCount'],
    queryFn: getPendingPartNumbersCount,
    staleTime: 30_000,
  });

  // ── Query: table view data ──────────────────────────
  const searchParams: PartSearchParams = {
    ...filters,
    search: searchText || undefined,
  };

  const { data: partsData, isLoading: tableLoading, error: tableError } = useQuery({
    queryKey: ['parts', searchParams],
    queryFn: () => listParts(searchParams),
    enabled: viewMode === 'table',
  });

  // ── Query: card grid data ───────────────────────────
  const { data: catalogGroups, isLoading: cardsLoading, error: cardsError } = useQuery({
    queryKey: ['catalogGroups', {
      search: searchText || undefined,
      category_id: filters.category_id,
      is_deprecated: filters.is_deprecated,
    }],
    queryFn: () => getCatalogGroups({
      search: searchText || undefined,
      category_id: filters.category_id,
      is_deprecated: filters.is_deprecated,
    }),
    enabled: viewMode === 'cards',
  });

  // ── Derived: cascading hierarchy options ──────────────
  const categoryOptions = hierarchy?.categories ?? [];
  const styleOptions = useMemo(() => {
    if (!filters.category_id || !hierarchy) return [];
    return hierarchy.categories.find(c => c.id === filters.category_id)?.styles ?? [];
  }, [filters.category_id, hierarchy]);
  const typeOptions = useMemo(() => {
    if (!filters.style_id || !hierarchy) return [];
    for (const cat of hierarchy.categories) {
      const style = cat.styles.find(s => s.id === filters.style_id);
      if (style) return style.types;
    }
    return [];
  }, [filters.style_id, hierarchy]);
  const colorOptions = hierarchy?.colors ?? [];

  // ── Mutations ───────────────────────────────────────
  const updateMutation = useMutation({
    mutationFn: ({ id, data }: { id: number; data: PartUpdate }) => updatePart(id, data),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['parts'] });
      queryClient.invalidateQueries({ queryKey: ['catalogGroups'] });
      queryClient.invalidateQueries({ queryKey: ['pendingPartNumbersCount'] });
      setEditingPart(null);
    },
  });

  const deleteMutation = useMutation({
    mutationFn: deletePart,
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['parts'] });
      queryClient.invalidateQueries({ queryKey: ['catalogGroups'] });
      queryClient.invalidateQueries({ queryKey: ['pendingPartNumbersCount'] });
      queryClient.invalidateQueries({ queryKey: ['hierarchy'] });
      setDeleteConfirm(null);
    },
  });

  // ── Sorting (table mode) ────────────────────────────
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

  const formatDollars = (value: number | null) =>
    value != null ? `$${value.toFixed(2)}` : '---';

  const items = partsData?.items ?? [];
  const total = partsData?.total ?? 0;
  const totalPages = partsData?.total_pages ?? 0;
  const currentPage = filters.page ?? 1;

  const selectClass = "rounded-lg border border-gray-300 dark:border-gray-600 bg-white dark:bg-gray-800 px-3 py-1.5 text-sm";

  const isLoading = viewMode === 'cards' ? cardsLoading : tableLoading;
  const error = viewMode === 'cards' ? cardsError : tableError;

  return (
    <div className="space-y-4">
      {/* ══════════════════════════════════════════════════
          HEADER BAR — search, view toggle, filters
          ══════════════════════════════════════════════════ */}
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
        <div className="flex gap-2 items-center">
          {/* Pending Part Numbers badge */}
          {(pendingCount ?? 0) > 0 && (
            <button
              className={`flex items-center gap-1.5 px-3 py-1.5 rounded-lg text-sm font-medium transition-colors ${
                filters.has_pending_pn
                  ? 'bg-amber-100 text-amber-800 dark:bg-amber-900/40 dark:text-amber-300 ring-1 ring-amber-300 dark:ring-amber-700'
                  : 'bg-amber-50 text-amber-700 dark:bg-amber-900/20 dark:text-amber-400 hover:bg-amber-100 dark:hover:bg-amber-900/30'
              }`}
              onClick={() => {
                // Pending filter forces table mode
                setViewMode('table');
                setFilters(prev => ({
                  ...prev,
                  has_pending_pn: prev.has_pending_pn ? undefined : true,
                  page: 1,
                }));
              }}
              title="Click to filter parts with pending part numbers"
            >
              <Clock className="h-4 w-4" />
              {pendingCount} Pending PN{pendingCount !== 1 ? 's' : ''}
            </button>
          )}

          {/* View toggle */}
          <div className="flex rounded-lg border border-gray-300 dark:border-gray-600 overflow-hidden">
            <button
              className={`p-1.5 transition-colors ${
                viewMode === 'cards'
                  ? 'bg-primary-500 text-white'
                  : 'bg-white dark:bg-gray-800 text-gray-500 hover:bg-gray-100 dark:hover:bg-gray-700'
              }`}
              onClick={() => setViewMode('cards')}
              title="Card grid view"
            >
              <LayoutGrid className="h-4 w-4" />
            </button>
            <button
              className={`p-1.5 transition-colors ${
                viewMode === 'table'
                  ? 'bg-primary-500 text-white'
                  : 'bg-white dark:bg-gray-800 text-gray-500 hover:bg-gray-100 dark:hover:bg-gray-700'
              }`}
              onClick={() => setViewMode('table')}
              title="Table view"
            >
              <List className="h-4 w-4" />
            </button>
          </div>

          <Button
            variant="secondary"
            size="sm"
            icon={<Filter className="h-4 w-4" />}
            onClick={() => setShowFilters(!showFilters)}
          >
            Filters
          </Button>

          {/* Navigate to Categories for part creation */}
          {canEdit && (
            <Button
              variant="secondary"
              size="sm"
              icon={<FolderTree className="h-4 w-4" />}
              onClick={() => navigate('/parts/categories')}
              title="Create and manage parts via the category tree"
            >
              Edit in Categories
            </Button>
          )}
        </div>
      </div>

      {/* ══════════════════════════════════════════════════
          FILTERS BAR
          ══════════════════════════════════════════════════ */}
      {showFilters && (
        <div className="flex flex-wrap gap-3 p-3 bg-gray-50 dark:bg-gray-800/50 rounded-lg border border-gray-200 dark:border-gray-700">
          <select
            className={selectClass}
            value={filters.category_id ?? ''}
            onChange={(e) => setFilters(prev => ({
              ...prev,
              category_id: e.target.value ? Number(e.target.value) : undefined,
              style_id: undefined,
              type_id: undefined,
              page: 1,
            }))}
          >
            <option value="">All Categories</option>
            {categoryOptions.map(c => (
              <option key={c.id} value={c.id}>{c.name}</option>
            ))}
          </select>

          {viewMode === 'table' && (
            <>
              <select
                className={selectClass}
                value={filters.style_id ?? ''}
                disabled={!filters.category_id}
                onChange={(e) => setFilters(prev => ({
                  ...prev,
                  style_id: e.target.value ? Number(e.target.value) : undefined,
                  type_id: undefined,
                  page: 1,
                }))}
              >
                <option value="">All Styles</option>
                {styleOptions.map(s => (
                  <option key={s.id} value={s.id}>{s.name}</option>
                ))}
              </select>

              <select
                className={selectClass}
                value={filters.type_id ?? ''}
                disabled={!filters.style_id}
                onChange={(e) => setFilters(prev => ({
                  ...prev,
                  type_id: e.target.value ? Number(e.target.value) : undefined,
                  page: 1,
                }))}
              >
                <option value="">All Types</option>
                {typeOptions.map(t => (
                  <option key={t.id} value={t.id}>{t.name}</option>
                ))}
              </select>

              <select
                className={selectClass}
                value={filters.color_id ?? ''}
                onChange={(e) => setFilters(prev => ({
                  ...prev,
                  color_id: e.target.value ? Number(e.target.value) : undefined,
                  page: 1,
                }))}
              >
                <option value="">All Colors</option>
                {colorOptions.map(c => (
                  <option key={c.id} value={c.id}>{c.name}</option>
                ))}
              </select>

              <div className="w-px bg-gray-300 dark:bg-gray-600 self-stretch" />

              <select
                className={selectClass}
                value={filters.part_type ?? ''}
                onChange={(e) => setFilters(prev => ({ ...prev, part_type: e.target.value || undefined, page: 1 }))}
              >
                <option value="">General + Specific</option>
                <option value="general">General Only</option>
                <option value="specific">Specific Only</option>
              </select>

              <select
                className={selectClass}
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

              <div className="w-px bg-gray-300 dark:bg-gray-600 self-stretch" />

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
                Low Stock
              </label>
            </>
          )}

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
            Deprecated
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

      {/* ══════════════════════════════════════════════════
          CONTENT — Card Grid or Table
          ══════════════════════════════════════════════════ */}
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
      ) : viewMode === 'cards' ? (
        /* ── CARD GRID VIEW ──────────────────────────── */
        <CardGridView
          groups={catalogGroups ?? []}
          canSeePricing={canSeePricing}
          searchText={searchText}
        />
      ) : (
        /* ── TABLE VIEW ──────────────────────────────── */
        <>
          <div className="text-sm text-gray-500 dark:text-gray-400">
            {total > 0 ? (
              <>Showing {(currentPage - 1) * (filters.page_size ?? 25) + 1}–{Math.min(currentPage * (filters.page_size ?? 25), total)} of {total} parts</>
            ) : (
              'No parts found'
            )}
          </div>

          <TableView
            items={items}
            canEdit={canEdit}
            canSeePricing={canSeePricing}
            handleSort={handleSort}
            SortIcon={SortIcon}
            formatDollars={formatDollars}
            onEdit={setEditingPart}
            onDelete={setDeleteConfirm}
            searchText={searchText}
          />

          {/* Pagination */}
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
        </>
      )}

      {/* ══════════════════════════════════════════════════
          MODALS — Edit Part + Delete Confirmation
          ══════════════════════════════════════════════════ */}

      {/* Edit Part (inline quick-edit for key fields) */}
      {editingPart && (
        <PartEditModal
          part={editingPart}
          onClose={() => setEditingPart(null)}
          onSave={(data) => updateMutation.mutate({ id: editingPart.id, data })}
          isLoading={updateMutation.isPending}
          error={updateMutation.isError ? (updateMutation.error as any)?.response?.data?.detail : null}
          canEdit={canEdit}
          canSeePricing={canSeePricing}
          onNavigateToCategories={() => navigate('/parts/categories')}
        />
      )}

      {/* Delete Confirmation */}
      {deleteConfirm && (
        <Modal isOpen={true} onClose={() => setDeleteConfirm(null)} title="Delete Part?" size="sm">
          <p className="text-gray-600 dark:text-gray-300 mb-4">
            Are you sure you want to delete <strong>{deleteConfirm.name}</strong>?
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


// ═══════════════════════════════════════════════════════════════════
// CARD GRID VIEW — grouped product cards
// ═══════════════════════════════════════════════════════════════════

interface CardGridViewProps {
  groups: CatalogGroup[];
  canSeePricing: boolean;
  searchText: string;
}

function CardGridView({ groups, canSeePricing, searchText }: CardGridViewProps) {
  const [expandedGroup, setExpandedGroup] = useState<string | null>(null);

  if (groups.length === 0) {
    return (
      <EmptyState
        icon={<Package className="h-12 w-12" />}
        title="No parts found"
        description={searchText ? "Try adjusting your search or filters." : "No parts in the catalog yet. Use the Categories page to create parts."}
      />
    );
  }

  const groupKey = (g: CatalogGroup) => `${g.category_id}-${g.brand_id ?? 'general'}`;

  return (
    <div>
      {/* Summary */}
      <div className="text-sm text-gray-500 dark:text-gray-400 mb-3">
        {groups.length} group{groups.length !== 1 ? 's' : ''} &middot;{' '}
        {groups.reduce((sum, g) => sum + g.variant_count, 0)} total variants
      </div>

      {/* Card grid */}
      <div className="grid grid-cols-1 md:grid-cols-2 xl:grid-cols-3 gap-4">
        {groups.map((group) => {
          const key = groupKey(group);
          const isExpanded = expandedGroup === key;

          return (
            <div
              key={key}
              className={`border rounded-xl transition-all ${
                isExpanded
                  ? 'border-primary-300 dark:border-primary-700 shadow-md col-span-full'
                  : 'border-gray-200 dark:border-gray-700 hover:shadow-md hover:border-gray-300 dark:hover:border-gray-600'
              } bg-white dark:bg-gray-800 overflow-hidden`}
            >
              {/* Card header */}
              <button
                className="w-full flex items-start gap-3 p-4 text-left"
                onClick={() => setExpandedGroup(isExpanded ? null : key)}
              >
                {/* Thumbnail placeholder */}
                <div className="w-14 h-14 rounded-lg bg-gray-100 dark:bg-gray-700 flex items-center justify-center flex-shrink-0">
                  {group.image_url ? (
                    <img
                      src={group.image_url}
                      alt=""
                      className="w-full h-full object-cover rounded-lg"
                    />
                  ) : (
                    <Box className="h-6 w-6 text-gray-400" />
                  )}
                </div>

                {/* Card body */}
                <div className="flex-1 min-w-0">
                  <div className="flex items-center gap-2 mb-0.5">
                    <h3 className="text-sm font-semibold text-gray-900 dark:text-gray-100 truncate">
                      {group.category_name}
                    </h3>
                    {group.brand_name ? (
                      <Badge variant="primary">{group.brand_name}</Badge>
                    ) : (
                      <Badge variant="default">General</Badge>
                    )}
                  </div>

                  <div className="flex items-center gap-4 text-xs text-gray-500 dark:text-gray-400">
                    <span>{group.variant_count} variant{group.variant_count !== 1 ? 's' : ''}</span>
                    <span>{group.total_stock} in stock</span>
                    {canSeePricing && group.price_range_low != null && (
                      <span>
                        ${group.price_range_low.toFixed(2)}
                        {group.price_range_high != null && group.price_range_high !== group.price_range_low && (
                          <>–${group.price_range_high.toFixed(2)}</>
                        )}
                      </span>
                    )}
                  </div>
                </div>

                {/* Expand indicator */}
                <div className="flex-shrink-0 pt-1">
                  {isExpanded ? (
                    <ChevronUp className="h-4 w-4 text-gray-400" />
                  ) : (
                    <ChevronDown className="h-4 w-4 text-gray-400" />
                  )}
                </div>
              </button>

              {/* Expanded variants table */}
              {isExpanded && (
                <div className="border-t border-gray-200 dark:border-gray-700">
                  <div className="overflow-x-auto">
                    <table className="w-full text-sm">
                      <thead>
                        <tr className="bg-gray-50 dark:bg-gray-800/80 border-b border-gray-200 dark:border-gray-700">
                          <th className="text-left px-3 py-2 font-medium text-gray-500 dark:text-gray-400 text-xs">Style</th>
                          <th className="text-left px-3 py-2 font-medium text-gray-500 dark:text-gray-400 text-xs">Type</th>
                          <th className="text-left px-3 py-2 font-medium text-gray-500 dark:text-gray-400 text-xs">Color</th>
                          <th className="text-left px-3 py-2 font-medium text-gray-500 dark:text-gray-400 text-xs">Name</th>
                          <th className="text-left px-3 py-2 font-medium text-gray-500 dark:text-gray-400 text-xs">Code</th>
                          <th className="text-right px-3 py-2 font-medium text-gray-500 dark:text-gray-400 text-xs">Stock</th>
                          {canSeePricing && (
                            <>
                              <th className="text-right px-3 py-2 font-medium text-gray-500 dark:text-gray-400 text-xs">Cost</th>
                              <th className="text-right px-3 py-2 font-medium text-gray-500 dark:text-gray-400 text-xs">Sell</th>
                            </>
                          )}
                          <th className="px-3 py-2 text-center text-xs font-medium text-gray-500 dark:text-gray-400">Status</th>
                        </tr>
                      </thead>
                      <tbody>
                        {group.variants.map((v) => (
                          <tr
                            key={v.id}
                            className="border-b border-gray-100 dark:border-gray-700/50 hover:bg-gray-50 dark:hover:bg-gray-700/30 transition-colors"
                          >
                            <td className="px-3 py-2 text-xs text-gray-600 dark:text-gray-400">{v.style_name ?? '—'}</td>
                            <td className="px-3 py-2 text-xs text-gray-600 dark:text-gray-400">{v.type_name ?? '—'}</td>
                            <td className="px-3 py-2 text-xs text-gray-600 dark:text-gray-400">{v.color_name ?? '—'}</td>
                            <td className="px-3 py-2 font-medium text-gray-900 dark:text-gray-100">{v.name}</td>
                            <td className="px-3 py-2 font-mono text-xs text-primary-600 dark:text-primary-400">
                              {v.code ?? <span className="text-gray-400">—</span>}
                            </td>
                            <td className="px-3 py-2 text-right font-medium">
                              <span className={v.total_stock <= 0 ? 'text-red-500' : 'text-gray-900 dark:text-gray-100'}>
                                {v.total_stock}
                              </span>
                            </td>
                            {canSeePricing && (
                              <>
                                <td className="px-3 py-2 text-right text-xs text-gray-600 dark:text-gray-400">
                                  {v.company_cost_price != null ? `$${v.company_cost_price.toFixed(2)}` : '---'}
                                </td>
                                <td className="px-3 py-2 text-right text-xs text-gray-600 dark:text-gray-400">
                                  {v.company_sell_price != null ? `$${v.company_sell_price.toFixed(2)}` : '---'}
                                </td>
                              </>
                            )}
                            <td className="px-3 py-2 text-center">
                              <div className="flex justify-center gap-1">
                                {v.has_pending_part_number && (
                                  <span title="Missing manufacturer part number">
                                    <AlertCircle className="h-3.5 w-3.5 text-amber-500" />
                                  </span>
                                )}
                                {v.is_deprecated && (
                                  <Badge variant="warning" className="text-[10px]">depr</Badge>
                                )}
                              </div>
                            </td>
                          </tr>
                        ))}
                      </tbody>
                    </table>
                  </div>
                </div>
              )}
            </div>
          );
        })}
      </div>
    </div>
  );
}


// ═══════════════════════════════════════════════════════════════════
// TABLE VIEW — flat paginated table
// ═══════════════════════════════════════════════════════════════════

interface TableViewProps {
  items: PartListItem[];
  canEdit: boolean;
  canSeePricing: boolean;
  handleSort: (column: string) => void;
  SortIcon: (props: { column: string }) => JSX.Element | null;
  formatDollars: (value: number | null) => string;
  onEdit: (part: PartListItem) => void;
  onDelete: (part: PartListItem) => void;
  searchText: string;
}

function TableView({ items, canEdit, canSeePricing, handleSort, SortIcon, formatDollars, onEdit, onDelete, searchText }: TableViewProps) {
  if (items.length === 0) {
    return (
      <EmptyState
        icon={<Package className="h-12 w-12" />}
        title="No parts found"
        description={searchText ? "Try adjusting your search or filters." : "No parts in the catalog yet. Use the Categories page to create parts."}
      />
    );
  }

  return (
    <div className="overflow-x-auto border border-gray-200 dark:border-gray-700 rounded-xl">
      <table className="w-full text-sm">
        <thead>
          <tr className="bg-gray-50 dark:bg-gray-800/80 border-b border-gray-200 dark:border-gray-700">
            <th className="text-left px-3 py-3 font-medium text-gray-600 dark:text-gray-400 cursor-pointer hover:text-gray-900 dark:hover:text-gray-200" onClick={() => handleSort('category_name')}>
              Category <SortIcon column="category_name" />
            </th>
            <th className="text-left px-3 py-3 font-medium text-gray-600 dark:text-gray-400 cursor-pointer hover:text-gray-900 dark:hover:text-gray-200" onClick={() => handleSort('style_name')}>
              Style <SortIcon column="style_name" />
            </th>
            <th className="text-left px-3 py-3 font-medium text-gray-600 dark:text-gray-400 cursor-pointer hover:text-gray-900 dark:hover:text-gray-200" onClick={() => handleSort('type_name')}>
              Type <SortIcon column="type_name" />
            </th>
            <th className="text-left px-3 py-3 font-medium text-gray-600 dark:text-gray-400 cursor-pointer hover:text-gray-900 dark:hover:text-gray-200" onClick={() => handleSort('color_name')}>
              Color <SortIcon column="color_name" />
            </th>
            <th className="text-left px-3 py-3 font-medium text-gray-600 dark:text-gray-400 cursor-pointer hover:text-gray-900 dark:hover:text-gray-200" onClick={() => handleSort('name')}>
              Name <SortIcon column="name" />
            </th>
            <th className="text-left px-3 py-3 font-medium text-gray-600 dark:text-gray-400 cursor-pointer hover:text-gray-900 dark:hover:text-gray-200" onClick={() => handleSort('code')}>
              Code <SortIcon column="code" />
            </th>
            <th className="text-left px-3 py-3 font-medium text-gray-600 dark:text-gray-400 cursor-pointer hover:text-gray-900 dark:hover:text-gray-200" onClick={() => handleSort('brand_name')}>
              Brand <SortIcon column="brand_name" />
            </th>
            <th className="text-right px-3 py-3 font-medium text-gray-600 dark:text-gray-400 cursor-pointer hover:text-gray-900 dark:hover:text-gray-200" onClick={() => handleSort('total_stock')}>
              Stock <SortIcon column="total_stock" />
            </th>
            {canSeePricing && (
              <>
                <th className="text-right px-3 py-3 font-medium text-gray-600 dark:text-gray-400 cursor-pointer hover:text-gray-900 dark:hover:text-gray-200" onClick={() => handleSort('company_cost_price')}>
                  Cost <SortIcon column="company_cost_price" />
                </th>
                <th className="text-right px-3 py-3 font-medium text-gray-600 dark:text-gray-400 cursor-pointer hover:text-gray-900 dark:hover:text-gray-200" onClick={() => handleSort('company_sell_price')}>
                  Sell <SortIcon column="company_sell_price" />
                </th>
              </>
            )}
            <th className="px-3 py-3 font-medium text-gray-600 dark:text-gray-400 text-center">
              Status
            </th>
            {canEdit && (
              <th className="px-3 py-3 font-medium text-gray-600 dark:text-gray-400 text-right">
                Actions
              </th>
            )}
          </tr>
        </thead>
        <tbody>
          {items.map((part) => (
            <tr
              key={part.id}
              className="border-b border-gray-100 dark:border-gray-700/50 hover:bg-primary-50/50 dark:hover:bg-primary-900/10 transition-colors"
            >
              <td className="px-3 py-2.5 text-gray-600 dark:text-gray-400 text-xs">{part.category_name ?? '—'}</td>
              <td className="px-3 py-2.5 text-gray-600 dark:text-gray-400 text-xs">{part.style_name ?? '—'}</td>
              <td className="px-3 py-2.5 text-gray-600 dark:text-gray-400 text-xs">{part.type_name ?? '—'}</td>
              <td className="px-3 py-2.5 text-gray-600 dark:text-gray-400 text-xs">{part.color_name ?? '—'}</td>
              <td className="px-3 py-2.5 font-medium text-gray-900 dark:text-gray-100">{part.name}</td>
              <td className="px-3 py-2.5 font-mono text-xs text-primary-600 dark:text-primary-400">
                {part.code ?? <span className="text-gray-400">—</span>}
              </td>
              <td className="px-3 py-2.5 text-gray-600 dark:text-gray-400 text-xs">{part.brand_name ?? '—'}</td>
              <td className="px-3 py-2.5 text-right font-medium">
                <span className={part.total_stock <= 0 ? 'text-red-500' : 'text-gray-900 dark:text-gray-100'}>
                  {part.total_stock}
                </span>
              </td>
              {canSeePricing && (
                <>
                  <td className="px-3 py-2.5 text-right text-gray-600 dark:text-gray-400 text-xs">{formatDollars(part.company_cost_price)}</td>
                  <td className="px-3 py-2.5 text-right text-gray-600 dark:text-gray-400 text-xs">{formatDollars(part.company_sell_price)}</td>
                </>
              )}
              <td className="px-3 py-2.5 text-center">
                <div className="flex justify-center gap-1">
                  {part.has_pending_part_number && (
                    <span title="Missing manufacturer part number">
                      <AlertCircle className="h-4 w-4 text-amber-500" />
                    </span>
                  )}
                  {part.is_deprecated && (
                    <Badge variant="warning">depr</Badge>
                  )}
                  {part.is_qr_tagged && (
                    <QrCode className="h-4 w-4 text-green-500" />
                  )}
                </div>
              </td>
              {canEdit && (
                <td className="px-3 py-2.5 text-right">
                  <div className="flex justify-end gap-1">
                    <button
                      className="p-1 rounded hover:bg-gray-200 dark:hover:bg-gray-700"
                      onClick={() => onEdit(part)}
                      title="Edit"
                    >
                      <Edit2 className="h-4 w-4 text-gray-500" />
                    </button>
                    <button
                      className="p-1 rounded hover:bg-red-100 dark:hover:bg-red-900/30"
                      onClick={() => onDelete(part)}
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
  );
}


// ═══════════════════════════════════════════════════════════════════
// Part Edit Modal — streamlined edit for key fields (no creation)
// ═══════════════════════════════════════════════════════════════════

interface PartEditModalProps {
  part: PartListItem;
  onClose: () => void;
  onSave: (data: PartUpdate) => void;
  isLoading: boolean;
  error?: string | null;
  canEdit: boolean;
  canSeePricing: boolean;
  onNavigateToCategories: () => void;
}

function PartEditModal({ part, onClose, onSave, isLoading, error, canEdit, canSeePricing, onNavigateToCategories }: PartEditModalProps) {
  const [name, setName] = useState(part.name);
  const [code, setCode] = useState(part.code ?? '');
  const [mpn, setMpn] = useState(part.manufacturer_part_number ?? '');
  const [costPrice, setCostPrice] = useState(part.company_cost_price != null ? String(part.company_cost_price) : '');
  const [markupPercent, setMarkupPercent] = useState(part.company_markup_percent != null ? String(part.company_markup_percent) : '');

  const isSpecific = part.part_type === 'specific';
  const computedSellPrice = costPrice && markupPercent
    ? (parseFloat(costPrice) * (1 + parseFloat(markupPercent) / 100)).toFixed(2)
    : part.company_sell_price?.toFixed(2) ?? '—';

  const handleSubmit = (e: React.FormEvent) => {
    e.preventDefault();
    onSave({
      name,
      code: code || undefined,
      manufacturer_part_number: mpn || undefined,
      company_cost_price: costPrice ? parseFloat(costPrice) : undefined,
      markup_percent: markupPercent ? parseFloat(markupPercent) : undefined,
    });
  };

  return (
    <Modal isOpen={true} onClose={onClose} title={`${canEdit ? 'Edit' : 'View'}: ${part.name}`} size="md">
      <form onSubmit={handleSubmit} className="space-y-4">
        {/* Hierarchy breadcrumb (read-only) */}
        <div className="flex items-center gap-2 text-sm text-gray-500 dark:text-gray-400 bg-gray-50 dark:bg-gray-800/50 rounded-lg px-3 py-2">
          <span>{part.category_name}</span>
          {part.style_name && <><span>&rarr;</span><span>{part.style_name}</span></>}
          {part.type_name && <><span>&rarr;</span><span>{part.type_name}</span></>}
          {part.color_name && <><span>&middot;</span><span>{part.color_name}</span></>}
          {part.brand_name && (
            <Badge variant="primary" className="ml-auto text-xs">{part.brand_name}</Badge>
          )}
          {!part.brand_name && (
            <Badge variant="default" className="ml-auto text-xs">General</Badge>
          )}
        </div>

        {/* Key editable fields */}
        <Input
          label="Name"
          value={name}
          onChange={(e) => setName(e.target.value)}
          disabled={!canEdit}
          required
        />

        <Input
          label="Code / SKU"
          value={code}
          onChange={(e) => setCode(e.target.value)}
          disabled={!canEdit}
          placeholder="Optional"
        />

        {isSpecific && (
          <Input
            label="Manufacturer Part Number (MPN)"
            value={mpn}
            onChange={(e) => setMpn(e.target.value)}
            disabled={!canEdit}
            placeholder={part.has_pending_part_number ? 'Pending — add MPN' : 'MPN'}
          />
        )}

        {/* Pricing summary */}
        {canSeePricing && (
          <div className="grid grid-cols-3 gap-3">
            <Input
              label="Cost"
              value={costPrice}
              onChange={(e) => setCostPrice(e.target.value)}
              disabled={!canEdit}
              type="number"
              step="0.01"
              min="0"
            />
            <Input
              label="Markup %"
              value={markupPercent}
              onChange={(e) => setMarkupPercent(e.target.value)}
              disabled={!canEdit}
              type="number"
              step="0.1"
              min="0"
            />
            <div className="space-y-1.5">
              <label className="block text-sm font-medium text-gray-700 dark:text-gray-300">Sell</label>
              <div className="px-3 py-2 rounded-lg bg-gray-100 dark:bg-gray-700 text-sm font-medium">
                ${computedSellPrice}
              </div>
            </div>
          </div>
        )}

        {/* Stock info (read-only) */}
        <div className="flex items-center gap-4 text-sm text-gray-600 dark:text-gray-400 border-t border-gray-200 dark:border-gray-700 pt-3">
          <span>Stock: <strong className={part.total_stock <= 0 ? 'text-red-500' : ''}>{part.total_stock}</strong></span>
          {part.is_deprecated && <Badge variant="danger">Deprecated</Badge>}
          {part.has_pending_part_number && (
            <span className="flex items-center gap-1 text-amber-500">
              <AlertCircle className="h-3.5 w-3.5" /> MPN needed
            </span>
          )}
        </div>

        {/* Alternatives (read-only summary) */}
        <div className="border-t border-gray-200 dark:border-gray-700 pt-3">
          <AlternativesSection partId={part.id} readOnly />
        </div>

        {error && (
          <div className="p-3 rounded-lg bg-red-50 dark:bg-red-900/20 border border-red-200 dark:border-red-800">
            <p className="text-sm text-red-600 dark:text-red-400">{error}</p>
          </div>
        )}

        <div className="flex items-center justify-between pt-2 border-t border-gray-200 dark:border-gray-700">
          <button
            type="button"
            className="text-sm text-primary-600 dark:text-primary-400 hover:underline flex items-center gap-1"
            onClick={onNavigateToCategories}
          >
            <FolderTree className="h-3.5 w-3.5" />
            Full edit in Categories
          </button>
          <div className="flex gap-2">
            <Button variant="secondary" type="button" onClick={onClose}>
              {canEdit ? 'Cancel' : 'Close'}
            </Button>
            {canEdit && (
              <Button type="submit" isLoading={isLoading}>
                Save Changes
              </Button>
            )}
          </div>
        </div>
      </form>
    </Modal>
  );
}
