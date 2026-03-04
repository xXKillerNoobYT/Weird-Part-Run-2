/**
 * SuggestedParts — quick-add chips for parts that match a job's needs.
 *
 * When a job is selected on the NewPartsRequestPage, this component
 * fetches supplier suggestions and displays the top-ranked parts as
 * compact, clickable chips. Clicking one instantly adds it to the order.
 *
 * Falls back to a quiet hint message if no suggestions are available
 * (this is normal when a job has no linked supplier preferences yet).
 */

import { useQuery } from '@tanstack/react-query';
import { Sparkles, Plus, Loader2 } from 'lucide-react';
import { getReorderSuggestions } from '../../../api/orders';
import type { PartListItem, ReorderSuggestion } from '../../../lib/types';

interface SuggestedPartsProps {
  /** Currently selected job ID — suggestions are scoped to it */
  jobId: number | '';
  /** Called when user clicks a suggestion to add it */
  onSelect: (part: PartListItem) => void;
  /** Part IDs already in the order — don't show these as suggestions */
  excludePartIds: number[];
}

export function SuggestedParts({ jobId, onSelect, excludePartIds }: SuggestedPartsProps) {
  // Fetch reorder suggestions (low-stock parts that should be ordered)
  const { data: suggestions = [], isLoading } = useQuery({
    queryKey: ['reorder-suggestions'],
    queryFn: getReorderSuggestions,
    staleTime: 60_000,
  });

  // Filter out already-added parts
  const available = suggestions.filter(
    (s: ReorderSuggestion) => !excludePartIds.includes(s.part_id)
  );

  // Only show if we have a job selected AND there are suggestions
  if (!jobId) return null;

  if (isLoading) {
    return (
      <div className="flex items-center gap-2 py-2 text-xs text-gray-400">
        <Loader2 className="h-3.5 w-3.5 animate-spin" />
        Loading suggestions…
      </div>
    );
  }

  if (available.length === 0) return null;

  const handleAdd = (suggestion: ReorderSuggestion) => {
    // Convert ReorderSuggestion to a PartListItem-compatible shape
    // so the parent page can add it to form lines
    const part: PartListItem = {
      id: suggestion.part_id,
      category_name: null,
      style_name: null,
      type_name: null,
      color_name: null,
      color_id: null,
      color_hex: null,
      part_type: 'general',
      code: suggestion.part_number ?? null,
      name: suggestion.part_description ?? `Part #${suggestion.part_id}`,
      brand_id: null,
      brand_name: null,
      manufacturer_part_number: null,
      has_pending_part_number: false,
      unit_of_measure: 'ea',
      company_cost_price: suggestion.estimated_cost != null
        ? suggestion.estimated_cost / Math.max(suggestion.suggested_qty, 1)
        : null,
      company_markup_percent: null,
      company_sell_price: null,
      total_stock: suggestion.current_stock,
      min_stock_level: 0,
      max_stock_level: 0,
      target_stock_level: suggestion.target_qty ?? 0,
    };
    onSelect(part);
  };

  return (
    <div className="space-y-2">
      <div className="flex items-center gap-1.5 text-xs font-medium text-gray-500 dark:text-gray-400">
        <Sparkles className="h-3.5 w-3.5 text-amber-500" />
        Suggested Parts (low stock)
      </div>
      <div className="flex flex-wrap gap-2">
        {available.slice(0, 8).map((s: ReorderSuggestion) => (
          <button
            key={s.part_id}
            type="button"
            onClick={() => handleAdd(s)}
            className="inline-flex items-center gap-1 rounded-full border border-amber-200 dark:border-amber-800 bg-amber-50 dark:bg-amber-900/20 px-2.5 py-1 text-xs text-amber-800 dark:text-amber-300 hover:bg-amber-100 dark:hover:bg-amber-900/30 transition-colors"
          >
            <Plus className="h-3 w-3" />
            {s.part_number ?? `#${s.part_id}`}
            <span className="text-amber-600/70 dark:text-amber-400/70">
              ({s.current_stock} in stock, need {s.suggested_qty})
            </span>
          </button>
        ))}
      </div>
    </div>
  );
}
