/**
 * ReturnSortingPage — warehouse triage for approved returns (Phase 7C).
 *
 * Shows returns that have been approved and need sorting. For each line
 * item, the backend provides a recommendation based on:
 *   - Item condition (new, like_new, used, damaged, defective)
 *   - Supplier return eligibility (condition + 90-day window)
 *   - Current stock vs restock target
 *
 * Warehouse staff can accept the recommendation or override it, then
 * submit all dispositions at once.
 *
 * Dispositions:
 *   return_to_supplier — queue for RMA
 *   restock            — move back to warehouse shelf
 *   write_off          — record as loss
 *
 * Lives under: Warehouse > Return Sorting tab
 * Permission: manage_orders
 */

import { useState, useMemo, useCallback } from 'react';
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import {
  ArrowLeftRight,
  PackageCheck,
  AlertTriangle,
  Trash2,
  Undo2,
  TrendingDown,
  Loader2,
  Check,
  CheckCircle2,
  ChevronDown,
  ChevronUp,
  Info,
} from 'lucide-react';
import toast from '../../../lib/toast';

import { PageSpinner } from '../../../components/ui/Spinner';
import { EmptyState } from '../../../components/ui/EmptyState';
import { Badge } from '../../../components/ui/Badge';
import { Modal } from '../../../components/ui/Modal';

import { listReturns, getSortingGuidance, processSortingDispositions } from '../../../api/orders';
import type {
  ReturnListItem,
  ReturnSortingGuidance,
  ReturnSortingDisposition,
  ReturnDisposition,
  ReturnCondition,
} from '../../../lib/types';


// ── Constants ────────────────────────────────────────────────────

const DISPOSITION_LABELS: Record<ReturnDisposition, string> = {
  return_to_supplier: 'Return to Supplier',
  restock: 'Restock',
  write_off: 'Write Off',
};

const DISPOSITION_COLORS: Record<ReturnDisposition, string> = {
  return_to_supplier: 'bg-green-100 text-green-800 dark:bg-green-900/30 dark:text-green-300',
  restock: 'bg-amber-100 text-amber-800 dark:bg-amber-900/30 dark:text-amber-300',
  write_off: 'bg-red-100 text-red-800 dark:bg-red-900/30 dark:text-red-300',
};

const DISPOSITION_ICONS: Record<ReturnDisposition, typeof Undo2> = {
  return_to_supplier: Undo2,
  restock: PackageCheck,
  write_off: Trash2,
};

const CONDITION_LABELS: Record<ReturnCondition, string> = {
  new: 'New',
  like_new: 'Like New',
  used: 'Used',
  damaged: 'Damaged',
  defective: 'Defective',
};

const CONDITION_COLORS: Record<string, string> = {
  new: 'bg-green-100 text-green-700 dark:bg-green-900/30 dark:text-green-300',
  like_new: 'bg-blue-100 text-blue-700 dark:bg-blue-900/30 dark:text-blue-300',
  used: 'bg-gray-100 text-gray-700 dark:bg-gray-700 dark:text-gray-300',
  damaged: 'bg-red-100 text-red-700 dark:bg-red-900/30 dark:text-red-300',
  defective: 'bg-red-100 text-red-700 dark:bg-red-900/30 dark:text-red-300',
};


// ── Main Page ────────────────────────────────────────────────────

