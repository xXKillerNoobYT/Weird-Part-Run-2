/**
 * ProcurementPage — procurement planning and reorder suggestions.
 *
 * Three views accessible via view selector:
 *  1. Reorder Alerts (default): priority-sorted list of parts needing reorder
 *  2. Supplier Groups: parts grouped by recommended supplier with combined totals
 *  3. Kanban: workflow columns for tracking procurement stages
 *
 * Dashboard stats are always visible above the view content.
 */

import { useState, useMemo } from 'react';
import { useQuery } from '@tanstack/react-query';
import {
  BarChart3,
  Package,
  AlertTriangle,
  TrendingUp,
  Clock,
  LayoutList,
  Grid3X3,
  Truck,
  ChevronRight,
  ShoppingCart,
} from 'lucide-react';
import {
  getProcurementDashboard,
  getReorderSuggestions,
  listPOs,
} from '../../../api/orders';
import { EmptyState } from '../../../components/ui/EmptyState';
import { PartIdentity } from '../../../components/ui/PartIdentity';
import type { ReorderSuggestion, POListItem } from '../../../lib/types';

type ViewMode = 'alerts' | 'grouped' | 'kanban';

const VIEW_OPTIONS: { label: string; value: ViewMode; icon: typeof LayoutList }[] = [
  { label: 'Reorder Alerts', value: 'alerts', icon: AlertTriangle },
  { label: 'Supplier Groups', value: 'grouped', icon: Grid3X3 },
  { label: 'Kanban', value: 'kanban', icon: LayoutList },
];


export function ProcurementPage() {
  const [view, setView] = useState<ViewMode>('alerts');

  const {
    data: dashboard,
    isLoading: dashLoading,
    isError: dashError,
  } = useQuery({
    queryKey: ['procurement', 'dashboard'],
    queryFn: getProcurementDashboard,
  });

  const {
    data: suggestions = [],
    isLoading: suggestionsLoading,
    isError: suggestionsError,
  } = useQuery({
    queryKey: ['procurement', 'suggestions'],
    queryFn: getReorderSuggestions,
  });

  // Fetch PO list for kanban view
  const { data: allPOs = [], isLoading: posLoading } = useQuery({
    queryKey: ['pos-for-kanban'],
    queryFn: () => listPOs(),
    enabled: view === 'kanban',
  });

  const isLoading = dashLoading || suggestionsLoading || (view === 'kanban' && posLoading);
  const isError = dashError || suggestionsError;

  return (
    <div className="space-y-6">
      {/* Header */}
      <div className="flex items-center justify-between flex-wrap gap-3">
        <h1 className="text-xl font-semibold text-gray-900 dark:text-gray-100">
          Procurement
        </h1>
        {/* View selector */}
        <div className="flex gap-1 rounded-lg border border-border bg-surface p-1 overflow-x-auto">
          {VIEW_OPTIONS.map((opt) => {
            const Icon = opt.icon;
            return (
              <button
                key={opt.value}
                onClick={() => setView(opt.value)}
                className={`inline-flex items-center gap-1.5 rounded-md px-3 py-1.5 text-xs font-medium transition-colors whitespace-nowrap ${
                  view === opt.value
                    ? 'bg-primary text-white'
                    : 'text-gray-600 hover:bg-gray-100 dark:text-gray-400 dark:hover:bg-gray-700'
                }`}
              >
                <Icon className="h-3.5 w-3.5 flex-shrink-0" />
                <span className="hidden sm:inline">{opt.label}</span>
              </button>
            );
          })}
        </div>
      </div>

      {/* Dashboard Stats */}
      <div className="grid grid-cols-2 gap-3 md:grid-cols-4">
        <StatCard
          icon={<AlertTriangle className="h-5 w-5 text-amber-500" />}
          label="Need Reorder"
          value={dashboard?.parts_needing_reorder ?? 0}
          loading={dashLoading}
        />
        <StatCard
          icon={<Package className="h-5 w-5 text-blue-500" />}
          label="Open PO Value"
          value={
            dashboard?.pending_po_value != null
              ? `$${dashboard.pending_po_value.toLocaleString(undefined, {
                  maximumFractionDigits: 0,
                })}`
              : '$0'
          }
          loading={dashLoading}
        />
        <StatCard
          icon={<Clock className="h-5 w-5 text-purple-500" />}
          label="Avg Lead Time"
          value={
            dashboard?.avg_lead_time_days != null
              ? `${dashboard.avg_lead_time_days.toFixed(1)}d`
              : '—'
          }
          loading={dashLoading}
        />
        <StatCard
          icon={<TrendingUp className="h-5 w-5 text-green-500" />}
          label="Overdue Deliveries"
          value={dashboard?.overdue_deliveries ?? 0}
          loading={dashLoading}
        />
      </div>

      {/* Content */}
      {isError ? (
        <div className="rounded-lg border border-red-200 dark:border-red-800 bg-red-50 dark:bg-red-900/20 p-4 text-sm text-red-700 dark:text-red-300">
          Failed to load procurement data. Please try refreshing.
        </div>
      ) : isLoading ? (
        <div className="flex justify-center py-12">
          <div className="h-8 w-8 animate-spin rounded-full border-4 border-primary border-t-transparent" />
        </div>
      ) : view === 'alerts' ? (
        <ReorderAlertsList suggestions={suggestions} />
      ) : view === 'grouped' ? (
        <SupplierGroupedView suggestions={suggestions} />
      ) : (
        <KanbanView suggestions={suggestions} poList={allPOs} />
      )}
    </div>
  );
}


