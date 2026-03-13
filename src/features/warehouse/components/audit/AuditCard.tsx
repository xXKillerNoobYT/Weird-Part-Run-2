/**
 * AuditCard — large touch-friendly card for counting a single item.
 *
 * Shows part details, expected qty, and a numeric input for actual count.
 * Three action buttons: Match, Discrepancy, Skip.
 */

import { useState } from 'react';
import { useMutation, useQueryClient } from '@tanstack/react-query';
import {
  Check, AlertTriangle, SkipForward, Minus, Plus, MapPin,
} from 'lucide-react';
import { Card } from '../../../../components/ui/Card';
import { Button } from '../../../../components/ui/Button';
import { recordAuditCount } from '../../../../api/warehouse';
import type { AuditItemResponse } from '../../../../lib/types';

interface AuditCardProps {
  auditId: number;
  item: AuditItemResponse;
  onCounted: () => void;
}

export function AuditCard({ auditId, item, onCounted }: AuditCardProps) {
  const queryClient = useQueryClient();
  const [actualQty, setActualQty] = useState(item.expected_qty);
  const [note, setNote] = useState('');

  const mutation = useMutation({
    mutationFn: ({ result }: { result: 'match' | 'discrepancy' | 'skipped' }) =>
      recordAuditCount(auditId, item.id, {
        actual_qty: actualQty,
        result,
        discrepancy_note: result === 'discrepancy' && note ? note : undefined,
      }),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['audit', auditId] });
      queryClient.invalidateQueries({ queryKey: ['audit-next-item', auditId] });
      onCounted();
    },
  });

  const isMatch = actualQty === item.expected_qty;

  return (
    <Card className="max-w-lg mx-auto">
      {/* Part info */}
      <div className="text-center mb-6">
        <h3 className="text-xl font-bold text-gray-900 dark:text-gray-100">
          {item.part_name}
        </h3>
        {item.part_code && (
          <p className="text-sm text-gray-500 dark:text-gray-400 mt-1">
            {item.part_code}
          </p>
        )}
        {item.shelf_location && (
          <p className="text-sm text-gray-500 dark:text-gray-400 mt-2 flex items-center justify-center gap-1">
            <MapPin className="h-3.5 w-3.5" />
            {item.shelf_location}
          </p>
        )}
      </div>

      {/* Expected qty */}
      <div className="text-center mb-6 p-4 rounded-xl bg-gray-50 dark:bg-gray-900/50">
        <p className="text-sm text-gray-500 dark:text-gray-400 mb-1">Expected Quantity</p>
        <p className="text-4xl font-bold text-gray-900 dark:text-gray-100">
          {item.expected_qty}
        </p>
      </div>

      {/* Actual qty input */}
      <div className="text-center mb-6">
        <p className="text-sm text-gray-500 dark:text-gray-400 mb-3">Actual Count</p>
        <div className="flex items-center justify-center gap-4">
          <button
            onClick={() => setActualQty((q) => Math.max(0, q - 1))}
            className="p-3 rounded-full bg-gray-100 dark:bg-gray-700 hover:bg-gray-200 dark:hover:bg-gray-600 transition-colors"
          >
            <Minus className="h-5 w-5 text-gray-600 dark:text-gray-300" />
          </button>
          <input
            type="number"
            min={0}
            value={actualQty}
            onChange={(e) => setActualQty(Math.max(0, parseInt(e.target.value) || 0))}
            className="w-24 text-center text-4xl font-bold text-gray-900 dark:text-gray-100 bg-transparent border-b-2 border-gray-300 dark:border-gray-600 focus:border-primary-500 focus:outline-none"
          />
          <button
            onClick={() => setActualQty((q) => q + 1)}
            className="p-3 rounded-full bg-gray-100 dark:bg-gray-700 hover:bg-gray-200 dark:hover:bg-gray-600 transition-colors"
          >
            <Plus className="h-5 w-5 text-gray-600 dark:text-gray-300" />
          </button>
        </div>
      </div>

      {/* Discrepancy note (shown when count doesn't match) */}
      {!isMatch && (
        <div className="mb-6">
          <textarea
            placeholder="Note about discrepancy (optional)..."
            value={note}
            onChange={(e) => setNote(e.target.value)}
            rows={2}
            className="w-full px-3 py-2 rounded-lg border border-gray-300 dark:border-gray-600 bg-white dark:bg-gray-800 text-sm text-gray-900 dark:text-gray-100 placeholder:text-gray-400 dark:placeholder:text-gray-500 focus:outline-none focus:ring-2 focus:ring-primary-300"
          />
        </div>
      )}

      {/* Action buttons — large touch targets */}
      <div className="grid grid-cols-3 gap-3">
        <Button
          variant="primary"
          size="lg"
          icon={<Check className="h-5 w-5" />}
          onClick={() => mutation.mutate({ result: isMatch ? 'match' : 'discrepancy' })}
          isLoading={mutation.isPending}
          disabled={mutation.isPending}
          className={isMatch
            ? 'bg-green-500 hover:bg-green-600'
            : 'bg-amber-500 hover:bg-amber-600'
          }
        >
          {isMatch ? 'Match' : 'Log'}
        </Button>
        <Button
          variant="danger"
          size="lg"
          icon={<AlertTriangle className="h-5 w-5" />}
          onClick={() => mutation.mutate({ result: 'discrepancy' })}
          isLoading={mutation.isPending}
          disabled={mutation.isPending || isMatch}
        >
          Discrepancy
        </Button>
        <Button
          variant="secondary"
          size="lg"
          icon={<SkipForward className="h-5 w-5" />}
          onClick={() => mutation.mutate({ result: 'skipped' })}
          isLoading={mutation.isPending}
          disabled={mutation.isPending}
        >
          Skip
        </Button>
      </div>

      {mutation.error && (
        <p className="text-sm text-red-500 text-center mt-3">
          {(mutation.error as Error).message}
        </p>
      )}
    </Card>
  );
}
