/**
 * SuggestionCard — individual companion suggestion with approve/discard actions.
 *
 * Shows source items, target description, suggested qty (editable),
 * reason text, and action buttons.
 */

import { useState } from 'react';
import { CheckCircle, XCircle, Info } from 'lucide-react';
import { Card } from '../../../../components/ui/Card';
import { Badge } from '../../../../components/ui/Badge';
import { Button } from '../../../../components/ui/Button';
import type { CompanionSuggestion } from '../../../../lib/types';

interface SuggestionCardProps {
  suggestion: CompanionSuggestion;
  onDecide: (id: number, action: 'approved' | 'discarded', qty?: number, notes?: string) => void;
  isDeciding?: boolean;
}

export function SuggestionCard({ suggestion, onDecide, isDeciding }: SuggestionCardProps) {
  const [qty, setQty] = useState(suggestion.suggested_qty);
  const [notes, setNotes] = useState('');
  const isPending = suggestion.status === 'pending';

  const statusVariant = {
    pending: 'warning' as const,
    approved: 'success' as const,
    discarded: 'danger' as const,
  }[suggestion.status];

  return (
    <Card className="p-4">
      {/* Header: Target + Status */}
      <div className="flex items-start justify-between gap-3 mb-3">
        <div className="min-w-0 flex-1">
          <div className="flex items-center gap-2 flex-wrap">
            <h4 className="font-semibold text-gray-900 dark:text-gray-100">
              {suggestion.suggested_qty}&times; {suggestion.target_description}
            </h4>
            <Badge variant={statusVariant}>{suggestion.status}</Badge>
          </div>
        </div>
      </div>

      {/* Source items */}
      <div className="mb-3">
        <p className="text-xs font-medium text-gray-500 dark:text-gray-400 mb-1">
          Triggered by:
        </p>
        <div className="flex flex-wrap gap-1.5">
          {suggestion.sources.map((src) => (
            <Badge key={src.id} variant="default">
              {src.qty}&times; {src.category_name}
              {src.style_name && ` (${src.style_name})`}
            </Badge>
          ))}
        </div>
      </div>

      {/* Reason */}
      <div className="flex items-start gap-2 mb-3 p-2.5 rounded-lg bg-blue-50 dark:bg-blue-900/20 border border-blue-100 dark:border-blue-800">
        <Info className="h-4 w-4 text-blue-500 dark:text-blue-400 mt-0.5 shrink-0" />
        <p className="text-xs text-blue-700 dark:text-blue-300">
          {suggestion.reason_text}
        </p>
      </div>

      {/* Actions (only for pending) */}
      {isPending && (
        <div className="flex flex-col sm:flex-row items-stretch sm:items-center gap-2 pt-2 border-t border-gray-100 dark:border-gray-700">
          {/* Qty override */}
          <div className="flex items-center gap-2">
            <label className="text-xs text-gray-500 dark:text-gray-400 whitespace-nowrap">
              Qty:
            </label>
            <input
              type="number"
              min={1}
              value={qty}
              onChange={(e) => setQty(Math.max(1, parseInt(e.target.value) || 1))}
              className="w-20 h-8 px-2 text-sm rounded-lg border border-gray-300 dark:border-gray-600 bg-white dark:bg-gray-800 text-gray-900 dark:text-gray-100 focus:outline-none focus:ring-2 focus:ring-primary-300"
            />
          </div>

          {/* Notes */}
          <input
            type="text"
            placeholder="Notes (optional)"
            value={notes}
            onChange={(e) => setNotes(e.target.value)}
            className="flex-1 h-8 px-2 text-sm rounded-lg border border-gray-300 dark:border-gray-600 bg-white dark:bg-gray-800 text-gray-900 dark:text-gray-100 placeholder:text-gray-400 focus:outline-none focus:ring-2 focus:ring-primary-300"
          />

          {/* Action buttons */}
          <div className="flex gap-2">
            <Button
              variant="primary"
              size="sm"
              icon={<CheckCircle className="h-4 w-4" />}
              isLoading={isDeciding}
              onClick={() => onDecide(suggestion.id, 'approved', qty, notes || undefined)}
            >
              Approve
            </Button>
            <Button
              variant="ghost"
              size="sm"
              icon={<XCircle className="h-4 w-4" />}
              isLoading={isDeciding}
              onClick={() => onDecide(suggestion.id, 'discarded', undefined, notes || undefined)}
            >
              Discard
            </Button>
          </div>
        </div>
      )}

      {/* Decided info (for history) */}
      {!isPending && suggestion.decided_at && (
        <div className="pt-2 border-t border-gray-100 dark:border-gray-700">
          <p className="text-xs text-gray-500 dark:text-gray-400">
            {suggestion.status === 'approved' ? 'Approved' : 'Discarded'}
            {suggestion.approved_qty && suggestion.approved_qty !== suggestion.suggested_qty && (
              <> (qty adjusted: {suggestion.suggested_qty} &rarr; {suggestion.approved_qty})</>
            )}
            {suggestion.notes && <> &mdash; {suggestion.notes}</>}
          </p>
        </div>
      )}
    </Card>
  );
}