// ═══════════════════════════════════════════════════════════════════
// INTERNAL: StatCard
// ═══════════════════════════════════════════════════════════════════

function StatCard({
  icon,
  label,
  value,
  loading,
}: {
  icon: React.ReactNode;
  label: string;
  value: string | number;
  loading: boolean;
}) {
  return (
    <div className="rounded-lg border border-border bg-surface p-3 sm:p-4 min-w-0">
      <div className="flex items-center gap-2 sm:gap-3">
        <div className="flex-shrink-0">{icon}</div>
        <div className="min-w-0 flex-1">
          <p className="text-xs font-medium text-gray-500 dark:text-gray-400 truncate">
            {label}
          </p>
          {loading ? (
            <div className="h-6 w-16 animate-pulse rounded bg-gray-200 dark:bg-gray-700 mt-1" />
          ) : (
            <p className="text-base sm:text-lg font-semibold text-gray-900 dark:text-gray-100 tabular-nums truncate">
              {value}
            </p>
          )}
        </div>
      </div>
    </div>
  );
}


// ═══════════════════════════════════════════════════════════════════
// VIEW: Reorder Alerts (table)
// ═══════════════════════════════════════════════════════════════════

function ReorderAlertsList({ suggestions }: { suggestions: ReorderSuggestion[] }) {
  if (suggestions.length === 0) {
    return (
      <EmptyState
        icon={<BarChart3 className="h-12 w-12" />}
        title="All stocked up!"
        description="No parts are below their reorder point right now."
      />
    );
  }

  return (
    <div className="overflow-hidden rounded-lg border border-border bg-surface">
      {/* Desktop table */}
      <div className="hidden sm:block overflow-x-auto">
        <table className="min-w-full divide-y divide-border">
          <thead className="bg-surface-secondary">
            <tr>
              <th className="px-4 py-3 text-left text-xs font-medium uppercase text-gray-500 dark:text-gray-400">
                Part
              </th>
              <th className="px-4 py-3 text-right text-xs font-medium uppercase text-gray-500 dark:text-gray-400">
                Current
              </th>
              <th className="px-4 py-3 text-right text-xs font-medium uppercase text-gray-500 dark:text-gray-400">
                Reorder Pt
              </th>
              <th className="px-4 py-3 text-right text-xs font-medium uppercase text-gray-500 dark:text-gray-400">
                Target
              </th>
              <th className="px-4 py-3 text-right text-xs font-medium uppercase text-gray-500 dark:text-gray-400">
                Suggested Qty
              </th>
              <th className="px-4 py-3 text-left text-xs font-medium uppercase text-gray-500 dark:text-gray-400">
                Best Supplier
              </th>
              <th className="px-4 py-3 text-right text-xs font-medium uppercase text-gray-500 dark:text-gray-400">
                Est. Cost
              </th>
            </tr>
          </thead>
          <tbody className="divide-y divide-border">
            {suggestions.map((s) => {
              const urgency =
                s.current_stock === 0
                  ? 'bg-red-50 dark:bg-red-900/10'
                  : s.current_stock <= (s.reorder_point ?? 0) / 2
                    ? 'bg-amber-50 dark:bg-amber-900/10'
                    : '';

              return (
                <tr
                  key={s.part_id}
                  className={`hover:bg-surface-secondary/50 transition-colors ${urgency}`}
                >
                  <td className="px-4 py-3">
                    <div className="font-medium text-sm text-gray-900 dark:text-gray-100">
                      {s.part_number}
                    </div>
                    {s.part_description && (
                      <div className="text-xs text-gray-500 dark:text-gray-400 truncate max-w-[200px]">
                        {s.part_description}
                      </div>
                    )}
                  </td>
                  <td className="px-4 py-3 text-sm text-right tabular-nums font-medium text-gray-900 dark:text-gray-100">
                    {s.current_stock}
                  </td>
                  <td className="px-4 py-3 text-sm text-right tabular-nums text-gray-500 dark:text-gray-400">
                    {s.reorder_point ?? '—'}
                  </td>
                  <td className="px-4 py-3 text-sm text-right tabular-nums text-gray-500 dark:text-gray-400">
                    {s.target_qty ?? '—'}
                  </td>
                  <td className="px-4 py-3 text-sm text-right tabular-nums font-semibold text-primary">
                    {s.suggested_order_qty}
                  </td>
                  <td className="px-4 py-3 text-sm text-gray-700 dark:text-gray-300">
                    {s.best_supplier_name || '—'}
                  </td>
                  <td className="px-4 py-3 text-sm text-right tabular-nums text-gray-700 dark:text-gray-300">
                    {s.estimated_cost != null
                      ? `$${s.estimated_cost.toLocaleString(undefined, {
                          minimumFractionDigits: 2,
                          maximumFractionDigits: 2,
                        })}`
                      : '—'}
                  </td>
                </tr>
              );
            })}
          </tbody>
        </table>
      </div>

      {/* Mobile: card list */}
      <div className="sm:hidden divide-y divide-border">
        {suggestions.map((s) => {
          const urgency =
            s.current_stock === 0
              ? 'border-l-4 border-l-red-500'
              : s.current_stock <= (s.reorder_point ?? 0) / 2
                ? 'border-l-4 border-l-amber-500'
                : '';

          return (
            <div key={s.part_id} className={`px-4 py-3 ${urgency}`}>
              <div className="flex items-center justify-between mb-1">
                <span className="text-sm font-medium text-gray-900 dark:text-gray-100">
                  {s.part_number}
                </span>
                <span className="text-sm font-semibold text-primary tabular-nums">
                  Order: {s.suggested_order_qty}
                </span>
              </div>
              {s.part_description && (
                <p className="text-xs text-gray-500 dark:text-gray-400 truncate mb-1">
                  {s.part_description}
                </p>
              )}
              <div className="flex items-center gap-3 text-xs text-gray-500 dark:text-gray-400">
                <span>Stock: {s.current_stock}</span>
                <span>·</span>
                <span>Reorder: {s.reorder_point}</span>
                {s.best_supplier_name && (
                  <>
                    <span>·</span>
                    <span>{s.best_supplier_name}</span>
                  </>
                )}
              </div>
            </div>
          );
        })}
      </div>
    </div>
  );
}


