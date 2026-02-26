/**
 * InventoryGridPage — paginated warehouse inventory table with
 * search, filters, stock health bars, and row actions.
 *
 * "Move" opens the wizard pre-filled with the selected part.
 * "Check" launches a 1-item spot-check audit (coming Phase 3 audit).
 * "+" opens the AddStockModal to receive new stock into the warehouse.
 */

import { useState, useEffect } from 'react';
import { useQuery } from '@tanstack/react-query';
import { Plus } from 'lucide-react';
import { Card } from '../../../components/ui/Card';
import { Button } from '../../../components/ui/Button';
import { PageSpinner } from '../../../components/ui/Spinner';
import { getWarehouseInventory } from '../../../api/warehouse';
import { useMovementWizardStore } from '../stores/movement-wizard-store';
import { MovementWizard } from '../components/wizard/MovementWizard';
import { InventoryFilters } from '../components/inventory/InventoryFilters';
import { InventoryTable } from '../components/inventory/InventoryTable';
import { AddStockModal } from '../components/inventory/AddStockModal';
import { QRLabelModal } from '../components/inventory/QRLabelModal';
import type { StockStatus, WarehouseInventoryItem } from '../../../lib/types';

export function InventoryGridPage() {
  const { open: openWizard } = useMovementWizardStore();

  // ── Filter state ───────────────────────────────────────
  const [search, setSearch] = useState('');
  const [debouncedSearch, setDebouncedSearch] = useState('');
  const [stockStatus, setStockStatus] = useState<StockStatus>('all');
  const [sortBy, setSortBy] = useState('part_name');
  const [sortDir, setSortDir] = useState<'asc' | 'desc'>('asc');
  const [page, setPage] = useState(1);

  // ── Add Stock modal ────────────────────────────────────
  const [addStockOpen, setAddStockOpen] = useState(false);

  // ── QR Label modal ───────────────────────────────────
  const [qrLabelItem, setQrLabelItem] = useState<WarehouseInventoryItem | null>(null);

  // Debounce search input
  useEffect(() => {
    const timer = setTimeout(() => setDebouncedSearch(search), 300);
    return () => clearTimeout(timer);
  }, [search]);

  // Reset page when filters change
  useEffect(() => {
    setPage(1);
  }, [debouncedSearch, stockStatus, sortBy, sortDir]);

  // ── Data fetching ──────────────────────────────────────
  const { data, isLoading } = useQuery({
    queryKey: ['warehouse-inventory', debouncedSearch, stockStatus, sortBy, sortDir, page],
    queryFn: () => getWarehouseInventory({
      search: debouncedSearch || undefined,
      stock_status: stockStatus === 'all' ? undefined : stockStatus,
      sort_by: sortBy,
      sort_dir: sortDir,
      page,
      page_size: 50,
    }),
    staleTime: 15_000,
  });

  const handleSort = (column: string) => {
    if (column === sortBy) {
      setSortDir((d) => (d === 'asc' ? 'desc' : 'asc'));
    } else {
      setSortBy(column);
      setSortDir('asc');
    }
  };

  const handleMove = (item: WarehouseInventoryItem) => {
    openWizard({
      fromLocationType: 'warehouse',
      selectedParts: [{
        part_id: item.part_id,
        part_name: item.part_name,
        part_code: item.part_code,
        available_qty: item.warehouse_qty,
        category_name: item.category_name,
        shelf_location: item.shelf_location,
        supplier_name: item.primary_supplier_name,
        qty: 1,
      }],
    });
  };

  const handleSpotCheck = (_item: WarehouseInventoryItem) => {
    // TODO: Navigate to audit page with spot-check for this part
  };

  if (isLoading && !data) {
    return <PageSpinner label="Loading inventory..." />;
  }

  const items = data?.items ?? [];
  const totalPages = data?.total_pages ?? 1;

  return (
    <>
      <div className="space-y-4">
        {/* Filters row with Add Stock button */}
        <div className="flex items-start justify-between gap-4">
          <div className="flex-1">
            <InventoryFilters
              search={search}
              onSearchChange={setSearch}
              stockStatus={stockStatus}
              onStockStatusChange={setStockStatus}
            />
          </div>
          <Button
            variant="primary"
            size="sm"
            onClick={() => setAddStockOpen(true)}
            className="flex-shrink-0"
          >
            <Plus className="h-4 w-4 mr-1" />
            Add Stock
          </Button>
        </div>

        <Card noPadding>
          <InventoryTable
            items={items}
            sortBy={sortBy}
            sortDir={sortDir}
            onSort={handleSort}
            onMove={handleMove}
            onSpotCheck={handleSpotCheck}
            onQRLabel={setQrLabelItem}
          />

          {/* Pagination */}
          {totalPages > 1 && (
            <div className="flex items-center justify-between px-4 py-3 border-t border-gray-200 dark:border-gray-700">
              <span className="text-sm text-gray-500 dark:text-gray-400">
                Page {page} of {totalPages} ({data?.total ?? 0} items)
              </span>
              <div className="flex gap-2">
                <Button
                  variant="secondary"
                  size="sm"
                  disabled={page <= 1}
                  onClick={() => setPage((p) => Math.max(1, p - 1))}
                >
                  Previous
                </Button>
                <Button
                  variant="secondary"
                  size="sm"
                  disabled={page >= totalPages}
                  onClick={() => setPage((p) => p + 1)}
                >
                  Next
                </Button>
              </div>
            </div>
          )}
        </Card>
      </div>

      <MovementWizard />
      <AddStockModal
        isOpen={addStockOpen}
        onClose={() => setAddStockOpen(false)}
      />
      <QRLabelModal
        isOpen={qrLabelItem !== null}
        onClose={() => setQrLabelItem(null)}
        item={qrLabelItem}
      />
    </>
  );
}
