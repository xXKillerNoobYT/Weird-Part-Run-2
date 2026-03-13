/**
 * ReturnAnalyticsPage — return reason analytics with breakdowns
 * by reason, type, condition, disposition, and top returned parts.
 */

import { useState } from 'react';
import { useQuery } from '@tanstack/react-query';
import { BarChart3, Package, AlertTriangle, ArrowDownRight } from 'lucide-react';
import { Card, CardHeader } from '../../../components/ui/Card';
import { PageSpinner } from '../../../components/ui/Spinner';
import { ErrorFallback } from '../../../components/ui/ErrorFallback';
import { EmptyState } from '../../../components/ui/EmptyState';
import { Badge } from '../../../components/ui/Badge';
import { getReturnAnalytics } from '../../../api/orders';
import type { ReturnAnalytics } from '../../../api/orders';


const REASON_LABELS: Record<string, string> = {
  defective: 'Defective',
  wrong_item: 'Wrong Item',
  surplus: 'Surplus',
  damaged: 'Damaged',
  unused: 'Unused',
};

const DISPOSITION_LABELS: Record<string, string> = {
  return_to_supplier: 'Return to Supplier',
  restock: 'Restock',
  write_off: 'Write Off',
};

const CONDITION_LABELS: Record<string, string> = {
  new: 'New',
  used: 'Used',
  damaged: 'Damaged',
  defective: 'Defective',
};

const TYPE_LABELS: Record<string, string> = {
  job_to_warehouse: 'Job → Warehouse',
  warehouse_to_supplier: 'Warehouse → Supplier',
};


export function ReturnAnalyticsPage() {
  const [startDate, setStartDate] = useState(() => {
    const d = new Date();
    d.setMonth(d.getMonth() - 3);
    return d.toISOString().split('T')[0];
  });
  const [endDate, setEndDate] = useState(() =>
    new Date().toISOString().split('T')[0],
  );
  const [hasGenerated, setHasGenerated] = useState(false);

  const { data, isLoading, isError, refetch } = useQuery({
    queryKey: ['return-analytics', startDate, endDate],
    queryFn: () => getReturnAnalytics({ start_date: startDate, end_date: endDate }),
    enabled: hasGenerated,
    staleTime: 30_000,
  });

  return (
    <div className="space-y-6">
      {/* Controls */}
      <Card>
        <div className="flex items-end flex-wrap gap-4">
          <div className="min-w-[140px]">
            <label className="block text-sm font-medium text-gray-700 dark:text-gray-300 mb-1">From</label>
            <input
              type="date"
              value={startDate}
              onChange={(e) => { setStartDate(e.target.value); setHasGenerated(false); }}
              className="w-full rounded-lg border border-gray-300 dark:border-gray-600
                         bg-white dark:bg-gray-700 px-3 py-2 text-sm
                         text-gray-900 dark:text-gray-100 min-h-[44px]"
            />
          </div>
          <div className="min-w-[140px]">
            <label className="block text-sm font-medium text-gray-700 dark:text-gray-300 mb-1">To</label>
            <input
              type="date"
              value={endDate}
              onChange={(e) => { setEndDate(e.target.value); setHasGenerated(false); }}
              className="w-full rounded-lg border border-gray-300 dark:border-gray-600
                         bg-white dark:bg-gray-700 px-3 py-2 text-sm
                         text-gray-900 dark:text-gray-100 min-h-[44px]"
            />
          </div>
          <button
            onClick={() => setHasGenerated(true)}
            className="inline-flex items-center gap-2 px-6 py-2.5 text-sm font-medium
                       bg-primary-600 text-white rounded-lg hover:bg-primary-700 min-h-[44px]"
          >
            <BarChart3 className="h-4 w-4" />
            Generate
          </button>
        </div>
      </Card>

      {isLoading && <PageSpinner label="Analyzing returns..." />}
      {isError && <ErrorFallback onRetry={refetch} />}
      {hasGenerated && !isLoading && !isError && !data && (
        <EmptyState
          icon={<BarChart3 className="h-12 w-12" />}
          title="No Return Data"
          description="No returns found for the selected period."
        />
      )}

      {data && <AnalyticsContent data={data} />}
    </div>
  );
}