// ═══════════════════════════════════════════════════════════════════
// VIEW: Supplier Groups
// ═══════════════════════════════════════════════════════════════════

function SupplierGroupedView({ suggestions }: { suggestions: ReorderSuggestion[] }) {
  // Group suggestions by best_supplier_id, with an "Unassigned" bucket
  const groups = useMemo(() => {
    const map = new Map<
      number | null,
      { supplierId: number | null; supplierName: string; items: ReorderSuggestion[]; totalCost: number }
    >();

    for (const s of suggestions) {
      const key = s.best_supplier_id;
      if (!map.has(key)) {
        map.set(key, {
          supplierId: key,
          supplierName: s.best_supplier_name || 'Unassigned',
          items: [],
          totalCost: 0,
        });
      }
      const g = map.get(key)!;
      g.items.push(s);
      g.totalCost += s.estimated_cost ?? 0;
    }

    // Sort: unassigned last, then by total cost descending
    return Array.from(map.values()).sort((a, b) => {
      if (!a.supplierId && b.supplierId) return 1;
      if (a.supplierId && !b.supplierId) return -1;
      return b.totalCost - a.totalCost;
    });
  }, [suggestions]);

  if (suggestions.length === 0) {
    return (
      <EmptyState
        icon={<Grid3X3 className="h-12 w-12" />}
        title="No reorder suggestions"
        description="All parts are above their reorder points."
      />
    );
  }

  return (
    <div className="space-y-4">
      {groups.map((g) => (
        <div
          key={g.supplierId ?? 'unassigned'}
          className="rounded-xl border border-gray-200 dark:border-gray-700 bg-white dark:bg-gray-800 shadow-sm overflow-hidden"
        >
          {/* Group header */}
          <div className="flex items-center justify-between px-5 py-3 bg-gray-50 dark:bg-gray-800/50 border-b border-gray-200 dark:border-gray-700">
            <div className="flex items-center gap-2">
              <Truck className="h-4 w-4 text-primary" />
              <h3 className="text-sm font-semibold text-gray-900 dark:text-gray-100">
                {g.supplierName}
              </h3>
              <span className="text-xs text-gray-500 dark:text-gray-400">
                ({g.items.length} part{g.items.length !== 1 ? 's' : ''})
              </span>
            </div>
            <div className="text-right">
              <span className="text-sm font-medium text-gray-900 dark:text-gray-100 tabular-nums">
                ${g.totalCost.toLocaleString(undefined, {
                  minimumFractionDigits: 2,
                  maximumFractionDigits: 2,
                })}
              </span>
              <span className="text-xs text-gray-500 dark:text-gray-400 ml-1">est.</span>
            </div>
          </div>

          {/* Items */}
          <div className="divide-y divide-gray-200 dark:divide-gray-700">
            {g.items.map((s) => (
              <div
                key={s.part_id}
                className="flex items-center justify-between gap-4 px-5 py-2.5"
              >
                <div className="flex-1 min-w-0">
                  <div className="flex items-center gap-2 flex-wrap">
                    <PartIdentity
                      compact
                      partName={s.part_name}
                      partDescription={s.part_description}
                      partNumber={s.part_number}
                      partId={s.part_id}
                      brandName={s.brand_name}
                      colorName={s.color_name}
                      colorHex={s.color_hex}
                      categoryName={s.category_name}
                      typeName={s.type_name}
                    />
                  </div>
                  <div className="flex items-center gap-2 mt-0.5 text-xs text-gray-500 dark:text-gray-400">
                    <span className="tabular-nums">
                      Stock: {s.current_stock} / {s.reorder_point}
                    </span>
                    {s.days_until_stockout != null && s.days_until_stockout <= 7 && (
                      <span className="text-red-600 dark:text-red-400 font-medium">
                        {s.days_until_stockout <= 0
                          ? 'Out of stock!'
                          : `${s.days_until_stockout}d to stockout`}
                      </span>
                    )}
                  </div>
                </div>
                <div className="flex items-center gap-4 flex-shrink-0">
                  <div className="text-right">
                    <p className="text-sm font-semibold text-primary tabular-nums">
                      {s.suggested_order_qty}
                    </p>
                    <p className="text-xs text-gray-500 dark:text-gray-400">to order</p>
                  </div>
                  {s.estimated_cost != null && (
                    <div className="text-right">
                      <p className="text-sm text-gray-900 dark:text-gray-100 tabular-nums">
                        ${s.estimated_cost.toFixed(2)}
                      </p>
                      <p className="text-xs text-gray-500 dark:text-gray-400">est.</p>
                    </div>
                  )}
                </div>
              </div>
            ))}
          </div>
        </div>
      ))}
    </div>
  );
}


