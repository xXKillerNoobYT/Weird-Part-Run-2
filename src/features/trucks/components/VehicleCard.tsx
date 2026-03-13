/**
 * VehicleCard — card component for a vehicle in the fleet list.
 *
 * Shows vehicle number, name, type, status, primary driver, odometer,
 * and maintenance urgency indicator.
 */

import {
  Truck,
  Car,
  User,
  Gauge,
  AlertTriangle,
  ChevronRight,
  Wrench,
  Home,
} from 'lucide-react';
import { useNavigate } from 'react-router-dom';
import { VehicleStatusBadge, VehicleTypeBadge } from './VehicleStatusBadge';
import type { VehicleListItem, VehicleType } from '../../../lib/types';

interface VehicleCardProps {
  vehicle: VehicleListItem;
}

/** Pick icon based on vehicle type. */
function VehicleIcon({ type, className }: { type: VehicleType; className?: string }) {
  switch (type) {
    case 'company_van':
    case 'company_truck':
      return <Truck className={className} />;
    default:
      return <Car className={className} />;
  }
}

export function VehicleCard({ vehicle }: VehicleCardProps) {
  const navigate = useNavigate();

  return (
    <div
      className="group bg-surface border border-border rounded-xl p-4 hover:border-blue-300 dark:hover:border-blue-600 transition-colors cursor-pointer"
      onClick={() => navigate(`/trucks/${vehicle.id}`)}
    >
      {/* Header — vehicle number + status + type */}
      <div className="flex items-start justify-between mb-2">
        <div className="flex-1 min-w-0">
          <div className="flex items-center gap-2 mb-1 flex-wrap">
            <VehicleIcon
              type={vehicle.vehicle_type}
              className="h-4 w-4 text-gray-400 dark:text-gray-500 shrink-0"
            />
            <span className="text-xs font-mono text-gray-500 dark:text-gray-400">
              {vehicle.vehicle_number}
            </span>
            <VehicleStatusBadge status={vehicle.status} />
          </div>
          <h3 className="text-sm font-semibold text-gray-900 dark:text-gray-100 truncate">
            {vehicle.vehicle_name || `${vehicle.make || ''} ${vehicle.model || ''}`.trim() || vehicle.vehicle_number}
          </h3>
          {vehicle.year && (
            <p className="text-xs text-gray-500 dark:text-gray-400">
              {vehicle.year} {vehicle.make} {vehicle.model}
            </p>
          )}
        </div>
        <ChevronRight className="h-4 w-4 text-gray-300 dark:text-gray-600 mt-1 shrink-0" />
      </div>

      {/* Stats row */}
      <div className="flex items-center gap-4 text-xs text-gray-500 dark:text-gray-400 flex-wrap">
        {/* Primary driver */}
        {vehicle.primary_driver_name && (
          <div className="flex items-center gap-1">
            <User className="h-3.5 w-3.5 shrink-0" />
            <span className="truncate max-w-[120px]">{vehicle.primary_driver_name}</span>
          </div>
        )}

        {/* Odometer */}
        {vehicle.current_odometer != null && vehicle.current_odometer > 0 && (
          <div className="flex items-center gap-1">
            <Gauge className="h-3.5 w-3.5 shrink-0" />
            <span>{vehicle.current_odometer.toLocaleString()} mi</span>
          </div>
        )}

        {/* Take-home indicator */}
        {vehicle.is_take_home && (
          <div className="flex items-center gap-1 text-blue-500 dark:text-blue-400">
            <Home className="h-3.5 w-3.5 shrink-0" />
            <span>Take-Home</span>
          </div>
        )}
      </div>

      {/* Maintenance alert indicator */}
      {(vehicle.overdue_maintenance_count ?? 0) > 0 && (
        <div className="mt-2 pt-2 border-t border-border flex items-center gap-2">
          <span className="inline-flex items-center gap-1 px-2 py-0.5 text-[10px] font-medium bg-red-50 dark:bg-red-900/20 text-red-600 dark:text-red-400 border border-red-200 dark:border-red-800 rounded-full">
            <AlertTriangle className="h-3 w-3" />
            {vehicle.overdue_maintenance_count} overdue
          </span>
          {(vehicle.upcoming_maintenance_count ?? 0) > 0 && (
            <span className="inline-flex items-center gap-1 px-2 py-0.5 text-[10px] font-medium bg-amber-50 dark:bg-amber-900/20 text-amber-600 dark:text-amber-400 border border-amber-200 dark:border-amber-800 rounded-full">
              <Wrench className="h-3 w-3" />
              {vehicle.upcoming_maintenance_count} upcoming
            </span>
          )}
        </div>
      )}

      {/* Type badge for private vehicles */}
      {vehicle.vehicle_type === 'private_vehicle' && (
        <div className={`mt-2 pt-2 ${(vehicle.overdue_maintenance_count ?? 0) === 0 ? 'border-t border-border' : ''}`}>
          <VehicleTypeBadge vehicleType={vehicle.vehicle_type} />
        </div>
      )}
    </div>
  );
}
