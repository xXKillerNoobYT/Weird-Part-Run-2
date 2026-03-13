/**
 * CustomerDedupModal — scanning for duplicate customers and merging them.
 *
 * Uses backend Jaccard similarity on name words + exact email matching.
 * For each duplicate pair, user picks which record to KEEP. The other
 * is deactivated and its jobs + contacts re-pointed to the keeper.
 */

import { useState } from 'react';
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import {
  ArrowRight, CheckCircle2, AlertTriangle, Search, Merge, Loader2,
} from 'lucide-react';
import { Modal } from '../../../components/ui/Modal';
import { Button } from '../../../components/ui/Button';
import { Badge } from '../../../components/ui/Badge';
import { Card } from '../../../components/ui/Card';
import { findDuplicateCustomers, mergeCustomers } from '../../../api/contacts';
import type { DuplicatePair } from '../../../api/contacts';
import { toast } from '../../../lib/toast';


interface CustomerDedupModalProps {
  onClose: () => void;
  onMerged: () => void;
}

export function CustomerDedupModal({ onClose, onMerged }: CustomerDedupModalProps) {
  const queryClient = useQueryClient();
  const [threshold, setThreshold] = useState(0.7);

  // ── Fetch duplicates ──────────────────────────────────────────
  const { data: pairs, isLoading, error, refetch } = useQuery({
    queryKey: ['customer-dedup', threshold],
    queryFn: () => findDuplicateCustomers(threshold),
    staleTime: 0,
  });

  // ── Merge mutation ────────────────────────────────────────────
  const mergeMut = useMutation({
    mutationFn: ({ keepId, mergeId }: { keepId: number; mergeId: number }) =>
      mergeCustomers(keepId, mergeId),
    onSuccess: () => {
      toast.success('Customers merged');
      queryClient.invalidateQueries({ queryKey: ['customer-dedup'] });
      onMerged();
    },
    onError: (err: Error) => {
      toast.error(err.message || 'Merge failed');
    },
  });

  return (
    <Modal isOpen onClose={onClose} title="Find Duplicate Customers" size="lg">
      <div className="space-y-4">
        {/* Threshold slider */}
        <div className="flex items-center gap-3 flex-wrap">
          <label className="text-sm text-gray-600 dark:text-gray-300 shrink-0">
            Similarity threshold:
          </label>
          <input
            type="range"
            min={0.5}
            max={1.0}
            step={0.05}
            value={threshold}
            onChange={(e) => setThreshold(Number(e.target.value))}
            className="flex-1 min-w-24"
          />
          <span className="text-sm font-mono w-10 text-right text-gray-700 dark:text-gray-200">
            {(threshold * 100).toFixed(0)}%
          </span>
          <Button size="sm" variant="ghost" icon={<Search size={14} />} onClick={() => refetch()}>
            Scan
          </Button>
        </div>

        {/* Loading */}
        {isLoading && (
          <div className="flex items-center justify-center gap-2 py-8 text-gray-500 dark:text-gray-400">
            <Loader2 className="h-5 w-5 animate-spin" /> Scanning for duplicates...
          </div>
        )}

        {/* Error */}
        {error && (
          <div className="p-3 bg-red-50 dark:bg-red-900/20 border border-red-200 dark:border-red-800 rounded-lg text-sm text-red-600 dark:text-red-400">
            <AlertTriangle className="h-4 w-4 inline mr-1" />
            Failed to scan: {(error as Error).message}
          </div>
        )}

        {/* No duplicates */}
        {pairs && pairs.length === 0 && (
          <div className="text-center py-8">
            <CheckCircle2 className="h-10 w-10 text-green-500 mx-auto mb-2" />
            <p className="text-sm text-gray-500 dark:text-gray-400">
              No duplicate customers found at {(threshold * 100).toFixed(0)}% threshold.
            </p>
          </div>
        )}

        {/* Duplicate pairs */}
        {pairs && pairs.length > 0 && (
          <div className="space-y-3 max-h-[50vh] overflow-y-auto">
            <p className="text-sm text-gray-500 dark:text-gray-400">
              Found <strong>{pairs.length}</strong> potential duplicate{pairs.length > 1 ? 's' : ''}.
              Click a customer to keep it — the other will be merged into it and deactivated.
            </p>

            {pairs.map((pair, idx) => (
              <DuplicatePairRow
                key={`${pair.a.id}-${pair.b.id}`}
                pair={pair}
                index={idx}
                isMerging={mergeMut.isPending}
                onMerge={(keepId, mergeId) => mergeMut.mutate({ keepId, mergeId })}
              />
            ))}
          </div>
        )}
      </div>

      {/* Footer */}
      <div className="flex justify-end mt-4 pt-3 border-t border-gray-200 dark:border-gray-700">
        <Button variant="ghost" size="sm" onClick={onClose}>Close</Button>
      </div>
    </Modal>
  );
}