// ═══════════════════════════════════════════════════════════════════
// VIEW: Kanban Board
// ═══════════════════════════════════════════════════════════════════

interface KanbanColumn {
  id: string;
  label: string;
  color: string;
  icon: typeof Package;
}

const KANBAN_COLUMNS: KanbanColumn[] = [
  { id: 'needs_reorder', label: 'Needs Reorder', color: 'border-t-red-500', icon: AlertTriangle },
  { id: 'ready_to_order', label: 'Ready to Order', color: 'border-t-amber-500', icon: ShoppingCart },
  { id: 'on_order', label: 'On Order', color: 'border-t-blue-500', icon: Truck },
  { id: 'received', label: 'Recently Received', color: 'border-t-green-500', icon: Package },
];

function KanbanView({
  suggestions,
  poList,
}: {
  suggestions: ReorderSuggestion[];
  poList: POListItem[];
}) {
  // Classify items into kanban columns
  const columns = useMemo(() => {
    // "Needs Reorder": suggestions with 0 pending_po_qty
    const needsReorder = suggestions.filter(
      (s) => s.pending_po_qty === 0 && s.expected_return_qty === 0,
    );

    // "Ready to Order": suggestions that have some pending or return expected
    // but not yet on a PO (pending_po_qty > 0 means already ordered)
    // For simplicity: items with pending_po_qty > 0 but still below reorder point
    const readyToOrder = suggestions.filter(
      (s) => s.pending_po_qty > 0 && s.current_stock + s.pending_po_qty < s.target_qty,
    );

    // "On Order": POs that are submitted/acknowledged
    const onOrder = poList.filter(
      (po) =>
        po.status === 'submitted' ||
        po.status === 'acknowledged' ||
        po.status === 'partially_received',
    );

    // "Received": POs that were recently received
    const received = poList.filter((po) => po.status === 'received');

    return { needsReorder, readyToOrder, onOrder, received };
  }, [suggestions, poList]);

  return (
    <div className="grid grid-cols-1 md:grid-cols-2 xl:grid-cols-4 gap-4">
      {/* Column 1: Needs Reorder */}
      <KanbanColumnCard
        column={KANBAN_COLUMNS[0]}
        count={columns.needsReorder.length}
      >
        {columns.needsReorder.length === 0 ? (
          <EmptyKanbanSlot />
        ) : (
          columns.needsReorder.slice(0, 10).map((s) => (
            <SuggestionKanbanCard key={s.part_id} suggestion={s} />
          ))
        )}
        {columns.needsReorder.length > 10 && (
          <p className="text-xs text-center text-gray-500 dark:text-gray-400 py-2">
            +{columns.needsReorder.length - 10} more
          </p>
        )}
      </KanbanColumnCard>

      {/* Column 2: Ready to Order */}
      <KanbanColumnCard
        column={KANBAN_COLUMNS[1]}
        count={columns.readyToOrder.length}
      >
        {columns.readyToOrder.length === 0 ? (
          <EmptyKanbanSlot />
        ) : (
          columns.readyToOrder.slice(0, 10).map((s) => (
            <SuggestionKanbanCard key={s.part_id} suggestion={s} />
          ))
        )}
      </KanbanColumnCard>

      {/* Column 3: On Order */}
      <KanbanColumnCard
        column={KANBAN_COLUMNS[2]}
        count={columns.onOrder.length}
      >
        {columns.onOrder.length === 0 ? (
          <EmptyKanbanSlot />
        ) : (
          columns.onOrder.slice(0, 10).map((po) => (
            <POKanbanCard key={po.id} po={po} />
          ))
        )}
      </KanbanColumnCard>

      {/* Column 4: Received */}
      <KanbanColumnCard
        column={KANBAN_COLUMNS[3]}
        count={columns.received.length}
      >
        {columns.received.length === 0 ? (
          <EmptyKanbanSlot />
        ) : (
          columns.received.slice(0, 10).map((po) => (
            <POKanbanCard key={po.id} po={po} />
          ))
        )}
      </KanbanColumnCard>
    </div>
  );
}


