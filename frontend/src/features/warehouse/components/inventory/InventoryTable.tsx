/**
 * InventoryTable — full table with stock health bars (desktop)
 * and color badges (mobile).
 *
 * Each row shows stock levels relative to min/target/max with
 * a visual progress bar on larger screens.
 */

import {
  ArrowUp, ArrowDown, ArrowRightLeft, Search, QrCode,
} from 'lucide-react';
import { Badge } from '../../../../components/ui/Badge';
import { Button } from '../../../../components/ui/Button';
import { cn } from '../../../../lib/utils';
import { useAuthStore } from '../../../../stores/auth-store';
import { PERMISSIONS } from '../../../../lib/constants';
import type { WarehouseInventoryItem } from '../../../../lib/types';

const statusLabels: Record<string, string> = {
  low_stock: 'Low',
  overstock: 'Over',
  in_range: 'OK',
  winding_down: 'Winding Down',
  zero: 'Zero',
};

const statusVariant: Record<string, 'success' | 'warning' | 'danger' | 'default' | 'primary'> = {
  low_stock: 'danger',
  overstock: 'warning',
  in_range: 'success',
  winding_down: 'default',
  zero: 'danger',
};

interface InventoryTableProps {
  items: WarehouseInventoryItem[];
  sortBy: string;
  sortDir: 'asc' | 'desc';
  onSort: (column: string) => void;
  onMove: (item: WarehouseInventoryItem) => void;
  onSpotCheck: (item: WarehouseInventoryItem) => void;
  onQRLabel: (item: WarehouseInventoryItem) => void;
}

function SortIcon({ column, sortBy, sortDir }: { column: string; sortBy: string; sortDir: string }) {
  if (column !== sortBy) return null;
  return sortDir === 'asc'
    ? <ArrowUp className="h-3 w-3 inline ml-1" />
    : <ArrowDown className="h-3 w-3 inline ml-1" />;
}

