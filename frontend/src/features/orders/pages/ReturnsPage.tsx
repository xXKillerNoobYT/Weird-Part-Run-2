/**
 * ReturnsPage — manage part returns and RMAs (updated Phase 7C).
 *
 * Role-aware views:
 *  - Field workers: simplified card view of their returns, create new
 *    job-to-warehouse returns, read-only supplier return status
 *  - Office staff (manage_orders): full table with type/status filters,
 *    search, all columns
 *
 * Located at: Orders > Returns tab
 */

import { useState } from 'react';
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import { Link } from 'react-router-dom';
import {
  Plus,
  RotateCcw,
  Search,
  ChevronRight,
  Package,
  Truck,
  Info,
  Check,
} from 'lucide-react';
import { listReturns, bulkApproveReturns } from '../../../api/orders';
import { EmptyState } from '../../../components/ui/EmptyState';
import { OrderStatusBadge } from '../components/OrderStatusBadge';
import {
  useBulkSelection,
  BulkCheckbox,
  BulkActionBar,
  type BulkAction,
} from '../components/BulkActionBar';
import { useAuthStore } from '../../../stores/auth-store';
import { PERMISSIONS } from '../../../lib/constants';
import type { ReturnListItem } from '../../../lib/types';


// ── Constants ────────────────────────────────────────────────────

const RETURN_TABS: { label: string; value: string | undefined }[] = [
  { label: 'All Returns', value: undefined },
  { label: 'Job Returns', value: 'job_to_warehouse' },
  { label: 'Supplier Returns', value: 'warehouse_to_supplier' },
];

const STATUS_TABS: { label: string; value: string | undefined }[] = [
  { label: 'All', value: undefined },
  { label: 'Draft', value: 'draft' },
  { label: 'Pending', value: 'pending_approval' },
  { label: 'Approved', value: 'approved' },
  { label: 'Shipped', value: 'shipped' },
];

/**
 * Status flow explanation for field workers — helps them understand
 * where their return is in the pipeline without needing warehouse access.
 */
const STATUS_FLOW_STEPS = [
  { label: 'Draft', desc: 'You created the return' },
  { label: 'Pending', desc: 'Waiting for office approval' },
  { label: 'Approved', desc: 'Office approved — warehouse will sort it' },
  { label: 'Shipped / Closed', desc: 'Items restocked or sent to supplier' },
];


// ── Main Page ────────────────────────────────────────────────────

export function ReturnsPage() {
  const { hasPermission } = useAuthStore();
  const isOfficeUser = hasPermission(PERMISSIONS.MANAGE_ORDERS);

  // Office users get the full table; field workers get the card view
  return isOfficeUser ? <OfficeReturnsView /> : <FieldWorkerReturnsView />;
}


// ── Office View (full table with filters) ────────────────────────

