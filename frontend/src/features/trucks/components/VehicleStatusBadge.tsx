/**
 * VehicleStatusBadge — color-coded pill showing vehicle status.
 *
 * Maps vehicle status + type to the appropriate Badge variant.
 */

import { Badge } from '../../../components/ui/Badge';
import type { VehicleStatus, VehicleType } from '../../../lib/types';

const STATUS_VARIANT: Record<VehicleStatus, 'success' | 'warning' | 'default' | 'danger'> = {
  active: 'success',
  inactive: 'default',
  maintenance: 'warning',
  retired: 'danger',
};

const STATUS_LABELS: Record<VehicleStatus, string> = {
  active: 'Active',
  inactive: 'Inactive',
  maintenance: 'In Maintenance',
  retired: 'Retired',
};

const TYPE_LABELS: Record<VehicleType, string> = {
  company_truck: 'Company Truck',
  company_van: 'Company Van',
  company_car: 'Company Car',
  private_vehicle: 'Private Vehicle',
};

interface VehicleStatusBadgeProps {
  status: VehicleStatus;
}

interface VehicleTypeBadgeProps {
  vehicleType: VehicleType;
}

export function VehicleStatusBadge({ status }: VehicleStatusBadgeProps) {
  return (
    <Badge variant={STATUS_VARIANT[status]}>
      {STATUS_LABELS[status]}
    </Badge>
  );
}

export function VehicleTypeBadge({ vehicleType }: VehicleTypeBadgeProps) {
  const isPrivate = vehicleType === 'private_vehicle';
  return (
    <Badge variant={isPrivate ? 'warning' : 'default'}>
      {TYPE_LABELS[vehicleType]}
    </Badge>
  );
}

export { STATUS_LABELS, TYPE_LABELS };
