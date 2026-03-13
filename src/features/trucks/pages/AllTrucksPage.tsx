/**
 * AllTrucksPage — fleet list with search, type/status filters, and create action.
 *
 * Shows VehicleCards in a responsive grid. Managers can create new vehicles
 * and access fleet-wide management. Follows the ActiveJobsPage pattern.
 */

import { useState, useEffect, useCallback } from 'react';
import { useQuery } from '@tanstack/react-query';
import { Plus, Search, Filter, Truck, X } from 'lucide-react';
import { PageSpinner } from '../../../components/ui/Spinner';
import { EmptyState } from '../../../components/ui/EmptyState';
import { Button } from '../../../components/ui/Button';
import { Input } from '../../../components/ui/Input';
import { useAuthStore } from '../../../stores/auth-store';
import { PERMISSIONS } from '../../../lib/constants';
import { listVehicles } from '../../../api/vehicles';
import { VehicleCard } from '../components/VehicleCard';
import { CreateVehicleModal } from '../components/CreateVehicleModal';
import type { VehicleType, VehicleStatus } from '../../../lib/types';

const TYPE_OPTIONS: { label: string; value: VehicleType | 'all' }[] = [
  { label: 'All Types', value: 'all' },
  { label: 'Company Truck', value: 'company_truck' },
  { label: 'Company Van', value: 'company_van' },
  { label: 'Company Car', value: 'company_car' },
  { label: 'Private Vehicle', value: 'private_vehicle' },
];

const STATUS_OPTIONS: { label: string; value: VehicleStatus | 'all' }[] = [
  { label: 'All', value: 'all' },
  { label: 'Active', value: 'active' },
  { label: 'Inactive', value: 'inactive' },
  { label: 'In Maintenance', value: 'maintenance' },
  { label: 'Retired', value: 'retired' },
];

