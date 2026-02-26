/**
 * Step 2: Select Parts — search and add parts to the movement batch.
 *
 * Context-aware: transfers show only parts with stock at source;
 * general "add stock" shows all catalog parts.
 *
 * Includes an optional QR scanner bubble for scanning shelf labels.
 */

import { useState, useCallback } from 'react';
import { useQuery } from '@tanstack/react-query';
import { Search, Plus, X, Package } from 'lucide-react';
import { Badge } from '../../../../../components/ui/Badge';
import { Spinner } from '../../../../../components/ui/Spinner';
import { cn } from '../../../../../lib/utils';
import { searchPartsForWizard } from '../../../../../api/warehouse';
import { useMovementWizardStore } from '../../../stores/movement-wizard-store';
import { QRScannerBubble } from '../QRScannerBubble';
import type { WiredPartQRData } from '../../../../../lib/qr-utils';

export function StepSelectParts() {
  const {
    fromLocationType,
    fromLocationId,
    selectedParts,
    addPart,
    removePart,
  } = useMovementWizardStore();

  const [searchText, setSearchText] = useState('');
  const [scanFeedback, setScanFeedback] = useState<string | null>(null);

  const { data: searchResults = [], isLoading } = useQuery({
    queryKey: ['wizard-parts-search', searchText, fromLocationType, fromLocationId],
    queryFn: () =>
      searchPartsForWizard({
        q: searchText,
        location_type: fromLocationType ?? undefined,
        location_id: fromLocationId,
        limit: 20,
      }),
    enabled: searchText.length >= 1,
    staleTime: 10_000,
  });

  const selectedIds = new Set(selectedParts.map((p) => p.part_id));

  // ── QR scan handler ──────────────────────────────────────────
  const handleQRScan = useCallback(
    async (data: WiredPartQRData) => {
      // Skip if already in the batch
      if (selectedIds.has(data.part_id)) {
        setScanFeedback('Already added');
        setTimeout(() => setScanFeedback(null), 2000);
        return;
      }

      // Look up the scanned part in the source location
      try {
        const results = await searchPartsForWizard({
          q: data.code || String(data.part_id),
          location_type: fromLocationType ?? undefined,
          location_id: fromLocationId,
          limit: 10,
        });

        const match = results.find((r) => r.part_id === data.part_id);
        if (match) {
          addPart(match);
          setScanFeedback(`Added: ${match.part_name}`);
        } else {
          setScanFeedback('Part not found at source');
        }
      } catch {
        setScanFeedback('Lookup failed');
      }

      setTimeout(() => setScanFeedback(null), 2500);
    },
    [selectedIds, fromLocationType, fromLocationId, addPart],
  );

  return (
    <div className="space-y-4">
      {/* QR Scanner bubble + search row */}
      <div className="flex items-start gap-4">
        <QRScannerBubble
          onScan={handleQRScan}
          disabled={selectedParts.length >= 20}
        />

        {/* Scan feedback toast */}
        {scanFeedback && (
          <div className="flex items-center gap-2 px-3 py-1.5 rounded-lg bg-primary-50 dark:bg-primary-900/20 border border-primary-200 dark:border-primary-800 text-sm text-primary-700 dark:text-primary-300 self-center">
            {scanFeedback}
          </div>
        )}
      </div>

      {/* Search */}
      <div className="relative">
        <Search className="absolute left-3 top-1/2 -translate-y-1/2 h-4 w-4 text-gray-400" />
        <input
          type="text"
          placeholder="Search parts by name or code..."
          value={searchText}
          onChange={(e) => setSearchText(e.target.value)}
          className="w-full pl-10 pr-4 py-2.5 rounded-lg border border-gray-300 dark:border-gray-600 bg-white dark:bg-gray-800 text-gray-900 dark:text-gray-100 text-sm focus:ring-2 focus:ring-primary-300 focus:border-primary-300 outline-none"
          autoFocus
        />
      </div>

      <div className="grid grid-cols-1 lg:grid-cols-2 gap-4">
        {/* Search Results */}
        <div>
          <h4 className="text-sm font-medium text-gray-700 dark:text-gray-300 mb-2">
            Search Results
          </h4>
          <div className="border border-gray-200 dark:border-gray-700 rounded-lg max-h-[300px] overflow-y-auto">
            {isLoading ? (
              <div className="flex justify-center py-8">
                <Spinner />
              </div>
            ) : searchResults.length === 0 ? (
              <div className="py-8 text-center text-sm text-gray-400">
                {searchText
                  ? 'No parts found'
                  : 'Type to search for parts'}
              </div>
            ) : (
              searchResults.map((part) => {
                const alreadyAdded = selectedIds.has(part.part_id);
                return (
                  <div
                    key={part.part_id}
                    className={cn(
                      'flex items-center gap-3 px-3 py-2.5 border-b border-gray-100 dark:border-gray-700 last:border-0',
                      alreadyAdded && 'opacity-50',
                    )}
                  >
                    {/* Part info */}
                    <div className="flex-1 min-w-0">
                      <div className="flex items-center gap-2">
                        <span className="text-sm font-medium text-gray-900 dark:text-gray-100 truncate">
                          {part.part_name}
                        </span>
                        {part.part_code && (
                          <Badge variant="secondary" className="text-xs flex-shrink-0">
                            {part.part_code}
                          </Badge>
                        )}
                      </div>
                      <div className="flex items-center gap-2 mt-0.5">
                        {part.category_name && (
                          <span className="text-xs text-gray-400">
                            {part.category_name}
                          </span>
                        )}
                        {part.shelf_location && (
                          <span className="text-xs text-gray-400">
                            Shelf: {part.shelf_location}
                          </span>
                        )}
                      </div>
                    </div>

                    {/* Available qty */}
                    <div className="text-right flex-shrink-0">
                      <span className="text-sm font-medium text-gray-700 dark:text-gray-300">
                        {part.available_qty}
                      </span>
                      <span className="text-xs text-gray-400 ml-1">avail</span>
                    </div>

                    {/* Add button */}
                    <button
                      onClick={() => addPart(part)}
                      disabled={alreadyAdded || selectedParts.length >= 20}
                      className={cn(
                        'p-1.5 rounded-lg transition-colors flex-shrink-0',
                        alreadyAdded
                          ? 'text-gray-300 cursor-not-allowed'
                          : 'text-primary-500 hover:bg-primary-50 dark:hover:bg-primary-900/30',
                      )}
                    >
                      <Plus className="h-4 w-4" />
                    </button>
                  </div>
                );
              })
            )}
          </div>
        </div>

        {/* Selected Parts Batch List */}
        <div>
          <h4 className="text-sm font-medium text-gray-700 dark:text-gray-300 mb-2">
            Selected Parts ({selectedParts.length}/20)
          </h4>
          <div className="border border-gray-200 dark:border-gray-700 rounded-lg max-h-[300px] overflow-y-auto">
            {selectedParts.length === 0 ? (
              <div className="flex flex-col items-center justify-center py-8 text-gray-400">
                <Package className="h-8 w-8 mb-2" />
                <span className="text-sm">No parts selected</span>
              </div>
            ) : (
              selectedParts.map((part) => (
                <div
                  key={part.part_id}
                  className="flex items-center gap-3 px-3 py-2.5 border-b border-gray-100 dark:border-gray-700 last:border-0"
                >
                  <div className="flex-1 min-w-0">
                    <span className="text-sm font-medium text-gray-900 dark:text-gray-100 truncate block">
                      {part.part_name}
                    </span>
                    {part.part_code && (
                      <span className="text-xs text-gray-400">
                        {part.part_code}
                      </span>
                    )}
                  </div>
                  <span className="text-xs text-gray-400 flex-shrink-0">
                    {part.available_qty} avail
                  </span>
                  <button
                    onClick={() => removePart(part.part_id)}
                    className="p-1 rounded-lg text-gray-400 hover:text-red-500 hover:bg-red-50 dark:hover:bg-red-900/30 transition-colors flex-shrink-0"
                  >
                    <X className="h-4 w-4" />
                  </button>
                </div>
              ))
            )}
          </div>
        </div>
      </div>
    </div>
  );
}
