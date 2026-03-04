/**
 * PartSearchModal — search-as-you-type modal for picking parts from the catalog.
 *
 * Used by the JPO creation form (and potentially any future form that needs
 * a "pick a part" flow). Searches hit GET /parts/catalog with a debounced
 * search param; already-added parts are grayed out to prevent duplicates.
 */

import { useState, useEffect, useRef, useCallback } from 'react';
import { useQuery } from '@tanstack/react-query';
import { Search, Package, Loader2 } from 'lucide-react';
import { Modal } from '../../../components/ui/Modal';
import { listParts } from '../../../api/parts';
import type { PartListItem } from '../../../lib/types';

interface PartSearchModalProps {
  isOpen: boolean;
  onClose: () => void;
  /** Called when user clicks a part — the caller adds it to form state */
  onSelect: (part: PartListItem) => void;
  /** Part IDs already in the form's line items — shown grayed-out */
  excludePartIds: number[];
}

export function PartSearchModal({
  isOpen,
  onClose,
  onSelect,
  excludePartIds,
}: PartSearchModalProps) {
  const [search, setSearch] = useState('');
  const [debouncedSearch, setDebouncedSearch] = useState('');
  const inputRef = useRef<HTMLInputElement>(null);

  // ── Debounce search input (300 ms) ─────────────────────────────
  useEffect(() => {
    const timer = setTimeout(() => setDebouncedSearch(search.trim()), 300);
    return () => clearTimeout(timer);
  }, [search]);

  // ── Auto-focus search input when modal opens ───────────────────
  useEffect(() => {
    if (isOpen) {
      // Small delay lets the modal animation settle before focusing
      const timer = setTimeout(() => inputRef.current?.focus(), 100);
      return () => clearTimeout(timer);
    }
    // Reset search when modal closes so it starts fresh next time
    setSearch('');
    setDebouncedSearch('');
  }, [isOpen]);

  // ── Fetch parts when debounced search has ≥2 characters ────────
  const { data, isLoading, isFetching } = useQuery({
    queryKey: ['part-search', debouncedSearch],
    queryFn: () => listParts({ search: debouncedSearch, page_size: 25 }),
    enabled: isOpen && debouncedSearch.length >= 2,
    staleTime: 30_000, // cache results for 30s so quick re-searches feel instant
  });

  const results = data?.items ?? [];
  const isExcluded = useCallback(
    (partId: number) => excludePartIds.includes(partId),
    [excludePartIds],
  );

  // ── Handle selecting a part ────────────────────────────────────
  const handleSelect = (part: PartListItem) => {
    if (isExcluded(part.id)) return;
    onSelect(part);
    onClose();
  };

  return (
    <Modal isOpen={isOpen} onClose={onClose} title="Search Parts" size="lg">
      {/* Search input */}
      <div className="relative mb-4">
        <Search className="absolute left-3 top-1/2 -translate-y-1/2 h-4 w-4 text-gray-400" />
        <input
          ref={inputRef}
          type="text"
          value={search}
          onChange={(e) => setSearch(e.target.value)}
          placeholder="Search by name, code, or brand…"
          className="w-full rounded-lg border border-gray-300 dark:border-gray-600 bg-white dark:bg-gray-800 pl-10 pr-4 py-2.5 text-sm text-gray-900 dark:text-gray-100 placeholder:text-gray-400 dark:placeholder:text-gray-500 focus:outline-none focus:ring-2 focus:ring-primary-300 focus:border-primary-500 transition-colors"
        />
        {isFetching && (
          <Loader2 className="absolute right-3 top-1/2 -translate-y-1/2 h-4 w-4 text-gray-400 animate-spin" />
        )}
      </div>

      {/* Results area */}
      <div className="min-h-[200px] max-h-[400px] overflow-y-auto -mx-2">
        {/* Prompt state: not enough characters typed */}
        {debouncedSearch.length < 2 && (
          <div className="flex flex-col items-center justify-center py-12 text-gray-400 dark:text-gray-500">
            <Package className="h-10 w-10 mb-2" />
            <p className="text-sm">Type at least 2 characters to search</p>
          </div>
        )}

        {/* Loading state */}
        {isLoading && debouncedSearch.length >= 2 && (
          <div className="flex items-center justify-center py-12">
            <Loader2 className="h-6 w-6 text-primary animate-spin" />
          </div>
        )}

        {/* No results */}
        {!isLoading && debouncedSearch.length >= 2 && results.length === 0 && (
          <div className="flex flex-col items-center justify-center py-12 text-gray-400 dark:text-gray-500">
            <Package className="h-10 w-10 mb-2" />
            <p className="text-sm">No parts found for &ldquo;{debouncedSearch}&rdquo;</p>
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
              className={`w-full text-left px-3 py-3 rounded-lg transition-colors ${
                excluded
                  ? 'opacity-50 cursor-not-allowed'
                  : 'hover:bg-gray-50 dark:hover:bg-gray-700/50 cursor-pointer'
              }`}
            >
              <div className="flex items-start justify-between gap-3">
                {/* Left: part info */}
                <div className="flex-1 min-w-0">
                  <div className="flex items-center gap-2 flex-wrap">
                    {part.code && (
                      <span className="text-xs font-mono bg-gray-100 dark:bg-gray-700 text-gray-600 dark:text-gray-300 px-1.5 py-0.5 rounded">
                        {part.code}
                      </span>
                    )}
                    <span className="text-sm font-medium text-gray-900 dark:text-gray-100 truncate">
                      {part.name}
                    </span>
                  </div>

                  <div className="mt-1 flex items-center gap-3 text-xs text-gray-500 dark:text-gray-400">
                    {part.brand_name && <span>{part.brand_name}</span>}
                    {part.category_name && <span>{part.category_name}</span>}
                  </div>
                </div>

                {/* Right: stock + unit OR "Already added" */}
                <div className="flex-shrink-0 text-right">
                  {excluded ? (
                    <span className="text-xs text-amber-600 dark:text-amber-400 font-medium">
                      Already added
                    </span>
                  ) : (
                    <>
                      <div className="text-sm font-medium text-gray-900 dark:text-gray-100">
                        {part.total_stock} {part.unit_of_measure}
                      </div>
                      <div className="text-xs text-gray-500 dark:text-gray-400">
                        in stock
                      </div>
                    </>
                  )}
                </div>
              </div>
            </button>
          );
        })}
      </div>
    </Modal>
  );
}