function AnalyticsContent({ data }: { data: ReturnAnalytics }) {
  const { totals, by_reason, by_type, by_condition, by_disposition, top_parts } = data;

  return (
    <>
      {/* Summary Cards */}
      <div className="grid grid-cols-1 sm:grid-cols-3 gap-4">
        <Card>
          <div className="flex items-center gap-3">
            <ArrowDownRight className="h-5 w-5 text-primary-500 flex-shrink-0" />
            <div className="min-w-0">
              <p className="text-xs text-gray-500 dark:text-gray-400">Total Returns</p>
              <p className="text-2xl font-bold text-gray-900 dark:text-gray-100">{totals.total_returns}</p>
            </div>
          </div>
        </Card>
        <Card>
          <div className="flex items-center gap-3">
            <Package className="h-5 w-5 text-primary-500 flex-shrink-0" />
            <div className="min-w-0">
              <p className="text-xs text-gray-500 dark:text-gray-400">Total Items Returned</p>
              <p className="text-2xl font-bold text-gray-900 dark:text-gray-100">{totals.total_items ?? 0}</p>
            </div>
          </div>
        </Card>
        <Card>
          <div className="flex items-center gap-3">
            <AlertTriangle className="h-5 w-5 text-red-500 flex-shrink-0" />
            <div className="min-w-0">
              <p className="text-xs text-gray-500 dark:text-gray-400">Total Cost Impact</p>
              <p className="text-2xl font-bold text-gray-900 dark:text-gray-100">
                ${(totals.total_cost ?? 0).toLocaleString()}
              </p>
            </div>
          </div>
        </Card>
      </div>

      {/* By Reason + By Disposition */}
      <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
        <Card noPadding>
          <CardHeader title="By Reason" subtitle="Why items were returned" />
          <BarList
            items={by_reason.map((r) => ({
              label: REASON_LABELS[r.reason] || r.reason,
              value: r.count,
              sub: `${r.total_qty} items`,
            }))}
            maxValue={Math.max(...by_reason.map((r) => r.count), 1)}
          />
        </Card>
        <Card noPadding>
          <CardHeader title="By Disposition" subtitle="What happened to returned items" />
          <BarList
            items={by_disposition.map((d) => ({
              label: DISPOSITION_LABELS[d.disposition] || d.disposition,
              value: d.count,
              sub: `${d.total_qty} items · $${(d.total_cost ?? 0).toLocaleString()}`,
            }))}
            maxValue={Math.max(...by_disposition.map((d) => d.count), 1)}
          />
        </Card>
      </div>

      {/* By Type + By Condition */}
      <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
        <Card noPadding>
          <CardHeader title="By Type" subtitle="Return flow direction" />
          <BarList
            items={by_type.map((t) => ({
              label: TYPE_LABELS[t.return_type] || t.return_type,
              value: t.return_count,
              sub: `${t.total_qty} items`,
            }))}
            maxValue={Math.max(...by_type.map((t) => t.return_count), 1)}
          />
        </Card>
        <Card noPadding>
          <CardHeader title="By Condition" subtitle="Item condition at return" />
          <BarList
            items={by_condition.map((c) => ({
              label: CONDITION_LABELS[c.condition] || c.condition,
              value: c.count,
              sub: `${c.total_qty} items`,
            }))}
            maxValue={Math.max(...by_condition.map((c) => c.count), 1)}
          />
        </Card>
      </div>

      {/* Top Returned Parts */}
      {top_parts.length > 0 && (
        <Card noPadding>
          <CardHeader title="Most Returned Parts" subtitle={`Top ${top_parts.length} parts by quantity`} />
          <div className="overflow-x-auto">
            <table className="w-full text-sm">
              <thead>
                <tr className="border-b border-gray-200 dark:border-gray-700 bg-gray-50 dark:bg-gray-800/50">
                  <th className="text-left px-4 py-3 font-medium text-gray-500 dark:text-gray-400">Part</th>
                  <th className="text-right px-4 py-3 font-medium text-gray-500 dark:text-gray-400">Returns</th>
                  <th className="text-right px-4 py-3 font-medium text-gray-500 dark:text-gray-400">Total Qty</th>
                </tr>
              </thead>
              <tbody className="divide-y divide-gray-100 dark:divide-gray-700/50">
                {top_parts.map((p) => (
                  <tr key={p.part_id} className="hover:bg-gray-50 dark:hover:bg-gray-800/30">
                    <td className="px-4 py-3">
                      <p className="font-medium text-gray-900 dark:text-gray-100">{p.part_name}</p>
                      <p className="text-xs text-gray-500 dark:text-gray-400">{p.part_code}</p>
                    </td>
                    <td className="text-right px-4 py-3 text-gray-900 dark:text-gray-100">
                      <Badge variant="default">{p.return_count}</Badge>
                    </td>
                    <td className="text-right px-4 py-3 font-medium text-gray-900 dark:text-gray-100">
                      {p.total_qty}
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        </Card>
      )}
    </>
  );
}


function BarList({ items, maxValue }: {
  items: { label: string; value: number; sub: string }[];
  maxValue: number;
}) {
  if (items.length === 0) {
    return (
      <p className="px-4 py-6 text-sm text-gray-500 dark:text-gray-400 text-center">
        No data
      </p>
    );
  }

  return (
    <div className="divide-y divide-gray-100 dark:divide-gray-700/50">
      {items.map((item) => (
        <div key={item.label} className="px-4 py-3">
          <div className="flex items-center justify-between mb-1">
            <span className="text-sm font-medium text-gray-900 dark:text-gray-100">
              {item.label}
            </span>
            <span className="text-sm font-bold text-gray-900 dark:text-gray-100">
              {item.value}
            </span>
          </div>
          <div className="flex items-center gap-3">
            <div className="flex-1 h-2 bg-gray-100 dark:bg-gray-700 rounded-full overflow-hidden">
              <div
                className="h-full bg-primary-500 rounded-full transition-all"
                style={{ width: `${Math.max((item.value / maxValue) * 100, 2)}%` }}
              />
            </div>
            <span className="text-xs text-gray-500 dark:text-gray-400 whitespace-nowrap">
              {item.sub}
            </span>
          </div>
        </div>
      ))}
    </div>
  );
}
