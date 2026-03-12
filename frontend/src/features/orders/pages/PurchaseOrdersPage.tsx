/**
 * PurchaseOrdersPage — unified view for all Purchase Orders (POs).
 *
 * Replaces the old 3 separate tabs (Draft POs, Active Orders, Incoming)
 * with a single page + in-page status filter tabs, matching the
 * PartsRequestsPage pattern for a consistent "one tab, many filters" UX.
 *
 * Sub-tabs:
 *   All       — every PO regardless of status
 *   Drafts    — draft POs being assembled
 *   Submitted — submitted / acknowledged, awaiting delivery
 *   Receiving — partially received, delivery in progress
 *   Complete  — received / closed / cancelled
 *
 * Phase 7E: Added bulk selection with BulkActionBar for batch
 * submit (drafts) and status updates (submitted).
 */

import { useState } from 'react';
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import { Link } from 'react-router-dom';
import { Plus, Search, ShoppingCart, Truck, Send } from 'lucide-react';
import { listPOs, bulkSubmitPOs } from '../../../api/orders';
import { EmptyState } from '../../../components/ui/EmptyState';
import { OrderStatusBadge } from '../components/OrderStatusBadge';
import {
  useBulkSelection,
  BulkCheckbox,
  BulkActionBar,
  type BulkAction,
} from '../components/BulkActionBar';
import type { POListItem } from '../../../lib/types';

// ── Filter tab definitions ───────────────────────────────────────
type POViewFilter = 'all' | 'drafts' | 'submitted' | 'receiving' | 'complete';

const STATUS_TABS: { label: string; value: POViewFilter }[] = [
  { label: 'All', value: 'all' },
  { label: 'Drafts', value: 'drafts' },
  { label: 'Submitted', value: 'submitted' },
  { label: 'Receiving', value: 'receiving' },
  { label: 'Complete', value: 'complete' },
];

/** Map each filter tab to the PO statuses it includes */
const FILTER_STATUSES: Record<POViewFilter, string[] | null> = {
  all: null,                                         // no filter
  drafts: ['draft'],
  submitted: ['submitted', 'acknowledged', 'confirmed'],
  receiving: ['partially_received'],
  complete: ['received', 'closed', 'cancelled'],
};

