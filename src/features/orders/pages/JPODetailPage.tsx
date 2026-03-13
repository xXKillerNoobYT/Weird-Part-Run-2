/**
 * JPODetailPage — full JPO view with line items, status, and linked POs.
 *
 * Depending on status, shows different action buttons:
 *  - draft → Edit / Submit for Approval
 *  - pending_approval → Approve / Reject (manager)
 *  - approved → Generate POs
 *  - ordering+ → view linked POs, receiving progress
 */

import { useState } from 'react';
import { useParams, Link, useNavigate } from 'react-router-dom';
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import {
  ArrowLeft,
  Send,
  CheckCircle2,
  XCircle,
  ClipboardList,
  Package,
} from 'lucide-react';
import { getJPO, submitJPO, reviewJPO, getStatusHistory } from '../../../api/orders';
import { OrderStatusBadge } from '../components/OrderStatusBadge';
import { EmptyState } from '../../../components/ui/EmptyState';
import { PartIdentity } from '../../../components/ui/PartIdentity';
import type { StatusHistoryEntry } from '../../../lib/types';

export function JPODetailPage() {
  const { id } = useParams<{ id: string }>();
  const navigate = useNavigate();
  const queryClient = useQueryClient();
  const jpoId = Number(id);
  const [mutationError, setMutationError] = useState<string | null>(null);

  const {
    data: jpo,
    isLoading,
    error,
  } = useQuery({
    queryKey: ['jpo', jpoId],
    queryFn: () => getJPO(jpoId),
    enabled: !isNaN(jpoId),
  });

  const { data: history = [] } = useQuery({
    queryKey: ['status-history', 'jpo', jpoId],
    queryFn: () => getStatusHistory('jpo', jpoId),
    enabled: !isNaN(jpoId),
  });

  /** Invalidate both detail + list caches after any status change */
  const invalidateJPO = () => {
    setMutationError(null);
    queryClient.invalidateQueries({ queryKey: ['jpo', jpoId] });
    queryClient.invalidateQueries({ queryKey: ['jpos'] });
    queryClient.invalidateQueries({ queryKey: ['status-history', 'jpo', jpoId] });
  };

  const submitMutation = useMutation({
    mutationFn: () => submitJPO(jpoId),
    onSuccess: invalidateJPO,
    onError: () => setMutationError('Failed to submit for approval. Please try again.'),
  });

  const approveMutation = useMutation({
    mutationFn: () => reviewJPO(jpoId, { action: 'approve' }),
    onSuccess: invalidateJPO,
    onError: () => setMutationError('Failed to approve. Please try again.'),
  });

  const rejectMutation = useMutation({
    mutationFn: (reason: string) =>
      reviewJPO(jpoId, { action: 'reject', notes: reason }),
    onSuccess: invalidateJPO,
    onError: () => setMutationError('Failed to reject. Please try again.'),
  });

  /** Prompt the manager for a rejection reason before calling the API */
  const handleReject = () => {
    const reason = window.prompt('Reason for rejection:');
    if (reason !== null && reason.trim()) {
      rejectMutation.mutate(reason.trim());
    }
  };

  if (isLoading) {
    return (
      <div className="flex justify-center py-16">
        <div className="h-8 w-8 animate-spin rounded-full border-4 border-primary border-t-transparent" />
      </div>
    );
  }

  if (error || !jpo) {
    return (
      <EmptyState
        icon={<ClipboardList className="h-12 w-12" />}
        title="JPO not found"
        description="This parts request may have been deleted or you don't have access."
        action={
          <Link to="/orders/parts-requests" className="text-sm text-primary hover:underline">
            ← Back to Parts Requests
          </Link>
        }
      />
    );
  }

  return (
    <div className="space-y-6">
      {/* Back link + header */}
      <div>
        <Link
          to="/orders/parts-requests"
          className="inline-flex items-center gap-1 text-sm text-gray-500 dark:text-gray-400 hover:text-primary mb-3"
        >
          <ArrowLeft className="h-4 w-4" />
          Back to Parts Requests
        </Link>
        <div className="flex items-start justify-between flex-wrap gap-3">
          <div className="flex items-center gap-3 flex-wrap">
            <h1 className="text-xl font-semibold text-gray-900 dark:text-gray-100">
              {jpo.order_number}
            </h1>
            <OrderStatusBadge status={jpo.status} type="jpo" />
          </div>

          {/* Action buttons based on status */}
          <div className="flex items-center gap-2 flex-wrap">
            {jpo.status === 'draft' && (
              <button
                onClick={() => submitMutation.mutate()}
                disabled={submitMutation.isPending}
                className="inline-flex items-center gap-2 rounded-lg bg-primary px-3 py-2 text-sm font-medium text-white shadow-sm hover:bg-primary/90 transition-colors disabled:opacity-50 min-h-[40px]"
              >
                <Send className="h-4 w-4" />
                <span className="hidden sm:inline">Submit for Approval</span>
                <span className="sm:hidden">Submit</span>
              </button>
            )}
            {jpo.status === 'pending_approval' && (
              <>
                <button
                  onClick={() => approveMutation.mutate()}
                  disabled={approveMutation.isPending}
                  className="inline-flex items-center gap-2 rounded-lg bg-green-600 px-3 py-2 text-sm font-medium text-white shadow-sm hover:bg-green-700 transition-colors disabled:opacity-50 min-h-[40px]"
                >
                  <CheckCircle2 className="h-4 w-4" />
                  Approve
                </button>
                <button
                  onClick={handleReject}
                  disabled={rejectMutation.isPending}
                  className="inline-flex items-center gap-2 rounded-lg bg-red-600 px-3 py-2 text-sm font-medium text-white shadow-sm hover:bg-red-700 transition-colors disabled:opacity-50 min-h-[40px]"
                >
                  <XCircle className="h-4 w-4" />
                  Reject
                </button>
              </>
            )}
            {jpo.status === 'approved' && (
              <button
                onClick={() => navigate(`/orders/parts-requests/${jpoId}/generate-pos`)}
                className="inline-flex items-center gap-2 rounded-lg bg-primary px-3 py-2 text-sm font-medium text-white shadow-sm hover:bg-primary/90 transition-colors min-h-[40px]"
              >
                <Package className="h-4 w-4" />
                Generate POs
              </button>
            )}
          </div>
        </div>
      </div>

      {/* Mutation error banner */}
      {mutationError && (
        <div className="flex items-center justify-between rounded-lg border border-red-200 dark:border-red-800 bg-red-50 dark:bg-red-900/20 px-4 py-3 text-sm text-red-700 dark:text-red-300">
          <span>{mutationError}</span>
          <button
            onClick={() => setMutationError(null)}
            className="ml-3 text-red-500 hover:text-red-700 dark:hover:text-red-300"
          >
            ✕
          </button>
        </div>
      )}

      {/* Info cards */}
      <div className="grid grid-cols-2 gap-3 md:grid-cols-4">
        <InfoCard label="Job" value={jpo.job_name || '—'} />
        <InfoCard label="Requested By" value={jpo.requester_name || '—'} />
        <InfoCard label="Priority" value={jpo.priority ?? 'normal'} />
        <InfoCard
          label="Date"
          value={jpo.created_at ? new Date(jpo.created_at).toLocaleDateString() : '—'}
        />
      </div>

      {/* Notes */}
      {jpo.notes && (
        <div className="rounded-lg border border-border bg-surface p-4">
          <h3 className="text-sm font-medium text-gray-700 dark:text-gray-300 mb-1">Notes</h3>
          <p className="text-sm text-gray-600 dark:text-gray-400 whitespace-pre-wrap">
            {jpo.notes}
          </p>
        </div>
      )}

      {/* Line items */}
      <div className="rounded-lg border border-border bg-surface overflow-hidden">
        <div className="border-b border-border bg-surface-secondary px-4 py-3">
          <h2 className="text-sm font-semibold text-gray-900 dark:text-gray-100">
            Line Items ({jpo.lines?.length ?? 0})
          </h2>
        </div>
        {jpo.lines && jpo.lines.length > 0 ? (
          <div className="overflow-x-auto">
            <table className="min-w-full divide-y divide-border">
              <thead className="bg-surface-secondary/50">
                <tr>
                  <th className="px-4 py-2.5 text-left text-xs font-medium uppercase text-gray-500 dark:text-gray-400">Part</th>
                  <th className="px-4 py-2.5 text-right text-xs font-medium uppercase text-gray-500 dark:text-gray-400">Requested</th>
                  <th className="px-4 py-2.5 text-right text-xs font-medium uppercase text-gray-500 dark:text-gray-400">Ordered</th>
                  <th className="px-4 py-2.5 text-right text-xs font-medium uppercase text-gray-500 dark:text-gray-400">Received</th>
                  <th className="px-4 py-2.5 text-left text-xs font-medium uppercase text-gray-500 dark:text-gray-400">Priority</th>
                  <th className="px-4 py-2.5 text-left text-xs font-medium uppercase text-gray-500 dark:text-gray-400">Notes</th>
                </tr>
              </thead>
              <tbody className="divide-y divide-border">
                {jpo.lines.map((line) => (
                  <tr key={line.id} className="hover:bg-surface-secondary/30 transition-colors">
                    <td className="px-4 py-3">
                      <PartIdentity
                        compact
                        partName={line.part_name}
                        partDescription={line.part_description}
                        partNumber={line.part_number}
                        partId={line.part_id}
                        brandName={line.brand_name}
                        colorName={line.color_name}
                        colorHex={line.color_hex}
                        categoryName={line.category_name}
                        typeName={line.type_name}
                      />
                    </td>
                    <td className="px-4 py-3 text-sm text-right tabular-nums text-gray-900 dark:text-gray-100">
                      {line.qty_requested}
                    </td>
                    <td className="px-4 py-3 text-sm text-right tabular-nums text-gray-500 dark:text-gray-400">
                      {line.qty_ordered}
                    </td>
                    <td className="px-4 py-3 text-sm text-right tabular-nums text-gray-500 dark:text-gray-400">
                      {line.qty_received}
                    </td>
                    <td className="px-4 py-3">
                      <span
                        className={`inline-flex items-center rounded-full px-2 py-0.5 text-xs font-medium ${line.priority === 'critical'
                            ? 'bg-red-100 text-red-700 dark:bg-red-900/30 dark:text-red-400'
                            : line.priority === 'urgent'
                              ? 'bg-amber-100 text-amber-700 dark:bg-amber-900/30 dark:text-amber-400'
                              : 'bg-gray-100 text-gray-600 dark:bg-gray-700 dark:text-gray-400'
                          }`}
                      >
                        {line.priority ?? 'normal'}
                      </span>
                    </td>
                    <td className="px-4 py-3 text-sm text-gray-500 dark:text-gray-400 truncate max-w-[150px]">
                      {line.notes || '—'}
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        ) : (
          <div className="p-8 text-center text-sm text-gray-500 dark:text-gray-400">
            No line items yet.
          </div>
        )}
      </div>

      {/* Status Timeline */}
      {history.length > 0 && (
        <div className="rounded-lg border border-border bg-surface p-4">
          <h2 className="text-sm font-semibold text-gray-900 dark:text-gray-100 mb-3">
            Status History
          </h2>
          <div className="space-y-3">
            {history.map((entry: StatusHistoryEntry) => (
              <div key={entry.id} className="flex items-start gap-3">
                <div className="mt-1.5 h-2 w-2 rounded-full bg-primary flex-shrink-0" />
                <div className="min-w-0">
                  <div className="flex items-center gap-2 text-sm">
                    <span className="font-medium text-gray-900 dark:text-gray-100">
                      {entry.old_status ? `${entry.old_status} → ${entry.new_status}` : entry.new_status}
                    </span>
                    {entry.changer_name && (
                      <span className="text-gray-500 dark:text-gray-400">
                        by {entry.changer_name}
                      </span>
                    )}
                  </div>
                  {entry.notes && (
                    <p className="text-xs text-gray-500 dark:text-gray-400 mt-0.5">
                      {entry.notes}
                    </p>
                  )}
                  <p className="text-xs text-gray-400 dark:text-gray-500 mt-0.5">
                    {entry.created_at ? new Date(entry.created_at).toLocaleString() : ''}
                  </p>
                </div>
              </div>
            ))}
          </div>
        </div>
      )}
    </div>
  );
}


function InfoCard({ label, value }: { label: string; value: string }) {
  return (
    <div className="rounded-lg border border-border bg-surface p-3">
      <p className="text-xs font-medium text-gray-500 dark:text-gray-400">{label}</p>
      <p className="mt-1 text-sm font-semibold text-gray-900 dark:text-gray-100 capitalize">
        {value}
      </p>
    </div>
  );
}