export function InventoryTable({
  items, sortBy, sortDir, onSort, onMove, onSpotCheck, onQRLabel,
}: InventoryTableProps) {
  const { hasPermission } = useAuthStore();
  const showDollars = hasPermission(PERMISSIONS.SHOW_DOLLAR_VALUES);
  const canMove = hasPermission(PERMISSIONS.MOVE_STOCK_WAREHOUSE);
  const canAudit = hasPermission(PERMISSIONS.PERFORM_AUDIT);

  if (items.length === 0) {
    return (
      <div className="flex flex-col items-center py-12 gap-3">
        <Search className="h-8 w-8 text-gray-400 dark:text-gray-500" />
        <p className="text-sm text-gray-500 dark:text-gray-400">
          No inventory items match your filters.
        </p>
      </div>
    );
  }

  return (
    <div className="overflow-x-auto">
      <table className="w-full text-sm">
        <thead>
          <tr className="border-b border-gray-200 dark:border-gray-700">
            {[
              { key: 'part_name', label: 'Part', align: 'text-left' },
              { key: 'category_name', label: 'Category', align: 'text-left' },
              { key: 'warehouse_qty', label: 'Qty', align: 'text-center' },
              { key: 'health_pct', label: 'Health', align: 'text-center' },
              { key: 'shelf_location', label: 'Shelf', align: 'text-left' },
            ].map((col) => (
              <th
                key={col.key}
                onClick={() => onSort(col.key)}
                className={cn(
                  'py-2 px-3 font-medium text-gray-500 dark:text-gray-400 cursor-pointer hover:text-gray-700 dark:hover:text-gray-200 select-none',
                  col.align,
                )}
              >
                {col.label}
                <SortIcon column={col.key} sortBy={sortBy} sortDir={sortDir} />
              </th>
            ))}
            {showDollars && (
              <th className="py-2 px-3 text-right font-medium text-gray-500 dark:text-gray-400">
                Value
              </th>
            )}
            <th className="py-2 px-3 text-left font-medium text-gray-500 dark:text-gray-400">
              Supplier
            </th>
            <th className="py-2 px-3 text-right font-medium text-gray-500 dark:text-gray-400">
              Actions
            </th>
          </tr>
        </thead>
        <tbody>
          {items.map((item) => (
            <tr
              key={item.part_id}
              className="border-b border-gray-100 dark:border-gray-800 last:border-0 hover:bg-gray-50 dark:hover:bg-gray-700/30"
            >
              {/* Part */}
              <td className="py-2.5 px-3">
                <div className="flex items-center gap-1.5">
                  <span className="font-medium text-gray-900 dark:text-gray-100">
                    {item.part_name}
                  </span>
                  {item.is_qr_tagged && (
                    <QrCode className="h-3.5 w-3.5 text-green-500 flex-shrink-0" title="QR Tagged" />
                  )}
                </div>
                {item.part_code && (
                  <span className="text-xs text-gray-500 dark:text-gray-400">
                    {item.part_code}
                  </span>
                )}
              </td>

              {/* Category */}
              <td className="py-2.5 px-3 text-gray-600 dark:text-gray-400">
                {item.category_name ?? '—'}
              </td>

              {/* Qty */}
              <td className="py-2.5 px-3 text-center">
                <span className="font-medium text-gray-900 dark:text-gray-100">
                  {item.warehouse_qty}
                </span>
                <span className="text-xs text-gray-500 dark:text-gray-400 ml-1">
                  / {item.target_stock_level}
                </span>
              </td>

              {/* Health Bar (desktop) / Badge (mobile) */}
              <td className="py-2.5 px-3 text-center">
                {/* Desktop: progress bar */}
                <div className="hidden sm:block">
                  <StockHealthBar item={item} />
                </div>
                {/* Mobile: badge */}
                <div className="sm:hidden">
                  <Badge variant={statusVariant[item.stock_status] ?? 'default'}>
                    {statusLabels[item.stock_status] ?? item.stock_status}
                  </Badge>
                </div>
              </td>

              {/* Shelf */}
              <td className="py-2.5 px-3 text-gray-600 dark:text-gray-400">
                {item.shelf_location ?? '—'}
              </td>

              {/* Value */}
              {showDollars && (
                <td className="py-2.5 px-3 text-right text-gray-700 dark:text-gray-300">
                  {item.total_value != null
                    ? `$${item.total_value.toFixed(2)}`
                    : '—'}
                </td>
              )}

              {/* Supplier */}
              <td className="py-2.5 px-3 text-gray-600 dark:text-gray-400 text-xs">
                {item.primary_supplier_name ?? '—'}
              </td>

              {/* Actions */}
              <td className="py-2.5 px-3 text-right">
                <div className="flex items-center justify-end gap-1">
                  <Button
                    variant="ghost"
                    size="sm"
                    icon={<QrCode className="h-3.5 w-3.5" />}
                    onClick={() => onQRLabel(item)}
                  >
                    QR
                  </Button>
                  {canMove && (
                    <Button
                      variant="ghost"
                      size="sm"
                      icon={<ArrowRightLeft className="h-3.5 w-3.5" />}
                      onClick={() => onMove(item)}
                    >
                      Move
                    </Button>
                  )}
                  {canAudit && (
                    <Button
                      variant="ghost"
                      size="sm"
                      icon={<Search className="h-3.5 w-3.5" />}
                      onClick={() => onSpotCheck(item)}
                    >
                      Check
                    </Button>
                  )}
                </div>
              </td>
            </tr>
          ))}
        </tbody>
      </table>
    </div>
  );
}

// ── Stock Health Progress Bar ────────────────────────────────────

function StockHealthBar({ item }: { item: WarehouseInventoryItem }) {
  const { min_stock_level, max_stock_level, warehouse_qty, stock_status } = item;

  // Prevent division by zero
  const range = max_stock_level - min_stock_level;
  const pct = range > 0
    ? Math.min(100, Math.max(0, ((warehouse_qty - min_stock_level) / range) * 100))
    : warehouse_qty > 0 ? 100 : 0;

  const barColor =
    stock_status === 'low_stock' || stock_status === 'zero'
      ? 'bg-red-500'
      : stock_status === 'overstock'
        ? 'bg-amber-500'
        : stock_status === 'winding_down'
          ? 'bg-gray-400'
          : 'bg-green-500';

  return (
    <div className="flex items-center gap-2">
      <div className="w-20 h-2 bg-gray-200 dark:bg-gray-700 rounded-full overflow-hidden">
        <div
          className={cn('h-full rounded-full transition-all', barColor)}
          style={{ width: `${pct}%` }}
        />
      </div>
      <Badge
        variant={statusVariant[stock_status] ?? 'default'}
        className="text-[10px]"
      >
        {statusLabels[stock_status] ?? stock_status}
      </Badge>
    </div>
  );
}