function KanbanColumnCard({
  column,
  count,
  children,
}: {
  column: KanbanColumn;
  count: number;
  children: React.ReactNode;
}) {
  const Icon = column.icon;
  return (
    <div
      className={`rounded-xl border border-gray-200 dark:border-gray-700 bg-gray-50 dark:bg-gray-800/50 border-t-4 ${column.color} overflow-hidden`}
    >
      <div className="flex items-center justify-between px-4 py-3">
        <div className="flex items-center gap-2">
          <Icon className="h-4 w-4 text-gray-500 dark:text-gray-400" />
          <h3 className="text-sm font-semibold text-gray-900 dark:text-gray-100">
            {column.label}
          </h3>
        </div>
        <span className="text-xs font-medium text-gray-500 dark:text-gray-400 bg-gray-200 dark:bg-gray-700 px-2 py-0.5 rounded-full tabular-nums">
          {count}
        </span>
      </div>
      <div className="px-3 pb-3 space-y-2 max-h-[500px] overflow-y-auto">{children}</div>
    </div>
  );
}


function SuggestionKanbanCard({ suggestion: s }: { suggestion: ReorderSuggestion }) {
  const isUrgent = s.current_stock === 0;
  return (
    <div
      className={`rounded-lg border bg-white dark:bg-gray-800 p-3 shadow-sm ${
        isUrgent
          ? 'border-red-300 dark:border-red-700'
          : 'border-gray-200 dark:border-gray-700'
      }`}
    >
      <div className="flex items-start justify-between gap-2">
        <PartIdentity
          partName={s.part_name}
          partDescription={s.part_description}
          partNumber={s.part_number}
          partId={s.part_id}
          brandName={s.brand_name}
          colorName={s.color_name}
          colorHex={s.color_hex}
          categoryName={s.category_name}
          typeName={s.type_name}
          className="min-w-0 flex-1"
        />
        {isUrgent && (
          <span className="flex-shrink-0 text-xs font-medium text-red-600 dark:text-red-400 bg-red-100 dark:bg-red-900/30 px-1.5 py-0.5 rounded">
            OUT
          </span>
        )}
      </div>
      <div className="flex items-center gap-3 mt-2 text-xs text-gray-500 dark:text-gray-400">
        <span className="tabular-nums">
          {s.current_stock}/{s.reorder_point}
        </span>
        <ChevronRight className="h-3 w-3" />
        <span className="font-medium text-primary tabular-nums">
          +{s.suggested_order_qty}
        </span>
      </div>
    </div>
  );
}