export function ReturnSortingPage() {
  // ── State ──────────────────────────────────────────────────────
  const [selectedReturnId, setSelectedReturnId] = useState<number | null>(null);
  const [dispositions, setDispositions] = useState<Map<number, ReturnSortingDisposition>>(new Map());
  const [confirmOpen, setConfirmOpen] = useState(false);
  const [expandedLine, setExpandedLine] = useState<number | null>(null);

  const queryClient = useQueryClient();

  // ── Data: approved returns that need sorting ───────────────────
  const { data: returns, isLoading: loadingReturns } = useQuery({
    queryKey: ['returns-for-sorting'],
    queryFn: () => listReturns({ status: 'approved' }),
    staleTime: 15_000,
  });

  // ── Data: sorting guidance for selected return ─────────────────
  const {
    data: guidance,
    isLoading: loadingGuidance,
    isError: guidanceError,
  } = useQuery({
    queryKey: ['return-sorting-guidance', selectedReturnId],
    queryFn: () => getSortingGuidance(selectedReturnId!),
    enabled: selectedReturnId !== null,
    staleTime: 30_000,
  });

  // When guidance loads, seed dispositions with recommendations
  useMemo(() => {
    if (!guidance) return;
    const map = new Map<number, ReturnSortingDisposition>();
    for (const item of guidance) {
      map.set(item.return_line_id, {
        return_line_id: item.return_line_id,
        disposition: item.recommended_disposition,
        notes: null,
      });
    }
    setDispositions(map);
  }, [guidance]);

  // ── Mutation: submit dispositions ──────────────────────────────
  const submitMutation = useMutation({
    mutationFn: () =>
      processSortingDispositions(selectedReturnId!, {
        dispositions: Array.from(dispositions.values()),
      }),
    onSuccess: (result) => {
      const r = result as Record<string, unknown[]>;
      const restocked = (r.restocked as unknown[])?.length ?? 0;
      const returned = (r.supplier_returns as unknown[])?.length ?? 0;
      const writtenOff = (r.write_offs as unknown[])?.length ?? 0;
      toast.success(
        `Sorted: ${restocked} restocked, ${returned} to supplier, ${writtenOff} written off`
      );
      // Reset state and refetch the returns list
      setSelectedReturnId(null);
      setDispositions(new Map());
      queryClient.invalidateQueries({ queryKey: ['returns-for-sorting'] });
      queryClient.invalidateQueries({ queryKey: ['return-sorting-guidance'] });
    },
    onError: () => {
      toast.error('Failed to process sorting dispositions');
    },
  });

  // ── Handlers ───────────────────────────────────────────────────

  const handleSelectReturn = useCallback((returnId: number) => {
    setSelectedReturnId(returnId);
    setDispositions(new Map());
    setExpandedLine(null);
  }, []);

  const handleChangeDisposition = useCallback(
    (lineId: number, disposition: ReturnDisposition) => {
      setDispositions((prev) => {
        const next = new Map(prev);
        const existing = next.get(lineId);
        next.set(lineId, {
          return_line_id: lineId,
          disposition,
          notes: existing?.notes ?? null,
        });
        return next;
      });
    },
    []
  );

  const handleChangeNotes = useCallback(
    (lineId: number, notes: string) => {
      setDispositions((prev) => {
        const next = new Map(prev);
        const existing = next.get(lineId);
        if (existing) {
          next.set(lineId, { ...existing, notes: notes || null });
        }
        return next;
      });
    },
    []
  );

  const handleSubmit = useCallback(() => {
    setConfirmOpen(true);
  }, []);

  const confirmSubmit = useCallback(() => {
    setConfirmOpen(false);
    submitMutation.mutate();
  }, [submitMutation]);

  const handleBackToList = useCallback(() => {
    setSelectedReturnId(null);
    setDispositions(new Map());
    setExpandedLine(null);
  }, []);

  // ── Derived values ─────────────────────────────────────────────

  const summary = useMemo(() => {
    const counts = { return_to_supplier: 0, restock: 0, write_off: 0 };
    for (const d of dispositions.values()) {
      counts[d.disposition]++;
    }
    return counts;
  }, [dispositions]);

  const allDecided = dispositions.size === (guidance?.length ?? 0) && dispositions.size > 0;

  // ── Render: Loading ────────────────────────────────────────────

  if (loadingReturns) {
    return <PageSpinner label="Loading approved returns..." />;
  }

  // ── Render: Sorting Detail View ────────────────────────────────

  if (selectedReturnId !== null) {
    return (
      <div className="space-y-4">
        {/* Header */}
        <div className="flex items-center justify-between flex-wrap gap-3">
          <div className="flex items-center gap-3">
            <button
              onClick={handleBackToList}
              className="p-2 rounded-lg bg-surface-secondary hover:bg-border transition-colors min-h-[44px] min-w-[44px] flex items-center justify-center"
              aria-label="Back to returns list"
            >
              <ArrowLeftRight className="h-5 w-5 text-gray-500 dark:text-gray-400" />
            </button>
            <div>
              <h2 className="text-lg font-semibold text-gray-900 dark:text-white">
                Sort Return Items
              </h2>
              <p className="text-sm text-gray-500 dark:text-gray-400">
                Review each item and choose a disposition
              </p>
            </div>
          </div>

          {/* Submit button */}
          <button
            onClick={handleSubmit}
            disabled={!allDecided || submitMutation.isPending}
            className="flex items-center gap-2 px-4 py-2 rounded-lg bg-primary-500 text-white hover:bg-primary-600 disabled:opacity-50 disabled:cursor-not-allowed transition-colors min-h-[44px]"
          >
            {submitMutation.isPending ? (
              <Loader2 className="h-4 w-4 animate-spin" />
            ) : (
              <Check className="h-4 w-4" />
            )}
            <span className="hidden sm:inline">Submit Sorting</span>
            <span className="sm:hidden">Submit</span>
          </button>
        </div>

        {/* Summary strip */}
        {dispositions.size > 0 && (
          <div className="flex items-center gap-4 flex-wrap px-4 py-3 rounded-lg bg-surface-secondary">
            <SummaryChip
              icon={Undo2}
              label="Supplier"
              count={summary.return_to_supplier}
              color="text-green-600 dark:text-green-400"
            />
            <SummaryChip
              icon={PackageCheck}
              label="Restock"
              count={summary.restock}
              color="text-amber-600 dark:text-amber-400"
            />
            <SummaryChip
              icon={Trash2}
              label="Write Off"
              count={summary.write_off}
              color="text-red-600 dark:text-red-400"
            />
          </div>
        )}

        {/* Guidance loading / error */}
        {loadingGuidance && <PageSpinner label="Analyzing return items..." />}
        {guidanceError && (
          <div className="px-4 py-3 rounded-lg bg-red-50 dark:bg-red-900/20 text-red-700 dark:text-red-300 text-sm">
            Failed to load sorting guidance. Please try again.
          </div>
        )}

        {/* Line items */}
        {guidance && (
          <div className="space-y-2">
            {guidance.map((item) => (
              <SortingLineItem
                key={item.return_line_id}
                item={item}
                disposition={dispositions.get(item.return_line_id)}
                isExpanded={expandedLine === item.return_line_id}
                onToggleExpand={() =>
                  setExpandedLine(
                    expandedLine === item.return_line_id ? null : item.return_line_id
                  )
                }
                onChangeDisposition={(d) =>
                  handleChangeDisposition(item.return_line_id, d)
                }
                onChangeNotes={(n) => handleChangeNotes(item.return_line_id, n)}
              />
            ))}
          </div>
        )}

        {/* Confirm modal */}
        <Modal
          isOpen={confirmOpen}
          onClose={() => setConfirmOpen(false)}
          title="Confirm Sorting"
        >
          <div className="space-y-3">
            <p className="text-sm text-gray-600 dark:text-gray-400">
              You are about to process {dispositions.size} items:
            </p>
            <ul className="space-y-1 text-sm">
              {summary.return_to_supplier > 0 && (
                <li className="flex items-center gap-2">
                  <Undo2 className="h-4 w-4 text-green-500" />
                  <span>
                    {summary.return_to_supplier} item(s) → Return to Supplier
                  </span>
                </li>
              )}
              {summary.restock > 0 && (
                <li className="flex items-center gap-2">
                  <PackageCheck className="h-4 w-4 text-amber-500" />
                  <span>{summary.restock} item(s) → Restock in Warehouse</span>
                </li>
              )}
              {summary.write_off > 0 && (
                <li className="flex items-center gap-2">
                  <Trash2 className="h-4 w-4 text-red-500" />
                  <span>{summary.write_off} item(s) → Write Off</span>
                </li>
              )}
            </ul>

            <div className="flex justify-end gap-2 pt-3">
              <button
                onClick={() => setConfirmOpen(false)}
                className="px-4 py-2 rounded-lg bg-surface-secondary hover:bg-border transition-colors text-sm min-h-[44px]"
              >
                Cancel
              </button>
              <button
                onClick={confirmSubmit}
                className="px-4 py-2 rounded-lg bg-primary-500 text-white hover:bg-primary-600 transition-colors text-sm min-h-[44px]"
              >
                Confirm & Process
              </button>
            </div>
          </div>
        </Modal>
      </div>
    );
  }

  // ── Render: Return Selection List ──────────────────────────────

  if (!returns || returns.length === 0) {
    return (
      <EmptyState
        icon={<ArrowLeftRight className="h-12 w-12" />}
        title="No Returns to Sort"
        description="When returns are approved, they'll appear here for warehouse sorting and triage."
      />
    );
  }

  return (
    <div className="space-y-4">
      <div>
        <h2 className="text-lg font-semibold text-gray-900 dark:text-white">
          Returns Awaiting Sorting
        </h2>
        <p className="text-sm text-gray-500 dark:text-gray-400">
          Select a return to review items and decide disposition
        </p>
      </div>

      <div className="space-y-2">
        {returns.map((ret) => (
          <ReturnCard key={ret.id} ret={ret} onSelect={handleSelectReturn} />
        ))}
      </div>
    </div>
  );
}


