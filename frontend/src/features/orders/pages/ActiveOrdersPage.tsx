/**
 * ActiveOrdersPage — submitted/acknowledged/partially received POs.
 *
 * Replaces the old PendingOrdersPage. Shows POs that have been sent
 * to suppliers and are in various stages of fulfillment.
 */

import { useQuery } from '@tanstack/react-query';
import { Link } from 'react-router-dom';
import { Package, Search } from 'lucide-react';
import { useState } from 'react';
import { listActivePOs } from '../../../api/orders';
import { EmptyState } from '../../../components/ui/EmptyState';
import { OrderStatusBadge } from '../components/OrderStatusBadge';

export function ActiveOrdersPage() {
  const [search, setSearch] = useState('');

  const { data: pos = [], isLoading, isError } = useQuery({
    queryKey: ['pos', 'active'],
    queryFn: listActivePOs,
  });

  const filtered = search
    ? pos.filter(
        (p) =>
          p.po_number.toLowerCase().includes(search.toLowerCase()) ||
          p.supplier_name?.toLowerCase().includes(search.toLowerCase())
      )
    : pos;

  return (
    <div className="space-y-4">
      <h1 className="text-xl font-semibold text-gray-900 dark:text-gray-100">
        Active Orders
      </h1>

      {/* Search */}
      <div className="relative">
        <Search className="absolute left-3 top-1/2 h-4 w-4 -translate-y-1/2 text-gray-400" />
        <input
          type="text"
          placeholder="Search by PO # or supplier..."
          value={search}
          onChange={(e) => setSearch(e.target.value)}
          className="w-full rounded-lg border border-border bg-surface py-2 pl-10 pr-4 text-sm text-gray-900 dark:text-gray-100 placeholder:text-gray-400"
        />
      </div>

      {isError ? (
        <div className="rounded-lg border border-red-200 dark:border-red-800 bg-red-50 dark:bg-red-900/20 p-4 text-sm text-red-700 dark:text-red-300">
          Failed to load active orders. Please try refreshing.
        </div>
      ) : isLoading ? (
        <div className="flex justify-center py-12">
          <div className="h-8 w-8 animate-spin rounded-full border-4 border-primary border-t-transparent" />
        </div>
      ) : filtered.length === 0 ? (
        <EmptyState
          icon={<Package className="h-12 w-12" />}
          title="No active orders"
          description="Submitted purchase orders will appear here as they're being fulfilled."
        />
      ) : (
        <div className="overflow-hidden rounded-lg border border-border bg-surface">
          <table className="min-w-full divide-y divide-border">
            <thead className="bg-surface-secondary">
              <tr>
                <th className="px-4 py-3 text-left text-xs font-medium uppercase text-gray-500 dark:text-gray-400">PO #</th>
                <th className="px-4 py-3 text-left text-xs font-medium uppercase text-gray-500 dark:text-gray-400">Supplier</th>
                <th className="px-4 py-3 text-left text-xs font-medium uppercase text-gray-500 dark:text-gray-400">Items</th>
                <th className="px-4 py-3 text-left text-xs font-medium uppercase text-gray-500 dark:text-gray-400">Status</th>
                <th className="px-4 py-3 text-right text-xs font-medium uppercase text-gray-500 dark:text-gray-400">Total</th>
                <th className="px-4 py-3 text-left text-xs font-medium uppercase text-gray-500 dark:text-gray-400">Expected</th>
              </tr>
            </thead>
            <tbody className="divide-y divide-border">
              {filtered.map((po) => (
                <tr
                  key={po.id}
                  className="hover:bg-surface-secondary/50 transition-colors cursor-pointer"
                >
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
                  <td className="px-4 py-3 text-right text-sm font-medium text-gray-900 dark:text-gray-100">
                    {po.total_cost != null
                      ? `$${po.total_cost.toLocaleString(undefined, { minimumFractionDigits: 2, maximumFractionDigits: 2 })}`
                      : '—'}
                  </td>
                  <td className="px-4 py-3 text-sm text-gray-500 dark:text-gray-400">
                    {po.expected_delivery
                      ? new Date(po.expected_delivery).toLocaleDateString()
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