function OfficeReturnsView() {
  const [typeFilter, setTypeFilter] = useState<string | undefined>(undefined);
  const [statusFilter, setStatusFilter] = useState<string | undefined>(undefined);
  const [search, setSearch] = useState('');
  const queryClient = useQueryClient();

  const { data: returns = [], isLoading, isError } = useQuery({
    queryKey: ['returns', typeFilter, statusFilter],
    queryFn: () =>
      listReturns({
        return_type: typeFilter,
        status: statusFilter,
      }),
  });

  const filtered = search
    ? returns.filter(
        (r: ReturnListItem) =>
          r.return_number.toLowerCase().includes(search.toLowerCase()) ||
          r.supplier_name?.toLowerCase().includes(search.toLowerCase()) ||
          r.job_name?.toLowerCase().includes(search.toLowerCase())
      )
    : returns;

  // Bulk selection
  const bulk = useBulkSelection(filtered);

  // Bulk approve returns
  const bulkApproveMut = useMutation({
    mutationFn: () =>
      bulkApproveReturns({ return_ids: [...bulk.selectedIds] }),
    onSuccess: () => {
      bulk.clear();
      queryClient.invalidateQueries({ queryKey: ['returns'] });
    },
  });

  // Only show approve action when pending_approval returns are selected
  const hasPendingSelected = bulk.selectedItems.some(
    (r) => r.status === 'pending_approval'
  );

  const bulkActions: BulkAction[] = [
    {
      label: 'Approve',
      icon: Check,
      onClick: () => bulkApproveMut.mutate(),
      variant: 'primary',
      loading: bulkApproveMut.isPending,
      show: hasPendingSelected,
    },
  ];

  /** Clear selection whenever filters change */
  const handleTypeFilter = (v: string | undefined) => {
    setTypeFilter(v);
    bulk.clear();
  };
  const handleStatusFilter = (v: string | undefined) => {
    setStatusFilter(v);
    bulk.clear();
  };

  return (
    <div className="space-y-4">
      {/* Header */}
      <div className="flex items-center justify-between flex-wrap gap-3">
        <h1 className="text-xl font-semibold text-gray-900 dark:text-gray-100">
          Returns
        </h1>
        <Link
          to="/orders/returns/new"
          className="inline-flex items-center gap-2 rounded-lg bg-primary px-3 py-2 text-sm font-medium text-white shadow-sm hover:bg-primary/90 transition-colors min-h-[44px]"
        >
          <Plus className="h-4 w-4" />
          <span className="hidden sm:inline">New Return</span>
        </Link>
      </div>

      {/* Return type tabs */}
      <div className="flex gap-1 border-b border-border overflow-x-auto">
        {RETURN_TABS.map((tab) => (
          <button
            key={tab.label}
            onClick={() => handleTypeFilter(tab.value)}
            className={`px-3 py-2 text-sm font-medium border-b-2 transition-colors whitespace-nowrap min-h-[44px] ${
              typeFilter === tab.value
                ? 'border-primary text-primary'
                : 'border-transparent text-gray-500 dark:text-gray-400 hover:text-gray-700 dark:hover:text-gray-300'
            }`}
          >
            {tab.label}
          </button>
        ))}
      </div>

      {/* Status filter pills */}
      <div className="flex flex-wrap gap-2">
        {STATUS_TABS.map((tab) => (
          <button
            key={tab.label}
            onClick={() => handleStatusFilter(tab.value)}
            className={`rounded-full px-3 py-1 text-xs font-medium transition-colors ${
              statusFilter === tab.value
                ? 'bg-primary text-white'
                : 'bg-gray-100 text-gray-600 hover:bg-gray-200 dark:bg-gray-700 dark:text-gray-300 dark:hover:bg-gray-600'
            }`}
          >
            {tab.label}
          </button>
        ))}
      </div>

      {/* Search */}
      <div className="relative">
        <Search className="absolute left-3 top-1/2 h-4 w-4 -translate-y-1/2 text-gray-400" />
        <input
          type="text"
          placeholder="Search by return #, supplier, or job..."
          value={search}
          onChange={(e) => setSearch(e.target.value)}
          className="w-full rounded-lg border border-border bg-surface py-2 pl-10 pr-4 text-sm text-gray-900 dark:text-gray-100 placeholder:text-gray-400 min-h-[44px]"
        />
      </div>

      {/* Returns list */}
      {isError ? (
        <div className="rounded-lg border border-red-200 dark:border-red-800 bg-red-50 dark:bg-red-900/20 p-4 text-sm text-red-700 dark:text-red-300">
          Failed to load returns. Please try refreshing.
        </div>
      ) : isLoading ? (
        <div className="flex justify-center py-12">
          <div className="h-8 w-8 animate-spin rounded-full border-4 border-primary border-t-transparent" />
        </div>
      ) : filtered.length === 0 ? (
        <EmptyState
          icon={<RotateCcw className="h-12 w-12" />}
          title="No returns"
          description={
            typeFilter || statusFilter || search
              ? 'No returns match your filters.'
              : 'No returns have been created yet.'
          }
        />
      ) : (
        <div className="overflow-x-auto rounded-lg border border-border bg-surface">
          <table className="min-w-full divide-y divide-border">
            <thead className="bg-surface-secondary">
              <tr>
                <BulkCheckbox
                  checked={bulk.allSelected}
                  indeterminate={bulk.someSelected}
                  onChange={bulk.toggleAll}
                  isHeader
                />
                <th className="px-4 py-3 text-left text-xs font-medium uppercase text-gray-500 dark:text-gray-400">Return #</th>
                <th className="px-4 py-3 text-left text-xs font-medium uppercase text-gray-500 dark:text-gray-400 hidden sm:table-cell">Type</th>
                <th className="px-4 py-3 text-left text-xs font-medium uppercase text-gray-500 dark:text-gray-400">Supplier / Job</th>
                <th className="px-4 py-3 text-left text-xs font-medium uppercase text-gray-500 dark:text-gray-400">Items</th>
                <th className="px-4 py-3 text-left text-xs font-medium uppercase text-gray-500 dark:text-gray-400">Status</th>
                <th className="px-4 py-3 text-left text-xs font-medium uppercase text-gray-500 dark:text-gray-400 hidden md:table-cell">Reason</th>
                <th className="px-4 py-3 text-left text-xs font-medium uppercase text-gray-500 dark:text-gray-400 hidden md:table-cell">Date</th>
              </tr>
            </thead>
            <tbody className="divide-y divide-border">
              {filtered.map((ret: ReturnListItem) => (
                <tr
                  key={ret.id}
                  className={`hover:bg-surface-secondary/50 transition-colors cursor-pointer ${
                    bulk.isSelected(ret.id) ? 'bg-primary/5 dark:bg-primary/10' : ''
                  }`}
                >
                  <BulkCheckbox
                    checked={bulk.isSelected(ret.id)}
                    onChange={() => bulk.toggle(ret.id)}
                  />
                  <td className="px-4 py-3">
                    <Link
                      to={`/orders/returns/${ret.id}`}
                      className="font-medium text-primary hover:underline"
                    >
                      {ret.return_number}
                    </Link>
                  </td>
                  <td className="px-4 py-3 text-sm text-gray-500 dark:text-gray-400 hidden sm:table-cell">
                    {ret.return_type === 'job_to_warehouse' ? 'Job → Warehouse' : 'Supplier RMA'}
                  </td>
                  <td className="px-4 py-3 text-sm text-gray-700 dark:text-gray-300">
                    {ret.return_type === 'warehouse_to_supplier'
                      ? ret.supplier_name || '—'
                      : ret.job_name || '—'}
                  </td>
                  <td className="px-4 py-3 text-sm text-gray-500 dark:text-gray-400">
                    {ret.line_count} item{ret.line_count !== 1 ? 's' : ''}
                  </td>
                  <td className="px-4 py-3">
                    <OrderStatusBadge status={ret.status} type="return" />
                  </td>
                  <td className="px-4 py-3 text-sm text-gray-500 dark:text-gray-400 capitalize hidden md:table-cell">
                    {ret.reason?.replace(/_/g, ' ') || '—'}
                  </td>
                  <td className="px-4 py-3 text-sm text-gray-500 dark:text-gray-400 hidden md:table-cell">
                    {ret.created_at
                      ? new Date(ret.created_at).toLocaleDateString()
                      : '—'}
                  </td>
                </tr>
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
        loading={bulkApproveMut.isPending}
      />
    </div>
  );
}


// ── Field Worker View (simplified card layout) ───────────────────

function FieldWorkerReturnsView() {
  const [search, setSearch] = useState('');

  const { data: returns = [], isLoading, isError } = useQuery({
    queryKey: ['returns', 'field-worker'],
    queryFn: () => listReturns({}),
  });

  const filtered = search
    ? returns.filter(
        (r: ReturnListItem) =>
          r.return_number.toLowerCase().includes(search.toLowerCase()) ||
          r.job_name?.toLowerCase().includes(search.toLowerCase())
      )
    : returns;

  // Separate active (non-closed) from completed
  const active = filtered.filter(
    (r) => !['closed', 'credited'].includes(r.status)
  );
  const completed = filtered.filter((r) =>
    ['closed', 'credited'].includes(r.status)
  );

  return (
    <div className="space-y-4">
      {/* Header */}
      <div className="flex items-center justify-between flex-wrap gap-3">
        <div>
          <h1 className="text-xl font-semibold text-gray-900 dark:text-gray-100">
            My Returns
          </h1>
          <p className="text-sm text-gray-500 dark:text-gray-400">
            Return unused parts from jobs back to the warehouse
          </p>
        </div>
        <Link
          to="/orders/returns/new"
          className="inline-flex items-center gap-2 rounded-lg bg-primary px-4 py-2 text-sm font-medium text-white shadow-sm hover:bg-primary/90 transition-colors min-h-[44px]"
        >
          <Plus className="h-4 w-4" />
          <span className="hidden sm:inline">New Return</span>
        </Link>
      </div>

      {/* How it works callout */}
      <ReturnFlowExplainer />

      {/* Search */}
      {returns.length > 3 && (
        <div className="relative">
          <Search className="absolute left-3 top-1/2 h-4 w-4 -translate-y-1/2 text-gray-400" />
          <input
            type="text"
            placeholder="Search by return # or job..."
            value={search}
            onChange={(e) => setSearch(e.target.value)}
            className="w-full rounded-lg border border-border bg-surface py-2 pl-10 pr-4 text-sm text-gray-900 dark:text-gray-100 placeholder:text-gray-400 min-h-[44px]"
          />
        </div>
      )}

      {/* Content */}
      {isError ? (
        <div className="rounded-lg border border-red-200 dark:border-red-800 bg-red-50 dark:bg-red-900/20 p-4 text-sm text-red-700 dark:text-red-300">
          Failed to load returns. Please try refreshing.
        </div>
      ) : isLoading ? (
        <div className="flex justify-center py-12">
          <div className="h-8 w-8 animate-spin rounded-full border-4 border-primary border-t-transparent" />
        </div>
      ) : returns.length === 0 ? (
        <EmptyState
          icon={<RotateCcw className="h-12 w-12" />}
          title="No returns yet"
          description="When you return unused parts from a job, they'll show up here so you can track their status."
        />
      ) : (
        <div className="space-y-6">
          {/* Active returns */}
          {active.length > 0 && (
            <div className="space-y-2">
              <h2 className="text-sm font-medium text-gray-500 dark:text-gray-400 uppercase tracking-wider">
                Active ({active.length})
              </h2>
              <div className="space-y-2">
                {active.map((ret) => (
                  <ReturnCard key={ret.id} ret={ret} />
                ))}
              </div>
            </div>
          )}

          {/* Completed returns */}
          {completed.length > 0 && (
            <div className="space-y-2">
              <h2 className="text-sm font-medium text-gray-500 dark:text-gray-400 uppercase tracking-wider">
                Completed ({completed.length})
              </h2>
              <div className="space-y-2">
                {completed.map((ret) => (
                  <ReturnCard key={ret.id} ret={ret} />
                ))}
              </div>
            </div>
          )}
        </div>
      )}
    </div>
  );
}


// ── Sub-components ───────────────────────────────────────────────

/** Card-style display for a return (used in field worker view) */
function ReturnCard({ ret }: { ret: ReturnListItem }) {
  return (
    <Link
      to={`/orders/returns/${ret.id}`}
      className="block p-4 rounded-lg bg-white dark:bg-surface-secondary border border-border hover:border-primary-300 dark:hover:border-primary-700 transition-colors shadow-sm"
    >
      <div className="flex items-center justify-between gap-3">
        <div className="min-w-0 flex-1">
          {/* Top line: return number + status */}
          <div className="flex items-center gap-2 flex-wrap">
            <span className="font-medium text-gray-900 dark:text-white">
              {ret.return_number}
            </span>
            <OrderStatusBadge status={ret.status} type="return" />
          </div>

          {/* Middle: job/supplier context */}
          <div className="flex items-center gap-2 mt-1 text-sm text-gray-500 dark:text-gray-400">
            {ret.return_type === 'job_to_warehouse' ? (
              <>
                <Truck className="h-3.5 w-3.5 flex-shrink-0" />
                <span className="truncate">
                  {ret.job_name ? `Job: ${ret.job_name}` : 'Job return'}
                </span>
              </>
            ) : (
              <>
                <Package className="h-3.5 w-3.5 flex-shrink-0" />
                <span className="truncate">
                  {ret.supplier_name
                    ? `Supplier: ${ret.supplier_name}`
                    : 'Supplier return'}
                </span>
              </>
            )}
            <span className="flex-shrink-0">
              • {ret.line_count} item{ret.line_count !== 1 ? 's' : ''}
            </span>
          </div>

          {/* Bottom: date */}
          {ret.created_at && (
            <p className="text-xs text-gray-400 dark:text-gray-500 mt-1">
              {new Date(ret.created_at).toLocaleDateString()}
            </p>
          )}
        </div>

        <ChevronRight className="h-5 w-5 text-gray-400 dark:text-gray-500 flex-shrink-0" />
      </div>
    </Link>
  );
}


/** Collapsible explainer showing the return flow stages */
function ReturnFlowExplainer() {
  const [isOpen, setIsOpen] = useState(false);

  return (
    <div className="rounded-lg border border-blue-200 dark:border-blue-800 bg-blue-50 dark:bg-blue-900/20">
      <button
        onClick={() => setIsOpen(!isOpen)}
        className="flex items-center gap-2 w-full px-4 py-3 text-sm text-blue-700 dark:text-blue-300 min-h-[44px]"
      >
        <Info className="h-4 w-4 flex-shrink-0" />
        <span className="font-medium">How returns work</span>
        <ChevronRight
          className={`h-4 w-4 ml-auto transition-transform ${
            isOpen ? 'rotate-90' : ''
          }`}
        />
      </button>

      {isOpen && (
        <div className="px-4 pb-4 space-y-2 border-t border-blue-200 dark:border-blue-800 pt-3">
          {STATUS_FLOW_STEPS.map((step, i) => (
            <div key={i} className="flex items-start gap-3">
              <div className="flex-shrink-0 w-6 h-6 rounded-full bg-blue-200 dark:bg-blue-800 text-blue-700 dark:text-blue-300 text-xs font-medium flex items-center justify-center mt-0.5">
                {i + 1}
              </div>
              <div>
                <span className="text-sm font-medium text-gray-900 dark:text-white">
                  {step.label}
                </span>
                <span className="text-sm text-gray-500 dark:text-gray-400">
                  {' — '}
                  {step.desc}
                </span>
              </div>
            </div>
          ))}
          <p className="text-xs text-gray-500 dark:text-gray-400 mt-2 ml-9">
            Once approved, warehouse staff sort items: restock, return to supplier, or write off.
          </p>
        </div>
      )}
    </div>
  );
}
