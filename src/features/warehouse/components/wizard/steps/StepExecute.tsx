/**
 * Step 7: Execute — fires the movement and shows success or error.
 *
 * Auto-fires on mount (user already confirmed at Step 6).
 * On success: shows a summary with check animation.
 * On failure: shows error with retry button.
 */

import { useEffect, useRef } from 'react';
import { useMutation } from '@tanstack/react-query';
import { CheckCircle, XCircle, RotateCcw } from 'lucide-react';
import { Button } from '../../../../../components/ui/Button';
import { Spinner } from '../../../../../components/ui/Spinner';
import { executeMovement } from '../../../../../api/warehouse';
import { useMovementWizardStore } from '../../../stores/movement-wizard-store';
import type { MovementRequest } from '../../../../../lib/types';

export function StepExecute() {
  const {
    fromLocationType,
    fromLocationId,
    toLocationType,
    toLocationId,
    reason,
    reasonDetail,
    notes,
    referenceNumber,
    photoPath,
    scanConfirmed,
    gpsLat,
    gpsLng,
    destinationType,
    destinationId,
    destinationLabel,
    buildMovementRequest,
    setExecuting,
    setExecuteResult,
    setExecuteError,
    executeResult,
    executeError,
    isExecuting,
  } = useMovementWizardStore();

  // Guard against double-fire with a ref
  const hasFired = useRef(false);

  const mutation = useMutation({
    mutationFn: (req: MovementRequest) => executeMovement(req),
    onMutate: () => {
      setExecuting(true);
      setExecuteError(null);
    },
    onSuccess: (data) => {
      setExecuting(false);
      setExecuteResult(data);
    },
    onError: (err: Error) => {
      setExecuting(false);
      setExecuteError(err.message || 'An unexpected error occurred.');
    },
  });

  // Auto-fire once on mount
  useEffect(() => {
    if (hasFired.current || executeResult) return;
    hasFired.current = true;

    const request: MovementRequest = {
      from_location_type: fromLocationType!,
      from_location_id: fromLocationId,
      to_location_type: toLocationType!,
      to_location_id: toLocationId,
      items: buildMovementRequest(),
      reason,
      reason_detail: reasonDetail,
      notes,
      reference_number: referenceNumber,
      photo_path: photoPath,
      scan_confirmed: scanConfirmed,
      gps_lat: gpsLat,
      gps_lng: gpsLng,
      destination_type: destinationType,
      destination_id: destinationId,
      destination_label: destinationLabel,
    };

    mutation.mutate(request);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  const handleRetry = () => {
    hasFired.current = false;
    setExecuteError(null);
    setExecuteResult(null);

    const request: MovementRequest = {
      from_location_type: fromLocationType!,
      from_location_id: fromLocationId,
      to_location_type: toLocationType!,
      to_location_id: toLocationId,
      items: buildMovementRequest(),
      reason,
      reason_detail: reasonDetail,
      notes,
      reference_number: referenceNumber,
      photo_path: photoPath,
      scan_confirmed: scanConfirmed,
      gps_lat: gpsLat,
      gps_lng: gpsLng,
      destination_type: destinationType,
      destination_id: destinationId,
      destination_label: destinationLabel,
    };

    mutation.mutate(request);
  };

  // ── Loading state ──────────────────────────────────────────
  if (isExecuting || mutation.isPending) {
    return (
      <div className="flex flex-col items-center justify-center py-16 gap-4">
        <Spinner />
        <span className="text-sm text-gray-500 dark:text-gray-400">
          Executing stock movement...
        </span>
        <p className="text-xs text-gray-500 dark:text-gray-400 max-w-xs text-center">
          Updating stock levels, logging movement, and recalculating forecasts.
        </p>
      </div>
    );
  }

  // ── Error state ────────────────────────────────────────────
  if (executeError) {
    return (
      <div className="flex flex-col items-center justify-center py-12 gap-6">
        <div className="p-4 rounded-full bg-red-50 dark:bg-red-900/30">
          <XCircle className="h-12 w-12 text-red-500" />
        </div>
        <div className="text-center">
          <h3 className="text-lg font-semibold text-gray-900 dark:text-gray-100 mb-2">
            Movement Failed
          </h3>
          <p className="text-sm text-red-600 dark:text-red-400 max-w-md">
            {executeError}
          </p>
        </div>
        <Button
          icon={<RotateCcw className="h-4 w-4" />}
          onClick={handleRetry}
        >
          Retry
        </Button>
      </div>
    );
  }

  // ── Success state ──────────────────────────────────────────
  if (executeResult) {
    return (
      <div className="flex flex-col items-center justify-center py-12 gap-6">
        <div className="p-4 rounded-full bg-green-50 dark:bg-green-900/30">
          <CheckCircle className="h-12 w-12 text-green-500" />
        </div>
        <div className="text-center">
          <h3 className="text-lg font-semibold text-gray-900 dark:text-gray-100 mb-2">
            Movement Complete
          </h3>
          <p className="text-sm text-gray-500 dark:text-gray-400">
            {executeResult.total_qty} unit{executeResult.total_qty !== 1 ? 's' : ''}{' '}
            across {executeResult.total_items} part
            {executeResult.total_items !== 1 ? 's' : ''} moved successfully.
          </p>
        </div>

        {/* Summary list */}
        <div className="w-full max-w-sm space-y-2">
          {executeResult.movements.map((m) => (
            <div
              key={m.movement_id}
              className="flex items-center justify-between px-4 py-2 rounded-lg bg-gray-50 dark:bg-gray-900/50 border border-gray-200 dark:border-gray-700"
            >
              <span className="text-sm text-gray-700 dark:text-gray-300 truncate mr-2">
                {m.part_name}
              </span>
              <span className="text-sm font-medium text-gray-900 dark:text-gray-100 whitespace-nowrap">
                x{m.qty}
              </span>
            </div>
          ))}
        </div>
      </div>
    );
  }

  // Fallback (shouldn't reach here)
  return null;
}
