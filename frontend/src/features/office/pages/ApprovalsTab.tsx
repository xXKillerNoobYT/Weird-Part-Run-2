/**
 * ApprovalsTab — Office module tab for managing pending approvals.
 *
 * Shows a unified queue of pending JPOs and pending returns:
 *   - Expandable rows to see line items inline
 *   - "Has Special Items" badge highlights flagged orders
 *   - Bulk approve/reject with notes
 *   - Filter by entity type (JPO / Return / All)
 *   - Badge count in tab header via countPendingApprovals
 *
 * Lives under: Orders > Office group > Approvals tab
 * Permission: manage_orders
 */

import { useState, useMemo, useCallback } from 'react';
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import { useNavigate } from 'react-router-dom';
import {
  CheckCircle,
  XCircle,
  AlertTriangle,
  ChevronDown,
  ChevronRight,
  Loader2,
  Package,
  RotateCcw,
  Clock,
  Sparkles,
  User,
  Briefcase,
  FolderTree,
} from 'lucide-react';
import { PageSpinner } from '../../../components/ui/Spinner';
import { EmptyState } from '../../../components/ui/EmptyState';
import { Badge } from '../../../components/ui/Badge';
import { Modal } from '../../../components/ui/Modal';
import { Button } from '../../../components/ui/Button';
import { OrderStatusBadge } from '../../orders/components/OrderStatusBadge';
import { SpecialItemPlacementModal } from '../../orders/components/SpecialItemPlacementModal';
import {
  getPendingApprovals,
  countPendingApprovals,
  bulkApproveOrReject,
  listFlaggedSpecialItems,
  resolveSpecialItem,
} from '../../../api/orders';
import { toast } from '../../../lib/toast';
import { formatRelativeTime } from '../../../lib/utils';
import type {
  PendingApprovalItem,
  BulkApprovalTarget,
  BulkApprovalResult,
  SpecialItemResponse,
} from '../../../lib/types';


// ── Filter options ──────────────────────────────────────────────

type EntityFilter = 'all' | 'jpo' | 'return';

const ENTITY_FILTERS: { label: string; value: EntityFilter }[] = [
  { label: 'All', value: 'all' },
  { label: 'Job Orders', value: 'jpo' },
  { label: 'Returns', value: 'return' },
];


// ── Expandable Row ──────────────────────────────────────────────

