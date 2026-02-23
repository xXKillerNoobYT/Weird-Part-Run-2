/**
 * PricingPage — view and edit part pricing (cost, markup, sell price).
 *
 * Features:
 *  - Permission-gated: requires `show_dollar_values` to view, `edit_pricing` to edit
 *  - Inline editing of cost price and markup percentage
 *  - Auto-calculated sell price (preview before save)
 *  - Searchable and sortable table
 *  - Bulk visibility: see all pricing at a glance
 */

import { useState, useCallback } from 'react';
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import {
  DollarSign, Search, ChevronUp, ChevronDown, Check, X,
  AlertTriangle, ChevronLeft, ChevronRight, Lock,
} from 'lucide-react';
import { Button } from '../../../components/ui/Button';
import { Input } from '../../../components/ui/Input';
import { Badge } from '../../../components/ui/Badge';
import { Spinner } from '../../../components/ui/Spinner';
import { EmptyState } from '../../../components/ui/EmptyState';
import { useAuthStore } from '../../../stores/auth-store';
import { PERMISSIONS } from '../../../lib/constants';
import { listParts, updatePartPricing } from '../../../api/parts';
import type { PartListItem, PartSearchParams } from '../../../lib/types';


export function PricingPage() {
  const { hasPermission } = useAuthStore();
  const canSeePricing = hasPermission(PERMISSIONS.SHOW_DOLLAR_VALUES);
  const canEditPricing = hasPermission(PERMISSIONS.EDIT_PRICING);

  // ── Gate: must have show_dollar_values permission ──
  if (!canSeePricing) {
    return (
      <EmptyState
        icon={<Lock className="h-12 w-12" />}
        title="Permission Required"
        description="You need the 'Show Dollar Values' permission to view pricing information. Ask an admin for access."
      />
    );
  }

  return <PricingTable canEdit={canEditPricing} />;
}


// ═══════════════════════════════════════════════════════════════
// Inner component (avoids hook issues from conditional early return)
// ═══════════════════════════════════════════════════════════════

