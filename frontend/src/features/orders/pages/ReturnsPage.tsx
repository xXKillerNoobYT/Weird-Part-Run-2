/**
 * ReturnsPage — manage part returns and RMAs.
 *
 * Two sections toggled by tabs:
 *  - Job Returns: parts coming back from field via truck → staging
 *  - Supplier Returns: RMA tracking with status timeline
 */

import { useState } from 'react';
import { useQuery } from '@tanstack/react-query';
import { Link } from 'react-router-dom';
import { Plus, RotateCcw, Search } from 'lucide-react';
import { listReturns } from '../../../api/orders';
import { EmptyState } from '../../../components/ui/EmptyState';
import { OrderStatusBadge } from '../components/OrderStatusBadge';
import type { ReturnListItem } from '../../../lib/types';

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

export function ReturnsPage() {
  const [typeFilter, setTypeFilter] = useState<string | undefined>(undefined);
  const [statusFilter, setStatusFilter] = useState<string | undefined>(undefined);
  const [search, setSearch] = useState('');

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

  return (
    <div className="space-y-4">
      {/* Header */}
      <div className="flex items-center justify-between flex-wrap gap-3">
        <h1 className="text-xl font-semibold text-gray-900 dark:text-gray-100">
          Returns
        </h1>
        <Link
          to="/orders/returns/new"
          className="inline-flex items-center gap-2 rounded-lg bg-primary px-3 py-2 text-sm font-medium text-white shadow-sm hover:bg-primary/90 transition-colors min-h-[40px]"
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
            onClick={() => setTypeFilter(tab.value)}
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
            onClick={() => setStatusFilter(tab.value)}
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
          className="w-full rounded-lg border border-border bg-surface py-2 pl-10 pr-4 text-sm text-gray-900 dark:text-gray-100 placeholder:text-gray-400"
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
        <div className="overflow-hidden rounded-lg border border-border bg-surface">
          <table className="min-w-full divide-y divide-border">
            <thead className="bg-surface-secondary">
              <tr>
                <th className="px-4 py-3 text-left text-xs font-medium uppercase text-gray-500 dark:text-gray-400">Return #</th>
                <th className="px-4 py-3 text-left text-xs font-medium uppercase text-gray-500 dark:text-gray-400">Type</th>
                <th className="px-4 py-3 text-left text-xs font-medium uppercase text-gray-500 dark:text-gray-400">Supplier / Job</th>
                <th className="px-4 py-3 text-left text-xs font-medium uppercase text-gray-500 dark:text-gray-400">Items</th>
                <th className="px-4 py-3 text-left text-xs font-medium uppercase text-gray-500 dark:text-gray-400">Status</th>
                <th className="px-4 py-3 text-left text-xs font-medium uppercase text-gray-500 dark:text-gray-400">Reason</th>
                <th className="px-4 py-3 text-left text-xs font-medium uppercase text-gray-500 dark:text-gray-400">Date</th>
              </tr>
            </thead>
            <tbody className="divide-y divide-border">
              {filtered.map((ret: ReturnListItem) => (
                <tr
                  key={ret.id}
                  className="hover:bg-surface-secondary/50 transition-colors cursor-pointer"
                >
                  <td className="px-4 py-3">
                    <Link
                      to={`/orders/returns/${ret.id}`}
                      className="font-medium text-primary hover:underline"
                    >
                      {ret.return_number}
                    </Link>
                  </td>
                  <td className="px-4 py-3 text-sm text-gray-500 dark:text-gray-400">
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
                  <td className="px-4 py-3 text-sm text-gray-500 dark:text-gray-400 capitalize">
                    {ret.reason?.replace(/_/g, ' ') || '—'}
                  </td>
                  <td className="px-4 py-3 text-sm text-gray-500 dark:text-gray-400">
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
    </div>
  );
}
