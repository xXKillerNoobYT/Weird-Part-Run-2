/**
 * CatalogBrowser — inline catalog panel for browsing & adding parts.
 *
 * Used in the NewPartsRequestPage three-area layout on desktop.
 * Provides persistent search + optional category filter + scrollable
 * results. Parts already in the order are grayed out. Click a result
 * to add it to the order.
 *
 * On mobile, the parent page falls back to PartSearchModal instead.
 */

import { useState, useEffect, useRef, useCallback } from 'react';
import { useQuery } from '@tanstack/react-query';
import { Search, Package, Loader2, Filter } from 'lucide-react';
import { listParts, listCategories } from '../../../api/parts';
import type { PartListItem, PartCategory } from '../../../lib/types';

interface CatalogBrowserProps {
  /** Called when user clicks a part to add it */
  onSelect: (part: PartListItem) => void;
  /** IDs of parts already in the order — shown grayed-out */
  excludePartIds: number[];
}

export function CatalogBrowser({ onSelect, excludePartIds }: CatalogBrowserProps) {
  const [search, setSearch] = useState('');
  const [debouncedSearch, setDebouncedSearch] = useState('');
  const [categoryId, setCategoryId] = useState<number | undefined>(undefined);
  const [showCategoryFilter, setShowCategoryFilter] = useState(false);
  const inputRef = useRef<HTMLInputElement>(null);

  // ── Debounce search input (300 ms) ──────────────────────────────
  useEffect(() => {
    const timer = setTimeout(() => setDebouncedSearch(search.trim()), 300);
    return () => clearTimeout(timer);
  }, [search]);

  // ── Fetch categories for the filter dropdown ────────────────────
  const { data: categories = [] } = useQuery({
    queryKey: ['categories-active'],
    queryFn: () => listCategories({ is_active: true }),
    staleTime: 60_000,
  });

  // ── Fetch parts when search has ≥2 chars OR a category is selected
  const searchEnabled = debouncedSearch.length >= 2 || categoryId != null;
  const { data, isLoading, isFetching } = useQuery({
    queryKey: ['catalog-browse', debouncedSearch, categoryId],
    queryFn: () =>
      listParts({
        search: debouncedSearch || undefined,
        category_id: categoryId,
        page_size: 30,
      }),
    enabled: searchEnabled,
    staleTime: 30_000,
  });

  const results = data?.items ?? [];
  const isExcluded = useCallback(
    (partId: number) => excludePartIds.includes(partId),
    [excludePartIds],
  );

  const handleSelect = (part: PartListItem) => {
    if (isExcluded(part.id)) return;
    onSelect(part);
  };

  return (
    <div className="flex flex-col h-full">
      {/* ── Header ────────────────────────────────────────────── */}
      <div className="flex items-center gap-2 mb-3">
        <h3 className="text-sm font-semibold text-gray-900 dark:text-gray-100 flex-1">
          Parts Catalog
        </h3>
        <button
          type="button"
          onClick={() => setShowCategoryFilter(!showCategoryFilter)}
          className={`p-1.5 rounded-md transition-colors ${
            showCategoryFilter || categoryId
              ? 'bg-primary/10 text-primary'
              : 'text-gray-400 hover:text-gray-600 dark:hover:text-gray-300'
          }`}
          title="Filter by category"
        >
          <Filter className="h-4 w-4" />
        </button>
      </div>

      {/* ── Search input ──────────────────────────────────────── */}
      <div className="relative mb-2">
        <Search className="absolute left-3 top-1/2 -translate-y-1/2 h-4 w-4 text-gray-400" />
        <input
          ref={inputRef}
          type="text"
          value={search}
          onChange={(e) => setSearch(e.target.value)}
          placeholder="Search parts by name, code, brand…"
          className="w-full rounded-lg border border-gray-300 dark:border-gray-600 bg-white dark:bg-gray-800 pl-10 pr-4 py-2 text-sm text-gray-900 dark:text-gray-100 placeholder:text-gray-400 dark:placeholder:text-gray-500 focus:outline-none focus:ring-2 focus:ring-primary-300 focus:border-primary-500 transition-colors"
        />
        {isFetching && (
          <Loader2 className="absolute right-3 top-1/2 -translate-y-1/2 h-4 w-4 text-gray-400 animate-spin" />
        )}
      </div>

      {/* ── Category filter (collapsible) ─────────────────────── */}
      {showCategoryFilter && (
        <div className="mb-2">
          <select
            value={categoryId ?? ''}
            onChange={(e) =>
              setCategoryId(e.target.value ? Number(e.target.value) : undefined)
            }
            className="block w-full rounded-lg border border-gray-300 dark:border-gray-600 bg-white dark:bg-gray-800 px-3 py-1.5 text-xs text-gray-900 dark:text-gray-100 focus:outline-none focus:ring-2 focus:ring-primary-300 focus:border-primary-500 transition-colors"
          >
            <option value="">All Categories</option>
            {categories.map((cat: PartCategory) => (
              <option key={cat.id} value={cat.id}>
                {cat.name}
              </option>
            ))}
          </select>
        </div>
      )}

      {/* ── Results area ──────────────────────────────────────── */}
      <div className="flex-1 overflow-y-auto min-h-0 -mx-1">
        {/* Prompt state */}
        {!searchEnabled && (
          <div className="flex flex-col items-center justify-center py-10 text-gray-400 dark:text-gray-500">
            <Package className="h-8 w-8 mb-2" />
            <p className="text-xs text-center">
              Type at least 2 characters or
              <br />
              select a category to browse
            </p>
          </div>
        )}

        {/* Loading state */}
        {isLoading && searchEnabled && (
          <div className="flex items-center justify-center py-10">
            <Loader2 className="h-5 w-5 text-primary animate-spin" />
          </div>
        )}

        {/* No results */}
        {!isLoading && searchEnabled && results.length === 0 && (
          <div className="flex flex-col items-center justify-center py-10 text-gray-400 dark:text-gray-500">
            <Package className="h-8 w-8 mb-2" />
            <p className="text-xs">No parts found</p>
          </div>
        )}

        {/* Results list */}
        {results.map((part) => {
          const excluded = isExcluded(part.id);
          return (
            <button
              key={part.id}
              type="button"
              disabled={excluded}
              onClick={() => handleSelect(part)}
              className={`w-full text-left px-2 py-2.5 rounded-lg transition-colors ${
                excluded
                  ? 'opacity-40 cursor-not-allowed'
                  : 'hover:bg-gray-50 dark:hover:bg-gray-700/50 cursor-pointer'
              }`}
            >
              <div className="flex items-start justify-between gap-2">
                <div className="flex-1 min-w-0">
                  <div className="flex items-center gap-1.5 flex-wrap">
                    {part.code && (
                      <span className="text-[10px] font-mono bg-gray-100 dark:bg-gray-700 text-gray-600 dark:text-gray-300 px-1 py-0.5 rounded leading-none">
                        {part.code}
                      </span>
                    )}
                    <span className="text-xs font-medium text-gray-900 dark:text-gray-100 truncate">
                      {part.name}
                    </span>
                  </div>
                  <div className="mt-0.5 flex items-center gap-2 text-[10px] text-gray-500 dark:text-gray-400">
                    {part.brand_name && <span>{part.brand_name}</span>}
                    {part.category_name && <span>{part.category_name}</span>}
                  </div>
                </div>

                <div className="flex-shrink-0 text-right">
                  {excluded ? (
                    <span className="text-[10px] text-amber-600 dark:text-amber-400 font-medium">
                      Added
                    </span>
                  ) : (
                    <div className="text-[10px] text-gray-500 dark:text-gray-400">
                      {part.total_stock} {part.unit_of_measure}
                    </div>
                  )}
                </div>
              </div>
            </button>
          );
        })}
      </div>
    </div>
  );
}
