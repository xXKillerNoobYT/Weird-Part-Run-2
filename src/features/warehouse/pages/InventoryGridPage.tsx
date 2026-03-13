/**
 * InventoryGridPage — paginated warehouse inventory table with
 * search, filters, stock health bars, and row actions.
 *
 * "Move" opens the wizard pre-filled with the selected part.
 * "Check" launches a 1-item spot-check audit (coming Phase 3 audit).
 * "+" opens the AddStockModal to receive new stock into the warehouse.
 */

import { useState, useEffect, useCallback } from 'react';
import { useNavigate } from 'react-router-dom';
import { useQuery } from '@tanstack/react-query';
import { Plus, Printer } from 'lucide-react';
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
import { BulkQRPrintModal } from '../components/inventory/BulkQRPrintModal';
import type { StockStatus, WarehouseInventoryItem } from '../../../lib/types';

export function InventoryGridPage() {
  const navigate = useNavigate();
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

  // ── Bulk QR print selection ────────────────────────
  const [selectedIds, setSelectedIds] = useState<Set<number>>(new Set());
  const [bulkQROpen, setBulkQROpen] = useState(false);

  const toggleSelect = useCallback((partId: number) => {
    setSelectedIds(prev => {
      const next = new Set(prev);
      if (next.has(partId)) next.delete(partId);
      else next.add(partId);
      return next;
    });
  }, []);

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

  const toggleSelectAll = useCallback(() => {
    const currentItems = data?.items ?? [];
    setSelectedIds(prev => {
      const allSelected = currentItems.every(i => prev.has(i.part_id));
      if (allSelected) {
        // Deselect all visible items
        const next = new Set(prev);
        currentItems.forEach(i => next.delete(i.part_id));
        return next;
      } else {
        // Select all visible items
        const next = new Set(prev);
        currentItems.forEach(i => next.add(i.part_id));
        return next;
      }
    });
  }, [data]);

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

  const handleSpotCheck = (item: WarehouseInventoryItem) => {
    navigate('/warehouse/audit', {
      state: {
        spotCheck: true,
        partId: item.part_id,
        partName: item.part_name,
      },
    });
  };

  if (isLoading && !data) {
    return <PageSpinner label="Loading inventory..." />;
  }

  const items = data?.items ?? [];
  const totalPages = data?.total_pages ?? 1;

  return (
    <>
      <div className="space-y-4">
        {/* Filters row with bulk actions and Add Stock button */}
        <div className="flex flex-wrap items-start justify-between gap-3">
          <div className="flex-1 min-w-0">
            <InventoryFilters
              search={search}
              onSearchChange={setSearch}
              stockStatus={stockStatus}
              onStockStatusChange={setStockStatus}
            />
          </div>
          <div className="flex items-center gap-2 flex-shrink-0">
            {selectedIds.size > 0 && (
              <Button
                variant="secondary"
                size="sm"
                onClick={() => setBulkQROpen(true)}
              >
                <Printer className="h-4 w-4 mr-1" />
                <span className="hidden sm:inline">Print QR</span> ({selectedIds.size})
              </Button>
            )}
            <Button
              variant="primary"
              size="sm"
              onClick={() => setAddStockOpen(true)}
            >
              <Plus className="h-4 w-4 mr-1" />
              <span className="hidden sm:inline">Add Stock</span>
            </Button>
          </div>
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
            selectedIds={selectedIds}
            onToggleSelect={toggleSelect}
            onToggleSelectAll={toggleSelectAll}
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
      <BulkQRPrintModal
        isOpen={bulkQROpen}
        onClose={() => {
          setBulkQROpen(false);
          setSelectedIds(new Set());
        }}
        items={items.filter(i => selectedIds.has(i.part_id))}
      />
    </>
  );
}
