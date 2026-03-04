/**
 * IncomingOrdersPage — orders in transit / ready for receiving.
 *
 * Shows POs that have been submitted or acknowledged with items still
 * outstanding. The "Receive Shipment" button opens the receiving wizard
 * (flexible: PO#, supplier, or item scan entry).
 *
 * Two views:
 *  - By PO: each row is a PO with expected items
 *  - All Parts: flat list of all incoming parts across POs (future)
 */

import { useState } from 'react';
import { useQuery } from '@tanstack/react-query';
import { Link } from 'react-router-dom';
import { PackageOpen, Search, Truck } from 'lucide-react';
import { listActivePOs } from '../../../api/orders';
import { EmptyState } from '../../../components/ui/EmptyState';
import { OrderStatusBadge } from '../components/OrderStatusBadge';

const VIEW_TABS: { label: string; value: 'by-po' | 'all-parts' }[] = [
  { label: 'By PO', value: 'by-po' },
  { label: 'All Parts', value: 'all-parts' },
];

export function IncomingOrdersPage() {
  const [view, setView] = useState<'by-po' | 'all-parts'>('by-po');
  const [search, setSearch] = useState('');

  const { data: activePOs = [], isLoading, isError } = useQuery({
    queryKey: ['pos', 'active'],
    queryFn: listActivePOs,
  });

  // Filter to incoming-relevant statuses
  const incomingPOs = activePOs.filter((po) =>
    ['submitted', 'acknowledged', 'partially_received'].includes(po.status)
  );

  const filtered = search
    ? incomingPOs.filter(
        (po) =>
          po.po_number.toLowerCase().includes(search.toLowerCase()) ||
          po.supplier_name?.toLowerCase().includes(search.toLowerCase())
      )
    : incomingPOs;

  return (
    <div className="space-y-4">
      {/* Header */}
      <div className="flex items-center justify-between">
        <h1 className="text-xl font-semibold text-gray-900 dark:text-gray-100">
          Incoming Orders
        </h1>
        <Link
          to="/orders/incoming/receive"
          className="inline-flex items-center gap-2 rounded-lg bg-primary px-4 py-2 text-sm font-medium text-white shadow-sm hover:bg-primary/90 transition-colors"
        >
          <Truck className="h-4 w-4" />
          Receive Shipment
        </Link>
      </div>

      {/* View toggle */}
      <div className="flex gap-1 border-b border-border">
        {VIEW_TABS.map((tab) => (
          <button
            key={tab.value}
            onClick={() => setView(tab.value)}
            className={`px-3 py-2 text-sm font-medium border-b-2 transition-colors ${
              view === tab.value
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
          placeholder="Search by PO # or supplier..."
          value={search}
          onChange={(e) => setSearch(e.target.value)}
          className="w-full rounded-lg border border-border bg-surface py-2 pl-10 pr-4 text-sm text-gray-900 dark:text-gray-100 placeholder:text-gray-400"
        />
      </div>

      {/* Content */}
      {isError ? (
        <div className="rounded-lg border border-red-200 dark:border-red-800 bg-red-50 dark:bg-red-900/20 p-4 text-sm text-red-700 dark:text-red-300">
          Failed to load incoming orders. Please try refreshing.
        </div>
      ) : isLoading ? (
        <div className="flex justify-center py-12">
          <div className="h-8 w-8 animate-spin rounded-full border-4 border-primary border-t-transparent" />
        </div>
      ) : view === 'by-po' ? (
        filtered.length === 0 ? (
          <EmptyState
            icon={<PackageOpen className="h-12 w-12" />}
            title="No incoming orders"
            description={
              search
                ? 'No incoming POs match your search.'
                : 'All submitted POs have been fully received. Nice work!'
            }
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
                  <th className="px-4 py-3 text-left text-xs font-medium uppercase text-gray-500 dark:text-gray-400">Expected</th>
                  <th className="px-4 py-3 text-right text-xs font-medium uppercase text-gray-500 dark:text-gray-400">Total</th>
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
                    <td className="px-4 py-3 text-sm text-gray-500 dark:text-gray-400">
                      {po.expected_delivery
                        ? new Date(po.expected_delivery).toLocaleDateString()
                        : '—'}
                    </td>
                    <td className="px-4 py-3 text-sm text-right text-gray-700 dark:text-gray-300 tabular-nums">
                      {po.total_cost != null
                        ? `$${po.total_cost.toLocaleString(undefined, { minimumFractionDigits: 2, maximumFractionDigits: 2 })}`
                        : '—'}
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )
      ) : (
        /* All Parts view — placeholder for now, will be expanded later */
        <EmptyState
          icon={<PackageOpen className="h-12 w-12" />}
          title="All Parts view"
          description="Flat list of all incoming parts across POs. Coming in Phase 5b."
        />
      )}
    </div>
  );
}