export function PurchaseOrdersPage() {
  const [activeTab, setActiveTab] = useState<POViewFilter>('all');
  const [search, setSearch] = useState('');
  const queryClient = useQueryClient();

  // Fetch all POs once — client-side filtering by tab is instant
  const { data: allPOs = [], isLoading, isError } = useQuery({
    queryKey: ['pos', 'all'],
    queryFn: () => listPOs(),
  });

  // Apply tab filter
  const statusFilter = FILTER_STATUSES[activeTab];
  const tabFiltered = statusFilter
    ? allPOs.filter((po) => statusFilter.includes(po.status))
    : allPOs;

  // Apply search filter
  const filtered = search
    ? tabFiltered.filter(
      (po) =>
        po.po_number.toLowerCase().includes(search.toLowerCase()) ||
        po.supplier_name?.toLowerCase().includes(search.toLowerCase())
    )
    : tabFiltered;

  // Bulk selection
  const bulk = useBulkSelection(filtered);

  // Bulk submit drafts
  const bulkSubmitMut = useMutation({
    mutationFn: () =>
      bulkSubmitPOs({ po_ids: [...bulk.selectedIds] }),
    onSuccess: () => {
      bulk.clear();
      queryClient.invalidateQueries({ queryKey: ['pos'] });
    },
  });

  // Only show submit action when draft POs are selected
  const hasDraftsSelected = bulk.selectedItems.some((p) => p.status === 'draft');

  const bulkActions: BulkAction[] = [
    {
      label: 'Submit',
      icon: Send,
      onClick: () => bulkSubmitMut.mutate(),
      variant: 'primary',
      loading: bulkSubmitMut.isPending,
      show: hasDraftsSelected,
    },
  ];

  // Show "Receive Shipment" on tabs where receiving makes sense
  const showReceiveButton = activeTab !== 'drafts' && activeTab !== 'complete';

  return (
    <div className="space-y-4">
      {/* Header */}
      <div className="flex items-center justify-between flex-wrap gap-3">
        <h1 className="text-xl font-semibold text-gray-900 dark:text-gray-100">
          Warehouse Purchase Orders
        </h1>
        <div className="flex items-center gap-2">
          {showReceiveButton && (
            <Link
              to="/orders/purchase-orders/receive"
              className="inline-flex items-center gap-2 rounded-lg border border-border bg-surface px-3 py-2 text-sm font-medium text-gray-700 dark:text-gray-300 shadow-sm hover:bg-surface-secondary transition-colors min-h-[40px]"
            >
              <Truck className="h-4 w-4" />
              <span className="hidden md:inline">Receive Shipment</span>
            </Link>
          )}
          <Link
            to="/orders/purchase-orders/new"
            className="inline-flex items-center gap-2 rounded-lg bg-primary px-3 py-2 text-sm font-medium text-white shadow-sm hover:bg-primary/90 transition-colors min-h-[40px]"
          >
            <Plus className="h-4 w-4" />
            <span className="hidden md:inline">New PO</span>
          </Link>
        </div>
      </div>

      {/* Status filter tabs */}
      <div className="flex gap-1 border-b border-border overflow-x-auto">
        {STATUS_TABS.map((tab) => {
          // Count items for this tab (from unfiltered set)
          const tabStatuses = FILTER_STATUSES[tab.value];
          const count = tabStatuses
            ? allPOs.filter((po) => tabStatuses.includes(po.status)).length
            : allPOs.length;

          return (
            <button
              key={tab.value}
              onClick={() => {
                setActiveTab(tab.value);
                bulk.clear();
              }}
              className={`flex items-center gap-1.5 px-3 py-2.5 text-sm font-medium border-b-2 transition-colors whitespace-nowrap min-h-[44px] ${activeTab === tab.value
                  ? 'border-primary text-primary'
                  : 'border-transparent text-gray-500 dark:text-gray-400 hover:text-gray-700 dark:hover:text-gray-300'
                }`}
            >
              {tab.label}
              {count > 0 && (
                <span
                  className={`text-xs rounded-full px-1.5 py-0.5 tabular-nums ${activeTab === tab.value
                      ? 'bg-primary/10 text-primary'
                      : 'bg-gray-100 dark:bg-gray-700 text-gray-500 dark:text-gray-400'
                    }`}
                >
                  {count}
                </span>
              )}
            </button>
          );
        })}
      </div>

      {/* Search */}
      <div className="relative">
        <Search className="absolute left-3 top-1/2 h-4 w-4 -translate-y-1/2 text-gray-400" />
        <input
          type="text"
          placeholder="Search by PO # or supplier..."
          value={search}
          onChange={(e) => setSearch(e.target.value)}
          className="w-full rounded-lg border border-border bg-surface py-2.5 pl-10 pr-4 text-sm text-gray-900 dark:text-gray-100 placeholder:text-gray-400 min-h-[44px]"
        />
      </div>

      {/* PO Table */}
      {isError ? (
        <div className="rounded-lg border border-red-200 dark:border-red-800 bg-red-50 dark:bg-red-900/20 p-4 text-sm text-red-700 dark:text-red-300">
          Failed to load purchase orders. Please try refreshing.
        </div>
      ) : isLoading ? (
        <div className="flex justify-center py-12">
          <div className="h-8 w-8 animate-spin rounded-full border-4 border-primary border-t-transparent" />
        </div>
      ) : filtered.length === 0 ? (
        <EmptyState
          icon={<ShoppingCart className="h-12 w-12" />}
          title={getEmptyTitle(activeTab)}
          description={getEmptyDescription(activeTab, !!search)}
        />
      ) : (
        <div className="overflow-x-auto overflow-hidden rounded-lg border border-border bg-surface">
          <table className="min-w-full divide-y divide-border">
            <thead className="bg-surface-secondary">
              <tr>
                <BulkCheckbox
                  checked={bulk.allSelected}
                  indeterminate={bulk.someSelected}
                  onChange={bulk.toggleAll}
                  isHeader
                />
                <th className="px-4 py-3 text-left text-xs font-medium uppercase text-gray-500 dark:text-gray-400">PO #</th>
                <th className="px-4 py-3 text-left text-xs font-medium uppercase text-gray-500 dark:text-gray-400">Supplier</th>
                <th className="px-4 py-3 text-left text-xs font-medium uppercase text-gray-500 dark:text-gray-400">Items</th>
                <th className="px-4 py-3 text-left text-xs font-medium uppercase text-gray-500 dark:text-gray-400">Status</th>
                <th className="px-4 py-3 text-left text-xs font-medium uppercase text-gray-500 dark:text-gray-400 hidden sm:table-cell">Expected</th>
                <th className="px-4 py-3 text-right text-xs font-medium uppercase text-gray-500 dark:text-gray-400">Total</th>
                <th className="px-4 py-3 text-left text-xs font-medium uppercase text-gray-500 dark:text-gray-400 hidden lg:table-cell">Created</th>
              </tr>
            </thead>
            <tbody className="divide-y divide-border">
              {filtered.map((po) => (
                <PORow
                  key={po.id}
                  po={po}
                  selected={bulk.isSelected(po.id)}
                  onToggle={() => bulk.toggle(po.id)}
                />
              ))}
            </tbody>
          </table>
        </div>
      )}

      {/* Bulk action bar */}
      <BulkActionBar
        count={bulk.selectedIds.size}
        onClear={bulk.clear}
        actions={bulkActions}
        loading={bulkSubmitMut.isPending}
      />
    </div>
  );
}