// ── Sub-components ───────────────────────────────────────────────

/** Card for a return in the selection list */
function ReturnCard({
  ret,
  onSelect,
}: {
  ret: ReturnListItem;
  onSelect: (id: number) => void;
}) {
  return (
    <button
      onClick={() => onSelect(ret.id)}
      className="w-full text-left p-4 rounded-lg bg-white dark:bg-surface-secondary border border-border hover:border-primary-300 dark:hover:border-primary-700 transition-colors shadow-sm"
    >
      <div className="flex items-center justify-between flex-wrap gap-2">
        <div className="min-w-0">
          <div className="flex items-center gap-2 flex-wrap">
            <span className="font-medium text-gray-900 dark:text-white">
              {ret.return_number}
            </span>
            <Badge
              variant={ret.return_type === 'job_to_warehouse' ? 'primary' : 'warning'}
            >
              {ret.return_type === 'job_to_warehouse' ? 'Job Return' : 'Supplier Return'}
            </Badge>
          </div>
          <p className="text-sm text-gray-500 dark:text-gray-400 mt-1 truncate">
            {ret.job_name && `Job: ${ret.job_name}`}
            {ret.supplier_name && `Supplier: ${ret.supplier_name}`}
            {!ret.job_name && !ret.supplier_name && 'General return'}
            {' • '}
            {ret.line_count} item{ret.line_count !== 1 ? 's' : ''}
          </p>
        </div>
        <div className="text-sm text-gray-500 dark:text-gray-400">
          {ret.initiator_name && <span>By {ret.initiator_name}</span>}
        </div>
      </div>
    </button>
  );
}