// ═════════════════════════════════════════════════════════════════
// Single duplicate pair row
// ═════════════════════════════════════════════════════════════════

function DuplicatePairRow({
  pair, index, isMerging, onMerge,
}: {
  pair: DuplicatePair; index: number; isMerging: boolean;
  onMerge: (keepId: number, mergeId: number) => void;
}) {
  return (
    <Card noPadding>
      <div className="p-3">
        {/* Similarity badge */}
        <div className="flex items-center justify-between mb-2">
          <Badge variant={pair.similarity >= 0.9 ? 'danger' : pair.similarity >= 0.8 ? 'warning' : 'default'}>
            {(pair.similarity * 100).toFixed(0)}% match — {pair.match_type}
          </Badge>
          <span className="text-xs text-gray-400">#{index + 1}</span>
        </div>

        {/* Side-by-side picks */}
        <div className="grid grid-cols-1 sm:grid-cols-[1fr_auto_1fr] gap-2 items-center">
          <CustomerPickButton
            customer={pair.a}
            otherCustomer={pair.b}
            isMerging={isMerging}
            onPick={() => onMerge(pair.a.id, pair.b.id)}
          />
          <ArrowRight className="hidden sm:block h-4 w-4 text-gray-300 dark:text-gray-600 mx-auto" />
          <CustomerPickButton
            customer={pair.b}
            otherCustomer={pair.a}
            isMerging={isMerging}
            onPick={() => onMerge(pair.b.id, pair.a.id)}
          />
        </div>
      </div>
    </Card>
  );
}


function CustomerPickButton({
  customer, otherCustomer, isMerging, onPick,
}: {
  customer: { id: number; name: string; email?: string; phone?: string };
  otherCustomer: { id: number; name: string };
  isMerging: boolean;
  onPick: () => void;
}) {
  return (
    <button
      disabled={isMerging}
      onClick={onPick}
      className="w-full text-left p-2.5 rounded-lg border border-gray-200 dark:border-gray-600
        hover:border-primary-400 dark:hover:border-primary-500
        hover:bg-primary-50 dark:hover:bg-primary-900/20
        disabled:opacity-50 disabled:cursor-not-allowed
        transition-colors group"
      title={`Keep "${customer.name}" — merge "${otherCustomer.name}" into it`}
    >
      <div className="flex items-center gap-2">
        <Merge className="h-4 w-4 text-gray-400 group-hover:text-primary-500 shrink-0" />
        <div className="min-w-0">
          <p className="text-sm font-medium text-gray-900 dark:text-gray-100 truncate">
            {customer.name}
          </p>
          <div className="flex items-center gap-3 text-xs text-gray-500 dark:text-gray-400 flex-wrap">
            {customer.email && <span>{customer.email}</span>}
            {customer.phone && <span>{customer.phone}</span>}
            <span className="text-gray-300 dark:text-gray-600">ID: {customer.id}</span>
          </div>
        </div>
      </div>
      <p className="text-[10px] text-gray-400 dark:text-gray-500 mt-1 group-hover:text-primary-500">
        Click to keep this record
      </p>
    </button>
  );
}