function POKanbanCard({ po }: { po: POListItem }) {
  const statusColors: Record<string, string> = {
    submitted: 'bg-blue-100 text-blue-700 dark:bg-blue-900/30 dark:text-blue-400',
    acknowledged: 'bg-indigo-100 text-indigo-700 dark:bg-indigo-900/30 dark:text-indigo-400',
    partially_received:
      'bg-amber-100 text-amber-700 dark:bg-amber-900/30 dark:text-amber-400',
    received: 'bg-green-100 text-green-700 dark:bg-green-900/30 dark:text-green-400',
  };

  return (
    <div className="rounded-lg border border-gray-200 dark:border-gray-700 bg-white dark:bg-gray-800 p-3 shadow-sm">
      <div className="flex items-start justify-between gap-2">
        <p className="text-sm font-medium text-gray-900 dark:text-gray-100">
          {po.po_number}
        </p>
        <span
          className={`text-xs font-medium px-1.5 py-0.5 rounded ${
            statusColors[po.status] ?? 'bg-gray-100 text-gray-600'
          }`}
        >
          {po.status.replace(/_/g, ' ')}
        </span>
      </div>
      <p className="text-xs text-gray-500 dark:text-gray-400 mt-0.5 truncate">
        {po.supplier_name ?? 'Unknown'}
      </p>
      <div className="flex items-center justify-between mt-2 text-xs text-gray-500 dark:text-gray-400">
        <span>
          {po.line_count} line{po.line_count !== 1 ? 's' : ''}
        </span>
        {po.total_cost > 0 && (
          <span className="tabular-nums">
            ${po.total_cost.toLocaleString(undefined, {
              minimumFractionDigits: 2,
              maximumFractionDigits: 2,
            })}
          </span>
        )}
      </div>
    </div>
  );
}


function EmptyKanbanSlot() {
  return (
    <div className="rounded-lg border-2 border-dashed border-gray-300 dark:border-gray-600 py-6 text-center">
      <p className="text-xs text-gray-400 dark:text-gray-500">No items</p>
    </div>
  );
}