export function AllTrucksPage() {
  const { hasPermission } = useAuthStore();
  const canManageFleet = hasPermission(PERMISSIONS.MANAGE_FLEET);

  // ── Filters ──
  const [search, setSearch] = useState('');
  const [debouncedSearch, setDebouncedSearch] = useState('');
  const [typeFilter, setTypeFilter] = useState<string>('all');
  const [statusFilter, setStatusFilter] = useState<string>('all');
  const [showFilters, setShowFilters] = useState(false);
  const [showCreate, setShowCreate] = useState(false);

  // Debounce search
  useEffect(() => {
    const timer = setTimeout(() => setDebouncedSearch(search), 300);
    return () => clearTimeout(timer);
  }, [search]);

  const { data: vehicles, isLoading, error } = useQuery({
    queryKey: ['vehicles', debouncedSearch, typeFilter, statusFilter],
    queryFn: () =>
      listVehicles({
        search: debouncedSearch || undefined,
        vehicle_type: typeFilter === 'all' ? undefined : typeFilter,
        status: statusFilter === 'all' ? undefined : statusFilter,
      }),
    staleTime: 15_000,
  });

  const hasActiveFilters = typeFilter !== 'all' || statusFilter !== 'all';

  const clearFilters = useCallback(() => {
    setTypeFilter('all');
    setStatusFilter('all');
  }, []);

  if (isLoading) return <PageSpinner label="Loading vehicles..." />;

  if (error) {
    return (
      <div className="text-center py-16">
        <p className="text-red-500">Failed to load vehicles. Please try again.</p>
      </div>
    );
  }

  return (
    <div className="space-y-4">
      {/* Header — search + filter + create */}
      <div className="flex items-center gap-3 flex-wrap">
        <div className="flex-1 min-w-[200px]">
          <Input
            placeholder="Search vehicles..."
            value={search}
            onChange={(e) => setSearch(e.target.value)}
            icon={<Search className="h-4 w-4" />}
            iconRight={
              search ? (
                <button onClick={() => setSearch('')} className="text-gray-400 hover:text-gray-600">
                  <X className="h-4 w-4" />
                </button>
              ) : undefined
            }
          />
        </div>

        <Button
          variant={hasActiveFilters ? 'primary' : 'secondary'}
          size="sm"
          icon={<Filter className="h-4 w-4" />}
          onClick={() => setShowFilters(!showFilters)}
        >
          <span className="hidden sm:inline">Filter</span>
        </Button>

        {canManageFleet && (
          <Button
            size="sm"
            icon={<Plus className="h-4 w-4" />}
            onClick={() => setShowCreate(true)}
          >
            <span className="hidden sm:inline">New Vehicle</span>
          </Button>
        )}
      </div>

      {/* Filter panel */}
      {showFilters && (
        <div className="flex flex-wrap gap-4 p-3 bg-surface-secondary rounded-lg border border-border">
          {/* Status chips */}
          <div className="flex items-center gap-2 flex-wrap">
            <span className="text-xs font-medium text-gray-500 dark:text-gray-400">Status:</span>
            <div className="flex gap-1 flex-wrap">
              {STATUS_OPTIONS.map((opt) => (
                <button
                  key={opt.value}
                  onClick={() => setStatusFilter(opt.value)}
                  className={`px-3 py-1.5 text-xs rounded-full transition-colors min-h-[36px] ${
                    statusFilter === opt.value
                      ? 'bg-blue-100 dark:bg-blue-900/40 text-blue-700 dark:text-blue-300'
                      : 'bg-gray-100 dark:bg-gray-800 text-gray-600 dark:text-gray-400 hover:bg-gray-200 dark:hover:bg-gray-700'
                  }`}
                >
                  {opt.label}
                </button>
              ))}
            </div>
          </div>

          {/* Type dropdown */}
          <div className="flex items-center gap-2">
            <span className="text-xs font-medium text-gray-500 dark:text-gray-400">Type:</span>
            <select
              value={typeFilter}
              onChange={(e) => setTypeFilter(e.target.value)}
              className="text-xs rounded-md border border-border bg-surface px-3 py-2 min-h-[36px]"
            >
              {TYPE_OPTIONS.map((opt) => (
                <option key={opt.value} value={opt.value}>{opt.label}</option>
              ))}
            </select>
          </div>

          {hasActiveFilters && (
            <button
              onClick={clearFilters}
              className="text-xs text-blue-500 hover:text-blue-700 dark:hover:text-blue-300"
            >
              Clear filters
            </button>
          )}
        </div>
      )}

      {/* Summary chip */}
      {vehicles && vehicles.length > 0 && (
        <p className="text-xs text-gray-500 dark:text-gray-400">
          {vehicles.length} vehicle{vehicles.length !== 1 ? 's' : ''}
          {debouncedSearch ? ` matching "${debouncedSearch}"` : ''}
        </p>
      )}

      {/* Vehicle grid */}
      {!vehicles || vehicles.length === 0 ? (
        <EmptyState
          icon={<Truck className="h-12 w-12" />}
          title={
            debouncedSearch || hasActiveFilters
              ? 'No vehicles match filters'
              : 'No Vehicles'
          }
          description={
            debouncedSearch || hasActiveFilters
              ? 'Try adjusting your search or filters.'
              : 'Add your first vehicle to start managing your fleet.'
          }
          action={
            canManageFleet && !debouncedSearch && !hasActiveFilters ? (
              <Button icon={<Plus className="h-4 w-4" />} onClick={() => setShowCreate(true)}>
                Add Vehicle
              </Button>
            ) : undefined
          }
        />
      ) : (
        <div className="grid grid-cols-1 md:grid-cols-2 xl:grid-cols-3 gap-3">
          {vehicles.map((v) => (
            <VehicleCard key={v.id} vehicle={v} />
          ))}
        </div>
      )}

      {/* Create modal */}
      <CreateVehicleModal
        isOpen={showCreate}
        onClose={() => setShowCreate(false)}
      />
    </div>
  );
}
