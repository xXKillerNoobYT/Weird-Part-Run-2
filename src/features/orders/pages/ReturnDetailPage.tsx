/**
 * ReturnDetailPage — detail view for a single return with status actions.
 *
 * Shows return metadata, line items, and context-aware action buttons
 * based on the current status in the return lifecycle:
 *   draft → pending_approval → approved → shipped → received_by_supplier → credited → closed
 *
 * For job_to_warehouse returns, the lifecycle is shorter (draft → approved → closed)
 * since there's no shipping/supplier step.
 */

import { useState } from 'react';
import { useParams, Link } from 'react-router-dom';
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import {
  ArrowLeft,
  Loader2,
  AlertCircle,
  Send,
  CheckCircle2,
  Truck,
  DollarSign,
  Package,
  FileText,
  Clock,
  User,
  MapPin,
} from 'lucide-react';
import {
  getReturn,
  submitReturn,
  approveReturn,
  updateReturnStatus,
  updateReturn,
  getStatusHistory,
} from '../../../api/orders';
import type {
  ReturnLineResponse,
  ReturnStatus,
  StatusHistoryEntry,
} from '../../../lib/types';
import { PartIdentity } from '../../../components/ui/PartIdentity';


// ── Status config ────────────────────────────────────────────────
const STATUS_COLORS: Record<ReturnStatus, string> = {
  draft: 'bg-gray-100 text-gray-700 dark:bg-gray-700 dark:text-gray-300',
  pending_approval: 'bg-amber-100 text-amber-700 dark:bg-amber-900/30 dark:text-amber-400',
  approved: 'bg-green-100 text-green-700 dark:bg-green-900/30 dark:text-green-400',
  shipped: 'bg-blue-100 text-blue-700 dark:bg-blue-900/30 dark:text-blue-400',
  received_by_supplier: 'bg-indigo-100 text-indigo-700 dark:bg-indigo-900/30 dark:text-indigo-400',
  credited: 'bg-purple-100 text-purple-700 dark:bg-purple-900/30 dark:text-purple-400',
  closed: 'bg-gray-100 text-gray-600 dark:bg-gray-700 dark:text-gray-400',
};

const STATUS_LABELS: Record<ReturnStatus, string> = {
  draft: 'Draft',
  pending_approval: 'Pending Approval',
  approved: 'Approved',
  shipped: 'Shipped',
  received_by_supplier: 'Received by Supplier',
  credited: 'Credited',
  closed: 'Closed',
};

const CONDITION_LABELS: Record<string, string> = {
  new: 'New',
  used: 'Used',
  damaged: 'Damaged',
  defective: 'Defective',
};

const DISPOSITION_LABELS: Record<string, string> = {
  return_to_supplier: 'Return to Supplier',
  restock: 'Restock',
  write_off: 'Write Off',
};

const DISPOSITION_COLORS: Record<string, string> = {
  return_to_supplier: 'bg-blue-100 text-blue-700 dark:bg-blue-900/30 dark:text-blue-400',
  restock: 'bg-green-100 text-green-700 dark:bg-green-900/30 dark:text-green-400',
  write_off: 'bg-red-100 text-red-700 dark:bg-red-900/30 dark:text-red-400',
};


