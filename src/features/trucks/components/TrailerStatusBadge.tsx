/**
 * TrailerStatusBadge — color-coded pill showing trailer status.
 */

import { Badge } from '../../../components/ui/Badge';
import type { TrailerStatus } from '../../../lib/types';

const STATUS_VARIANT: Record<TrailerStatus, 'success' | 'warning' | 'default' | 'danger'> = {
  active: 'success',
  in_transit: 'warning',
  maintenance: 'danger',
  inactive: 'default',
};

export const TRAILER_STATUS_LABELS: Record<TrailerStatus, string> = {
  active: 'Active',
  in_transit: 'In Transit',
  maintenance: 'Maintenance',
  inactive: 'Inactive',
};

interface TrailerStatusBadgeProps {
  status: TrailerStatus;
}

export function TrailerStatusBadge({ status }: TrailerStatusBadgeProps) {
  return (
    <Badge variant={STATUS_VARIANT[status] ?? 'default'}>
      {TRAILER_STATUS_LABELS[status] ?? status}
    </Badge>
  );
}
