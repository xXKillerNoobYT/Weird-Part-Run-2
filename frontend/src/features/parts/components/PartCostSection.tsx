/**
 * PartCostSection — Expandable cost detail panel for a part.
 *
 * Shows within the PricingPage when a row is expanded:
 *   - Weighted average cost (from FIFO layers)
 *   - Cost history sparkline (90-day trend)
 *   - Active cost layers (audit view)
 *   - Margin management (custom vs company default)
 *   - Calculated sell price
 *
 * Permission: requires `show_dollar_values` to view, `edit_pricing` to modify margins.
 */

import { useState } from 'react';
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import {
  Layers, TrendingUp, BarChart3, Percent, RotateCcw, Check, X,
} from 'lucide-react';
import { Button } from '../../../components/ui/Button';
import { Badge } from '../../../components/ui/Badge';
import { Spinner } from '../../../components/ui/Spinner';
import { getPartCostSummary, getCostHistory, getCostLayers, setCustomMargin, clearCustomMargin } from '../../../api/costs';
import type { CostLayer, CostHistoryPoint, PartCostSummary } from '../../../lib/types';


interface PartCostSectionProps {
  partId: number;
  partName: string;
  canEdit: boolean;
}

export function PartCostSection({ partId, partName, canEdit }: PartCostSectionProps) {
  const queryClient = useQueryClient();

  // ── Queries ──────────────────────────────────────────────────
  const { data: summary, isLoading: loadingSummary } = useQuery({
    queryKey: ['part-cost-summary', partId],
    queryFn: () => getPartCostSummary(partId),
    staleTime: 30_000,
  });

  const { data: history } = useQuery({
    queryKey: ['cost-history', partId],
    queryFn: () => getCostHistory(partId, 90),
    staleTime: 60_000,
  });

  const { data: layers } = useQuery({
    queryKey: ['cost-layers', partId],
    queryFn: () => getCostLayers(partId),
    staleTime: 30_000,
  });

  // ── Margin editing ───────────────────────────────────────────
  const [editingMargin, setEditingMargin] = useState(false);
  const [marginInput, setMarginInput] = useState('');

  const marginMutation = useMutation({
    mutationFn: (percent: number) => setCustomMargin(partId, percent),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['part-cost-summary', partId] });
      setEditingMargin(false);
    },
  });

  const clearMarginMutation = useMutation({
    mutationFn: () => clearCustomMargin(partId),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['part-cost-summary', partId] });
    },
  });

  const startMarginEdit = () => {
    setMarginInput(String(summary?.custom_margin_percent ?? summary?.effective_margin_percent ?? 25));
    setEditingMargin(true);
  };

  const saveMargin = () => {
    const val = parseFloat(marginInput);
    if (!isNaN(val) && val >= 0 && val <= 100) {
      marginMutation.mutate(val);
    }
  };

  // ── Format helpers ───────────────────────────────────────────
  const fmt = (v: number) => `$${v.toFixed(2)}`;

  if (loadingSummary) {
    return (
      <div className="flex items-center justify-center py-6">
        <Spinner size="md" />
      </div>
    );
  }

  if (!summary) return null;

  return (
    <div className="bg-gray-50 dark:bg-gray-800/50 rounded-lg p-4 space-y-4 border border-gray-200 dark:border-gray-700">
      {/* ── Header ──────────────────────────────────────────── */}
      <div className="flex items-center gap-2 text-sm font-medium text-gray-700 dark:text-gray-300">
        <BarChart3 className="h-4 w-4 text-primary-500" />
        Cost Details — {partName}
      </div>

      {/* ── KPI Row ─────────────────────────────────────────── */}
      <div className="grid grid-cols-2 sm:grid-cols-4 gap-3">
        <CostKPI
          label="Weighted Avg Cost"
          value={fmt(summary.weighted_avg_cost)}
          icon={<TrendingUp className="h-3.5 w-3.5" />}
        />
        <CostKPI
          label="Active Layers"
          value={String(summary.active_layers)}
          icon={<Layers className="h-3.5 w-3.5" />}
        />
        <CostKPI
          label="Effective Margin"
          value={`${summary.effective_margin_percent.toFixed(1)}%`}
          icon={<Percent className="h-3.5 w-3.5" />}
          badge={
            summary.custom_margin_percent != null
              ? <Badge variant="warning">Custom</Badge>
              : <Badge variant="default">Default</Badge>
          }
        />
        <CostKPI
          label="Sell Price"
          value={fmt(summary.calculated_sell_price)}
          icon={<BarChart3 className="h-3.5 w-3.5" />}
          highlight
        />
      </div>

      {/* ── Sparkline ───────────────────────────────────────── */}
      {history && history.length > 1 && (
        <div>
          <p className="text-xs text-gray-500 dark:text-gray-400 mb-1">
            Cost trend (90 days)
          </p>
          <CostSparkline data={history} />
        </div>
      )}

      {/* ── Margin Controls ─────────────────────────────────── */}
      {canEdit && (
        <div className="flex items-center gap-2 flex-wrap">
          {editingMargin ? (
            <div className="flex items-center gap-2">
              <input
                type="number"
                min="0"
                max="100"
                step="0.5"
                className="w-20 text-right rounded border border-primary-300 dark:border-primary-600 bg-white dark:bg-gray-800 px-2 py-1.5 text-sm"
                value={marginInput}
                onChange={(e) => setMarginInput(e.target.value)}
                autoFocus
              />
              <span className="text-sm text-gray-500">%</span>
              <button
                className="p-1.5 rounded text-green-600 hover:bg-green-100 dark:hover:bg-green-900/30"
                onClick={saveMargin}
                title="Save margin"
              >
                <Check className="h-4 w-4" />
              </button>
              <button
                className="p-1.5 rounded text-gray-500 hover:bg-gray-200 dark:hover:bg-gray-700"
                onClick={() => setEditingMargin(false)}
                title="Cancel"
              >
                <X className="h-4 w-4" />
              </button>
            </div>
          ) : (
            <>
              <Button variant="secondary" size="sm" onClick={startMarginEdit}>
                <Percent className="h-3.5 w-3.5 mr-1" />
                Set Custom Margin
              </Button>
              {summary.custom_margin_percent != null && (
                <Button
                  variant="secondary"
                  size="sm"
                  onClick={() => clearMarginMutation.mutate()}
                  isLoading={clearMarginMutation.isPending}
                >
                  <RotateCcw className="h-3.5 w-3.5 mr-1" />
                  Revert to Default
                </Button>
              )}
            </>
          )}
        </div>
      )}

      {/* ── Cost Layers Table ───────────────────────────────── */}
      {layers && layers.length > 0 && (
        <div>
          <p className="text-xs font-medium text-gray-600 dark:text-gray-400 mb-2">
            Active Cost Layers (FIFO order)
          </p>
          <div className="overflow-x-auto">
            <table className="w-full text-xs">
              <thead>
                <tr className="border-b border-gray-200 dark:border-gray-600 text-gray-500 dark:text-gray-400">
                  <th className="text-left py-1.5 pr-3 font-medium">Date</th>
                  <th className="text-left py-1.5 pr-3 font-medium">PO</th>
                  <th className="text-right py-1.5 pr-3 font-medium">Original</th>
                  <th className="text-right py-1.5 pr-3 font-medium">Remaining</th>
                  <th className="text-right py-1.5 font-medium">Unit Cost</th>
                </tr>
              </thead>
              <tbody className="divide-y divide-gray-100 dark:divide-gray-700/50">
                {layers.map((layer) => (
                  <tr key={layer.id} className="text-gray-700 dark:text-gray-300">
                    <td className="py-1.5 pr-3">{layer.purchase_date}</td>
                    <td className="py-1.5 pr-3 text-primary-600 dark:text-primary-400">
                      {layer.po_number ?? '—'}
                    </td>
                    <td className="py-1.5 pr-3 text-right">{layer.original_qty}</td>
                    <td className="py-1.5 pr-3 text-right font-medium">{layer.remaining_qty}</td>
                    <td className="py-1.5 text-right">{fmt(layer.unit_cost)}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        </div>
      )}

      {/* ── Last updated ────────────────────────────────────── */}
      {summary.cost_last_updated && (
        <p className="text-xs text-gray-400 dark:text-gray-500">
          Cost last updated: {new Date(summary.cost_last_updated).toLocaleDateString()}
        </p>
      )}
    </div>
  );
}


// ── Sub-components ──────────────────────────────────────────────────

function CostKPI({
  label,
  value,
  icon,
  badge,
  highlight,
}: {
  label: string;
  value: string;
  icon: React.ReactNode;
  badge?: React.ReactNode;
  highlight?: boolean;
}) {
  return (
    <div className="bg-white dark:bg-gray-800 rounded-lg p-3 border border-gray-200 dark:border-gray-700">
      <div className="flex items-center gap-1.5 mb-1">
        <span className="text-gray-400 dark:text-gray-500">{icon}</span>
        <span className="text-xs text-gray-500 dark:text-gray-400">{label}</span>
        {badge}
      </div>
      <p className={`text-lg font-bold ${
        highlight
          ? 'text-primary-600 dark:text-primary-400'
          : 'text-gray-900 dark:text-gray-100'
      }`}>
        {value}
      </p>
    </div>
  );
}


/**
 * CostSparkline — lightweight inline SVG sparkline for cost history.
 *
 * Uses an SVG polyline to draw a mini trend chart. No charting library needed.
 * The line color reflects cost direction (green = decreasing, amber = stable, red = increasing).
 */
function CostSparkline({ data }: { data: CostHistoryPoint[] }) {
  if (data.length < 2) return null;

  const width = 200;
  const height = 40;
  const padding = 2;

  const costs = data.map((d) => d.weighted_avg_cost);
  const min = Math.min(...costs);
  const max = Math.max(...costs);
  const range = max - min || 1;

  const points = costs.map((cost, i) => {
    const x = padding + (i / (costs.length - 1)) * (width - padding * 2);
    const y = height - padding - ((cost - min) / range) * (height - padding * 2);
    return `${x},${y}`;
  }).join(' ');

  // Color based on trend direction (first vs last)
  const first = costs[0];
  const last = costs[costs.length - 1];
  const delta = last - first;
  const strokeColor = delta > first * 0.05
    ? '#ef4444'   // red — cost increasing
    : delta < -first * 0.05
      ? '#22c55e'  // green — cost decreasing
      : '#f59e0b'; // amber — stable

  return (
    <svg
      width={width}
      height={height}
      viewBox={`0 0 ${width} ${height}`}
      className="block"
    >
      <polyline
        points={points}
        fill="none"
        stroke={strokeColor}
        strokeWidth="2"
        strokeLinecap="round"
        strokeLinejoin="round"
      />
      {/* End dot */}
      {costs.length > 0 && (
        <circle
          cx={padding + ((costs.length - 1) / (costs.length - 1)) * (width - padding * 2)}
          cy={height - padding - ((last - min) / range) * (height - padding * 2)}
          r="3"
          fill={strokeColor}
        />
      )}
    </svg>
  );
}