function ApprovalRow({
  item,
  isSelected,
  onToggleSelect,
  isExpanded,
  onToggleExpand,
}: {
  item: PendingApprovalItem;
  isSelected: boolean;
  onToggleSelect: () => void;
  isExpanded: boolean;
  onToggleExpand: () => void;
}) {
  const navigate = useNavigate();

  const handleNavigate = () => {
    if (item.entity_type === 'jpo') {
      navigate(`/orders/parts-requests/${item.entity_id}`);
    } else {
      navigate(`/orders/returns/${item.entity_id}`);
    }
  };

  return (
    <div className="border-b border-gray-200 dark:border-gray-700 last:border-b-0">
      {/* ── Main row ──────────────────────────────────────── */}
      <div className="flex items-center gap-2 px-3 py-2.5 hover:bg-gray-50 dark:hover:bg-gray-800/50 transition-colors min-h-[52px]">
        {/* Checkbox */}
        <label className="flex-shrink-0 min-w-[36px] min-h-[36px] flex items-center justify-center">
          <input
            type="checkbox"
            checked={isSelected}
            onChange={onToggleSelect}
            className="h-4 w-4 rounded border-gray-300 dark:border-gray-600 text-primary focus:ring-primary"
          />
        </label>

        {/* Expand toggle */}
        <button
          type="button"
          onClick={onToggleExpand}
          className="flex-shrink-0 p-1 rounded hover:bg-gray-200 dark:hover:bg-gray-700 transition-colors min-w-[28px] min-h-[28px] flex items-center justify-center"
        >
          {isExpanded ? (
            <ChevronDown className="h-4 w-4 text-gray-400 dark:text-gray-500" />
          ) : (
            <ChevronRight className="h-4 w-4 text-gray-400 dark:text-gray-500" />
          )}
        </button>

        {/* Entity type icon */}
        <div className="flex-shrink-0">
          {item.entity_type === 'jpo' ? (
            <Package className="h-4 w-4 text-blue-500 dark:text-blue-400" />
          ) : (
            <RotateCcw className="h-4 w-4 text-amber-500 dark:text-amber-400" />
          )}
        </div>

        {/* Reference + details */}
        <button
          type="button"
          onClick={handleNavigate}
          className="flex-1 min-w-0 text-left"
        >
          <div className="flex items-center gap-2 flex-wrap">
            <span className="text-sm font-medium text-gray-900 dark:text-gray-100 font-mono">
              {item.reference_number}
            </span>
            <OrderStatusBadge
              status={item.status}
              type={item.entity_type === 'jpo' ? 'jpo' : 'return'}
            />
            {item.priority === 'urgent' && (
              <Badge variant="danger">Urgent</Badge>
            )}
            {item.has_special_items && (
              <span className="inline-flex items-center gap-0.5 rounded-full bg-violet-100 dark:bg-violet-900/30 text-violet-600 dark:text-violet-400 px-2 py-0.5 text-[10px] font-medium">
                <Sparkles className="h-3 w-3" />
                Special Items
              </span>
            )}
          </div>
          <div className="flex items-center gap-3 mt-0.5 text-xs text-gray-500 dark:text-gray-400">
            {item.requester_name && (
              <span className="inline-flex items-center gap-1">
                <User className="h-3 w-3" />
                {item.requester_name}
              </span>
            )}
            {item.job_name && (
              <span className="inline-flex items-center gap-1 truncate max-w-[200px]">
                <Briefcase className="h-3 w-3" />
                {item.job_name}
              </span>
            )}
            {item.entity_type === 'return' && item.supplier_name && (
              <span className="truncate max-w-[150px]">
                → {item.supplier_name}
              </span>
            )}
            <span className="inline-flex items-center gap-1 flex-shrink-0">
              <Clock className="h-3 w-3" />
              {formatRelativeTime(item.created_at)}
            </span>
          </div>
        </button>

        {/* Line count badge */}
        <span className="flex-shrink-0 text-xs text-gray-500 dark:text-gray-400 tabular-nums">
          {item.line_count} {item.line_count === 1 ? 'line' : 'lines'}
        </span>
      </div>

      {/* ── Expanded detail (inline summary — full detail on click) ── */}
      {isExpanded && (
        <div className="px-4 pb-3 pl-[72px] text-xs text-gray-500 dark:text-gray-400 space-y-1.5">
          <div className="flex flex-wrap gap-x-4 gap-y-1">
            <span>
              <strong className="text-gray-700 dark:text-gray-300">Type:</strong>{' '}
              {item.entity_type === 'jpo'
                ? item.order_type === 'warehouse' ? 'Warehouse Restock' : 'Job Order'
                : `Return (${item.return_type?.replace(/_/g, ' ') ?? 'unknown'})`}
            </span>
            {item.reason && (
              <span>
                <strong className="text-gray-700 dark:text-gray-300">Reason:</strong>{' '}
                {item.reason.replace(/_/g, ' ')}
              </span>
            )}
          </div>
          <button
            type="button"
            onClick={handleNavigate}
            className="text-primary hover:underline font-medium"
          >
            View full details →
          </button>
        </div>
      )}
    </div>
  );
}


// ── Main Component ──────────────────────────────────────────────

