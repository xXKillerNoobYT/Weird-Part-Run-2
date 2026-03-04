/**
 * PODetailPage — full PO view with line items, receiving, timeline, and PDF actions.
 *
 * Depending on status, shows different action buttons:
 *  - draft → Edit / Submit
 *  - submitted → Mark Acknowledged / Copy PDF / Copy Text
 *  - acknowledged → receiving actions
 *  - partially_received → continue receiving
 *  - received → Close PO
 */

import { useState } from 'react';
import { useParams, Link } from 'react-router-dom';
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import {
  ArrowLeft,
  Send,
  FileText,
  Clipboard,
  Check,
  Package,
  DollarSign,
} from 'lucide-react';
import {
  getPO,
  submitPO,
  updatePOStatus,
  getPOClipboardText,
  getStatusHistory,
} from '../../../api/orders';
import { OrderStatusBadge } from '../components/OrderStatusBadge';
import { EmptyState } from '../../../components/ui/EmptyState';
import type { StatusHistoryEntry } from '../../../lib/types';

export function PODetailPage() {
  const { id } = useParams<{ id: string }>();
  const queryClient = useQueryClient();
  const poId = Number(id);
  const [mutationError, setMutationError] = useState<string | null>(null);

  const {
    data: po,
    isLoading,
    error,
  } = useQuery({
    queryKey: ['po', poId],
    queryFn: () => getPO(poId),
    enabled: !isNaN(poId),
  });

  const { data: history = [] } = useQuery({
    queryKey: ['status-history', 'po', poId],
    queryFn: () => getStatusHistory('po', poId),
    enabled: !isNaN(poId),
  });

  /** Invalidate detail + list + timeline caches after status changes */
  const invalidatePO = () => {
    setMutationError(null);
    queryClient.invalidateQueries({ queryKey: ['po', poId] });
    queryClient.invalidateQueries({ queryKey: ['pos'] });
    queryClient.invalidateQueries({ queryKey: ['status-history', 'po', poId] });
  };

  const submitMutation = useMutation({
    mutationFn: () => submitPO(poId),
    onSuccess: invalidatePO,
    onError: () => setMutationError('Failed to submit PO. Please try again.'),
  });

  const acknowledgeMutation = useMutation({
    mutationFn: () => updatePOStatus(poId, 'acknowledged'),
    onSuccess: invalidatePO,
    onError: () => setMutationError('Failed to mark as acknowledged. Please try again.'),
  });

  const copyTextMutation = useMutation({
    mutationFn: () => getPOClipboardText(poId),
    onSuccess: (result) => {
      setMutationError(null);
      navigator.clipboard.writeText(result.text).catch(() => {
        // Fallback: show text in alert if clipboard fails
        alert(result.text);
      });
    },
    onError: () => setMutationError('Failed to copy PO text. Please try again.'),
  });

  if (isLoading) {
    return (
      <div className="flex justify-center py-16">
        <div className="h-8 w-8 animate-spin rounded-full border-4 border-primary border-t-transparent" />
      </div>
    );
  }

  if (error || !po) {
    return (
      <EmptyState
        icon={<Package className="h-12 w-12" />}
        title="PO not found"
        description="This purchase order may have been deleted or you don't have access."
        action={
          <Link to="/orders/drafts" className="text-sm text-primary hover:underline">
            ← Back to Draft POs
          </Link>
        }
      />
    );
  }

  const isSubmittable = po.status === 'draft';
  const canAcknowledge = po.status === 'submitted';
  const canCopyText = ['submitted', 'acknowledged', 'partially_received', 'received'].includes(po.status);

  return (
    <div className="space-y-6">
      {/* Back + header */}
      <div>
        <Link
          to={po.status === 'draft' ? '/orders/drafts' : '/orders/active'}
          className="inline-flex items-center gap-1 text-sm text-gray-500 dark:text-gray-400 hover:text-primary mb-3"
        >
          <ArrowLeft className="h-4 w-4" />
          Back
        </Link>
        <div className="flex items-center justify-between">
          <div className="flex items-center gap-3">
            <h1 className="text-xl font-semibold text-gray-900 dark:text-gray-100">
              {po.po_number}
            </h1>
            <OrderStatusBadge status={po.status} type="po" />
          </div>

          {/* Action buttons */}
          <div className="flex items-center gap-2">
            {isSubmittable && (
              <button
                onClick={() => submitMutation.mutate()}
                disabled={submitMutation.isPending}
                className="inline-flex items-center gap-2 rounded-lg bg-primary px-4 py-2 text-sm font-medium text-white shadow-sm hover:bg-primary/90 transition-colors disabled:opacity-50"
              >
                <Send className="h-4 w-4" />
                Submit to Supplier
              </button>
            )}
            {canAcknowledge && (
              <button
                onClick={() => acknowledgeMutation.mutate()}
                disabled={acknowledgeMutation.isPending}
                className="inline-flex items-center gap-2 rounded-lg bg-blue-600 px-4 py-2 text-sm font-medium text-white shadow-sm hover:bg-blue-700 transition-colors disabled:opacity-50"
              >
                <FileText className="h-4 w-4" />
                Mark Acknowledged
              </button>
            )}
            {canCopyText && (
              <button
                onClick={() => copyTextMutation.mutate()}
                disabled={copyTextMutation.isPending}
                className="inline-flex items-center gap-2 rounded-lg border border-border bg-surface px-4 py-2 text-sm font-medium text-gray-700 dark:text-gray-300 shadow-sm hover:bg-surface-secondary transition-colors disabled:opacity-50"
              >
                {copyTextMutation.isPending ? (
                  <div className="h-4 w-4 animate-spin rounded-full border-2 border-gray-400 border-t-transparent" />
                ) : copyTextMutation.isSuccess ? (
                  <Check className="h-4 w-4 text-green-500" />
                ) : (
                  <Clipboard className="h-4 w-4" />
                )}
                {copyTextMutation.isSuccess ? 'Copied!' : 'Copy Text'}
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
      <div className="grid grid-cols-2 gap-4 md:grid-cols-4">
        <InfoCard label="Supplier" value={po.supplier_name || '—'} />
        <InfoCard
          label="Order Date"
          value={po.order_date ? new Date(po.order_date).toLocaleDateString() : '—'}
        />
        <InfoCard
          label="Expected Delivery"
          value={po.expected_delivery ? new Date(po.expected_delivery).toLocaleDateString() : '—'}
        />
        <InfoCard
          label="Total"
          value={
            po.total_cost != null
              ? `$${po.total_cost.toLocaleString(undefined, { minimumFractionDigits: 2, maximumFractionDigits: 2 })}`
              : '—'
          }
          icon={<DollarSign className="h-4 w-4 text-green-500" />}
        />
      </div>

      {/* Notes */}
      {(po.notes || po.internal_notes) && (
        <div className="grid gap-4 md:grid-cols-2">
          {po.notes && (
            <div className="rounded-lg border border-border bg-surface p-4">
              <h3 className="text-sm font-medium text-gray-700 dark:text-gray-300 mb-1">Notes</h3>
              <p className="text-sm text-gray-600 dark:text-gray-400 whitespace-pre-wrap">
                {po.notes}
              </p>
            </div>
          )}
          {po.internal_notes && (
            <div className="rounded-lg border border-amber-200 dark:border-amber-800 bg-amber-50 dark:bg-amber-900/10 p-4">
              <h3 className="text-sm font-medium text-amber-700 dark:text-amber-400 mb-1">
                Internal Notes
              </h3>
              <p className="text-sm text-amber-600 dark:text-amber-300 whitespace-pre-wrap">
                {po.internal_notes}
              </p>
            </div>
          )}
        </div>
      )}

      {/* Line items */}
      <div className="rounded-lg border border-border bg-surface overflow-hidden">
        <div className="border-b border-border bg-surface-secondary px-4 py-3">
          <h2 className="text-sm font-semibold text-gray-900 dark:text-gray-100">
            Line Items ({po.lines?.length ?? 0})
          </h2>
        </div>
        {po.lines && po.lines.length > 0 ? (
          <table className="min-w-full divide-y divide-border">
            <thead className="bg-surface-secondary/50">
              <tr>
                <th className="px-4 py-2.5 text-left text-xs font-medium uppercase text-gray-500 dark:text-gray-400">Part</th>
                <th className="px-4 py-2.5 text-right text-xs font-medium uppercase text-gray-500 dark:text-gray-400">Ordered</th>
                <th className="px-4 py-2.5 text-right text-xs font-medium uppercase text-gray-500 dark:text-gray-400">Received</th>
                <th className="px-4 py-2.5 text-right text-xs font-medium uppercase text-gray-500 dark:text-gray-400">Unit Cost</th>
                <th className="px-4 py-2.5 text-right text-xs font-medium uppercase text-gray-500 dark:text-gray-400">Line Total</th>
                <th className="px-4 py-2.5 text-left text-xs font-medium uppercase text-gray-500 dark:text-gray-400">Status</th>
              </tr>
            </thead>
            <tbody className="divide-y divide-border">
              {po.lines.map((line) => (
                <tr key={line.id} className="hover:bg-surface-secondary/30 transition-colors">
                  <td className="px-4 py-3">
                    <div className="text-sm font-medium text-gray-900 dark:text-gray-100">
                      {line.part_number || `Part #${line.part_id}`}
                    </div>
                    {line.part_description && (
                      <div className="text-xs text-gray-500 dark:text-gray-400 truncate max-w-[250px]">
                        {line.part_description}
                      </div>
                    )}
                  </td>
                  <td className="px-4 py-3 text-sm text-right tabular-nums text-gray-900 dark:text-gray-100">
                    {line.qty_ordered}
                  </td>
                  <td className="px-4 py-3 text-sm text-right tabular-nums text-gray-500 dark:text-gray-400">
                    {line.qty_received}
                  </td>
                  <td className="px-4 py-3 text-sm text-right tabular-nums text-gray-700 dark:text-gray-300">
                    {line.unit_cost != null
                      ? `$${line.unit_cost.toFixed(2)}`
                      : '—'}
                  </td>
                  <td className="px-4 py-3 text-sm text-right tabular-nums font-medium text-gray-900 dark:text-gray-100">
                    {line.unit_cost != null
                      ? `$${(line.qty_ordered * line.unit_cost).toLocaleString(undefined, { minimumFractionDigits: 2, maximumFractionDigits: 2 })}`
                      : '—'}
                  </td>
                  <td className="px-4 py-3">
                    <span
                      className={`inline-flex items-center rounded-full px-2 py-0.5 text-xs font-medium ${
                        line.status === 'received'
                          ? 'bg-green-100 text-green-700 dark:bg-green-900/30 dark:text-green-400'
                          : line.status === 'partial'
                            ? 'bg-amber-100 text-amber-700 dark:bg-amber-900/30 dark:text-amber-400'
                            : line.status === 'backordered'
                              ? 'bg-red-100 text-red-700 dark:bg-red-900/30 dark:text-red-400'
                              : line.status === 'cancelled'
                                ? 'bg-gray-100 text-gray-600 dark:bg-gray-700 dark:text-gray-400'
                                : 'bg-blue-100 text-blue-700 dark:bg-blue-900/30 dark:text-blue-400'
                      }`}
                    >
                      {line.status ?? 'pending'}
                    </span>
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        ) : (
          <div className="p-8 text-center text-sm text-gray-500 dark:text-gray-400">
            No line items yet.
          </div>
        )}

        {/* Totals footer */}
        {po.lines && po.lines.length > 0 && (
          <div className="border-t border-border bg-surface-secondary px-4 py-3">
            <div className="flex justify-end gap-8 text-sm">
              {po.subtotal != null && (
                <div className="text-gray-500 dark:text-gray-400">
                  Subtotal: <span className="font-medium text-gray-900 dark:text-gray-100 tabular-nums">
                    ${po.subtotal.toLocaleString(undefined, { minimumFractionDigits: 2, maximumFractionDigits: 2 })}
                  </span>
                </div>
              )}
              {(po.tax_amount ?? 0) > 0 && (
                <div className="text-gray-500 dark:text-gray-400">
                  Tax: <span className="font-medium text-gray-900 dark:text-gray-100 tabular-nums">
                    ${po.tax_amount!.toLocaleString(undefined, { minimumFractionDigits: 2, maximumFractionDigits: 2 })}
                  </span>
                </div>
              )}
              {(po.shipping_cost ?? 0) > 0 && (
                <div className="text-gray-500 dark:text-gray-400">
                  Shipping: <span className="font-medium text-gray-900 dark:text-gray-100 tabular-nums">
                    ${po.shipping_cost!.toLocaleString(undefined, { minimumFractionDigits: 2, maximumFractionDigits: 2 })}
                  </span>
                </div>
              )}
              <div className="font-semibold text-gray-900 dark:text-gray-100">
                Total: <span className="tabular-nums">
                  ${(po.total_cost ?? 0).toLocaleString(undefined, { minimumFractionDigits: 2, maximumFractionDigits: 2 })}
                </span>
              </div>
            </div>
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
                    {entry.changed_by_name && (
                      <span className="text-gray-500 dark:text-gray-400">
                        by {entry.changed_by_name}
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


function InfoCard({
  label,
  value,
  icon,
}: {
  label: string;
  value: string;
  icon?: React.ReactNode;
}) {
  return (
    <div className="rounded-lg border border-border bg-surface p-3">
      <div className="flex items-center gap-2">
        {icon}
        <p className="text-xs font-medium text-gray-500 dark:text-gray-400">{label}</p>
      </div>
      <p className="mt-1 text-sm font-semibold text-gray-900 dark:text-gray-100">
        {value}
      </p>
    </div>
  );
}
