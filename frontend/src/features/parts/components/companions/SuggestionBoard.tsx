/**
 * SuggestionBoard — pending suggestions list + history toggle.
 *
 * Fetches pending and historical suggestions, shows SuggestionCards
 * for pending items, and a collapsible history table for past decisions.
 */

import { useState } from 'react';
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import { ChevronDown, ChevronRight, History, Inbox } from 'lucide-react';
import { listCompanionSuggestions, decideCompanionSuggestion } from '../../../../api/parts';
import { SuggestionCard } from './SuggestionCard';
import { Spinner } from '../../../../components/ui/Spinner';
import { EmptyState } from '../../../../components/ui/EmptyState';
import type { CompanionSuggestion } from '../../../../lib/types';

export function SuggestionBoard() {
  const queryClient = useQueryClient();
  const [showHistory, setShowHistory] = useState(false);
  const [decidingId, setDecidingId] = useState<number | null>(null);

  // Pending suggestions
  const { data: pending = [], isLoading: pendingLoading } = useQuery({
    queryKey: ['companion-suggestions', 'pending'],
    queryFn: () => listCompanionSuggestions({ status: 'pending' }),
  });

  // History (only loaded when expanded)
  const { data: history = [], isLoading: historyLoading } = useQuery({
    queryKey: ['companion-suggestions', 'decided'],
    queryFn: () => listCompanionSuggestions({ status: undefined, page_size: 100 }),
    enabled: showHistory,
    select: (data) => data.filter((s) => s.status !== 'pending'),
  });

  // Decision mutation
  const decideMutation = useMutation({
    mutationFn: ({
      id,
      action,
      qty,
      notes,
    }: {
      id: number;
      action: 'approved' | 'discarded';
      qty?: number;
      notes?: string;
    }) =>
      decideCompanionSuggestion(id, {
        action,
        approved_qty: qty,
        notes,
      }),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['companion-suggestions'] });
      queryClient.invalidateQueries({ queryKey: ['companion-stats'] });
      setDecidingId(null);
    },
  });

  const handleDecide = (
    id: number,
    action: 'approved' | 'discarded',
    qty?: number,
    notes?: string,
  ) => {
    setDecidingId(id);
    decideMutation.mutate({ id, action, qty, notes });
  };

  return (
    <div className="space-y-4">
      {/* Pending section */}
      <div>
        <h3 className="text-sm font-semibold text-gray-700 dark:text-gray-300 mb-3 flex items-center gap-2">
          <Inbox className="h-4 w-4" />
          Pending Suggestions
          {pending.length > 0 && (
            <span className="text-xs font-normal text-gray-500 dark:text-gray-400">
              ({pending.length})
            </span>
          )}
        </h3>

        {pendingLoading ? (
          <div className="flex justify-center py-8">
            <Spinner />
          </div>
        ) : pending.length === 0 ? (
          <EmptyState
            icon={<Inbox className="h-12 w-12" />}
            title="No pending suggestions"
            description="Generate suggestions using the 'What Should I Also Order?' tab, or create rules in the 'Link Rules' tab."
            className="py-8"
          />
        ) : (
          <div className="space-y-3">
            {pending.map((s) => (
              <SuggestionCard
                key={s.id}
                suggestion={s}
                onDecide={handleDecide}
                isDeciding={decidingId === s.id && decideMutation.isPending}
              />
            ))}
          </div>
        )}
      </div>

      {/* History toggle */}
      <div className="border-t border-gray-200 dark:border-gray-700 pt-3">
        <button
          onClick={() => setShowHistory(!showHistory)}
          className="flex items-center gap-2 text-sm font-medium text-gray-600 dark:text-gray-400 hover:text-gray-900 dark:hover:text-gray-200 transition-colors"
        >
          {showHistory ? (
            <ChevronDown className="h-4 w-4" />
          ) : (
            <ChevronRight className="h-4 w-4" />
          )}
          <History className="h-4 w-4" />
          History
        </button>

        {showHistory && (
          <div className="mt-3">
            {historyLoading ? (
              <div className="flex justify-center py-4">
                <Spinner />
              </div>
            ) : history.length === 0 ? (
              <p className="text-sm text-gray-500 dark:text-gray-400 py-4 text-center">
                No past decisions yet.
              </p>
            ) : (
              <div className="space-y-2">
                {history.map((s) => (
                  <SuggestionCard
                    key={s.id}
                    suggestion={s}
                    onDecide={handleDecide}
                  />
                ))}
              </div>
            )}
          </div>
        )}
      </div>
    </div>
  );
}
