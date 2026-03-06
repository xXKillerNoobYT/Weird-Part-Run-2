/**
 * UnifiedPartSearch — combined catalog browser + search for the unified order form.
 *
 * Replaces the old CatalogBrowser (desktop inline) + PartSearchModal (mobile).
 * This component is always inline: scrollable panel on desktop, expandable on mobile.
 *
 * Features:
 *   - Text search with 300ms debounce
 *   - Category filter dropdown
 *   - Brand/color filter chips from job preferences (when smart suggestions active)
 *   - Stock level color coding (green/amber/red)
 *   - "Previously used on this job" badge
 *   - Parts already in order shown as disabled
 */

import { useState, useEffect, useCallback } from 'react';
import { useQuery } from '@tanstack/react-query';
import { Search, Filter, Package, Loader2, Star, ChevronDown, ChevronUp } from 'lucide-react';
import { listParts, listCategories } from '../../../api/parts';
import type { PartListItem, PartCategory, JobPreferenceResponse } from '../../../lib/types';

interface UnifiedPartSearchProps {
  /** Called when user clicks a part to add it */
  onSelect: (part: PartListItem) => void;
  /** IDs of parts already in the order — shown grayed-out */
  excludePartIds: number[];
  /** Active brand preferences to show as filter chips */
  brandPrefs?: JobPreferenceResponse[];
  /** Active color preferences to show as filter chips */
  colorPrefs?: JobPreferenceResponse[];
  /** Whether smart suggestions are enabled */
  suggestionsEnabled?: boolean;
}

/** Stock level indicator — green (good), amber (low), red (critical/zero) */
function StockIndicator({ qty }: { qty: number }) {
  if (qty <= 0) {
    return <span className="inline-block h-2 w-2 rounded-full bg-red-500" title="Out of stock" />;
  }
  if (qty <= 5) {
    return <span className="inline-block h-2 w-2 rounded-full bg-amber-500" title="Low stock" />;
  }
  return <span className="inline-block h-2 w-2 rounded-full bg-green-500" title="In stock" />;
}