export function ReturnDetailPage() {
  const { id } = useParams<{ id: string }>();
  const queryClient = useQueryClient();
  const returnId = Number(id);

  // ── Inline editing state for shipping / RMA / credit ──────────
  const [trackingNumber, setTrackingNumber] = useState('');
  const [rmaNumber, setRmaNumber] = useState('');
  const [creditAmount, setCreditAmount] = useState<number | ''>('');
  const [actionError, setActionError] = useState('');

  // ── Fetch return ──────────────────────────────────────────────
  const {
    data: ret,
    isLoading,
    isError,
    error,
  } = useQuery({
    queryKey: ['return-detail', returnId],
    queryFn: () => getReturn(returnId),
    enabled: !isNaN(returnId),
  });

  const { data: history = [] } = useQuery({
    queryKey: ['status-history', 'return', returnId],
    queryFn: () => getStatusHistory('return', returnId),
    enabled: !isNaN(returnId),
  });

  // ── Mutations ─────────────────────────────────────────────────
  const invalidate = () => {
    queryClient.invalidateQueries({ queryKey: ['return-detail', returnId] });
    queryClient.invalidateQueries({ queryKey: ['returns'] });
    queryClient.invalidateQueries({ queryKey: ['status-history', 'return', returnId] });
  };

  const submitMut = useMutation({
    mutationFn: () => submitReturn(returnId),
    onSuccess: invalidate,
    onError: (e: Error) => setActionError(e.message),
  });

  const approveMut = useMutation({
    mutationFn: () => approveReturn(returnId),
    onSuccess: invalidate,
    onError: (e: Error) => setActionError(e.message),
  });

  const statusMut = useMutation({
    mutationFn: ({
      status,
      extras,
    }: {
      status: string;
      extras?: Record<string, unknown>;
    }) => updateReturnStatus(returnId, status, extras),
    onSuccess: invalidate,
    onError: (e: Error) => setActionError(e.message),
  });

  const updateMut = useMutation({
    mutationFn: (updates: Record<string, unknown>) =>
      updateReturn(returnId, updates as Parameters<typeof updateReturn>[1]),
    onSuccess: invalidate,
    onError: (e: Error) => setActionError(e.message),
  });

  const isBusy =
    submitMut.isPending ||
    approveMut.isPending ||
    statusMut.isPending ||
    updateMut.isPending;

  // ── Loading / error states ────────────────────────────────────
  if (isLoading) {
    return (
      <div className="flex items-center justify-center py-24">
        <Loader2 className="h-8 w-8 text-primary animate-spin" />
      </div>
    );
  }

  if (isError || !ret) {
    return (
      <div className="space-y-4">
        <Link
          to="/orders/returns"
          className="inline-flex items-center gap-1.5 text-sm text-gray-500 dark:text-gray-400 hover:text-primary transition-colors min-h-[44px]"
        >
          <ArrowLeft className="h-4 w-4" />
          Back to Returns
        </Link>
        <div className="flex items-start gap-3 p-4 bg-red-50 dark:bg-red-900/20 border border-red-200 dark:border-red-800 rounded-lg">
          <AlertCircle className="h-5 w-5 text-red-500 mt-0.5" />
          <p className="text-sm text-red-600 dark:text-red-400">
            {(error as Error)?.message || 'Return not found.'}
          </p>
        </div>
      </div>
    );
  }

  // ── Determine available actions ───────────────────────────────
  const isSupplierReturn = ret.return_type === 'warehouse_to_supplier';
  const actions = getActions(ret.status, isSupplierReturn);

  return (
    <div className="space-y-4">
      {/* ── Back link ──────────────────────────────────────────── */}
      <Link
        to="/orders/returns"
        className="inline-flex items-center gap-1.5 text-sm text-gray-500 dark:text-gray-400 hover:text-primary transition-colors min-h-[44px]"
      >
        <ArrowLeft className="h-4 w-4" />
        Back to Returns
      </Link>

      {/* ── Header row ─────────────────────────────────────────── */}
      <div className="flex items-start justify-between flex-wrap gap-3">
        <div>
          <div className="flex items-center gap-3 flex-wrap">
            <h1 className="text-xl font-semibold text-gray-900 dark:text-gray-100">
              {ret.return_number}
            </h1>
            <span
              className={`inline-flex rounded-full px-2.5 py-1 text-xs font-medium ${STATUS_COLORS[ret.status]
                }`}
            >
              {STATUS_LABELS[ret.status]}
            </span>
          </div>
          <p className="text-sm text-gray-500 dark:text-gray-400 mt-0.5">
            {ret.return_type === 'job_to_warehouse' ? 'Job → Warehouse' : 'Warehouse → Supplier'}
            {' · '}
            {ret.reason.replace(/_/g, ' ')}
          </p>
        </div>
      </div>

      {/* ── Action error ───────────────────────────────────────── */}
      {actionError && (
        <div className="flex items-start gap-3 p-3 bg-red-50 dark:bg-red-900/20 border border-red-200 dark:border-red-800 rounded-lg">
          <AlertCircle className="h-5 w-5 text-red-500 flex-shrink-0 mt-0.5" />
          <p className="text-sm text-red-600 dark:text-red-400">{actionError}</p>
        </div>
      )}

      {/* ── Metadata grid ──────────────────────────────────────── */}
      <div className="rounded-xl border border-gray-200 dark:border-gray-700 bg-white dark:bg-gray-800 shadow-sm p-5">
        <div className="grid grid-cols-2 sm:grid-cols-4 gap-4 text-sm">
          {ret.supplier_name && (
            <MetaField icon={Package} label="Supplier" value={ret.supplier_name} />
          )}
          {ret.job_name && (
            <MetaField icon={MapPin} label="Job" value={ret.job_name} />
          )}
          <MetaField
            icon={User}
            label="Initiated By"
            value={ret.initiator_name ?? 'Unknown'}
          />
          <MetaField
            icon={Clock}
            label="Created"
            value={ret.created_at ? new Date(ret.created_at).toLocaleDateString() : '—'}
          />
          {ret.rma_number && (
            <MetaField icon={FileText} label="RMA #" value={ret.rma_number} />
          )}
          {ret.shipping_carrier && (
            <MetaField icon={Truck} label="Carrier" value={ret.shipping_carrier} />
          )}
          {ret.tracking_number && (
            <MetaField icon={Truck} label="Tracking" value={ret.tracking_number} />
          )}
          {ret.credit_amount > 0 && (
            <MetaField
              icon={DollarSign}
              label="Credit"
              value={`$${ret.credit_amount.toFixed(2)}`}
            />
          )}
        </div>
        {ret.notes && (
          <div className="mt-3 pt-3 border-t border-gray-200 dark:border-gray-700">
            <p className="text-xs text-gray-500 dark:text-gray-400">Notes</p>
            <p className="text-sm text-gray-700 dark:text-gray-300 mt-0.5">
              {ret.notes}
            </p>
          </div>
        )}
      </div>

      {/* ── Return Lines ───────────────────────────────────────── */}
      <div className="rounded-xl border border-gray-200 dark:border-gray-700 bg-white dark:bg-gray-800 shadow-sm">
        <div className="px-5 py-3 border-b border-gray-200 dark:border-gray-700">
          <h2 className="text-sm font-semibold text-gray-900 dark:text-gray-100">
            Return Items ({ret.line_count})
          </h2>
        </div>

        {(ret.lines ?? []).length === 0 ? (
          <div className="p-8 text-center text-sm text-gray-500 dark:text-gray-400">
            No items on this return.
          </div>
        ) : (
          <div className="divide-y divide-gray-200 dark:divide-gray-700">
            {(ret.lines ?? []).map((line: ReturnLineResponse) => (
              <div key={line.id} className="flex items-center gap-4 px-5 py-3">
                <div className="flex-1 min-w-0">
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
                  <div className="flex items-center gap-2 mt-1 flex-wrap">
                    <span className="text-xs text-gray-500 dark:text-gray-400">
                      Qty: {line.qty}
                    </span>
                    <span className="text-xs text-gray-500 dark:text-gray-400">
                      · {CONDITION_LABELS[line.condition] ?? line.condition}
                    </span>
                    <span
                      className={`inline-flex rounded-full px-1.5 py-0.5 text-xs font-medium ${DISPOSITION_COLORS[line.disposition] ?? 'bg-gray-100 text-gray-600'
                        }`}
                    >
                      {DISPOSITION_LABELS[line.disposition] ?? line.disposition}
                    </span>
                  </div>
                  {line.notes && (
                    <p className="text-xs text-gray-400 dark:text-gray-500 mt-0.5 italic">
                      {line.notes}
                    </p>
                  )}
                </div>

                {line.unit_cost !== null && line.unit_cost > 0 && (
                  <div className="text-right flex-shrink-0">
                    <p className="text-sm font-medium text-gray-900 dark:text-gray-100 tabular-nums">
                      ${(line.unit_cost * line.qty).toFixed(2)}
                    </p>
                    <p className="text-xs text-gray-500 dark:text-gray-400 tabular-nums">
                      ${line.unit_cost.toFixed(2)} ea
                    </p>
                  </div>
                )}
              </div>
            ))}
          </div>
        )}
      </div>

      {/* ── Action Panel ───────────────────────────────────────── */}
      {actions.length > 0 && (
        <div className="rounded-xl border border-gray-200 dark:border-gray-700 bg-white dark:bg-gray-800 shadow-sm p-5 space-y-4">
          <h3 className="text-sm font-semibold text-gray-900 dark:text-gray-100">
            Actions
          </h3>

          {/* Inline fields for shipping info (when status is approved, supplier return) */}
          {ret.status === 'approved' && isSupplierReturn && (
            <div className="grid grid-cols-1 sm:grid-cols-3 gap-3">
              <div className="space-y-1">
                <label className="block text-xs font-medium text-gray-600 dark:text-gray-400">
                  RMA Number
                </label>
                <input
                  type="text"
                  value={rmaNumber}
                  onChange={(e) => setRmaNumber(e.target.value)}
                  placeholder="Supplier RMA #"
                  className="block w-full rounded-lg border border-gray-300 dark:border-gray-600 bg-white dark:bg-gray-800 px-3 py-1.5 text-sm text-gray-900 dark:text-gray-100 placeholder:text-gray-400 focus:outline-none focus:ring-2 focus:ring-primary-300 transition-colors"
                />
              </div>
              <div className="space-y-1">
                <label className="block text-xs font-medium text-gray-600 dark:text-gray-400">
                  Tracking Number
                </label>
                <input
                  type="text"
                  value={trackingNumber}
                  onChange={(e) => setTrackingNumber(e.target.value)}
                  placeholder="Shipping tracking"
                  className="block w-full rounded-lg border border-gray-300 dark:border-gray-600 bg-white dark:bg-gray-800 px-3 py-1.5 text-sm text-gray-900 dark:text-gray-100 placeholder:text-gray-400 focus:outline-none focus:ring-2 focus:ring-primary-300 transition-colors"
                />
              </div>
            </div>
          )}

          {/* Credit amount field (when status is received_by_supplier) */}
          {ret.status === 'received_by_supplier' && (
            <div className="max-w-xs space-y-1">
              <label className="block text-xs font-medium text-gray-600 dark:text-gray-400">
                Credit Amount
              </label>
              <input
                type="number"
                min={0}
                step={0.01}
                value={creditAmount}
                onChange={(e) =>
                  setCreditAmount(e.target.value ? Number(e.target.value) : '')
                }
                placeholder="$0.00"
                className="block w-full rounded-lg border border-gray-300 dark:border-gray-600 bg-white dark:bg-gray-800 px-3 py-1.5 text-sm text-gray-900 dark:text-gray-100 placeholder:text-gray-400 tabular-nums focus:outline-none focus:ring-2 focus:ring-primary-300 transition-colors"
              />
            </div>
          )}

          {/* Action buttons */}
          <div className="flex items-center gap-3 flex-wrap">
            {actions.map((action) => (
              <button
                key={action.status}
                type="button"
                disabled={isBusy}
                onClick={() => {
                  setActionError('');
                  if (action.status === '__submit__') {
                    submitMut.mutate();
                  } else if (action.status === '__approve__') {
                    approveMut.mutate();
                  } else {
                    const extras: Record<string, unknown> = {};
                    if (trackingNumber.trim())
                      extras.tracking_number = trackingNumber.trim();
                    if (rmaNumber.trim()) extras.rma_number = rmaNumber.trim();
                    if (creditAmount) extras.credit_amount = creditAmount;
                    statusMut.mutate({ status: action.status, extras });
                  }
                }}
                className={`inline-flex items-center gap-2 rounded-lg px-4 py-2 text-sm font-medium shadow-sm transition-colors min-h-[44px] ${action.className} disabled:opacity-50`}
              >
                {isBusy ? (
                  <Loader2 className="h-4 w-4 animate-spin" />
                ) : (
                  <action.icon className="h-4 w-4" />
                )}
                {action.label}
              </button>
            ))}
          </div>
        </div>
      )}

      {/* Status History Timeline */}
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
                  </div>
                  <p className="text-xs text-gray-500 dark:text-gray-400">
                    {entry.changer_name} · {entry.created_at ? new Date(entry.created_at).toLocaleString() : '—'}
                  </p>
                  {entry.notes && (
                    <p className="text-xs text-gray-400 dark:text-gray-500 mt-0.5">{entry.notes}</p>
                  )}
                </div>
              </div>
            ))}
          </div>
        </div>
      )}
    </div>
  );
}