function PricingTable({ canEdit }: { canEdit: boolean }) {
  const queryClient = useQueryClient();

  // ── Search & sort state ──────────────────────────
  const [searchText, setSearchText] = useState('');
  const [filters, setFilters] = useState<PartSearchParams>({
    page: 1,
    page_size: 25,
    sort_by: 'name',
    sort_dir: 'asc',
  });

  // ── Inline edit state ────────────────────────────
  const [editingId, setEditingId] = useState<number | null>(null);
  const [editCost, setEditCost] = useState('');
  const [editMarkup, setEditMarkup] = useState('');

  // ── Query ────────────────────────────────────────
  const searchParams: PartSearchParams = {
    ...filters,
    search: searchText || undefined,
  };

  const { data: partsData, isLoading, error } = useQuery({
    queryKey: ['parts', searchParams],
    queryFn: () => listParts(searchParams),
  });

  // ── Mutation: inline price edit ──────────────────
  const pricingMutation = useMutation({
    mutationFn: ({ id, cost, markup }: { id: number; cost: number; markup: number }) =>
      updatePartPricing(id, { company_cost_price: cost, company_markup_percent: markup }),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['parts'] });
      setEditingId(null);
    },
  });

  // ── Sorting ──────────────────────────────────────
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

  // ── Inline edit helpers ──────────────────────────
  const startEditing = (part: PartListItem) => {
    setEditingId(part.id);
    setEditCost(String(part.company_cost_price ?? 0));
    setEditMarkup(String(part.company_markup_percent ?? 0));
  };

  const cancelEditing = () => {
    setEditingId(null);
    setEditCost('');
    setEditMarkup('');
  };

  const saveEditing = () => {
    if (editingId == null) return;
    const cost = parseFloat(editCost) || 0;
    const markup = parseFloat(editMarkup) || 0;
    pricingMutation.mutate({ id: editingId, cost, markup });
  };

  const editSellPreview = (parseFloat(editCost) || 0) * (1 + (parseFloat(editMarkup) || 0) / 100);

  // ── Format helpers ───────────────────────────────
  const fmt = (v: number | null) => v != null ? `$${v.toFixed(2)}` : '—';
  const fmtPct = (v: number | null) => v != null ? `${v.toFixed(1)}%` : '—';

  const items = partsData?.items ?? [];
  const total = partsData?.total ?? 0;
  const totalPages = partsData?.total_pages ?? 0;
  const currentPage = filters.page ?? 1;

  return (
    <div className="space-y-4">
      {/* ── Header ─────────────────────────────── */}
      <div className="flex flex-col sm:flex-row gap-3 items-start sm:items-center justify-between">
        <div className="flex-1 w-full sm:max-w-md">
          <Input
            placeholder="Search parts to view pricing..."
            icon={<Search className="h-4 w-4" />}
            value={searchText}
            onChange={(e) => {
              setSearchText(e.target.value);
              setFilters(prev => ({ ...prev, page: 1 }));
            }}
          />
        </div>
        {canEdit && (
          <Badge variant="success">
            <DollarSign className="h-3 w-3 mr-0.5" />
            Inline edit enabled
          </Badge>
        )}
      </div>

      {/* ── Results summary ────────────────────── */}
      <div className="text-sm text-gray-500 dark:text-gray-400">
        {total > 0 ? (
          <>Showing {(currentPage - 1) * (filters.page_size ?? 25) + 1}–{Math.min(currentPage * (filters.page_size ?? 25), total)} of {total} parts</>
        ) : isLoading ? 'Loading...' : 'No parts found'}
      </div>

      {/* ── Pricing Table ──────────────────────── */}
      {isLoading ? (
        <div className="flex justify-center py-12">
          <Spinner size="lg" />
        </div>
      ) : error ? (
        <EmptyState
          icon={<AlertTriangle className="h-12 w-12 text-red-400" />}
          title="Error loading pricing"
          description={String(error)}
        />
      ) : items.length === 0 ? (
        <EmptyState
          icon={<DollarSign className="h-12 w-12" />}
          title="No parts found"
          description="Add parts in the Catalog tab to manage pricing."
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
                  Part Name <SortIcon column="name" />
                </th>
                <th className="text-left px-4 py-3 font-medium text-gray-600 dark:text-gray-400">
                  Brand
                </th>
                <th className="text-left px-4 py-3 font-medium text-gray-600 dark:text-gray-400">
                  UoM
                </th>
                <th className="text-right px-4 py-3 font-medium text-gray-600 dark:text-gray-400 cursor-pointer hover:text-gray-900 dark:hover:text-gray-200" onClick={() => handleSort('company_cost_price')}>
                  Cost <SortIcon column="company_cost_price" />
                </th>
                <th className="text-right px-4 py-3 font-medium text-gray-600 dark:text-gray-400">
                  Markup
                </th>
                <th className="text-right px-4 py-3 font-medium text-gray-600 dark:text-gray-400 cursor-pointer hover:text-gray-900 dark:hover:text-gray-200" onClick={() => handleSort('company_sell_price')}>
                  Sell <SortIcon column="company_sell_price" />
                </th>
                <th className="text-right px-4 py-3 font-medium text-gray-600 dark:text-gray-400">
                  Margin
                </th>
                {canEdit && (
                  <th className="text-center px-4 py-3 font-medium text-gray-600 dark:text-gray-400">
                    Actions
                  </th>
                )}
              </tr>
            </thead>
            <tbody>
              {items.map((part) => {
                const isEditing = editingId === part.id;
                const cost = part.company_cost_price ?? 0;
                const sell = part.company_sell_price ?? 0;
                const margin = sell > 0 ? ((sell - cost) / sell * 100) : 0;

                return (
                  <tr
                    key={part.id}
                    className={`border-b border-gray-100 dark:border-gray-700/50 transition-colors ${
                      isEditing
                        ? 'bg-primary-50/50 dark:bg-primary-900/10'
                        : 'hover:bg-gray-50 dark:hover:bg-gray-800/30'
                    }`}
                  >
                    <td className="px-4 py-3 font-mono text-xs text-primary-600 dark:text-primary-400">
                      {part.code}
                    </td>
                    <td className="px-4 py-3 font-medium text-gray-900 dark:text-gray-100">
                      {part.name}
                    </td>
                    <td className="px-4 py-3 text-gray-600 dark:text-gray-400">
                      {part.brand_name ?? '—'}
                    </td>
                    <td className="px-4 py-3 text-gray-500 dark:text-gray-400">
                      {part.unit_of_measure}
                    </td>

                    {/* Cost */}
                    <td className="px-4 py-3 text-right">
                      {isEditing ? (
                        <input
                          type="number"
                          min="0"
                          step="0.01"
                          className="w-24 text-right rounded border border-primary-300 dark:border-primary-600 bg-white dark:bg-gray-800 px-2 py-1 text-sm"
                          value={editCost}
                          onChange={(e) => setEditCost(e.target.value)}
                          autoFocus
                        />
                      ) : (
                        <span className="text-gray-700 dark:text-gray-300">{fmt(part.company_cost_price)}</span>
                      )}
                    </td>

                    {/* Markup */}
                    <td className="px-4 py-3 text-right">
                      {isEditing ? (
                        <div className="inline-flex items-center gap-0.5">
                          <input
                            type="number"
                            min="0"
                            step="0.1"
                            className="w-20 text-right rounded border border-primary-300 dark:border-primary-600 bg-white dark:bg-gray-800 px-2 py-1 text-sm"
                            value={editMarkup}
                            onChange={(e) => setEditMarkup(e.target.value)}
                          />
                          <span className="text-gray-400 text-xs">%</span>
                        </div>
                      ) : (
                        <span className="text-gray-600 dark:text-gray-400">{fmtPct(part.company_markup_percent)}</span>
                      )}
                    </td>

                    {/* Sell */}
                    <td className="px-4 py-3 text-right font-medium">
                      {isEditing ? (
                        <span className="text-primary-600 dark:text-primary-400">
                          ${editSellPreview.toFixed(2)}
                        </span>
                      ) : (
                        <span className="text-gray-900 dark:text-gray-100">{fmt(part.company_sell_price)}</span>
                      )}
                    </td>

                    {/* Margin */}
                    <td className="px-4 py-3 text-right">
                      <Badge
                        variant={margin >= 30 ? 'success' : margin >= 15 ? 'warning' : 'danger'}
                      >
                        {margin.toFixed(1)}%
                      </Badge>
                    </td>

                    {/* Actions */}
                    {canEdit && (
                      <td className="px-4 py-3 text-center">
                        {isEditing ? (
                          <div className="flex justify-center gap-1">
                            <button
                              className="p-1 rounded hover:bg-green-100 dark:hover:bg-green-900/30"
                              onClick={saveEditing}
                              title="Save"
                            >
                              <Check className="h-4 w-4 text-green-600" />
                            </button>
                            <button
                              className="p-1 rounded hover:bg-gray-200 dark:hover:bg-gray-700"
                              onClick={cancelEditing}
                              title="Cancel"
                            >
                              <X className="h-4 w-4 text-gray-500" />
                            </button>
                          </div>
                        ) : (
                          <button
                            className="p-1 rounded hover:bg-gray-200 dark:hover:bg-gray-700"
                            onClick={() => startEditing(part)}
                            title="Edit pricing"
                          >
                            <DollarSign className="h-4 w-4 text-gray-500" />
                          </button>
                        )}
                      </td>
                    )}
                  </tr>
                );
              })}
            </tbody>
          </table>
        </div>
      )}

      {/* ── Pagination ─────────────────────────── */}
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

      {/* ── Inline edit mutation error ─────────── */}
      {pricingMutation.isError && (
        <div className="p-3 bg-red-50 dark:bg-red-900/20 border border-red-200 dark:border-red-800 rounded-lg text-sm text-red-600 dark:text-red-400">
          Failed to update pricing: {(pricingMutation.error as any)?.response?.data?.detail ?? 'Unknown error'}
        </div>
      )}
    </div>
  );
}
