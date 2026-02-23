/**
 * ForecastingPage — demand forecasting and reorder predictions.
 *
 * Features:
 *  - Read-only view of forecasting data (populated by backend forecast service)
 *  - Sorted by urgency: days-until-low ascending, so critical items surface first
 *  - Color-coded urgency badges: red (<7d), amber (7-14d), green (>14d)
 *  - Summary KPI cards at top: critical items, suggested orders, avg ADU
 *  - Searchable and paginated
 */

import { useState, useMemo } from 'react';
import { useQuery } from '@tanstack/react-query';
import {
  TrendingUp, Search, AlertTriangle, ChevronLeft,
  ChevronRight, ShoppingCart, Clock, Activity,
} from 'lucide-react';
import { Button } from '../../../components/ui/Button';
import { Input } from '../../../components/ui/Input';
import { Badge } from '../../../components/ui/Badge';
import { Card } from '../../../components/ui/Card';
import { Spinner } from '../../../components/ui/Spinner';
import { EmptyState } from '../../../components/ui/EmptyState';
import { getForecasting } from '../../../api/parts';
import type { ForecastItem } from '../../../lib/types';


export function ForecastingPage() {
  const [searchText, setSearchText] = useState('');
  const [page, setPage] = useState(1);
  const pageSize = 25;

  // ── Query ────────────────────────────────────────
  const { data: forecastData, isLoading, error } = useQuery({
    queryKey: ['forecasting', { page, page_size: pageSize }],
    queryFn: () => getForecasting({ page, page_size: pageSize }),
  });

  // ── Client-side search filter (API already sorted by urgency) ──
  const items = useMemo(() => {
    const all = forecastData?.items ?? [];
    if (!searchText) return all;
    const term = searchText.toLowerCase();
    return all.filter(
      (item) =>
        (item.code ?? '').toLowerCase().includes(term) ||
        item.name.toLowerCase().includes(term) ||
        (item.category_name ?? '').toLowerCase().includes(term) ||
        (item.brand_name ?? '').toLowerCase().includes(term),
    );
  }, [forecastData, searchText]);

  const total = forecastData?.total ?? 0;
  const totalPages = forecastData?.total_pages ?? 0;

  // ── KPI calculations ─────────────────────────────
  const allItems = forecastData?.items ?? [];
  const criticalCount = allItems.filter(i => i.forecast_days_until_low < 7).length;
  const orderCount = allItems.filter(i => i.forecast_suggested_order > 0).length;
  const avgAdu = allItems.length > 0
    ? allItems.reduce((sum, i) => sum + (i.forecast_adu_30 ?? 0), 0) / allItems.length
    : 0;

  // ── Urgency badge helper ─────────────────────────
  const urgencyBadge = (daysUntilLow: number) => {
    if (daysUntilLow < 0) return <Badge variant="danger">BELOW MIN</Badge>;
    if (daysUntilLow < 7) return <Badge variant="danger">{daysUntilLow}d</Badge>;
    if (daysUntilLow < 14) return <Badge variant="warning">{daysUntilLow}d</Badge>;
    if (daysUntilLow < 30) return <Badge variant="default">{daysUntilLow}d</Badge>;
    return <span className="text-green-600 dark:text-green-400 font-medium">{daysUntilLow}d</span>;
  };

  return (
    <div className="space-y-4">
      {/* ── KPI Cards ───────────────────────────── */}
      <div className="grid grid-cols-1 sm:grid-cols-3 gap-4">
        <Card className="flex items-center gap-3">
          <div className="p-2 rounded-lg bg-red-100 dark:bg-red-900/30">
            <AlertTriangle className="h-5 w-5 text-red-500" />
          </div>
          <div>
            <p className="text-2xl font-bold text-gray-900 dark:text-gray-100">{criticalCount}</p>
            <p className="text-sm text-gray-500 dark:text-gray-400">Critical (&lt;7 days)</p>
          </div>
        </Card>

        <Card className="flex items-center gap-3">
          <div className="p-2 rounded-lg bg-amber-100 dark:bg-amber-900/30">
            <ShoppingCart className="h-5 w-5 text-amber-500" />
          </div>
          <div>
            <p className="text-2xl font-bold text-gray-900 dark:text-gray-100">{orderCount}</p>
            <p className="text-sm text-gray-500 dark:text-gray-400">Suggested Orders</p>
          </div>
        </Card>

        <Card className="flex items-center gap-3">
          <div className="p-2 rounded-lg bg-blue-100 dark:bg-blue-900/30">
            <Activity className="h-5 w-5 text-blue-500" />
          </div>
          <div>
            <p className="text-2xl font-bold text-gray-900 dark:text-gray-100">{avgAdu.toFixed(1)}</p>
            <p className="text-sm text-gray-500 dark:text-gray-400">Avg Daily Usage (30d)</p>
          </div>
        </Card>
      </div>

      {/* ── Search ──────────────────────────────── */}
      <div className="flex flex-col sm:flex-row gap-3 items-start sm:items-center justify-between">
        <div className="flex-1 w-full sm:max-w-md">
          <Input
            placeholder="Search by code or name..."
            icon={<Search className="h-4 w-4" />}
            value={searchText}
            onChange={(e) => setSearchText(e.target.value)}
          />
        </div>
        <div className="flex items-center gap-2 text-sm text-gray-500 dark:text-gray-400">
          <Clock className="h-4 w-4" />
          Sorted by urgency (most critical first)
        </div>
      </div>

      {/* ── Table ───────────────────────────────── */}
      {isLoading ? (
        <div className="flex justify-center py-12">
          <Spinner size="lg" />
        </div>
      ) : error ? (
        <EmptyState
          icon={<AlertTriangle className="h-12 w-12 text-red-400" />}
          title="Error loading forecast data"
          description={String(error)}
        />
      ) : items.length === 0 ? (
        <EmptyState
          icon={<TrendingUp className="h-12 w-12" />}
          title="No forecast data"
          description="Forecast data will appear once the forecast service has run and parts have usage history."
        />
      ) : (
        <div className="overflow-x-auto border border-gray-200 dark:border-gray-700 rounded-xl">
          <table className="w-full text-sm">
            <thead>
              <tr className="bg-gray-50 dark:bg-gray-800/80 border-b border-gray-200 dark:border-gray-700">
                <th className="text-left px-4 py-3 font-medium text-gray-600 dark:text-gray-400">Category</th>
                <th className="text-left px-4 py-3 font-medium text-gray-600 dark:text-gray-400">Code</th>
                <th className="text-left px-4 py-3 font-medium text-gray-600 dark:text-gray-400">Part Name</th>
                <th className="text-left px-4 py-3 font-medium text-gray-600 dark:text-gray-400">Brand</th>
                <th className="text-right px-4 py-3 font-medium text-gray-600 dark:text-gray-400">Current Stock</th>
                <th className="text-right px-4 py-3 font-medium text-gray-600 dark:text-gray-400">Min Level</th>
                <th className="text-right px-4 py-3 font-medium text-gray-600 dark:text-gray-400">ADU (30d)</th>
                <th className="text-right px-4 py-3 font-medium text-gray-600 dark:text-gray-400">ADU (90d)</th>
                <th className="text-right px-4 py-3 font-medium text-gray-600 dark:text-gray-400">Reorder Point</th>
                <th className="text-right px-4 py-3 font-medium text-gray-600 dark:text-gray-400">Target Qty</th>
                <th className="text-center px-4 py-3 font-medium text-gray-600 dark:text-gray-400">Days Until Low</th>
                <th className="text-right px-4 py-3 font-medium text-gray-600 dark:text-gray-400">Suggested Order</th>
              </tr>
            </thead>
            <tbody>
              {items.map((item) => (
                <tr
                  key={item.id}
                  className={`border-b border-gray-100 dark:border-gray-700/50 transition-colors ${
                    item.forecast_days_until_low < 7
                      ? 'bg-red-50/50 dark:bg-red-900/10'
                      : 'hover:bg-gray-50 dark:hover:bg-gray-800/30'
                  }`}
                >
                  <td className="px-4 py-3 text-gray-600 dark:text-gray-400">
                    {item.category_name ?? '—'}
                  </td>
                  <td className="px-4 py-3 font-mono text-xs text-primary-600 dark:text-primary-400">
                    {item.code ?? '—'}
                  </td>
                  <td className="px-4 py-3 font-medium text-gray-900 dark:text-gray-100">
                    {item.name}
                  </td>
                  <td className="px-4 py-3 text-gray-600 dark:text-gray-400">
                    {item.brand_name ?? '—'}
                  </td>
                  <td className="px-4 py-3 text-right">
                    <span className={
                      item.total_stock <= item.min_stock_level
                        ? 'text-red-500 font-medium'
                        : 'text-gray-700 dark:text-gray-300'
                    }>
                      {item.total_stock}
                    </span>
                  </td>
                  <td className="px-4 py-3 text-right text-gray-600 dark:text-gray-400">
                    {item.min_stock_level}
                  </td>
                  <td className="px-4 py-3 text-right text-gray-700 dark:text-gray-300">
                    {item.forecast_adu_30.toFixed(2)}
                  </td>
                  <td className="px-4 py-3 text-right text-gray-700 dark:text-gray-300">
                    {item.forecast_adu_90.toFixed(2)}
                  </td>
                  <td className="px-4 py-3 text-right text-gray-600 dark:text-gray-400">
                    {item.forecast_reorder_point}
                  </td>
                  <td className="px-4 py-3 text-right text-gray-600 dark:text-gray-400">
                    {item.forecast_target_qty}
                  </td>
                  <td className="px-4 py-3 text-center">
                    {urgencyBadge(item.forecast_days_until_low)}
                  </td>
                  <td className="px-4 py-3 text-right">
                    {item.forecast_suggested_order > 0 ? (
                      <span className="font-semibold text-amber-600 dark:text-amber-400">
                        {item.forecast_suggested_order}
                      </span>
                    ) : (
                      <span className="text-gray-400">—</span>
                    )}
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      )}

      {/* ── Pagination ─────────────────────────── */}
      {totalPages > 1 && (
        <div className="flex items-center justify-between">
          <Button
            variant="secondary"
            size="sm"
            icon={<ChevronLeft className="h-4 w-4" />}
            disabled={page <= 1}
            onClick={() => setPage(p => p - 1)}
          >
            Previous
          </Button>
          <span className="text-sm text-gray-500">
            Page {page} of {totalPages} ({total} parts)
          </span>
          <Button
            variant="secondary"
            size="sm"
            iconRight={<ChevronRight className="h-4 w-4" />}
            disabled={page >= totalPages}
            onClick={() => setPage(p => p + 1)}
          >
            Next
          </Button>
        </div>
      )}
    </div>
  );
}