// ═══════════════════════════════════════════════════════════════════
// INTERNAL: MetaField
// ═══════════════════════════════════════════════════════════════════

function MetaField({
  icon: Icon,
  label,
  value,
}: {
  icon: React.ComponentType<{ className?: string }>;
  label: string;
  value: string;
}) {
  return (
    <div>
      <p className="text-xs text-gray-500 dark:text-gray-400 flex items-center gap-1">
        <Icon className="h-3 w-3" />
        {label}
      </p>
      <p className="text-sm font-medium text-gray-900 dark:text-gray-100 mt-0.5">
        {value}
      </p>
    </div>
  );
}


// ═══════════════════════════════════════════════════════════════════
// INTERNAL: getActions — returns available actions based on status
// ═══════════════════════════════════════════════════════════════════

interface ActionDef {
  status: string; // next status, or '__submit__'/'__approve__' for special mutations
  label: string;
  icon: React.ComponentType<{ className?: string }>;
  className: string;
}

function getActions(status: ReturnStatus, isSupplierReturn: boolean): ActionDef[] {
  switch (status) {
    case 'draft':
      return [
        {
          status: '__submit__',
          label: 'Submit for Approval',
          icon: Send,
          className: 'bg-primary text-white hover:bg-primary/90',
        },
      ];

    case 'pending_approval':
      return [
        {
          status: '__approve__',
          label: 'Approve',
          icon: CheckCircle2,
          className: 'bg-green-600 text-white hover:bg-green-700',
        },
      ];

    case 'approved':
      if (isSupplierReturn) {
        return [
          {
            status: 'shipped',
            label: 'Mark as Shipped',
            icon: Truck,
            className: 'bg-blue-600 text-white hover:bg-blue-700',
          },
        ];
      }
      // Job returns can go straight to closed (restocked)
      return [
        {
          status: 'closed',
          label: 'Close (Items Restocked)',
          icon: CheckCircle2,
          className: 'bg-green-600 text-white hover:bg-green-700',
        },
      ];

    case 'shipped':
      return [
        {
          status: 'received_by_supplier',
          label: 'Received by Supplier',
          icon: Package,
          className: 'bg-indigo-600 text-white hover:bg-indigo-700',
        },
      ];

    case 'received_by_supplier':
      return [
        {
          status: 'credited',
          label: 'Mark as Credited',
          icon: DollarSign,
          className: 'bg-purple-600 text-white hover:bg-purple-700',
        },
      ];

    case 'credited':
      return [
        {
          status: 'closed',
          label: 'Close Return',
          icon: CheckCircle2,
          className: 'bg-green-600 text-white hover:bg-green-700',
        },
      ];

    default:
      return [];
  }
}
