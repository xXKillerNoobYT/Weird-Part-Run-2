/**
 * WarehouseExecPage — management spreadsheet for warehouse executives.
 *
 * Provides a tabular view of ALL parts with inline-editable fields:
 *   - Pricing: cost, markup %, auto-computed sell (permission-gated)
 *   - Warehouse stock count (manual override via audit adjustment)
 *   - Min / Target / Max inventory levels
 *
 * Uses the same backend list-parts API but renders a dense, editable table
 * instead of the catalog card/list views.
 */

import { useState, useCallback, useRef, useEffect } from 'react';
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import {
  Save, Search, ChevronDown, ChevronUp, Filter,
  DollarSign, Target, Warehouse, Package, Check, X,
} from 'lucide-react';
import { Card, CardHeader } from '../../../components/ui/Card';
import { Button } from '../../../components/ui/Button';
import { Input } from '../../../components/ui/Input';
import { Badge } from '../../../components/ui/Badge';
import { Spinner } from '../../../components/ui/Spinner';
import { listParts, updatePart, updatePartPricing } from '../../../api/parts';
import { useAuthStore } from '../../../stores/auth-store';
import { cn } from '../../../lib/utils';
import type { PartListItem, PartSearchParams, PartUpdate, PartPricingUpdate } from '../../../lib/types';


// ── Inline-editable cell ─────────────────────────────────────────

interface EditableCellProps {
  value: string | number | null;
  partId: number;
  field: string;
  type?: 'number' | 'text';
  step?: string;
  min?: string;
  disabled?: boolean;
  onSave: (partId: number, field: string, value: string) => void;
}

function EditableCell({
  value, partId, field, type = 'number', step = '1', min = '0',
  disabled = false, onSave,
}: EditableCellProps) {
  const [editing, setEditing] = useState(false);
  const [localValue, setLocalValue] = useState(String(value ?? ''));
  const inputRef = useRef<HTMLInputElement>(null);

  // Sync when external value changes
  useEffect(() => {
    if (!editing) setLocalValue(String(value ?? ''));
  }, [value, editing]);

  useEffect(() => {
    if (editing && inputRef.current) {
      inputRef.current.focus();
      inputRef.current.select();
    }
  }, [editing]);

  const commit = () => {
    setEditing(false);
    if (localValue !== String(value ?? '')) {
      onSave(partId, field, localValue);
    }
  };

  const cancel = () => {
    setEditing(false);
    setLocalValue(String(value ?? ''));
  };

  if (disabled) {
    return (
      <span className="text-sm text-gray-500 dark:text-gray-400 tabular-nums">
        {value ?? '—'}
      </span>
    );
  }

  if (!editing) {
    return (
      <button
        className="text-sm text-gray-900 dark:text-gray-100 tabular-nums px-2 py-1 -mx-2 -my-1 rounded hover:bg-primary-50 dark:hover:bg-primary-900/20 transition-colors w-full text-right cursor-text"
        onClick={() => setEditing(true)}
        title="Click to edit"
      >
        {value != null && value !== '' && value !== 0 ? value : '—'}
      </button>
    );
  }

  return (
    <input
      ref={inputRef}
      type={type}
      step={step}
      min={min}
      className="w-full text-sm text-right tabular-nums px-2 py-1 -mx-2 -my-1 rounded border border-primary-300 dark:border-primary-600 bg-white dark:bg-gray-800 text-gray-900 dark:text-gray-100 outline-none focus:ring-2 focus:ring-primary-300"
      value={localValue}
      onChange={(e) => setLocalValue(e.target.value)}
      onBlur={commit}
      onKeyDown={(e) => {
        if (e.key === 'Enter') commit();
        if (e.key === 'Escape') cancel();
        // Tab will trigger blur → commit
      }}
    />
  );
}


// ── Main Page ────────────────────────────────────────────────────

