/**
 * ManualTriggerPanel — "What Should I Also Order?" form.
 *
 * Lets users input category + style + qty rows, then generates
 * companion suggestions via the suggestion engine.
 */

import { useState } from 'react';
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import { Plus, Sparkles, Package } from 'lucide-react';
import { getHierarchy, generateCompanionSuggestions } from '../../../../api/parts';
import { TriggerItemRow } from './TriggerItemRow';
import { SuggestionCard } from './SuggestionCard';
import { Button } from '../../../../components/ui/Button';
import { EmptyState } from '../../../../components/ui/EmptyState';
import type { CompanionSuggestion, ManualTriggerItem } from '../../../../lib/types';

interface TriggerRow {
  category_id: number | '';
  style_id: number | '' | null;
  qty: number;
}

export function ManualTriggerPanel() {
  const queryClient = useQueryClient();
  const [rows, setRows] = useState<TriggerRow[]>([
    { category_id: '', style_id: null, qty: 1 },
    { category_id: '', style_id: null, qty: 1 },
  ]);
  const [results, setResults] = useState<CompanionSuggestion[]>([]);
  const [hasGenerated, setHasGenerated] = useState(false);

  // Hierarchy for pickers
  const { data: hierarchy } = useQuery({
    queryKey: ['hierarchy'],
    queryFn: getHierarchy,
    staleTime: 5 * 60 * 1000,
  });

  const categories = hierarchy?.categories ?? [];

  const getStylesForCategory = (catId: number | '') => {
    if (!catId) return [];
    const cat = categories.find((c) => c.id === catId);
    return cat?.styles ?? [];
  };

  // Generate mutation
  const generateMutation = useMutation({
    mutationFn: generateCompanionSuggestions,
    onSuccess: (data) => {
      setResults(data);
      setHasGenerated(true);
      queryClient.invalidateQueries({ queryKey: ['companion-suggestions'] });
      queryClient.invalidateQueries({ queryKey: ['companion-stats'] });
    },
  });

  const handleChange = (index: number, field: string, value: any) => {
    const updated = [...rows];
    updated[index] = { ...updated[index], [field]: value };
    // Reset style when category changes
    if (field === 'category_id') {
      updated[index].style_id = null;
    }
    setRows(updated);
  };

  const handleRemove = (index: number) => {
    if (rows.length <= 1) return;
    setRows(rows.filter((_, i) => i !== index));
  };

  const handleAdd = () => {
    setRows([...rows, { category_id: '', style_id: null, qty: 1 }]);
  };

  const handleGenerate = () => {
    const validItems: ManualTriggerItem[] = rows
      .filter((r) => r.category_id !== '')
      .map((r) => ({
        category_id: r.category_id as number,
        style_id: r.style_id ? (r.style_id as number) : undefined,
        qty: r.qty,
      }));

    if (validItems.length === 0) return;

    generateMutation.mutate({ items: validItems });
  };

  const validRowCount = rows.filter((r) => r.category_id !== '').length;

  return (
    <div className="space-y-6">
      {/* Input form */}
      <div>
        <p className="text-sm text-gray-600 dark:text-gray-400 mb-4">
          Enter the parts you're ordering, and the system will suggest companion
          items you might also need based on your defined rules.
        </p>

        <div className="space-y-2 mb-4">
          {rows.map((row, idx) => (
            <TriggerItemRow
              key={idx}
              index={idx}
              categoryId={row.category_id}
              styleId={row.style_id}
              qty={row.qty}
              categories={categories}
              styles={getStylesForCategory(row.category_id)}
              canRemove={rows.length > 1}
              onChange={handleChange}
              onRemove={handleRemove}
            />
          ))}
        </div>

        <div className="flex flex-col sm:flex-row items-stretch sm:items-center gap-3">
          <button
            onClick={handleAdd}
            className="text-sm text-primary-600 dark:text-primary-400 hover:underline flex items-center gap-1"
          >
            <Plus className="h-3.5 w-3.5" /> Add another item
          </button>

          <div className="flex-1" />

          <Button
            variant="primary"
            icon={<Sparkles className="h-4 w-4" />}
            onClick={handleGenerate}
            disabled={validRowCount === 0}
            isLoading={generateMutation.isPending}
          >
            Generate Suggestions
          </Button>
        </div>
      </div>

      {/* Results */}
      {hasGenerated && (
        <div className="border-t border-gray-200 dark:border-gray-700 pt-4">
          <h3 className="text-sm font-semibold text-gray-700 dark:text-gray-300 mb-3">
            Results
          </h3>

          {results.length === 0 ? (
            <EmptyState
              icon={<Package className="h-10 w-10" />}
              title="No suggestions found"
              description="No companion rules matched the categories you entered. Try adding rules in the 'Link Rules' tab."
              className="py-6"
            />
          ) : (
            <div className="space-y-3">
              {results.map((s) => (
                <SuggestionCard
                  key={s.id}
                  suggestion={s}
                  onDecide={() => {
                    // Decisions happen on the Suggestions tab
                  }}
                />
              ))}
              <p className="text-xs text-gray-500 dark:text-gray-400 text-center mt-2">
                Suggestions are now pending on the Suggestions tab.
              </p>
            </div>
          )}
        </div>
      )}
    </div>
  );
}
