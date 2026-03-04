/**
 * PartsRequestsPage — Job Parts Orders (JPOs) list.
 *
 * Shows all JPOs with status filter tabs. Field workers see their own
 * requests; office users see everything. "New Parts Request" button
 * opens the JPO creation flow.
 */

import { useState } from 'react';
import { useQuery } from '@tanstack/react-query';
import { Link } from 'react-router-dom';
import { Plus, ClipboardList, Search } from 'lucide-react';
import { listJPOs } from '../../../api/orders';
import { EmptyState } from '../../../components/ui/EmptyState';
import { OrderStatusBadge } from '../components/OrderStatusBadge';
import type { JPOListItem, JPOStatus } from '../../../lib/types';

const STATUS_TABS: { label: string; value: string | undefined }[] = [
  { label: 'All', value: undefined },
  { label: 'Draft', value: 'draft' },
  { label: 'Pending Approval', value: 'pending_approval' },
  { label: 'Approved', value: 'approved' },
  { label: 'In Progress', value: 'ordering' },
];

export function PartsRequestsPage() {
  const [statusFilter, setStatusFilter] = useState<string | undefined>(undefined);
  const [search, setSearch] = useState('');

  const { data: jpos = [], isLoading, isError } = useQuery({
    queryKey: ['jpos', statusFilter],
    queryFn: () => listJPOs(statusFilter ? { status: statusFilter } : undefined),
  });

  const filteredJPOs = search
    ? jpos.filter(
        (j) =>
          j.order_number.toLowerCase().includes(search.toLowerCase()) ||
          j.job_name?.toLowerCase().includes(search.toLowerCase()) ||
          j.requester_name?.toLowerCase().includes(search.toLowerCase())
      )
    : jpos;

  return (
    <div className="space-y-4">
      {/* Header */}
      <div className="flex items-center justify-between">
        <h1 className="text-xl font-semibold text-gray-900 dark:text-gray-100">
          Parts Requests
        </h1>
        <Link
          to="/orders/parts-requests/new"
          className="inline-flex items-center gap-2 rounded-lg bg-primary px-4 py-2 text-sm font-medium text-white shadow-sm hover:bg-primary/90 transition-colors"
        >
          <Plus className="h-4 w-4" />
          New Parts Request
        </Link>
      </div>

      {/* Status filter tabs */}
      <div className="flex gap-1 border-b border-border">
        {STATUS_TABS.map((tab) => (
          <button
            key={tab.label}
            onClick={() => setStatusFilter(tab.value)}
            className={`px-3 py-2 text-sm font-medium border-b-2 transition-colors ${
              statusFilter === tab.value
                ? 'border-primary text-primary'
                : 'border-transparent text-gray-500 dark:text-gray-400 hover:text-gray-700 dark:hover:text-gray-300'
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
          placeholder="Search by order #, job, or requester..."
          value={search}
          onChange={(e) => setSearch(e.target.value)}
          className="w-full rounded-lg border border-border bg-surface py-2 pl-10 pr-4 text-sm text-gray-900 dark:text-gray-100 placeholder:text-gray-400"
        />
      </div>

      {/* JPO List */}
      {isError ? (
        <div className="rounded-lg border border-red-200 dark:border-red-800 bg-red-50 dark:bg-red-900/20 p-4 text-sm text-red-700 dark:text-red-300">
          Failed to load parts requests. Please try refreshing.
        </div>
      ) : isLoading ? (
        <div className="flex justify-center py-12">
          <div className="h-8 w-8 animate-spin rounded-full border-4 border-primary border-t-transparent" />
        </div>
      ) : filteredJPOs.length === 0 ? (
        <EmptyState
          icon={<ClipboardList className="h-12 w-12" />}
          title="No parts requests"
          description={statusFilter ? 'No requests match this filter.' : 'Create your first parts request to get started.'}
        />
      ) : (
        <div className="overflow-hidden rounded-lg border border-border bg-surface">
          <table className="min-w-full divide-y divide-border">
            <thead className="bg-surface-secondary">
              <tr>
                <th className="px-4 py-3 text-left text-xs font-medium uppercase text-gray-500 dark:text-gray-400">Order #</th>
                <th className="px-4 py-3 text-left text-xs font-medium uppercase text-gray-500 dark:text-gray-400">Job</th>
                <th className="px-4 py-3 text-left text-xs font-medium uppercase text-gray-500 dark:text-gray-400">Items</th>
                <th className="px-4 py-3 text-left text-xs font-medium uppercase text-gray-500 dark:text-gray-400">Status</th>
                <th className="px-4 py-3 text-left text-xs font-medium uppercase text-gray-500 dark:text-gray-400">Requested By</th>
                <th className="px-4 py-3 text-left text-xs font-medium uppercase text-gray-500 dark:text-gray-400">Date</th>
              </tr>
            </thead>
            <tbody className="divide-y divide-border">
              {filteredJPOs.map((jpo) => (
                <tr
                  key={jpo.id}
                  className="hover:bg-surface-secondary/50 transition-colors cursor-pointer"
                >
                  <td className="px-4 py-3">
                    <Link
                      to={`/orders/parts-requests/${jpo.id}`}
                      className="font-medium text-primary hover:underline"
                    >
                      {jpo.order_number}
                    </Link>
                  </td>
                  <td className="px-4 py-3 text-sm text-gray-700 dark:text-gray-300">
                    {jpo.job_name || jpo.job_number || '—'}
                  </td>
                  <td className="px-4 py-3 text-sm text-gray-500 dark:text-gray-400">
                    {jpo.line_count} item{jpo.line_count !== 1 ? 's' : ''}
                  </td>
                  <td className="px-4 py-3">
                    <OrderStatusBadge status={jpo.status} type="jpo" />
                  </td>
                  <td className="px-4 py-3 text-sm text-gray-500 dark:text-gray-400">
                    {jpo.requester_name || '—'}
                  </td>
                  <td className="px-4 py-3 text-sm text-gray-500 dark:text-gray-400">
                    {jpo.created_at
                      ? new Date(jpo.created_at).toLocaleDateString()
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
