/**
 * AddStockModal — add parts from the catalog to warehouse inventory.
 *
 * Flow:
 * 1. Search for a part by name, code, or MPN
 * 2. Select it from the dropdown
 * 3. If the part already has warehouse stock, show a banner with existing info
 *    and pre-fill location fields from existing data
 * 4. Enter quantity, shelf location, and optional bin
 * 5. Confirm → creates a 'receive' movement in the audit trail
 *
 * Supports adding one part at a time. The modal stays open after success
 * so you can add another part quickly (toast confirms each addition).
 */

import { useState, useEffect, useCallback } from 'react';
import { Search, Package, MapPin, Hash, AlertCircle } from 'lucide-react';
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import { Modal } from '../../../../components/ui/Modal';
import { Input } from '../../../../components/ui/Input';
import { Button } from '../../../../components/ui/Button';
import { Spinner } from '../../../../components/ui/Spinner';
import { listParts } from '../../../../api/parts';
import { receiveStock, getWarehouseInventory } from '../../../../api/warehouse';

interface AddStockModalProps {
  isOpen: boolean;
  onClose: () => void;
}

export function AddStockModal({ isOpen, onClose }: AddStockModalProps) {
  const queryClient = useQueryClient();

  // ── Search state ───────────────────────────────────────────
  const [searchTerm, setSearchTerm] = useState('');
  const [debouncedSearch, setDebouncedSearch] = useState('');
  const [selectedPart, setSelectedPart] = useState<{
    id: number;
    name: string;
    code?: string | null;
    shelf_location?: string | null;
    bin_location?: string | null;
  } | null>(null);

  // ── Form state ─────────────────────────────────────────────
  const [qty, setQty] = useState<number>(1);
  const [shelfLocation, setShelfLocation] = useState('');
  const [binLocation, setBinLocation] = useState('');
  const [notes, setNotes] = useState('');

  // ── Feedback ──────────────────────────────────────────────
  const [successMessage, setSuccessMessage] = useState('');
  const [errorMessage, setErrorMessage] = useState('');

  // Debounce search
  useEffect(() => {
    const timer = setTimeout(() => setDebouncedSearch(searchTerm), 300);
    return () => clearTimeout(timer);
  }, [searchTerm]);

  // Reset form when modal opens/closes
  useEffect(() => {
    if (isOpen) {
      resetForm();
    }
  }, [isOpen]);

  const resetForm = () => {
    setSearchTerm('');
    setDebouncedSearch('');
    setSelectedPart(null);
    setQty(1);
    setShelfLocation('');
    setBinLocation('');
    setNotes('');
    setSuccessMessage('');
    setErrorMessage('');
  };

  // ── Part search query ──────────────────────────────────────
  const { data: searchResults, isLoading: searching } = useQuery({
    queryKey: ['add-stock-search', debouncedSearch],
    queryFn: () =>
      listParts({
        search: debouncedSearch,
        page: 1,
        page_size: 10,
        sort_by: 'name',
        sort_dir: 'asc',
      }),
    enabled: !selectedPart && debouncedSearch.length >= 2,
  });

  const filteredResults = searchResults?.items ?? [];

  // ── Check existing warehouse stock for the selected part ───
  const { data: existingStock, isLoading: checkingStock } = useQuery({
    queryKey: ['warehouse-stock-check', selectedPart?.id],
    queryFn: async () => {
      const result = await getWarehouseInventory({
        part_id: selectedPart!.id,
        page: 1,
        page_size: 1,
      });
      // If we found this part in inventory with stock, return its data
      const match = result.items.find(
        (i) => i.part_id === selectedPart!.id && i.warehouse_qty > 0
      );
      return match ?? null;
    },
    enabled: !!selectedPart,
  });

  // ── Select a part ──────────────────────────────────────────
  const handleSelectPart = useCallback(
    (part: {
      id: number;
      name: string;
      code?: string | null;
      shelf_location?: string | null;
      bin_location?: string | null;
    }) => {
      setSelectedPart(part);
      setSearchTerm('');
      setDebouncedSearch('');
      // Pre-fill location from the part record itself
      if (part.shelf_location) setShelfLocation(part.shelf_location);
      if (part.bin_location) setBinLocation(part.bin_location);
    },
    []
  );

  // When stock check completes, override location fields from warehouse data
  // (warehouse data is more current than the static part record)
  useEffect(() => {
    if (existingStock) {
      if (existingStock.shelf_location) setShelfLocation(existingStock.shelf_location);
      if (existingStock.bin_location) setBinLocation(existingStock.bin_location);
    }
  }, [existingStock]);

  // ── Submit mutation ────────────────────────────────────────
  const { mutate: submitReceive, isPending: submitting } = useMutation({
    mutationFn: () =>
      receiveStock({
        items: [
          {
            part_id: selectedPart!.id,
            qty,
            shelf_location: shelfLocation || null,
            bin_location: binLocation || null,
            notes: notes || null,
          },
        ],
        reason: 'Stock Received',
      }),
    onSuccess: (result) => {
      setErrorMessage('');
      // Invalidate inventory grid so it refreshes
      queryClient.invalidateQueries({ queryKey: ['warehouse-inventory'] });
      queryClient.invalidateQueries({ queryKey: ['warehouse-dashboard'] });
      queryClient.invalidateQueries({ queryKey: ['warehouse-stock-check'] });

      // Show success + reset for another addition
      setSuccessMessage(
        `Added ${result.total_qty}× ${selectedPart!.name} to warehouse`
      );
      setSelectedPart(null);
      setQty(1);
      setShelfLocation('');
      setBinLocation('');
      setNotes('');

      // Auto-clear success message after 3s
      setTimeout(() => setSuccessMessage(''), 3000);
    },
    onError: (error: any) => {
      const detail =
        error?.response?.data?.detail ??
        error?.message ??
        'Failed to add stock. Please try again.';
      setErrorMessage(detail);
    },
  });

  const canSubmit = selectedPart !== null && qty >= 1;

  return (
    <Modal
      isOpen={isOpen}
      onClose={onClose}
      title="Add Stock to Warehouse"
      size="md"
    >
      <div className="space-y-4 max-h-[70vh] overflow-y-auto">
        {/* Success toast */}
        {successMessage && (
          <div className="flex items-center gap-2 px-3 py-2 rounded-lg bg-green-50 dark:bg-green-900/20 border border-green-200 dark:border-green-800 text-sm text-green-700 dark:text-green-300">
            <Package className="h-4 w-4 flex-shrink-0" />
            {successMessage}
          </div>
        )}

        {/* Error toast */}
        {errorMessage && (
          <div className="flex items-center gap-2 px-3 py-2 rounded-lg bg-red-50 dark:bg-red-900/20 border border-red-200 dark:border-red-800 text-sm text-red-700 dark:text-red-300">
            <AlertCircle className="h-4 w-4 flex-shrink-0" />
            {errorMessage}
          </div>
        )}

        {/* Part search / selection */}
        {selectedPart ? (
          <div className="flex items-center gap-2 p-3 rounded-lg bg-primary-50 dark:bg-primary-900/20 border border-primary-200 dark:border-primary-800">
            <Package className="h-4 w-4 text-primary-600 dark:text-primary-400 flex-shrink-0" />
            <div className="flex-1 min-w-0">
              <span className="text-sm font-medium text-primary-700 dark:text-primary-300 truncate block">
                {selectedPart.name}
              </span>
              {selectedPart.code && (
                <span className="text-xs text-primary-500 font-mono">
                  {selectedPart.code}
                </span>
              )}
            </div>
            <button
              className="text-xs text-primary-500 hover:underline flex-shrink-0"
              onClick={() => {
                setSelectedPart(null);
                setShelfLocation('');
                setBinLocation('');
              }}
            >
              Change
            </button>
          </div>
        ) : (
          <div className="relative">
            <Input
              label="Search for a part"
              value={searchTerm}
              onChange={(e) => setSearchTerm(e.target.value)}
              placeholder="Search by name, code, or MPN..."
              icon={<Search className="h-4 w-4" />}
            />

            {/* Search results dropdown */}
            {debouncedSearch.length >= 2 && (
              <div className="absolute z-10 left-0 right-0 top-full mt-1 bg-white dark:bg-gray-800 border border-gray-200 dark:border-gray-700 rounded-lg shadow-lg max-h-48 overflow-y-auto">
                {searching ? (
                  <div className="flex justify-center py-3">
                    <Spinner size="sm" />
                  </div>
                ) : filteredResults.length === 0 ? (
                  <p className="text-sm text-gray-500 dark:text-gray-400 p-3 text-center">
                    No parts found
                  </p>
                ) : (
                  filteredResults.map((part) => (
                    <button
                      key={part.id}
                      className="w-full text-left px-3 py-2 hover:bg-gray-50 dark:hover:bg-gray-700/50 transition-colors border-b border-gray-100 dark:border-gray-700/50 last:border-b-0"
                      onClick={() =>
                        handleSelectPart({
                          id: part.id,
                          name: part.name,
                          code: part.code,
                          shelf_location: (part as any).shelf_location,
                          bin_location: (part as any).bin_location,
                        })
                      }
                    >
                      <div className="flex items-center justify-between">
                        <span className="text-sm font-medium text-gray-900 dark:text-gray-100">
                          {part.name}
                        </span>
                        {part.code && (
                          <span className="text-xs text-gray-500 font-mono">
                            {part.code}
                          </span>
                        )}
                      </div>
                      <div className="flex items-center gap-2 mt-0.5">
                        {part.brand_name && (
                          <span className="text-xs text-gray-500 dark:text-gray-400">
                            {part.brand_name}
                          </span>
                        )}
                        {part.category_name && (
                          <span className="text-xs text-gray-400 dark:text-gray-500">
                            {part.category_name}
                          </span>
                        )}
                      </div>
                    </button>
                  ))
                )}
              </div>
            )}
          </div>
        )}

        {/* "Already in warehouse" notice */}
        {selectedPart && !checkingStock && existingStock && (
          <div className="flex items-start gap-2.5 px-3 py-2.5 rounded-lg bg-amber-50 dark:bg-amber-900/20 border border-amber-200 dark:border-amber-800">
            <AlertCircle className="h-4 w-4 text-amber-600 dark:text-amber-400 flex-shrink-0 mt-0.5" />
            <div className="text-sm">
              <p className="font-medium text-amber-700 dark:text-amber-300">
                Already in warehouse
              </p>
              <p className="text-amber-600 dark:text-amber-400 mt-0.5">
                Current stock: <strong>{existingStock.warehouse_qty}</strong> units
                {existingStock.shelf_location && (
                  <> &middot; Shelf: <strong>{existingStock.shelf_location}</strong></>
                )}
                {existingStock.bin_location && (
                  <> &middot; Bin: <strong>{existingStock.bin_location}</strong></>
                )}
              </p>
              <p className="text-amber-500 dark:text-amber-500 text-xs mt-1">
                Adding more will increase the existing count.
              </p>
            </div>
          </div>
        )}

        {/* Stock check loading indicator */}
        {selectedPart && checkingStock && (
          <div className="flex items-center gap-2 px-3 py-2 text-sm text-gray-400">
            <Spinner size="sm" /> Checking existing stock...
          </div>
        )}

        {/* Quantity */}
        <div>
          <Input
            label="Quantity"
            type="number"
            min={1}
            value={String(qty)}
            onChange={(e) => setQty(Math.max(1, parseInt(e.target.value) || 1))}
            icon={<Hash className="h-4 w-4" />}
          />
        </div>

        {/* Shelf Location */}
        <div>
          <Input
            label="Shelf Location"
            value={shelfLocation}
            onChange={(e) => setShelfLocation(e.target.value)}
            placeholder="e.g. Row A, Shelf 3"
            icon={<MapPin className="h-4 w-4" />}
          />
          <p className="mt-1 text-xs text-gray-400 dark:text-gray-500">
            General area in the warehouse where this part is stored
          </p>
        </div>

        {/* Bin Location (optional) */}
        <div>
          <Input
            label="Bin (optional)"
            value={binLocation}
            onChange={(e) => setBinLocation(e.target.value)}
            placeholder="e.g. Bin 12"
            icon={<Package className="h-4 w-4" />}
          />
          <p className="mt-1 text-xs text-gray-400 dark:text-gray-500">
            Specific bin within the shelf area — leave blank if not applicable
          </p>
        </div>

        {/* Notes */}
        <div className="space-y-1.5">
          <label className="block text-sm font-medium text-gray-700 dark:text-gray-300">
            Notes
          </label>
          <textarea
            value={notes}
            onChange={(e) => setNotes(e.target.value)}
            className="w-full rounded-lg border border-gray-300 dark:border-gray-600 bg-white dark:bg-gray-800 px-3 py-2 text-sm min-h-[60px] text-gray-900 dark:text-gray-100"
            placeholder="e.g. Initial count, delivery received..."
          />
        </div>
      </div>

      {/* Footer */}
      <div className="flex justify-end gap-2 mt-4 pt-4 border-t border-gray-200 dark:border-gray-700">
        <Button variant="secondary" onClick={onClose}>
          Close
        </Button>
        <Button
          variant="primary"
          onClick={() => submitReceive()}
          disabled={!canSubmit}
          isLoading={submitting}
        >
          Add to Warehouse
        </Button>
      </div>
    </Modal>
  );
}
