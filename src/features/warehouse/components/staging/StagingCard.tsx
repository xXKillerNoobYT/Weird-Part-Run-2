/**
 * StagingCard — a card per destination group showing pulled items
 * with color aging (normal < 24h, warning 24-48h, critical > 48h).
 *
 * Quick action buttons open the wizard pre-filled to load the
 * staged items onto a truck or return them to the shelf.
 */

import { Clock, Truck, RotateCcw } from 'lucide-react';
import { Card } from '../../../../components/ui/Card';
import { Badge } from '../../../../components/ui/Badge';
import { Button } from '../../../../components/ui/Button';
import { cn, formatDateTime } from '../../../../lib/utils';
import { useMovementWizardStore } from '../../stores/movement-wizard-store';
import type { StagingGroup, AgingStatus } from '../../../../lib/types';

const agingBg: Record<AgingStatus, string> = {
  normal: '',
  warning: 'ring-2 ring-amber-300 dark:ring-amber-700',
  critical: 'ring-2 ring-red-400 dark:ring-red-700',
};

const agingBadge: Record<AgingStatus, { variant: 'default' | 'warning' | 'danger'; label: string }> = {
  normal: { variant: 'default', label: 'Fresh' },
  warning: { variant: 'warning', label: '> 24h' },
  critical: { variant: 'danger', label: '> 48h' },
};

interface StagingCardProps {
  group: StagingGroup;
}

export function StagingCard({ group }: StagingCardProps) {
  const { open } = useMovementWizardStore();

  const wizardParts = group.items.map((item) => ({
    part_id: item.part_id,
    part_name: item.part_name,
    part_code: item.part_code,
    available_qty: item.qty,
    supplier_name: item.supplier_name,
    qty: item.qty,
  }));

  const handleLoadTruck = () => {
    open({
      fromLocationType: 'pulled',
      toLocationType: 'truck',
      toLocationId: group.destination_id ?? 1,
      selectedParts: wizardParts,
      destinationType: group.destination_type ?? undefined,
      destinationId: group.destination_id ?? undefined,
      destinationLabel: group.destination_label,
    });
  };

  const handleReturnToShelf = () => {
    open({
      fromLocationType: 'pulled',
      toLocationType: 'warehouse',
      selectedParts: wizardParts,
    });
  };

  return (
    <Card className={cn('transition-shadow', agingBg[group.aging_status])}>
      {/* Header */}
      <div className="flex items-center justify-between mb-4">
        <div>
          <h3 className="font-semibold text-gray-900 dark:text-gray-100">
            {group.destination_label}
          </h3>
          <p className="text-xs text-gray-500 dark:text-gray-400">
            {group.total_qty} unit{group.total_qty !== 1 ? 's' : ''} staged
          </p>
        </div>
        <Badge variant={agingBadge[group.aging_status].variant}>
          <Clock className="h-3 w-3 mr-1" />
          {agingBadge[group.aging_status].label}
        </Badge>
      </div>

      {/* Items list */}
      <div className="space-y-2 mb-4">
        {group.items.map((item) => (
          <div
            key={item.stock_id}
            className={cn(
              'flex items-center justify-between px-3 py-2 rounded-lg text-sm',
              item.aging_status === 'critical'
                ? 'bg-red-50 dark:bg-red-900/20'
                : item.aging_status === 'warning'
                  ? 'bg-amber-50 dark:bg-amber-900/20'
                  : 'bg-gray-50 dark:bg-gray-900/50',
            )}
          >
            <div className="min-w-0 flex-1 mr-2">
              <span className="text-gray-900 dark:text-gray-100 font-medium truncate block">
                {item.part_name}
              </span>
              <span className="text-xs text-gray-500 dark:text-gray-400">
                {item.tagged_by_name && `Pulled by ${item.tagged_by_name}`}
                {item.staged_at && ` \u00B7 ${formatDateTime(item.staged_at)}`}
              </span>
            </div>
            <span className="font-medium text-gray-900 dark:text-gray-100 whitespace-nowrap">
              x{item.qty}
            </span>
          </div>
        ))}
      </div>

      {/* Actions */}
      <div className="flex gap-2">
        <Button
          variant="primary"
          size="sm"
          icon={<Truck className="h-4 w-4" />}
          onClick={handleLoadTruck}
          className="flex-1"
        >
          Load Truck
        </Button>
        <Button
          variant="secondary"
          size="sm"
          icon={<RotateCcw className="h-4 w-4" />}
          onClick={handleReturnToShelf}
          className="flex-1"
        >
          Return
        </Button>
      </div>
    </Card>
  );
}