export function ApprovalsTab() {
  const queryClient = useQueryClient();
  const [entityFilter, setEntityFilter] = useState<EntityFilter>('all');
  const [selected, setSelected] = useState<Set<string>>(new Set()); // "jpo:123" keys
  const [expanded, setExpanded] = useState<Set<string>>(new Set());
  const [showBulkModal, setShowBulkModal] = useState(false);
  const [bulkAction, setBulkAction] = useState<'approve' | 'reject'>('approve');
  const [bulkNotes, setBulkNotes] = useState('');
  const [bulkResults, setBulkResults] = useState<BulkApprovalResult[] | null>(null);
  const [placementItem, setPlacementItem] = useState<SpecialItemResponse | null>(null);

  // ── Queries ───────────────────────────────────────────────────
  const {
    data: items = [],
    isLoading,
    isError,
  } = useQuery({
    queryKey: ['pending-approvals'],
    queryFn: () => getPendingApprovals({ limit: 200 }),
    staleTime: 15_000,
    refetchInterval: 30_000,
  });

  const { data: counts } = useQuery({
    queryKey: ['pending-approvals-count'],
    queryFn: countPendingApprovals,
    staleTime: 15_000,
    refetchInterval: 30_000,
  });

  const { data: flaggedItems = [] } = useQuery({
    queryKey: ['flagged-special-items'],
    queryFn: () => listFlaggedSpecialItems(),
    staleTime: 30_000,
  });

  // ── Filtered items ────────────────────────────────────────────
  const filteredItems = useMemo(
    () =>
      entityFilter === 'all'
        ? items
        : items.filter((i) => i.entity_type === entityFilter),
    [items, entityFilter],
  );

  // ── Selection helpers ─────────────────────────────────────────
  const makeKey = (item: PendingApprovalItem) => `${item.entity_type}:${item.entity_id}`;

  const toggleSelect = useCallback((item: PendingApprovalItem) => {
    const key = makeKey(item);
    setSelected((prev) => {
      const next = new Set(prev);
      if (next.has(key)) next.delete(key);
      else next.add(key);
      return next;
    });
  }, []);

  const selectAll = useCallback(() => {
    setSelected(new Set(filteredItems.map(makeKey)));
  }, [filteredItems]);

  const deselectAll = useCallback(() => {
    setSelected(new Set());
  }, []);

  const toggleExpand = useCallback((item: PendingApprovalItem) => {
    const key = makeKey(item);
    setExpanded((prev) => {
      const next = new Set(prev);
      if (next.has(key)) next.delete(key);
      else next.add(key);
      return next;
    });
  }, []);

  // ── Bulk action mutation ──────────────────────────────────────
  const bulkMutation = useMutation({
    mutationFn: (action: { items: BulkApprovalTarget[]; action: 'approve' | 'reject'; notes?: string }) =>
      bulkApproveOrReject(action),
    onSuccess: (results) => {
      setBulkResults(results);
      // Refresh all related queries
      queryClient.invalidateQueries({ queryKey: ['pending-approvals'] });
      queryClient.invalidateQueries({ queryKey: ['pending-approvals-count'] });
      queryClient.invalidateQueries({ queryKey: ['jpos'] });
      queryClient.invalidateQueries({ queryKey: ['returns'] });
      setSelected(new Set());
    },
  });

  const dismissMutation = useMutation({
    mutationFn: (itemId: number) =>
      resolveSpecialItem(itemId, { notes: 'Dismissed from Approvals' }),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['flagged-special-items'] });
      toast.success('Special item dismissed');
    },
    onError: () => toast.error('Failed to dismiss item'),
  });

  const handleBulkAction = (action: 'approve' | 'reject') => {
    setBulkAction(action);
    setBulkNotes('');
    setBulkResults(null);
    setShowBulkModal(true);
  };

  const executeBulk = () => {
    const targets: BulkApprovalTarget[] = Array.from(selected).map((key) => {
      const [entity_type, entity_id] = key.split(':');
      return { entity_type: entity_type as 'jpo' | 'return', entity_id: Number(entity_id) };
    });
    bulkMutation.mutate({
      items: targets,
      action: bulkAction,
      notes: bulkNotes.trim() || undefined,
    });
  };

  // ── Loading / Error / Empty states ────────────────────────────
  if (isLoading) return <PageSpinner />;

  if (isError) {
    return (
      <EmptyState
        icon={AlertTriangle}
        title="Failed to load approvals"
        description="Could not fetch pending approvals. Please try again."
      />
    );
  }

  return (
    <div className="space-y-4">
      {/* ── Header bar ──────────────────────────────────────── */}
      <div className="flex items-center justify-between flex-wrap gap-3">
        <div className="flex items-center gap-3">
          <h2 className="text-lg font-semibold text-gray-900 dark:text-gray-100">
            Approvals
          </h2>
          {counts && (
            <div className="flex items-center gap-2">
              {counts.jpo_count > 0 && (
                <Badge variant="primary">{counts.jpo_count} JPO{counts.jpo_count !== 1 ? 's' : ''}</Badge>
              )}
              {counts.return_count > 0 && (
                <Badge variant="warning">{counts.return_count} Return{counts.return_count !== 1 ? 's' : ''}</Badge>
              )}
            </div>
          )}
        </div>

        {/* Filter chips */}
        <div className="flex items-center gap-1.5">
          {ENTITY_FILTERS.map((f) => (
            <button
              key={f.value}
              type="button"
              onClick={() => setEntityFilter(f.value)}
              className={`rounded-full px-3 py-1.5 text-xs font-medium transition-colors min-h-[36px] ${
                entityFilter === f.value
                  ? 'bg-primary text-white'
                  : 'bg-gray-100 dark:bg-gray-700 text-gray-600 dark:text-gray-400 hover:bg-gray-200 dark:hover:bg-gray-600'
              }`}
            >
              {f.label}
            </button>
          ))}
        </div>
      </div>

      {/* ── Bulk action bar (visible when items selected) ──── */}
      {selected.size > 0 && (
        <div className="flex items-center gap-2 bg-primary/5 dark:bg-primary/10 border border-primary/20 rounded-lg px-4 py-2.5 flex-wrap">
          <span className="text-sm font-medium text-primary">
            {selected.size} selected
          </span>
          <span className="flex-1" />
          <button
            type="button"
            onClick={deselectAll}
            className="text-xs text-gray-500 dark:text-gray-400 hover:text-gray-700 dark:hover:text-gray-200 min-h-[36px] px-2"
          >
            Deselect All
          </button>
          <button
            type="button"
            onClick={() => handleBulkAction('approve')}
            className="inline-flex items-center gap-1.5 rounded-lg bg-green-600 text-white px-3 py-1.5 text-sm font-medium hover:bg-green-700 transition-colors min-h-[36px]"
          >
            <CheckCircle className="h-4 w-4" />
            <span className="hidden sm:inline">Approve</span>
          </button>
          <button
            type="button"
            onClick={() => handleBulkAction('reject')}
            className="inline-flex items-center gap-1.5 rounded-lg bg-red-600 text-white px-3 py-1.5 text-sm font-medium hover:bg-red-700 transition-colors min-h-[36px]"
          >
            <XCircle className="h-4 w-4" />
            <span className="hidden sm:inline">Reject</span>
          </button>
        </div>
      )}

      {/* ── Items list ──────────────────────────────────────── */}
      {filteredItems.length === 0 ? (
        <EmptyState
          icon={CheckCircle}
          title="No pending approvals"
          description={
            entityFilter === 'all'
              ? 'All orders and returns have been reviewed.'
              : `No pending ${entityFilter === 'jpo' ? 'job orders' : 'returns'} to approve.`
          }
        />
      ) : (
        <div className="rounded-lg border border-gray-200 dark:border-gray-700 bg-white dark:bg-gray-800 overflow-hidden">
          {/* Select All header */}
          <div className="flex items-center gap-2 px-3 py-2 bg-gray-50 dark:bg-gray-800/70 border-b border-gray-200 dark:border-gray-700">
            <label className="flex-shrink-0 min-w-[36px] min-h-[36px] flex items-center justify-center">
              <input
                type="checkbox"
                checked={selected.size === filteredItems.length && filteredItems.length > 0}
                onChange={() => (selected.size === filteredItems.length ? deselectAll() : selectAll())}
                className="h-4 w-4 rounded border-gray-300 dark:border-gray-600 text-primary focus:ring-primary"
              />
            </label>
            <span className="text-xs text-gray-500 dark:text-gray-400 font-medium">
              {selected.size === filteredItems.length && filteredItems.length > 0
                ? 'Deselect All'
                : `Select All (${filteredItems.length})`}
            </span>
          </div>

          {/* Rows */}
          {filteredItems.map((item) => {
            const key = makeKey(item);
            return (
              <ApprovalRow
                key={key}
                item={item}
                isSelected={selected.has(key)}
                onToggleSelect={() => toggleSelect(item)}
                isExpanded={expanded.has(key)}
                onToggleExpand={() => toggleExpand(item)}
              />
            );
          })}
        </div>
      )}

      {/* ── Flagged Special Items ────────────────────────── */}
      {flaggedItems.length > 0 && (
        <div className="space-y-2">
          <div className="flex items-center gap-2">
            <FolderTree className="h-4 w-4 text-violet-500 dark:text-violet-400" />
            <h3 className="text-sm font-semibold text-gray-900 dark:text-gray-100">
              Flagged Special Items
            </h3>
            <Badge variant="default">{flaggedItems.length}</Badge>
            <span className="text-xs text-gray-500 dark:text-gray-400">
              — These items aren't in the catalog yet. Place them or dismiss.
            </span>
          </div>

          <div className="rounded-lg border border-violet-200 dark:border-violet-800 bg-violet-50/50 dark:bg-violet-900/10 overflow-hidden divide-y divide-violet-100 dark:divide-violet-800/50">
            {flaggedItems.map((flagged) => (
              <div
                key={flagged.id}
                className="flex items-center gap-3 px-4 py-3 min-h-[52px] flex-wrap"
              >
                <Sparkles className="h-4 w-4 text-violet-500 dark:text-violet-400 flex-shrink-0" />

                <div className="flex-1 min-w-0">
                  <p className="text-sm font-medium text-gray-900 dark:text-gray-100 truncate">
                    {flagged.description}
                  </p>
                  <div className="flex items-center gap-3 mt-0.5 text-xs text-gray-500 dark:text-gray-400 flex-wrap">
                    {flagged.part_number && (
                      <span className="font-mono">MPN: {flagged.part_number}</span>
                    )}
                    {flagged.requester_name && (
                      <span className="inline-flex items-center gap-1">
                        <User className="h-3 w-3" />
                        {flagged.requester_name}
                      </span>
                    )}
                    {flagged.job_name && (
                      <span className="inline-flex items-center gap-1">
                        <Briefcase className="h-3 w-3" />
                        {flagged.job_name}
                      </span>
                    )}
                  </div>
                </div>

                <div className="flex items-center gap-2 flex-shrink-0">
                  <Button
                    size="sm"
                    variant="secondary"
                    onClick={() => setPlacementItem(flagged)}
                  >
                    <FolderTree className="h-3.5 w-3.5" />
                    <span className="hidden sm:inline ml-1">Place in Catalog</span>
                  </Button>
                  <button
                    type="button"
                    onClick={() => dismissMutation.mutate(flagged.id)}
                    disabled={dismissMutation.isPending}
                    className="p-1.5 rounded text-gray-400 dark:text-gray-500 hover:text-red-500 dark:hover:text-red-400 hover:bg-red-50 dark:hover:bg-red-900/20 transition-colors min-h-[36px] min-w-[36px] flex items-center justify-center"
                    title="Dismiss"
                  >
                    <XCircle className="h-4 w-4" />
                  </button>
                </div>
              </div>
            ))}
          </div>
        </div>
      )}

      {/* ── Bulk action confirmation modal ──────────────────── */}
      <Modal
        isOpen={showBulkModal}
        onClose={() => {
          setShowBulkModal(false);
          setBulkResults(null);
        }}
        title={
          bulkResults
            ? 'Bulk Action Complete'
            : `${bulkAction === 'approve' ? 'Approve' : 'Reject'} ${selected.size} Item${selected.size !== 1 ? 's' : ''}`
        }
      >
        {bulkResults ? (
          // ── Results view ───────────────────────────────────
          <div className="space-y-3">
            {bulkResults.map((r, i) => (
              <div
                key={i}
                className={`flex items-center gap-2 rounded-lg px-3 py-2 text-sm ${
                  r.success
                    ? 'bg-green-50 dark:bg-green-900/20 text-green-700 dark:text-green-400'
                    : 'bg-red-50 dark:bg-red-900/20 text-red-700 dark:text-red-400'
                }`}
              >
                {r.success ? (
                  <CheckCircle className="h-4 w-4 flex-shrink-0" />
                ) : (
                  <XCircle className="h-4 w-4 flex-shrink-0" />
                )}
                <span className="font-mono">
                  {r.entity_type.toUpperCase()} #{r.entity_id}
                </span>
                {r.error && (
                  <span className="text-xs opacity-70 ml-2">{r.error}</span>
                )}
              </div>
            ))}
            <div className="flex justify-end pt-2">
              <button
                type="button"
                onClick={() => {
                  setShowBulkModal(false);
                  setBulkResults(null);
                }}
                className="rounded-lg bg-gray-100 dark:bg-gray-700 text-gray-700 dark:text-gray-300 px-4 py-2 text-sm font-medium hover:bg-gray-200 dark:hover:bg-gray-600 min-h-[44px]"
              >
                Close
              </button>
            </div>
          </div>
        ) : (
          // ── Confirmation form ──────────────────────────────
          <div className="space-y-4">
            <p className="text-sm text-gray-600 dark:text-gray-400">
              {bulkAction === 'approve'
                ? `You are about to approve ${selected.size} pending item${selected.size !== 1 ? 's' : ''}. This will move them forward in the workflow.`
                : `You are about to reject ${selected.size} pending item${selected.size !== 1 ? 's' : ''}. They will be sent back to the requester.`}
            </p>

            <div>
              <label className="block text-sm font-medium text-gray-700 dark:text-gray-300 mb-1">
                Notes (optional)
              </label>
              <textarea
                value={bulkNotes}
                onChange={(e) => setBulkNotes(e.target.value)}
                placeholder={
                  bulkAction === 'approve'
                    ? 'Optional approval notes…'
                    : 'Reason for rejection…'
                }
                rows={3}
                className="w-full rounded-lg border border-gray-300 dark:border-gray-600 bg-white dark:bg-gray-800 px-3 py-2 text-sm text-gray-900 dark:text-gray-100 placeholder:text-gray-400 dark:placeholder:text-gray-500 focus:ring-2 focus:ring-primary-300 focus:border-primary-500 resize-none"
              />
            </div>

            <div className="flex justify-end gap-2 pt-2">
              <button
                type="button"
                onClick={() => setShowBulkModal(false)}
                className="rounded-lg bg-gray-100 dark:bg-gray-700 text-gray-700 dark:text-gray-300 px-4 py-2 text-sm font-medium hover:bg-gray-200 dark:hover:bg-gray-600 min-h-[44px]"
              >
                Cancel
              </button>
              <button
                type="button"
                onClick={executeBulk}
                disabled={bulkMutation.isPending}
                className={`inline-flex items-center gap-1.5 rounded-lg text-white px-4 py-2 text-sm font-medium transition-colors min-h-[44px] disabled:opacity-50 ${
                  bulkAction === 'approve'
                    ? 'bg-green-600 hover:bg-green-700'
                    : 'bg-red-600 hover:bg-red-700'
                }`}
              >
                {bulkMutation.isPending ? (
                  <Loader2 className="h-4 w-4 animate-spin" />
                ) : bulkAction === 'approve' ? (
                  <CheckCircle className="h-4 w-4" />
                ) : (
                  <XCircle className="h-4 w-4" />
                )}
                {bulkAction === 'approve' ? 'Approve' : 'Reject'}
              </button>
            </div>
          </div>
        )}
      </Modal>

      {/* ── Special item placement wizard ────────────────── */}
      {placementItem && (
        <SpecialItemPlacementModal
          item={placementItem}
          onClose={() => setPlacementItem(null)}
        />
      )}
    </div>
  );
}