/* ── PO table row ──────────────────────────────────────────────── */

function PORow({
  po,
  selected,
  onToggle,
}: {
  po: POListItem;
  selected: boolean;
  onToggle: () => void;
}) {
  return (
    <tr className={`hover:bg-surface-secondary/50 transition-colors cursor-pointer ${selected ? 'bg-primary/5 dark:bg-primary/10' : ''
      }`}>
      <BulkCheckbox checked={selected} onChange={onToggle} />
      <td className="px-4 py-3">
        <Link
          to={`/orders/pos/${po.id}`}
          className="font-medium text-primary hover:underline"
        >
          {po.po_number}
        </Link>
      </td>
      <td className="px-4 py-3 text-sm text-gray-700 dark:text-gray-300">
        {po.supplier_name || '—'}
      </td>
      <td className="px-4 py-3 text-sm text-gray-500 dark:text-gray-400">
        {po.line_count} item{po.line_count !== 1 ? 's' : ''}
      </td>
      <td className="px-4 py-3">
        <OrderStatusBadge status={po.status} type="po" />
      </td>
      <td className="px-4 py-3 text-sm text-gray-500 dark:text-gray-400 hidden sm:table-cell">
        {po.expected_delivery
          ? new Date(po.expected_delivery).toLocaleDateString()
          : '—'}
      </td>
      <td className="px-4 py-3 text-sm text-right text-gray-700 dark:text-gray-300 tabular-nums">
        {po.total_cost != null
          ? `$${po.total_cost.toLocaleString(undefined, { minimumFractionDigits: 2, maximumFractionDigits: 2 })}`
          : '—'}
      </td>
      <td className="px-4 py-3 text-sm text-gray-500 dark:text-gray-400 hidden lg:table-cell">
        {po.created_at
          ? new Date(po.created_at).toLocaleDateString()
          : '—'}
      </td>
    </tr>
  );
}


/* ── Empty state helpers ───────────────────────────────────────── */

function getEmptyTitle(tab: POViewFilter): string {
  switch (tab) {
    case 'drafts': return 'No draft POs';
    case 'submitted': return 'No submitted POs';
    case 'receiving': return 'Nothing to receive';
    case 'complete': return 'No completed POs';
    default: return 'No purchase orders';
  }
}

function getEmptyDescription(tab: POViewFilter, hasSearch: boolean): string {
  if (hasSearch) return 'No POs match your search.';
  switch (tab) {
    case 'drafts': return 'Create a new PO or auto-generate from approved parts requests.';
    case 'submitted': return 'No POs are currently awaiting delivery.';
    case 'receiving': return 'All deliveries are fully received. Nice work!';
    case 'complete': return 'No POs have been completed yet.';
    default: return 'Create your first purchase order to get started.';
  }
}
