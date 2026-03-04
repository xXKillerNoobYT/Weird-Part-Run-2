/**
 * MyTruckPage — current user's assigned vehicle dashboard.
 *
 * Shows the driver's assigned vehicle info, pending deliveries, maintenance
 * alerts, today's mileage, and recent mileage history. Uses the `/trucks/my-vehicle`
 * API endpoint which returns a MyVehicleDashboard composite payload.
 */

import { useQuery } from '@tanstack/react-query';
import { useNavigate } from 'react-router-dom';
import {
  Truck,
  Car,
  Gauge,
  Package,
  AlertTriangle,
  Wrench,
  Home,
  ChevronRight,
  MapPin,
  Calendar,
  Clock,
} from 'lucide-react';
import { PageSpinner } from '../../../components/ui/Spinner';
import { EmptyState } from '../../../components/ui/EmptyState';
import { Badge } from '../../../components/ui/Badge';
import { Button } from '../../../components/ui/Button';
import { getMyVehicle } from '../../../api/vehicles';
import { VehicleStatusBadge, VehicleTypeBadge } from '../components/VehicleStatusBadge';
import type { VehicleType, MaintenanceAlert, VehicleDeliveryItem, MileageLog } from '../../../lib/types';

export function MyTruckPage() {
  const navigate = useNavigate();

  const { data: dashboard, isLoading, error } = useQuery({
    queryKey: ['my-vehicle'],
    queryFn: getMyVehicle,
    staleTime: 30_000,
  });

  if (isLoading) return <PageSpinner label="Loading your vehicle..." />;

  if (error) {
    return (
      <div className="text-center py-16">
        <p className="text-red-500">Failed to load vehicle data.</p>
      </div>
    );
  }

  // No vehicle assigned to this user
  if (!dashboard?.vehicle) {
    return (
      <EmptyState
        icon={<Truck className="h-12 w-12" />}
        title="No Vehicle Assigned"
        description="You don't have a vehicle assigned to you yet. Contact your fleet manager to get assigned."
      />
    );
  }

  const { vehicle, assignment, pending_deliveries, maintenance_alerts, todays_mileage, recent_mileage } = dashboard;

  return (
    <div className="space-y-6">
      {/* ── Vehicle Header Card ── */}
      <div
        className="bg-surface border border-border rounded-xl p-5 cursor-pointer hover:border-blue-300 dark:hover:border-blue-600 transition-colors"
        onClick={() => navigate(`/trucks/${vehicle.id}`)}
      >
        <div className="flex items-start justify-between">
          <div className="flex items-start gap-4">
            <div className="flex items-center justify-center h-12 w-12 rounded-lg bg-blue-50 dark:bg-blue-900/20 text-blue-500 dark:text-blue-400 shrink-0">
              <VehicleIcon type={vehicle.vehicle_type} className="h-6 w-6" />
            </div>
            <div className="min-w-0">
              <div className="flex items-center gap-2 mb-1 flex-wrap">
                <span className="text-xs font-mono text-gray-500 dark:text-gray-400">
                  {vehicle.vehicle_number}
                </span>
                <VehicleStatusBadge status={vehicle.status} />
                {vehicle.vehicle_type === 'private_vehicle' && (
                  <VehicleTypeBadge vehicleType={vehicle.vehicle_type} />
                )}
              </div>
              <h2 className="text-lg font-semibold text-gray-900 dark:text-gray-100 truncate">
                {vehicle.vehicle_name || `${vehicle.make || ''} ${vehicle.model || ''}`.trim() || vehicle.vehicle_number}
              </h2>
              {vehicle.year && (
                <p className="text-sm text-gray-500 dark:text-gray-400">
                  {vehicle.year} {vehicle.make} {vehicle.model}
                  {vehicle.color ? ` · ${vehicle.color}` : ''}
                </p>
              )}
            </div>
          </div>
          <ChevronRight className="h-5 w-5 text-gray-300 dark:text-gray-600 mt-1 shrink-0" />
        </div>

        {/* Quick stats */}
        <div className="mt-4 flex items-center gap-6 text-sm text-gray-500 dark:text-gray-400 flex-wrap">
          {vehicle.current_odometer > 0 && (
            <div className="flex items-center gap-1.5">
              <Gauge className="h-4 w-4 shrink-0" />
              <span>{vehicle.current_odometer.toLocaleString()} mi</span>
            </div>
          )}
          {vehicle.license_plate && (
            <div className="flex items-center gap-1.5">
              <span className="text-xs font-mono bg-gray-100 dark:bg-gray-800 px-2 py-0.5 rounded">
                {vehicle.license_plate}
              </span>
            </div>
          )}
          {assignment?.is_take_home && (
            <div className="flex items-center gap-1.5 text-blue-500 dark:text-blue-400">
              <Home className="h-4 w-4 shrink-0" />
              <span>Take-Home</span>
            </div>
          )}
          {assignment?.home_to_shop_miles != null && (
            <div className="flex items-center gap-1.5">
              <MapPin className="h-4 w-4 shrink-0" />
              <span>{assignment.home_to_shop_miles} mi commute</span>
            </div>
          )}
        </div>
      </div>

      {/* ── Dashboard Grid ── */}
      <div className="grid grid-cols-1 lg:grid-cols-2 gap-4">
        {/* Maintenance Alerts */}
        <DashboardSection
          title="Maintenance Alerts"
          icon={<Wrench className="h-4 w-4" />}
          count={maintenance_alerts.length}
          emptyMessage="No upcoming maintenance"
        >
          {maintenance_alerts.map((alert) => (
            <MaintenanceAlertRow key={alert.maintenance_type_id} alert={alert} />
          ))}
        </DashboardSection>

        {/* Pending Deliveries */}
        <DashboardSection
          title="Pending Deliveries"
          icon={<Package className="h-4 w-4" />}
          count={pending_deliveries.length}
          emptyMessage="No pending deliveries"
        >
          {pending_deliveries.map((item) => (
            <DeliveryItemRow key={item.id} item={item} />
          ))}
        </DashboardSection>

        {/* Today's Mileage */}
        <DashboardSection
          title="Today's Mileage"
          icon={<Gauge className="h-4 w-4" />}
          emptyMessage={todays_mileage ? undefined : 'No mileage logged today'}
          action={
            !todays_mileage ? (
              <Button
                size="sm"
                variant="secondary"
                onClick={() => navigate('/trucks/mileage')}
              >
                Log Mileage
              </Button>
            ) : undefined
          }
        >
          {todays_mileage && (
            <div className="space-y-2">
              <div className="flex items-center justify-between text-sm">
                <span className="text-gray-500 dark:text-gray-400">Start</span>
                <span className="font-mono text-gray-900 dark:text-gray-100">
                  {todays_mileage.odometer_start?.toLocaleString() ?? '—'}
                </span>
              </div>
              <div className="flex items-center justify-between text-sm">
                <span className="text-gray-500 dark:text-gray-400">End</span>
                <span className="font-mono text-gray-900 dark:text-gray-100">
                  {todays_mileage.odometer_end?.toLocaleString() ?? '—'}
                </span>
              </div>
              <div className="flex items-center justify-between text-sm font-medium pt-1 border-t border-border">
                <span className="text-gray-700 dark:text-gray-300">Total</span>
                <span className="font-mono text-gray-900 dark:text-gray-100">
                  {todays_mileage.total_miles?.toLocaleString() ?? '—'} mi
                </span>
              </div>
            </div>
          )}
        </DashboardSection>

        {/* Recent Mileage History */}
        <DashboardSection
          title="Recent Mileage"
          icon={<Calendar className="h-4 w-4" />}
          count={recent_mileage.length}
          emptyMessage="No mileage history"
          action={
            recent_mileage.length > 0 ? (
              <Button
                size="sm"
                variant="ghost"
                onClick={() => navigate('/trucks/mileage')}
              >
                View All
              </Button>
            ) : undefined
          }
        >
          {recent_mileage.slice(0, 5).map((log) => (
            <MileageRow key={log.id} log={log} />
          ))}
        </DashboardSection>
      </div>
    </div>
  );
}


