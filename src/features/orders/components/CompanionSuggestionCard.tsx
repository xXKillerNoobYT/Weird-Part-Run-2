/**
 * CompanionSuggestionCard — compact card showing a companion suggestion
 * from the Link Rules engine.
 *
 * When collapsed: shows target description, qty, and reason.
 * When expanded: fetches & displays matching parts from the target
 * category so the user can quick-add them to the order.
 *
 * Used inside UnifiedOrderPage's right "Suggestions" panel.
 */

import { useState } from 'react';
import { useQuery } from '@tanstack/react-query';
import {
  Sparkles,
  ChevronDown,
  ChevronUp,
  Plus,
  Loader2,
  Check,
} from 'lucide-react';
import { listParts } from '../../../api/parts';
import type { CompanionSuggestion, PartListItem } from '../../../lib/types';


interface CompanionSuggestionCardProps {
  /** The companion suggestion from the engine */
  suggestion: CompanionSuggestion;
  /** Called when user clicks "+" on a matching part to add it to the order */
  onAdd: (part: PartListItem) => void;
  /** IDs of parts already in the order — shown as disabled / "Added" */
  excludePartIds: number[];
}

// ── Tiny stock dot (matches the one in UnifiedPartSearch) ───────────
function StockDot({ qty }: { qty: number }) {
  if (qty <= 0)
    return <span className="inline-block h-1.5 w-1.5 rounded-full bg-red-500 flex-shrink-0" title="Out of stock" />;
  if (qty <= 5)
    return <span className="inline-block h-1.5 w-1.5 rounded-full bg-amber-500 flex-shrink-0" title="Low stock" />;
  return <span className="inline-block h-1.5 w-1.5 rounded-full bg-green-500 flex-shrink-0" title="In stock" />;
}

// ── Reason-type badge color mapping ─────────────────────────────────
const REASON_COLORS: Record<string, string> = {
  rule:    'bg-violet-100 dark:bg-violet-900/30 text-violet-600 dark:text-violet-400',
  learned: 'bg-emerald-100 dark:bg-emerald-900/30 text-emerald-600 dark:text-emerald-400',
  mixed:   'bg-amber-100 dark:bg-amber-900/30 text-amber-600 dark:text-amber-400',
};


export function CompanionSuggestionCard({
  suggestion,
  onAdd,
  excludePartIds,
}: CompanionSuggestionCardProps) {
  const [expanded, setExpanded] = useState(false);

  // ── Fetch matching parts only when expanded ────────────────────────
  // Uses both category_id and style_id (when available) for precise results.
  const { data, isLoading } = useQuery({
    queryKey: [
      'companion-card-parts',
      suggestion.target_category_id,
      suggestion.target_style_id ?? null,
    ],
    queryFn: () =>
      listParts({
        category_id: suggestion.target_category_id,
        style_id: suggestion.target_style_id ?? undefined,
        page_size: 8,
      }),
    enabled: expanded,
    staleTime: 60_000,
  });

  const matchingParts = data?.items ?? [];

  const reasonColor =
    REASON_COLORS[suggestion.reason_type] ?? REASON_COLORS.mixed;

  // ── Source categories chip text (what triggered this suggestion) ────
  const sourceText =
    suggestion.sources.length > 0
      ? suggestion.sources
          .map((s) =>
            s.style_name
              ? `${s.category_name} › ${s.style_name}`
              : s.category_name ?? `Cat #${s.category_id}`,
          )
          .join(', ')
      : null;

  return (
    <div className="rounded-lg border border-violet-200 dark:border-violet-800/50 bg-violet-50/50 dark:bg-violet-900/10 overflow-hidden">
      {/* ── Clickable header ──────────────────────────────────── */}
      <button
        type="button"
        onClick={() => setExpanded(!expanded)}
        className="w-full text-left px-3 py-2.5 flex items-start gap-2 hover:bg-violet-50 dark:hover:bg-violet-900/20 transition-colors min-h-[44px]"
      >
        <Sparkles className="h-3.5 w-3.5 text-violet-500 flex-shrink-0 mt-0.5" />

        <div className="flex-1 min-w-0">
          {/* Target description (e.g. "Switches > Decora") */}
          <p className="text-xs font-medium text-gray-900 dark:text-gray-100 leading-tight truncate">
            {suggestion.target_description}
          </p>

          {/* Reason text (compact) */}
          <p className="text-[10px] text-gray-500 dark:text-gray-400 mt-0.5 leading-snug line-clamp-2">
            {suggestion.reason_text}
          </p>

          {/* Badges row */}
          <div className="flex items-center gap-1.5 mt-1 flex-wrap">
            <span
              className={`inline-block rounded px-1.5 py-0.5 text-[10px] font-medium leading-none ${reasonColor}`}
            >
              {suggestion.reason_type}
            </span>
            <span className="text-[10px] text-gray-400 dark:text-gray-500">
              Qty {suggestion.suggested_qty}
            </span>
          </div>

          {/* Source trigger (what in the cart caused this) */}
          {sourceText && (
            <p className="text-[10px] text-gray-400 dark:text-gray-500 mt-1 truncate">
              From: {sourceText}
            </p>
          )}
        </div>

        <span className="flex-shrink-0 mt-0.5">
          {expanded ? (
            <ChevronUp className="h-3.5 w-3.5 text-gray-400 dark:text-gray-500" />
          ) : (
            <ChevronDown className="h-3.5 w-3.5 text-gray-400 dark:text-gray-500" />
          )}
        </span>
      </button>

      {/* ── Expanded: matching parts mini-list ─────────────────── */}
      {expanded && (
        <div className="border-t border-violet-200 dark:border-violet-800/50">
          {isLoading ? (
            <div className="flex items-center justify-center py-4">
              <Loader2 className="h-4 w-4 animate-spin text-violet-400" />
            </div>
          ) : matchingParts.length === 0 ? (
            <p className="text-[10px] text-gray-500 dark:text-gray-400 text-center py-3 px-2">
              No parts found in this category
            </p>
          ) : (
            <ul className="divide-y divide-violet-100 dark:divide-violet-800/30 max-h-[200px] overflow-y-auto">
              {matchingParts.map((part) => {
                const alreadyAdded = excludePartIds.includes(part.id);
                return (
                  <li key={part.id}>
                    <button
                      type="button"
                      disabled={alreadyAdded}
                      onClick={() => onAdd(part)}
                      className={`w-full text-left px-3 py-2 flex items-center gap-2 transition-colors min-h-[40px] ${
                        alreadyAdded
                          ? 'opacity-40 cursor-not-allowed'
                          : 'hover:bg-violet-100/50 dark:hover:bg-violet-900/20 cursor-pointer'
                      }`}
                    >
                      <StockDot qty={part.total_stock} />
                      <div className="flex-1 min-w-0">
                        <p className="text-[11px] font-medium text-gray-900 dark:text-gray-100 truncate">
                          {part.name}
                        </p>
                        <p className="text-[10px] text-gray-500 dark:text-gray-400 truncate">
                          {part.code && `${part.code} · `}
                          {part.brand_name && `${part.brand_name} · `}
                          Stock: {part.total_stock}
                        </p>
                      </div>
                      {alreadyAdded ? (
                        <Check className="h-3.5 w-3.5 text-green-500 flex-shrink-0" />
                      ) : (
                        <Plus className="h-3.5 w-3.5 text-violet-500 flex-shrink-0" />
                      )}
                    </button>
                  </li>
                );
              })}
            </ul>
          )}
        </div>
      )}
    </div>
  );
}