/** Single line item with sorting controls */
function SortingLineItem({
  item,
  disposition,
  isExpanded,
  onToggleExpand,
  onChangeDisposition,
  onChangeNotes,
}: {
  item: ReturnSortingGuidance;
  disposition?: ReturnSortingDisposition;
  isExpanded: boolean;
  onToggleExpand: () => void;
  onChangeDisposition: (d: ReturnDisposition) => void;
  onChangeNotes: (n: string) => void;
}) {
  const currentDisposition = disposition?.disposition ?? item.recommended_disposition;
  const isOverridden = disposition && disposition.disposition !== item.recommended_disposition;
  const Icon = DISPOSITION_ICONS[currentDisposition];

  return (
    <div className="rounded-lg border border-border bg-white dark:bg-surface-secondary overflow-hidden">
      {/* Main row */}
      <div
        className="flex items-center gap-3 p-3 cursor-pointer hover:bg-gray-50 dark:hover:bg-surface-secondary/80 transition-colors"
        onClick={onToggleExpand}
      >
        {/* Disposition indicator */}
        <div
          className={`flex-shrink-0 w-10 h-10 rounded-lg flex items-center justify-center ${DISPOSITION_COLORS[currentDisposition]}`}
        >
          <Icon className="h-5 w-5" />
        </div>

        {/* Part info */}
        <div className="flex-1 min-w-0">
          <div className="flex items-center gap-2 flex-wrap">
            <span className="font-medium text-gray-900 dark:text-white text-sm truncate">
              {item.part_description || item.part_number || `Part #${item.part_id}`}
            </span>
            {item.part_number && item.part_description && (
              <span className="text-xs text-gray-400 dark:text-gray-500">
                {item.part_number}
              </span>
            )}
          </div>
          <div className="flex items-center gap-2 mt-0.5 flex-wrap">
            <span className="text-xs text-gray-500 dark:text-gray-400">
              Qty: {item.qty}
            </span>
            <span className={`text-xs px-1.5 py-0.5 rounded ${CONDITION_COLORS[item.condition] ?? CONDITION_COLORS.used}`}>
              {CONDITION_LABELS[item.condition] ?? item.condition}
            </span>
            {item.below_target && (
              <span className="flex items-center gap-1 text-xs text-amber-600 dark:text-amber-400">
                <TrendingDown className="h-3 w-3" />
                Below target
              </span>
            )}
            {isOverridden && (
              <span className="text-xs text-blue-600 dark:text-blue-400 font-medium">
                (overridden)
              </span>
            )}
          </div>
        </div>

        {/* Disposition label + expand toggle */}
        <div className="flex items-center gap-2 flex-shrink-0">
          <span className={`hidden sm:inline-block text-xs px-2 py-1 rounded-full ${DISPOSITION_COLORS[currentDisposition]}`}>
            {DISPOSITION_LABELS[currentDisposition]}
          </span>
          {isExpanded ? (
            <ChevronUp className="h-4 w-4 text-gray-400" />
          ) : (
            <ChevronDown className="h-4 w-4 text-gray-400" />
          )}
        </div>
      </div>

      {/* Expanded detail */}
      {isExpanded && (
        <div className="border-t border-border p-4 space-y-4 bg-gray-50/50 dark:bg-surface/50">
          {/* Recommendation info */}
          <div className="flex items-start gap-2 p-3 rounded-lg bg-blue-50 dark:bg-blue-900/20 text-blue-700 dark:text-blue-300 text-sm">
            <Info className="h-4 w-4 mt-0.5 flex-shrink-0" />
            <div>
              <p className="font-medium">Recommendation: {DISPOSITION_LABELS[item.recommended_disposition]}</p>
              <p className="text-xs mt-0.5 opacity-80">{item.recommendation_reason}</p>
            </div>
          </div>

          {/* Stock info */}
          <div className="grid grid-cols-2 sm:grid-cols-4 gap-3 text-sm">
            <div>
              <span className="text-gray-500 dark:text-gray-400 text-xs block">Stock</span>
              <span className="font-medium text-gray-900 dark:text-white">
                {item.current_stock}
              </span>
            </div>
            <div>
              <span className="text-gray-500 dark:text-gray-400 text-xs block">Target</span>
              <span className="font-medium text-gray-900 dark:text-white">
                {item.target_qty}
              </span>
            </div>
            <div>
              <span className="text-gray-500 dark:text-gray-400 text-xs block">Returnable</span>
              <span className={`font-medium ${item.returnable_to_supplier ? 'text-green-600 dark:text-green-400' : 'text-red-600 dark:text-red-400'}`}>
                {item.returnable_to_supplier ? 'Yes' : 'No'}
              </span>
            </div>
            <div>
              <span className="text-gray-500 dark:text-gray-400 text-xs block">Condition</span>
              <span className="font-medium text-gray-900 dark:text-white">
                {CONDITION_LABELS[item.condition] ?? item.condition}
              </span>
            </div>
          </div>

          {/* Below target warning */}
          {item.below_target && (
            <div className="flex items-start gap-2 p-3 rounded-lg bg-amber-50 dark:bg-amber-900/20 text-amber-700 dark:text-amber-300 text-sm">
              <AlertTriangle className="h-4 w-4 mt-0.5 flex-shrink-0" />
              <span>
                Stock is below target ({item.current_stock} of {item.target_qty})
                — consider restocking instead of returning to supplier.
              </span>
            </div>
          )}

          {/* Non-return reason */}
          {item.non_return_reason && (
            <div className="flex items-start gap-2 p-3 rounded-lg bg-red-50 dark:bg-red-900/20 text-red-700 dark:text-red-300 text-sm">
              <AlertTriangle className="h-4 w-4 mt-0.5 flex-shrink-0" />
              <span>{item.non_return_reason}</span>
            </div>
          )}

          {/* Disposition selector */}
          <div>
            <label className="block text-xs font-medium text-gray-700 dark:text-gray-300 mb-2">
              Choose Disposition
            </label>
            <div className="flex flex-wrap gap-2">
              {(['return_to_supplier', 'restock', 'write_off'] as ReturnDisposition[]).map((d) => {
                const DIcon = DISPOSITION_ICONS[d];
                const isActive = currentDisposition === d;
                return (
                  <button
                    key={d}
                    onClick={() => onChangeDisposition(d)}
                    className={`flex items-center gap-2 px-3 py-2 rounded-lg border text-sm min-h-[44px] transition-colors ${
                      isActive
                        ? `border-primary-500 ${DISPOSITION_COLORS[d]} ring-2 ring-primary-300 dark:ring-primary-700`
                        : 'border-border bg-surface hover:bg-surface-secondary text-gray-700 dark:text-gray-300'
                    }`}
                  >
                    <DIcon className="h-4 w-4" />
                    {DISPOSITION_LABELS[d]}
                    {isActive && <CheckCircle2 className="h-4 w-4" />}
                  </button>
                );
              })}
            </div>
          </div>

          {/* Notes */}
          <div>
            <label className="block text-xs font-medium text-gray-700 dark:text-gray-300 mb-1">
              Notes (optional)
            </label>
            <input
              type="text"
              value={disposition?.notes ?? ''}
              onChange={(e) => onChangeNotes(e.target.value)}
              placeholder="Add a note about this item..."
              className="w-full px-3 py-2 rounded-lg border border-border bg-surface text-sm text-gray-900 dark:text-white placeholder-gray-400 dark:placeholder-gray-500 focus:outline-none focus:ring-2 focus:ring-primary-300 dark:focus:ring-primary-700 min-h-[44px]"
            />
          </div>

          {/* Checklist (condition inspection reminders) */}
          <div className="space-y-1">
            <label className="block text-xs font-medium text-gray-700 dark:text-gray-300">
              Inspection Checklist
            </label>
            <InspectionChecklist />
          </div>
        </div>
      )}
    </div>
  );
}