// ── Subcomponents ─────────────────────────────────────────────────

function VehicleIcon({ type, className }: { type: VehicleType; className?: string }) {
  switch (type) {
    case 'company_van':
    case 'company_truck':
      return <Truck className={className} />;
    default:
      return <Car className={className} />;
  }
}

interface DashboardSectionProps {
  title: string;
  icon: React.ReactNode;
  count?: number;
  emptyMessage?: string;
  action?: React.ReactNode;
  children: React.ReactNode;
}

function DashboardSection({ title, icon, count, emptyMessage, action, children }: DashboardSectionProps) {
  const hasContent = Array.isArray(children)
    ? children.length > 0
    : children != null;

  return (
    <div className="bg-surface border border-border rounded-xl p-4">
      <div className="flex items-center justify-between mb-3">
        <div className="flex items-center gap-2">
          <span className="text-gray-400 dark:text-gray-500">{icon}</span>
          <h3 className="text-sm font-medium text-gray-900 dark:text-gray-100">{title}</h3>
          {count != null && count > 0 && (
            <Badge variant="default">{count}</Badge>
          )}
        </div>
        {action}
      </div>
      {hasContent ? (
        <div className="space-y-2">{children}</div>
      ) : emptyMessage ? (
        <p className="text-sm text-gray-400 dark:text-gray-500 text-center py-4">
          {emptyMessage}
        </p>
      ) : null}
    </div>
  );
}