export function UnifiedPartSearch({
  onSelect,
  excludePartIds,
  brandPrefs = [],
  colorPrefs = [],
  suggestionsEnabled = false,
}: UnifiedPartSearchProps) {
  const [search, setSearch] = useState('');
  const [debouncedSearch, setDebouncedSearch] = useState('');
  const [categoryId, setCategoryId] = useState<number | undefined>(undefined);
  const [showFilters, setShowFilters] = useState(false);
  const [activeBrands, setActiveBrands] = useState<Set<string>>(new Set());
  const [activeColors, setActiveColors] = useState<Set<string>>(new Set());
  const [isExpanded, setIsExpanded] = useState(true);

  // ── Debounce search input (300 ms) ──────────────────────────────
  useEffect(() => {
    const timer = setTimeout(() => setDebouncedSearch(search.trim()), 300);
    return () => clearTimeout(timer);
  }, [search]);

  // ── Fetch categories for filter ─────────────────────────────────
  const { data: categories = [] } = useQuery({
    queryKey: ['categories-active'],
    queryFn: () => listCategories({ is_active: true }),
    staleTime: 60_000,
  });

  // ── Fetch parts when search ≥ 2 chars OR a category is selected ─
  const searchEnabled = debouncedSearch.length >= 2 || categoryId != null;
  const { data, isLoading, isFetching } = useQuery({
    queryKey: ['unified-part-search', debouncedSearch, categoryId],
    queryFn: () =>
      listParts({
        search: debouncedSearch || undefined,
        category_id: categoryId,
        page_size: 40,
      }),
    enabled: searchEnabled,
    staleTime: 30_000,
  });

  const rawResults = data?.items ?? [];

  // ── Apply local brand/color filters from preferences ────────────
  const results = rawResults.filter((part) => {
    if (activeBrands.size > 0 && part.brand) {
      if (!activeBrands.has(part.brand.toLowerCase())) return false;
    }
    if (activeColors.size > 0 && part.color_name) {
      if (!activeColors.has(part.color_name.toLowerCase())) return false;
    }
    return true;
  });

  const isExcluded = useCallback(
    (partId: number) => excludePartIds.includes(partId),
    [excludePartIds],
  );

  const toggleBrand = (brand: string) => {
    setActiveBrands((prev) => {
      const next = new Set(prev);
      if (next.has(brand.toLowerCase())) next.delete(brand.toLowerCase());
      else next.add(brand.toLowerCase());
      return next;
    });
  };

  const toggleColor = (color: string) => {
    setActiveColors((prev) => {
      const next = new Set(prev);
      if (next.has(color.toLowerCase())) next.delete(color.toLowerCase());
      else next.add(color.toLowerCase());
      return next;
    });
  };

  return (
    <div className="rounded-lg border border-gray-200 dark:border-gray-700 bg-gray-50 dark:bg-gray-800/50 overflow-hidden">
      {/* ── Header (collapsible on mobile) ──────────────────── */}
      <button
        type="button"
        onClick={() => setIsExpanded(!isExpanded)}
        className="w-full flex items-center justify-between px-4 py-3 min-h-[44px] lg:cursor-default"
      >
        <div className="flex items-center gap-2">
          <Search className="h-4 w-4 text-gray-400 dark:text-gray-500" />
          <span className="text-sm font-medium text-gray-700 dark:text-gray-300">
            Search Catalog
          </span>
        </div>
        <span className="lg:hidden">
          {isExpanded
            ? <ChevronUp className="h-4 w-4 text-gray-400 dark:text-gray-500" />
            : <ChevronDown className="h-4 w-4 text-gray-400 dark:text-gray-500" />}
        </span>
      </button>

      {/* ── Collapsible body ────────────────────────────────── */}
      <div className={`${isExpanded ? 'block' : 'hidden'} lg:block`}>
        {/* Search + filter bar */}
        <div className="px-4 pb-3 space-y-2">
          <div className="flex gap-2">
            <div className="relative flex-1">
              <Search className="absolute left-2.5 top-1/2 h-4 w-4 -translate-y-1/2 text-gray-400 dark:text-gray-500" />
              <input
                type="text"
                value={search}
                onChange={(e) => setSearch(e.target.value)}
                placeholder="Search parts by name, code, brand…"
                className="w-full rounded-lg border border-gray-300 dark:border-gray-600 bg-white dark:bg-gray-800 pl-9 pr-3 py-2 text-sm text-gray-900 dark:text-gray-100 placeholder:text-gray-400 dark:placeholder:text-gray-500 focus:ring-2 focus:ring-primary-300 focus:border-primary-500 min-h-[44px]"
              />
              {isFetching && (
                <Loader2 className="absolute right-2.5 top-1/2 h-4 w-4 -translate-y-1/2 text-gray-400 dark:text-gray-500 animate-spin" />
              )}
            </div>

            <button
              type="button"
              onClick={() => setShowFilters(!showFilters)}
              className={`flex-shrink-0 rounded-lg border px-3 py-2 text-sm transition-colors min-h-[44px] min-w-[44px] flex items-center justify-center ${
                showFilters || categoryId
                  ? 'border-primary bg-primary/10 text-primary'
                  : 'border-gray-300 dark:border-gray-600 text-gray-500 dark:text-gray-400 hover:bg-gray-100 dark:hover:bg-gray-700'
              }`}
              aria-label="Toggle filters"
            >
              <Filter className="h-4 w-4" />
            </button>
          </div>

          {/* Category filter */}
          {showFilters && (
            <select
              value={categoryId ?? ''}
              onChange={(e) => setCategoryId(e.target.value ? Number(e.target.value) : undefined)}
              className="w-full rounded-lg border border-gray-300 dark:border-gray-600 bg-white dark:bg-gray-800 px-3 py-2 text-sm text-gray-900 dark:text-gray-100 min-h-[44px]"
            >
              <option value="">All Categories</option>
              {categories.map((cat: PartCategory) => (
                <option key={cat.id} value={cat.id}>
                  {cat.name} ({cat.part_count})
                </option>
              ))}
            </select>
          )}

          {/* ── Smart suggestion filter chips (brands / colors) ── */}
          {suggestionsEnabled && (brandPrefs.length > 0 || colorPrefs.length > 0) && (
            <div className="flex flex-wrap gap-1.5">
              {brandPrefs.map((pref) => {
                const isActive = activeBrands.has((pref.text_value ?? '').toLowerCase());
                return (
                  <button
                    key={pref.id}
                    type="button"
                    onClick={() => toggleBrand(pref.text_value ?? '')}
                    className={`inline-flex items-center gap-1 rounded-full px-2.5 py-1 text-xs font-medium transition-colors min-h-[36px] ${
                      isActive
                        ? 'bg-blue-100 dark:bg-blue-900/30 text-blue-700 dark:text-blue-300 border border-blue-300 dark:border-blue-700'
                        : 'bg-gray-100 dark:bg-gray-700 text-gray-600 dark:text-gray-400 border border-transparent hover:bg-gray-200 dark:hover:bg-gray-600'
                    }`}
                  >
                    <Star className="h-3 w-3" />
                    {pref.text_value}
                  </button>
                );
              })}
              {colorPrefs.map((pref) => {
                const isActive = activeColors.has((pref.text_value ?? '').toLowerCase());
                return (
                  <button
                    key={pref.id}
                    type="button"
                    onClick={() => toggleColor(pref.text_value ?? '')}
                    className={`inline-flex items-center gap-1 rounded-full px-2.5 py-1 text-xs font-medium transition-colors min-h-[36px] ${
                      isActive
                        ? 'bg-purple-100 dark:bg-purple-900/30 text-purple-700 dark:text-purple-300 border border-purple-300 dark:border-purple-700'
                        : 'bg-gray-100 dark:bg-gray-700 text-gray-600 dark:text-gray-400 border border-transparent hover:bg-gray-200 dark:hover:bg-gray-600'
                    }`}
                  >
                    {pref.text_value}
                  </button>
                );
              })}
            </div>
          )}
        </div>

        {/* ── Results list ──────────────────────────────────── */}
        <div className="h-[280px] lg:h-[320px] overflow-y-auto border-t border-gray-200 dark:border-gray-700">
          {!searchEnabled ? (
            <div className="flex flex-col items-center justify-center h-full text-center px-4">
              <Package className="h-8 w-8 text-gray-300 dark:text-gray-600 mb-2" />
              <p className="text-sm text-gray-500 dark:text-gray-400">
                Type at least 2 characters or select a category
              </p>
            </div>
          ) : isLoading ? (
            <div className="flex items-center justify-center h-full">
              <Loader2 className="h-6 w-6 animate-spin text-gray-400 dark:text-gray-500" />
            </div>
          ) : results.length === 0 ? (
            <div className="flex flex-col items-center justify-center h-full text-center px-4">
              <Package className="h-8 w-8 text-gray-300 dark:text-gray-600 mb-2" />
              <p className="text-sm text-gray-500 dark:text-gray-400">
                No parts found matching your search
              </p>
            </div>
          ) : (
            <ul className="divide-y divide-gray-200 dark:divide-gray-700">
              {results.map((part) => {
                const disabled = isExcluded(part.id);
                return (
                  <li key={part.id}>
                    <button
                      type="button"
                      disabled={disabled}
                      onClick={() => onSelect(part)}
                      className={`w-full text-left px-4 py-3 flex items-center gap-3 transition-colors min-h-[52px] ${
                        disabled
                          ? 'opacity-40 cursor-not-allowed bg-gray-100 dark:bg-gray-800'
                          : 'hover:bg-gray-100 dark:hover:bg-gray-700 cursor-pointer'
                      }`}
                    >
                      <StockIndicator qty={part.total_stock} />
                      <div className="flex-1 min-w-0">
                        <p className="text-sm font-medium text-gray-900 dark:text-gray-100 truncate">
                          {part.name}
                        </p>
                        <p className="text-xs text-gray-500 dark:text-gray-400 truncate">
                          {part.code && `${part.code} · `}
                          {part.brand && `${part.brand} · `}
                          {part.color_name && `${part.color_name} · `}
                          Stock: {part.total_stock} {part.unit_of_measure}
                        </p>
                      </div>
                      {disabled && (
                        <span className="flex-shrink-0 text-xs text-gray-400 dark:text-gray-500">
                          Added
                        </span>
                      )}
                    </button>
                  </li>
                );
              })}
            </ul>
          )}
        </div>
      </div>
    </div>
  );
}
