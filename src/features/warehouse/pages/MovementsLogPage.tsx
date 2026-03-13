/**
 * MovementsLogPage — paginated chronological log of all stock movements.
 *
 * Supports filtering by movement type, date range. Rows expand
 * to show full details (notes, reference #, costs, GPS).
 * Photo thumbnails expand to a lightbox on click.
 */

import { useState, useEffect } from 'react';
import { useQuery } from '@tanstack/react-query';
import { Card } from '../../../components/ui/Card';
import { Button } from '../../../components/ui/Button';
import { PageSpinner } from '../../../components/ui/Spinner';
import { getMovements } from '../../../api/warehouse';
import { MovementFilters } from '../components/movements/MovementFilters';
import { MovementsTable } from '../components/movements/MovementsTable';

export function MovementsLogPage() {
  const [movementType, setMovementType] = useState('');
  const [dateFrom, setDateFrom] = useState('');
  const [dateTo, setDateTo] = useState('');
  const [page, setPage] = useState(1);

  // Reset page when filters change
  useEffect(() => {
    setPage(1);
  }, [movementType, dateFrom, dateTo]);

  const { data, isLoading } = useQuery({
    queryKey: ['warehouse-movements', movementType, dateFrom, dateTo, page],
    queryFn: () => getMovements({
      movement_type: movementType || undefined,
      date_from: dateFrom || undefined,
      date_to: dateTo || undefined,
      page,
      page_size: 50,
    }),
    staleTime: 10_000,
  });

  if (isLoading && !data) {
    return <PageSpinner label="Loading movements..." />;
  }

  const items = data?.items ?? [];
  const totalPages = data?.total_pages ?? 1;

  return (
    <div className="space-y-4">
      <MovementFilters
        movementType={movementType}
        onMovementTypeChange={setMovementType}
        dateFrom={dateFrom}
        onDateFromChange={setDateFrom}
        dateTo={dateTo}
        onDateToChange={setDateTo}
      />

      <Card noPadding>
        <MovementsTable items={items} />

        {/* Pagination */}
        {totalPages > 1 && (
          <div className="flex items-center justify-between px-4 py-3 border-t border-gray-200 dark:border-gray-700">
            <span className="text-sm text-gray-500 dark:text-gray-400">
              Page {page} of {totalPages} ({data?.total ?? 0} movements)
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
  );
}