export function WarehouseExecPage() {
  const queryClient = useQueryClient();
  const { user } = useAuthStore();
  const showDollars = user?.permissions.includes('show_dollar_values') ?? false;
  const canEdit = user?.permissions.includes('manage_warehouse') ?? false;

  // Filters
  const [search, setSearch] = useState('');
  const [debouncedSearch, setDebouncedSearch] = useState('');
  const [sortBy, setSortBy] = useState('name');
  const [sortDir, setSortDir] = useState<'asc' | 'desc'>('asc');
  const [page, setPage] = useState(1);
  const pageSize = 50;

  // Debounce search
  useEffect(() => {
    const timer = setTimeout(() => {
      setDebouncedSearch(search);
      setPage(1);
    }, 300);
    return () => clearTimeout(timer);
  }, [search]);

  const params: PartSearchParams = {
    search: debouncedSearch || undefined,
    sort_by: sortBy,
    sort_dir: sortDir,
    page,
    page_size: pageSize,
  };

  const { data, isLoading } = useQuery({
    queryKey: ['office-exec-parts', params],
    queryFn: () => listParts(params),
    staleTime: 10_000,
  });

  const parts = data?.items ?? [];
  const total = data?.total ?? 0;
  const totalPages = data?.total_pages ?? 0;

  // ── Mutations ──────────────────────────────────────────────────

  const updateMut = useMutation({
    mutationFn: ({ partId, updates }: { partId: number; updates: PartUpdate }) =>
      updatePart(partId, updates),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['office-exec-parts'] });
    },
  });

  const pricingMut = useMutation({
    mutationFn: ({ partId, pricing }: { partId: number; pricing: PartPricingUpdate }) =>
      updatePartPricing(partId, pricing),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['office-exec-parts'] });
    },
  });

  const handleCellSave = useCallback((partId: number, field: string, value: string) => {
    const numVal = value ? parseFloat(value) : 0;

    // Pricing fields go through the pricing endpoint
    if (field === 'company_cost_price' || field === 'company_markup_percent') {
      // Find current part to get the other pricing value
      const part = parts.find((p) => p.id === partId);
      if (!part) return;

      const pricing: PartPricingUpdate = {
        company_cost_price: field === 'company_cost_price'
          ? numVal
          : (part.company_cost_price ?? 0),
        company_markup_percent: field === 'company_markup_percent'
          ? numVal
          : (part.company_markup_percent ?? 0),
      };
      pricingMut.mutate({ partId, pricing });
      return;
    }

    // Stock target fields go through the regular update endpoint
    const updates: PartUpdate = { [field]: Math.max(0, Math.round(numVal)) };
    updateMut.mutate({ partId, updates });
  }, [parts, pricingMut, updateMut]);

  // ── Sort toggle ────────────────────────────────────────────────

  const toggleSort = (col: string) => {
    if (sortBy === col) {
      setSortDir((d) => d === 'asc' ? 'desc' : 'asc');
    } else {
      setSortBy(col);
      setSortDir('asc');
    }
    setPage(1);
  };

  const SortIcon = ({ col }: { col: string }) => {
    if (sortBy !== col) return null;
    return sortDir === 'asc'
      ? <ChevronUp className="h-3 w-3 inline ml-0.5" />
      : <ChevronDown className="h-3 w-3 inline ml-0.5" />;
  };

  // ── Render ─────────────────────────────────────────────────────

  return (
    <div className="space-y-4">
      {/* Search bar */}
      <div className="flex items-center gap-3">
        <div className="relative flex-1 max-w-md">
          <Search className="absolute left-3 top-1/2 -translate-y-1/2 h-4 w-4 text-gray-400" />
          <input
            type="text"
            placeholder="Search parts by name, code, category..."
            className="w-full pl-10 pr-4 py-2 rounded-lg border border-gray-300 dark:border-gray-600 bg-white dark:bg-gray-800 text-sm text-gray-900 dark:text-gray-100 placeholder:text-gray-400 dark:placeholder:text-gray-500 focus:outline-none focus:ring-2 focus:ring-primary-300"
            value={search}
            onChange={(e) => setSearch(e.target.value)}
          />
        </div>
        <Badge variant="default">{total} parts</Badge>
        {(updateMut.isPending || pricingMut.isPending) && (
          <Badge variant="warning">Saving...</Badge>
        )}
      </div>

      {/* Table */}
      <Card className="overflow-hidden">
        <div className="overflow-x-auto">
          <table className="w-full text-sm">
            <thead>
              <tr className="bg-gray-50 dark:bg-gray-800/80 border-b border-gray-200 dark:border-gray-700">
                <th className="text-left px-3 py-2.5 font-medium text-gray-600 dark:text-gray-300 cursor-pointer select-none" onClick={() => toggleSort('name')}>
                  Part <SortIcon col="name" />
                </th>
                <th className="text-left px-3 py-2.5 font-medium text-gray-600 dark:text-gray-300 cursor-pointer select-none" onClick={() => toggleSort('category')}>
                  Category <SortIcon col="category" />
                </th>
                <th className="text-left px-3 py-2.5 font-medium text-gray-600 dark:text-gray-300">
                  Brand
                </th>
                {showDollars && (
                  <>
                    <th className="text-right px-3 py-2.5 font-medium text-gray-600 dark:text-gray-300 w-24">
                      Cost
                    </th>
                    <th className="text-right px-3 py-2.5 font-medium text-gray-600 dark:text-gray-300 w-20">
                      Markup %
                    </th>
                    <th className="text-right px-3 py-2.5 font-medium text-gray-600 dark:text-gray-300 w-24">
                      Sell
                    </th>
                  </>
                )}
                <th className="text-right px-3 py-2.5 font-medium text-gray-600 dark:text-gray-300 w-20">
                  Stock
                </th>
                <th className="text-right px-3 py-2.5 font-medium text-gray-600 dark:text-gray-300 w-16">
                  Min
                </th>
                <th className="text-right px-3 py-2.5 font-medium text-gray-600 dark:text-gray-300 w-16">
                  Target
                </th>
                <th className="text-right px-3 py-2.5 font-medium text-gray-600 dark:text-gray-300 w-16">
                  Max
                </th>
              </tr>
            </thead>
            <tbody className="divide-y divide-gray-100 dark:divide-gray-800">
              {isLoading ? (
                <tr>
                  <td colSpan={showDollars ? 10 : 7} className="text-center py-12">
                    <Spinner label="Loading parts..." />
                  </td>
                </tr>
              ) : parts.length === 0 ? (
                <tr>
                  <td colSpan={showDollars ? 10 : 7} className="text-center py-12 text-gray-500 dark:text-gray-400">
                    No parts found
                  </td>
                </tr>
              ) : (
                parts.map((part) => {
                  const computedSell = (part.company_cost_price ?? 0) *
                    (1 + (part.company_markup_percent ?? 0) / 100);
                  const stockStatus = part.total_stock < part.min_stock_level
                    ? 'low' : part.total_stock > part.max_stock_level
                    ? 'over' : 'ok';

                  return (
                    <tr
                      key={part.id}
                      className="hover:bg-gray-50 dark:hover:bg-gray-800/50 transition-colors"
                    >
                      {/* Part name + code */}
                      <td className="px-3 py-2">
                        <div className="flex items-center gap-2 min-w-0">
                          {part.color_hex && (
                            <span
                              className="inline-block w-3 h-3 rounded-full border border-gray-300 dark:border-gray-600 shrink-0"
                              style={{ backgroundColor: part.color_hex }}
                            />
                          )}
                          <div className="min-w-0">
                            <p className="font-medium text-gray-900 dark:text-gray-100 truncate">
                              {part.name}
                            </p>
                            {part.code && (
                              <p className="text-xs text-gray-500 dark:text-gray-400">{part.code}</p>
                            )}
                          </div>
                        </div>
                      </td>

                      {/* Category */}
                      <td className="px-3 py-2 text-gray-600 dark:text-gray-400 truncate max-w-[150px]">
                        {part.category_name ?? '—'}
                      </td>

                      {/* Brand */}
                      <td className="px-3 py-2 text-gray-600 dark:text-gray-400 truncate max-w-[120px]">
                        {part.brand_name ?? 'General'}
                      </td>

                      {/* Pricing (permission-gated) */}
                      {showDollars && (
                        <>
                          <td className="px-3 py-2 text-right">
                            <EditableCell
                              value={part.company_cost_price}
                              partId={part.id}
                              field="company_cost_price"
                              step="0.01"
                              disabled={!canEdit}
                              onSave={handleCellSave}
                            />
                          </td>
                          <td className="px-3 py-2 text-right">
                            <EditableCell
                              value={part.company_markup_percent}
                              partId={part.id}
                              field="company_markup_percent"
                              step="0.1"
                              disabled={!canEdit}
                              onSave={handleCellSave}
                            />
                          </td>
                          <td className="px-3 py-2 text-right">
                            <span className="text-sm tabular-nums text-gray-700 dark:text-gray-300">
                              ${computedSell.toFixed(2)}
                            </span>
                          </td>
                        </>
                      )}

                      {/* Stock (read-only) */}
                      <td className="px-3 py-2 text-right">
                        <span className={cn(
                          'text-sm font-medium tabular-nums',
                          part.total_stock === 0
                            ? 'text-red-500'
                            : 'text-gray-900 dark:text-gray-100',
                        )}>
                          {part.total_stock}
                        </span>
                      </td>

                      {/* Min */}
                      <td className="px-3 py-2 text-right">
                        <EditableCell
                          value={part.min_stock_level ?? 0}
                          partId={part.id}
                          field="min_stock_level"
                          disabled={!canEdit}
                          onSave={handleCellSave}
                        />
                      </td>

                      {/* Target */}
                      <td className="px-3 py-2 text-right">
                        <EditableCell
                          value={part.target_stock_level ?? 0}
                          partId={part.id}
                          field="target_stock_level"
                          disabled={!canEdit}
                          onSave={handleCellSave}
                        />
                      </td>

                      {/* Max */}
                      <td className="px-3 py-2 text-right">
                        <EditableCell
                          value={part.max_stock_level ?? 0}
                          partId={part.id}
                          field="max_stock_level"
                          disabled={!canEdit}
                          onSave={handleCellSave}
                        />
                      </td>
                    </tr>
                  );
                })
              )}
            </tbody>
          </table>
        </div>

        {/* Pagination */}
        {totalPages > 1 && (
          <div className="flex items-center justify-between px-4 py-3 border-t border-gray-200 dark:border-gray-700">
            <p className="text-sm text-gray-500 dark:text-gray-400">
              Page {page} of {totalPages} ({total} parts)
            </p>
            <div className="flex gap-2">
              <Button
                size="sm"
                variant="secondary"
                disabled={page <= 1}
                onClick={() => setPage((p) => Math.max(1, p - 1))}
              >
                Previous
              </Button>
              <Button
                size="sm"
                variant="secondary"
                disabled={page >= totalPages}
                onClick={() => setPage((p) => p + 1)}
              >
                Next
              </Button>
            </div>
          </div>
        )}
      </Card>
    </div>
  );
}