function MaintenanceAlertRow({ alert }: { alert: MaintenanceAlert }) {
  return (
    <div className="flex items-center justify-between py-1.5">
      <div className="flex items-center gap-2 min-w-0">
        {alert.is_overdue ? (
          <AlertTriangle className="h-4 w-4 text-red-500 shrink-0" />
        ) : (
          <Clock className="h-4 w-4 text-amber-500 shrink-0" />
        )}
        <span className="text-sm text-gray-900 dark:text-gray-100 truncate">
          {alert.maintenance_type_name}
        </span>
      </div>
      <div className="text-xs text-right shrink-0 ml-2">
        {alert.is_overdue ? (
          <span className="text-red-600 dark:text-red-400 font-medium">Overdue</span>
        ) : alert.days_until_due != null ? (
          <span className="text-amber-600 dark:text-amber-400">
            {alert.days_until_due}d
          </span>
        ) : alert.miles_until_due != null ? (
          <span className="text-amber-600 dark:text-amber-400">
            {alert.miles_until_due.toLocaleString()} mi
          </span>
        ) : null}
      </div>
    </div>
  );
}

function DeliveryItemRow({ item }: { item: VehicleDeliveryItem }) {
  return (
    <div className="flex items-center justify-between py-1.5">
      <div className="min-w-0">
        <p className="text-sm text-gray-900 dark:text-gray-100 truncate">
          {item.part_description ?? item.part_number ?? `Part #${item.part_id}`}
        </p>
        <p className="text-xs text-gray-500 dark:text-gray-400">
          Job #{item.job_id} · Qty: {item.qty_assigned}
        </p>
      </div>
      <Badge
        variant={
          item.status === 'delivered' ? 'success'
          : item.status === 'in_transit' ? 'warning'
          : 'default'
        }
      >
        {item.status}
      </Badge>
    </div>
  );
}

function MileageRow({ log }: { log: MileageLog }) {
  return (
    <div className="flex items-center justify-between py-1.5">
      <span className="text-sm text-gray-500 dark:text-gray-400">
        {log.log_date}
      </span>
      <span className="text-sm font-mono text-gray-900 dark:text-gray-100">
        {log.total_miles?.toLocaleString() ?? '—'} mi
      </span>
    </div>
  );
}