/** Static inspection checklist — reminder for warehouse staff */
function InspectionChecklist() {
  const [checks, setChecks] = useState([false, false, false]);

  const items = [
    'Check for physical damage',
    'Check if opened or used',
    'Check for custom modifications',
  ];

  return (
    <div className="space-y-1">
      {items.map((label, i) => (
        <label
          key={i}
          className="flex items-center gap-2 text-sm text-gray-600 dark:text-gray-400 cursor-pointer py-1"
        >
          <input
            type="checkbox"
            checked={checks[i]}
            onChange={() =>
              setChecks((prev) => {
                const next = [...prev];
                next[i] = !next[i];
                return next;
              })
            }
            className="rounded border-border text-primary-500 focus:ring-primary-300 dark:focus:ring-primary-700 h-4 w-4"
          />
          {label}
          {checks[i] && (
            <CheckCircle2 className="h-3.5 w-3.5 text-green-500" />
          )}
        </label>
      ))}
    </div>
  );
}


/** Summary chip shown in the header strip */
function SummaryChip({
  icon: Icon,
  label,
  count,
  color,
}: {
  icon: typeof Undo2;
  label: string;
  count: number;
  color: string;
}) {
  return (
    <div className="flex items-center gap-1.5 text-sm">
      <Icon className={`h-4 w-4 ${color}`} />
      <span className="text-gray-600 dark:text-gray-400">{label}:</span>
      <span className={`font-medium ${color}`}>{count}</span>
    </div>
  );
}
