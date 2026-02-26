/**
 * Step 6: Preview — shows before/after state and asks for confirmation.
 *
 * Calls the backend preview endpoint to get exact before/after stock levels,
 * supplier chain info, and any warnings.
 */

import { useEffect } from 'react';
import { useQuery } from '@tanstack/react-query';
import { AlertTriangle, ArrowRight, ShieldAlert } from 'lucide-react';
import { Badge } from '../../../../../components/ui/Badge';
import { Spinner } from '../../../../../components/ui/Spinner';
import { cn } from '../../../../../lib/utils';
import { previewMovement } from '../../../../../api/warehouse';
import { useMovementWizardStore } from '../../../stores/movement-wizard-store';
import { useAuthStore } from '../../../../../stores/auth-store';
import { PERMISSIONS } from '../../../../../lib/constants';
import type { MovementRequest } from '../../../../../lib/types';

export function StepPreview() {
  const {
    fromLocationType,
    fromLocationId,
    toLocationType,
    toLocationId,
    selectedParts,
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
    setPreview,
  } = useMovementWizardStore();

  const { hasPermission } = useAuthStore();
  const showDollars = hasPermission(PERMISSIONS.SHOW_DOLLAR_VALUES);

  // Build the request
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

  const {
    data: preview,
    isLoading,
    error,
  } = useQuery({
    queryKey: ['movement-preview', JSON.stringify(request)],
    queryFn: () => previewMovement(request),
    staleTime: 0,
  });

  // Store preview in wizard state so canAdvance can check it
  useEffect(() => {
    if (preview) {
      setPreview(preview);
    }
  }, [preview, setPreview]);

  if (isLoading) {
    return (
      <div className="flex flex-col items-center justify-center py-12 gap-4">
        <Spinner />
        <span className="text-sm text-gray-400">Calculating preview...</span>
      </div>
    );
  }

  if (error || !preview) {
    return (
      <div className="text-center py-12">
        <ShieldAlert className="h-10 w-10 text-red-400 mx-auto mb-3" />
        <p className="text-sm text-red-600 dark:text-red-400">
          Failed to generate preview. Please go back and check your selections.
        </p>
      </div>
    );
  }

  return (
    <div className="space-y-6">
      {/* Warnings */}
      {preview.warnings.length > 0 && (
        <div className="space-y-2">
          {preview.warnings.map((w, i) => (
            <div
              key={i}
              className="flex items-start gap-2 px-3 py-2 rounded-lg bg-amber-50 dark:bg-amber-900/20 border border-amber-200 dark:border-amber-800"
            >
              <AlertTriangle className="h-4 w-4 text-amber-500 mt-0.5 flex-shrink-0" />
              <span className="text-sm text-amber-700 dark:text-amber-400">
                {w}
              </span>
            </div>
          ))}
        </div>
      )}

      {/* Preview Table */}
      <div className="overflow-x-auto">
        <table className="w-full text-sm">
          <thead>
            <tr className="border-b border-gray-200 dark:border-gray-700">
              <th className="text-left py-2 px-3 text-gray-500 dark:text-gray-400 font-medium">
                Part
              </th>
              <th className="text-center py-2 px-3 text-gray-500 dark:text-gray-400 font-medium">
                Qty
              </th>
              <th className="text-center py-2 px-3 text-gray-500 dark:text-gray-400 font-medium">
                Source
              </th>
              <th className="text-center py-2 px-3 text-gray-500 dark:text-gray-400 font-medium">
                Dest
              </th>
              {showDollars && (
                <th className="text-right py-2 px-3 text-gray-500 dark:text-gray-400 font-medium">
                  Value
                </th>
              )}
              <th className="text-left py-2 px-3 text-gray-500 dark:text-gray-400 font-medium">
                Supplier
              </th>
            </tr>
          </thead>
          <tbody>
            {preview.lines.map((line) => (
              <tr
                key={line.part_id}
                className="border-b border-gray-100 dark:border-gray-800 last:border-0"
              >
                <td className="py-2.5 px-3">
                  <div className="font-medium text-gray-900 dark:text-gray-100">
                    {line.part_name}
                  </div>
                  {line.part_code && (
                    <span className="text-xs text-gray-400">
                      {line.part_code}
                    </span>
                  )}
                </td>
                <td className="text-center py-2.5 px-3 font-medium text-gray-900 dark:text-gray-100">
                  {line.qty}
                </td>
                <td className="text-center py-2.5 px-3">
                  <span className="text-gray-400">{line.source_before}</span>
                  <ArrowRight className="inline h-3 w-3 mx-1 text-gray-300" />
                  <span
                    className={cn(
                      'font-medium',
                      line.source_after === 0
                        ? 'text-red-500'
                        : 'text-gray-900 dark:text-gray-100',
                    )}
                  >
                    {line.source_after}
                  </span>
                </td>
                <td className="text-center py-2.5 px-3">
                  <span className="text-gray-400">{line.dest_before}</span>
                  <ArrowRight className="inline h-3 w-3 mx-1 text-gray-300" />
                  <span className="font-medium text-gray-900 dark:text-gray-100">
                    {line.dest_after}
                  </span>
                </td>
                {showDollars && (
                  <td className="text-right py-2.5 px-3 text-gray-700 dark:text-gray-300">
                    {line.line_value != null
                      ? `$${line.line_value.toFixed(2)}`
                      : '—'}
                  </td>
                )}
                <td className="py-2.5 px-3">
                  {line.supplier_name && (
                    <div className="flex items-center gap-1">
                      <span className="text-gray-700 dark:text-gray-300 text-xs">
                        {line.supplier_name}
                      </span>
                      {line.supplier_source && (
                        <Badge
                          variant={
                            line.supplier_source === 'preferred'
                              ? 'primary'
                              : 'secondary'
                          }
                          className="text-[10px]"
                        >
                          {line.supplier_source}
                        </Badge>
                      )}
                    </div>
                  )}
                </td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>

      {/* Totals */}
      <div className="flex items-center justify-between px-4 py-3 rounded-lg bg-gray-50 dark:bg-gray-900/50 border border-gray-200 dark:border-gray-700">
        <span className="text-sm font-medium text-gray-700 dark:text-gray-300">
          Total: {preview.total_qty} units
        </span>
        {showDollars && preview.total_value != null && (
          <span className="text-sm font-medium text-gray-700 dark:text-gray-300">
            ${preview.total_value.toFixed(2)}
          </span>
        )}
      </div>

      {/* Confirmation warning */}
      <div className="px-4 py-3 rounded-lg bg-amber-50 dark:bg-amber-900/20 border border-amber-200 dark:border-amber-800">
        <p className="text-sm text-amber-700 dark:text-amber-400 font-medium">
          This action cannot be undone. Stock levels will be updated immediately.
        </p>
      </div>
    </div>
  );
}
