/**
 * DeliveriesTab — delivery items grouped by job with deliver/return actions.
 */

import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import { MapPin, CheckCircle, RotateCcw } from 'lucide-react';
import { PageSpinner } from '../../../../components/ui/Spinner';
import { EmptyState } from '../../../../components/ui/EmptyState';
import { Badge } from '../../../../components/ui/Badge';
import { PartIdentity } from '../../../../components/ui/PartIdentity';
import { listDeliveries, markDelivered, returnDelivery } from '../../../../api/vehicles';
import type { VehicleDeliveryItem, DeliveryStatus } from '../../../../lib/types';


const DELIVERY_VARIANT: Record<DeliveryStatus, 'success' | 'warning' | 'default' | 'danger'> = {
  assigned: 'default',
  loaded: 'default',
  in_transit: 'warning',
  delivered: 'success',
  returned: 'danger',
};


export function DeliveriesTab({ vehicleId }: { vehicleId: number }) {
  const queryClient = useQueryClient();

  const { data: deliveries, isLoading } = useQuery({
    queryKey: ['vehicle-deliveries', vehicleId],
    queryFn: () => listDeliveries(vehicleId),
    staleTime: 15_000,
  });

  const deliverMut = useMutation({
    mutationFn: (itemId: number) => markDelivered(vehicleId, itemId),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['vehicle-deliveries', vehicleId] });
    },
  });

  const returnMut = useMutation({
    mutationFn: (itemId: number) => returnDelivery(vehicleId, itemId),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['vehicle-deliveries', vehicleId] });
    },
  });

  if (isLoading) return <PageSpinner label="Loading deliveries..." />;

  if (!deliveries || deliveries.length === 0) {
    return (
      <EmptyState
        icon={<MapPin className="h-12 w-12" />}
        title="No Deliveries"
        description="No delivery items assigned to this vehicle."
      />
    );
  }

  // Group by job
  const byJob = new Map<number, VehicleDeliveryItem[]>();
  for (const d of deliveries) {
    const items = byJob.get(d.job_id) ?? [];
    items.push(d);
    byJob.set(d.job_id, items);
  }

  return (
    <div className="space-y-4">
      {Array.from(byJob.entries()).map(([jobId, items]) => (
        <div key={jobId} className="bg-surface border border-border rounded-xl overflow-hidden">
          <div className="px-4 py-2 bg-surface-secondary border-b border-border">
            <span className="text-xs font-medium text-gray-500 dark:text-gray-400">
              Job #{jobId} — {items[0].job_name ?? 'Unknown'}
            </span>
          </div>
          <div className="divide-y divide-border">
            {items.map((item) => (
              <div key={item.id} className="flex items-center gap-3 px-4 py-2.5">
                <div className="flex-1 min-w-0">
                  <PartIdentity
                    compact
                    partName={item.part_description}
                    partNumber={item.part_number}
                    partId={item.part_id}
                  />
                  <p className="text-xs text-gray-500 dark:text-gray-400">
                    Qty: {item.qty_assigned}
                    {item.qty_delivered > 0 && ` · Delivered: ${item.qty_delivered}`}
                    {item.assigner_name && ` · By: ${item.assigner_name}`}
                  </p>
                </div>
                <Badge variant={DELIVERY_VARIANT[item.status]}>{item.status}</Badge>
                {/* Action buttons for pending items */}
                {(item.status === 'assigned' || item.status === 'loaded' || item.status === 'in_transit') && (
                  <div className="flex items-center gap-1 shrink-0">
                    <button
                      onClick={() => deliverMut.mutate(item.id)}
                      className="p-1.5 text-green-500 hover:bg-green-50 dark:hover:bg-green-900/20 rounded transition-colors"
                      title="Mark delivered"
                    >
                      <CheckCircle className="h-4 w-4" />
                    </button>
                    <button
                      onClick={() => returnMut.mutate(item.id)}
                      className="p-1.5 text-amber-500 hover:bg-amber-50 dark:hover:bg-amber-900/20 rounded transition-colors"
                      title="Return undelivered"
                    >
                      <RotateCcw className="h-4 w-4" />
                    </button>
                  </div>
                )}
              </div>
            ))}
          </div>
        </div>
      ))}
    </div>
  );
}
