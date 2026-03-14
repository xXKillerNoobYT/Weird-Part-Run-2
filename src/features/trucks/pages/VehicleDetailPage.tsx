/**
 * VehicleDetailPage — full vehicle detail with internal sub-tabs.
 *
 * Sub-tabs: Overview (default), Assignments, Inventory, Deliveries, Maintenance, Mileage.
 * Accessible via /trucks/:id. Follows the JobDetailPage tabbed-detail pattern.
 */

import { useState } from 'react';
import { useParams, useNavigate } from 'react-router-dom';
import { useQuery } from '@tanstack/react-query';
import {
  ArrowLeft,
  Truck,
  Users,
  Package,
  Wrench,
  Gauge,
  MapPin,
} from 'lucide-react';
import { PageSpinner } from '../../../components/ui/Spinner';
import { Button } from '../../../components/ui/Button';
import { getVehicle } from '../../../api/vehicles';
import { VehicleStatusBadge, VehicleTypeBadge } from '../components/VehicleStatusBadge';
import {
  VehicleIcon,
  OverviewTab,
  AssignmentsTab,
  InventoryTab,
  DeliveriesTab,
  MaintenanceTab,
  MileageTab,
} from '../components/vehicle-detail';
import type { SubTab } from '../components/vehicle-detail';


// ── Sub-tab Definitions ──────────────────────────────────────────

const TABS: { id: SubTab; label: string; mobileLabel: string; icon: React.ReactNode }[] = [
  { id: 'overview', label: 'Overview', mobileLabel: 'Info', icon: <Truck className="h-4 w-4" /> },
  { id: 'assignments', label: 'Assignments', mobileLabel: 'Drivers', icon: <Users className="h-4 w-4" /> },
  { id: 'inventory', label: 'Inventory', mobileLabel: 'Parts', icon: <Package className="h-4 w-4" /> },
  { id: 'deliveries', label: 'Deliveries', mobileLabel: 'Deliver', icon: <MapPin className="h-4 w-4" /> },
  { id: 'maintenance', label: 'Maintenance', mobileLabel: 'Maint.', icon: <Wrench className="h-4 w-4" /> },
  { id: 'mileage', label: 'Mileage', mobileLabel: 'Miles', icon: <Gauge className="h-4 w-4" /> },
];


// ── Main Page Component ──────────────────────────────────────────

export function VehicleDetailPage() {
  const { id } = useParams<{ id: string }>();
  const vehicleId = Number(id);
  const navigate = useNavigate();

  const [activeTab, setActiveTab] = useState<SubTab>('overview');

  const { data: vehicle, isLoading, error } = useQuery({
    queryKey: ['vehicle', vehicleId],
    queryFn: () => getVehicle(vehicleId),
    staleTime: 15_000,
  });

  if (isLoading) return <PageSpinner label="Loading vehicle..." />;

  if (error || !vehicle) {
    return (
      <div className="text-center py-16">
        <p className="text-red-500">Vehicle not found or failed to load.</p>
        <Button variant="secondary" className="mt-4" onClick={() => navigate('/trucks/fleet')}>
          Back to Fleet
        </Button>
      </div>
    );
  }

  const vehicleName =
    vehicle.vehicle_name ||
    `${vehicle.make || ''} ${vehicle.model || ''}`.trim() ||
    vehicle.vehicle_number;

  return (
    <div className="space-y-4">
      {/* Back + Header */}
      <div className="flex items-start gap-3">
        <button
          onClick={() => navigate('/trucks/fleet')}
          className="mt-1 p-2 rounded-md hover:bg-gray-100 dark:hover:bg-gray-800 transition-colors"
        >
          <ArrowLeft className="h-5 w-5 text-gray-500" />
        </button>

        <div className="flex-1 min-w-0">
          <div className="flex items-center gap-2 mb-1 flex-wrap">
            <VehicleIcon type={vehicle.vehicle_type} className="h-4 w-4 text-gray-400 dark:text-gray-500" />
            <span className="text-xs font-mono text-gray-500 dark:text-gray-400">
              {vehicle.vehicle_number}
            </span>
            <VehicleStatusBadge status={vehicle.status} />
            {vehicle.vehicle_type === 'private_vehicle' && (
              <VehicleTypeBadge vehicleType={vehicle.vehicle_type} />
            )}
          </div>
          <h1 className="text-xl font-bold text-gray-900 dark:text-gray-100 truncate">
            {vehicleName}
          </h1>
          {vehicle.year && (
            <p className="text-sm text-gray-500 dark:text-gray-400">
              {vehicle.year} {vehicle.make} {vehicle.model}
              {vehicle.color ? ` · ${vehicle.color}` : ''}
            </p>
          )}
        </div>
      </div>

      {/* Quick Stats */}
      <div className="flex items-center gap-4 text-sm text-gray-500 dark:text-gray-400 flex-wrap">
        {vehicle.current_odometer > 0 && (
          <div className="flex items-center gap-1.5">
            <Gauge className="h-4 w-4 shrink-0" />
            <span>{vehicle.current_odometer.toLocaleString()} mi</span>
          </div>
        )}
        {vehicle.license_plate && (
          <span className="text-xs font-mono bg-gray-100 dark:bg-gray-800 px-2 py-0.5 rounded">
            {vehicle.license_plate}
          </span>
        )}
        {vehicle.primary_driver_name && (
          <div className="flex items-center gap-1.5">
            <Users className="h-4 w-4 shrink-0" />
            <span>{vehicle.primary_driver_name}</span>
          </div>
        )}
        {vehicle.assignment_count > 0 && (
          <span className="text-xs">{vehicle.assignment_count} driver{vehicle.assignment_count !== 1 ? 's' : ''}</span>
        )}
      </div>

      {/* Internal tab bar */}
      <div className="flex gap-1 border-b border-border overflow-x-auto">
        {TABS.map((tab) => (
          <button
            key={tab.id}
            onClick={() => setActiveTab(tab.id)}
            className={`flex items-center gap-1.5 px-3 py-2 text-sm font-medium whitespace-nowrap border-b-2 transition-colors ${activeTab === tab.id
              ? 'border-blue-500 text-blue-600 dark:text-blue-400'
              : 'border-transparent text-gray-500 dark:text-gray-400 hover:text-gray-700 dark:hover:text-gray-300'
              }`}
          >
            {tab.icon}
            <span className="hidden sm:inline">{tab.label}</span>
            <span className="sm:hidden">{tab.mobileLabel}</span>
          </button>
        ))}
      </div>

      {/* Tab content */}
      {activeTab === 'overview' && <OverviewTab vehicle={vehicle} />}
      {activeTab === 'assignments' && <AssignmentsTab vehicleId={vehicleId} vehicleName={vehicleName} />}
      {activeTab === 'inventory' && <InventoryTab vehicleId={vehicleId} />}
      {activeTab === 'deliveries' && <DeliveriesTab vehicleId={vehicleId} />}
      {activeTab === 'maintenance' && <MaintenanceTab vehicleId={vehicleId} />}
      {activeTab === 'mileage' && <MileageTab vehicleId={vehicleId} />}
    </div>
  );
}
