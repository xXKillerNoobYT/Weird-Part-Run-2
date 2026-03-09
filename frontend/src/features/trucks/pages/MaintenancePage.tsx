/**
 * MaintenancePage — cross-fleet maintenance dashboard.
 *
 * Shows overdue alerts, upcoming maintenance, and fleet-wide cost summaries.
 * Allows managers to log service and manage maintenance types.
 * Accessible via Trucks > Maintenance tab.
 */

import { useState } from 'react';
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import { useNavigate } from 'react-router-dom';
import {
  AlertTriangle,
  Clock,
  Wrench,
  Calendar,
  ChevronDown,
  ChevronUp,
  Plus,
  Settings,
} from 'lucide-react';
import { PageSpinner } from '../../../components/ui/Spinner';
import { EmptyState } from '../../../components/ui/EmptyState';
import { Badge } from '../../../components/ui/Badge';
import { Button } from '../../../components/ui/Button';
import { Input } from '../../../components/ui/Input';
import { Modal } from '../../../components/ui/Modal';
import { useAuthStore } from '../../../stores/auth-store';
import { PERMISSIONS } from '../../../lib/constants';
import {
  getOverdueMaintenance,
  getUpcomingMaintenance,
  listMaintenanceTypes,
  createMaintenanceType,
  updateMaintenanceType,
  logService,
  listVehicles,
} from '../../../api/vehicles';
import type { MaintenanceAlert } from '../../../lib/types';

type SubView = 'overview' | 'types';

export function MaintenancePage() {
  const { hasPermission } = useAuthStore();
  const canManageFleet = hasPermission(PERMISSIONS.MANAGE_FLEET);

  const [subView, setSubView] = useState<SubView>('overview');
  const [daysAhead, setDaysAhead] = useState(30);

  return (
    <div className="space-y-4">
      {/* Header with sub-view toggle */}
      <div className="flex items-center justify-between flex-wrap gap-3">
        <div className="flex items-center gap-2">
          <button
            onClick={() => setSubView('overview')}
            className={`px-3 py-1.5 text-sm rounded-lg transition-colors min-h-[36px] ${
              subView === 'overview'
                ? 'bg-blue-100 dark:bg-blue-900/40 text-blue-700 dark:text-blue-300 font-medium'
                : 'text-gray-600 dark:text-gray-400 hover:bg-gray-100 dark:hover:bg-gray-800'
            }`}
          >
            <span className="flex items-center gap-1.5">
              <Calendar className="h-4 w-4" />
              <span className="hidden sm:inline">Overview</span>
            </span>
          </button>
          {canManageFleet && (
            <button
              onClick={() => setSubView('types')}
              className={`px-3 py-1.5 text-sm rounded-lg transition-colors min-h-[36px] ${
                subView === 'types'
                  ? 'bg-blue-100 dark:bg-blue-900/40 text-blue-700 dark:text-blue-300 font-medium'
                  : 'text-gray-600 dark:text-gray-400 hover:bg-gray-100 dark:hover:bg-gray-800'
              }`}
            >
              <span className="flex items-center gap-1.5">
                <Settings className="h-4 w-4" />
                <span className="hidden sm:inline">Maintenance Types</span>
              </span>
            </button>
          )}
        </div>

        {subView === 'overview' && (
          <div className="flex items-center gap-2">
            <span className="text-xs text-gray-500 dark:text-gray-400">Next</span>
            <select
              value={daysAhead}
              onChange={(e) => setDaysAhead(Number(e.target.value))}
              className="text-xs rounded-md border border-border bg-surface px-2 py-1.5 min-h-[36px]"
            >
              <option value={7}>7 days</option>
              <option value={14}>14 days</option>
              <option value={30}>30 days</option>
              <option value={60}>60 days</option>
              <option value={90}>90 days</option>
            </select>
          </div>
        )}
      </div>

      {subView === 'overview' ? (
        <MaintenanceOverview daysAhead={daysAhead} canManageFleet={canManageFleet} />
      ) : (
        <MaintenanceTypesManager />
      )}
    </div>
  );
}


// ── Overview View ─────────────────────────────────────────────────────

function MaintenanceOverview({ daysAhead, canManageFleet }: { daysAhead: number; canManageFleet: boolean }) {
  const navigate = useNavigate();
  const [showLogService, setShowLogService] = useState(false);

  const { data: overdue, isLoading: loadingOverdue } = useQuery({
    queryKey: ['maintenance-overdue'],
    queryFn: () => getOverdueMaintenance(),
    staleTime: 30_000,
  });

  const { data: upcoming, isLoading: loadingUpcoming } = useQuery({
    queryKey: ['maintenance-upcoming', daysAhead],
    queryFn: () => getUpcomingMaintenance({ days_ahead: daysAhead }),
    staleTime: 30_000,
  });

  const isLoading = loadingOverdue || loadingUpcoming;
  if (isLoading) return <PageSpinner label="Loading maintenance data..." />;

  const overdueCount = overdue?.length ?? 0;
  const upcomingCount = upcoming?.length ?? 0;

  return (
    <div className="space-y-4">
      {/* Summary cards */}
      <div className="grid grid-cols-2 sm:grid-cols-4 gap-3">
        <StatCard
          label="Overdue"
          value={overdueCount}
          color={overdueCount > 0 ? 'red' : 'green'}
          icon={<AlertTriangle className="h-4 w-4" />}
        />
        <StatCard
          label={`Due within ${daysAhead}d`}
          value={upcomingCount}
          color={upcomingCount > 0 ? 'amber' : 'green'}
          icon={<Clock className="h-4 w-4" />}
        />
        <StatCard
          label="Total Alerts"
          value={overdueCount + upcomingCount}
          color="blue"
          icon={<Wrench className="h-4 w-4" />}
        />
        {canManageFleet && (
          <div className="flex items-center justify-center">
            <Button
              size="sm"
              icon={<Plus className="h-4 w-4" />}
              onClick={() => setShowLogService(true)}
            >
              <span className="hidden sm:inline">Log Service</span>
            </Button>
          </div>
        )}
      </div>

      {/* Overdue section */}
      {overdueCount > 0 && (
        <AlertSection
          title="Overdue Maintenance"
          alerts={overdue!}
          variant="overdue"
          onVehicleClick={(id) => navigate(`/trucks/${id}`)}
        />
      )}

      {/* Upcoming section */}
      {upcomingCount > 0 ? (
        <AlertSection
          title={`Upcoming (Next ${daysAhead} Days)`}
          alerts={upcoming!}
          variant="upcoming"
          onVehicleClick={(id) => navigate(`/trucks/${id}`)}
        />
      ) : overdueCount === 0 ? (
        <EmptyState
          icon={<Wrench className="h-12 w-12" />}
          title="All Clear"
          description="No maintenance is overdue or upcoming. Your fleet is in good shape."
        />
      ) : null}

      {/* Log Service Modal */}
      {showLogService && (
        <LogServiceModal
          isOpen={showLogService}
          onClose={() => setShowLogService(false)}
        />
      )}
    </div>
  );
}


// ── Alert Section ─────────────────────────────────────────────────────

function AlertSection({
  title,
  alerts,
  variant,
  onVehicleClick,
}: {
  title: string;
  alerts: MaintenanceAlert[];
  variant: 'overdue' | 'upcoming';
  onVehicleClick: (vehicleId: number) => void;
}) {
  const [expanded, setExpanded] = useState(true);
  const borderColor = variant === 'overdue'
    ? 'border-red-200 dark:border-red-800'
    : 'border-amber-200 dark:border-amber-800';
  const headerBg = variant === 'overdue'
    ? 'bg-red-50 dark:bg-red-900/20'
    : 'bg-amber-50 dark:bg-amber-900/20';

  return (
    <div className={`border ${borderColor} rounded-xl overflow-hidden`}>
      <button
        onClick={() => setExpanded(!expanded)}
        className={`w-full flex items-center justify-between p-3 ${headerBg} min-h-[44px]`}
      >
        <div className="flex items-center gap-2">
          {variant === 'overdue' ? (
            <AlertTriangle className="h-4 w-4 text-red-500" />
          ) : (
            <Clock className="h-4 w-4 text-amber-500" />
          )}
          <span className="text-sm font-medium text-gray-900 dark:text-gray-100">{title}</span>
          <Badge variant={variant === 'overdue' ? 'danger' : 'warning'}>{alerts.length}</Badge>
        </div>
        {expanded ? <ChevronUp className="h-4 w-4 text-gray-400" /> : <ChevronDown className="h-4 w-4 text-gray-400" />}
      </button>

      {expanded && (
        <div className="divide-y divide-border">
          {alerts.map((alert) => (
            <div
              key={`${alert.vehicle_id}-${alert.maintenance_type_id}`}
              className="flex items-center justify-between p-3 hover:bg-gray-50 dark:hover:bg-gray-800/50 cursor-pointer transition-colors"
              onClick={() => onVehicleClick(alert.vehicle_id)}
            >
              <div className="min-w-0 flex-1">
                <div className="flex items-center gap-2 flex-wrap">
                  <span className="text-xs font-mono text-gray-500 dark:text-gray-400">
                    {alert.vehicle_number}
                  </span>
                  <span className="text-sm font-medium text-gray-900 dark:text-gray-100 truncate">
                    {alert.vehicle_name}
                  </span>
                </div>
                <p className="text-sm text-gray-600 dark:text-gray-400 mt-0.5">
                  {alert.maintenance_type_name}
                </p>
              </div>
              <div className="text-right shrink-0 ml-3">
                {alert.is_overdue ? (
                  <span className="text-xs font-medium text-red-600 dark:text-red-400">
                    Overdue
                    {alert.days_until_due != null && ` by ${Math.abs(alert.days_until_due)}d`}
                  </span>
                ) : (
                  <div className="text-xs text-gray-500 dark:text-gray-400">
                    {alert.days_until_due != null && (
                      <div>{alert.days_until_due}d away</div>
                    )}
                    {alert.miles_until_due != null && (
                      <div>{alert.miles_until_due.toLocaleString()} mi</div>
                    )}
                    {alert.next_due_date && (
                      <div className="text-gray-400 dark:text-gray-500">
                        {new Date(alert.next_due_date).toLocaleDateString()}
                      </div>
                    )}
                  </div>
                )}
              </div>
            </div>
          ))}
        </div>
      )}
    </div>
  );
}


// ── Log Service Modal (fleet-wide) ────────────────────────────────────

function LogServiceModal({ isOpen, onClose }: { isOpen: boolean; onClose: () => void }) {
  const queryClient = useQueryClient();
  const [vehicleId, setVehicleId] = useState<number | ''>('');
  const [typeId, setTypeId] = useState<number | ''>('');
  const [serviceDate, setServiceDate] = useState(new Date().toISOString().slice(0, 10));
  const [odometer, setOdometer] = useState('');
  const [cost, setCost] = useState('');
  const [vendor, setVendor] = useState('');
  const [description, setDescription] = useState('');
  const [error, setError] = useState('');

  const { data: vehicles } = useQuery({
    queryKey: ['vehicles'],
    queryFn: () => listVehicles({ status: 'active' }),
    staleTime: 60_000,
    enabled: isOpen,
  });

  const { data: types } = useQuery({
    queryKey: ['maintenance-types'],
    queryFn: () => listMaintenanceTypes({ active_only: true }),
    staleTime: 60_000,
    enabled: isOpen,
  });

  const mutation = useMutation({
    mutationFn: () =>
      logService(vehicleId as number, {
        maintenance_type_id: typeId as number,
        service_date: serviceDate,
        odometer_reading: odometer ? Number(odometer) : undefined,
        cost: cost ? Number(cost) : undefined,
        vendor: vendor.trim() || undefined,
        description: description.trim() || undefined,
      }),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['maintenance-overdue'] });
      queryClient.invalidateQueries({ queryKey: ['maintenance-upcoming'] });
      queryClient.invalidateQueries({ queryKey: ['vehicle'] });
      onClose();
    },
    onError: (err: any) => {
      setError(err?.response?.data?.detail || err?.response?.data?.message || err?.message || 'Failed to log service');
    },
  });

  function handleSubmit(e: React.FormEvent) {
    e.preventDefault();
    setError('');
    if (!vehicleId || !typeId) {
      setError('Please select a vehicle and maintenance type');
      return;
    }
    mutation.mutate();
  }

  return (
    <Modal isOpen={isOpen} onClose={onClose} title="Log Maintenance Service" size="md">
      <form onSubmit={handleSubmit} className="space-y-4">
        {error && (
          <div className="p-3 bg-red-50 dark:bg-red-900/20 border border-red-200 dark:border-red-800 rounded-lg text-sm text-red-600 dark:text-red-400">
            {error}
          </div>
        )}

        <div className="grid grid-cols-1 sm:grid-cols-2 gap-4">
          <div className="space-y-1.5">
            <label className="block text-sm font-medium text-gray-700 dark:text-gray-300">Vehicle *</label>
            <select
              value={vehicleId}
              onChange={(e) => setVehicleId(e.target.value ? Number(e.target.value) : '')}
              className="block w-full rounded-lg border border-gray-300 dark:border-gray-600 bg-white dark:bg-gray-800 px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-primary-300 focus:border-primary-500"
            >
              <option value="">Select vehicle...</option>
              {vehicles?.map((v) => (
                <option key={v.id} value={v.id}>
                  {v.vehicle_number} — {v.vehicle_name || `${v.make || ''} ${v.model || ''}`.trim()}
                </option>
              ))}
            </select>
          </div>

          <div className="space-y-1.5">
            <label className="block text-sm font-medium text-gray-700 dark:text-gray-300">Service Type *</label>
            <select
              value={typeId}
              onChange={(e) => setTypeId(e.target.value ? Number(e.target.value) : '')}
              className="block w-full rounded-lg border border-gray-300 dark:border-gray-600 bg-white dark:bg-gray-800 px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-primary-300 focus:border-primary-500"
            >
              <option value="">Select type...</option>
              {types?.map((t) => (
                <option key={t.id} value={t.id}>{t.name}</option>
              ))}
            </select>
          </div>
        </div>

        <div className="grid grid-cols-1 sm:grid-cols-3 gap-4">
          <Input
            label="Service Date *"
            type="date"
            value={serviceDate}
            onChange={(e) => setServiceDate(e.target.value)}
          />
          <Input
            label="Odometer"
            type="number"
            placeholder="e.g. 48250"
            value={odometer}
            onChange={(e) => setOdometer(e.target.value)}
          />
          <Input
            label="Cost ($)"
            type="number"
            step="0.01"
            placeholder="e.g. 89.99"
            value={cost}
            onChange={(e) => setCost(e.target.value)}
          />
        </div>

        <Input
          label="Vendor"
          placeholder="e.g. Jiffy Lube"
          value={vendor}
          onChange={(e) => setVendor(e.target.value)}
        />

        <Input
          label="Description / Notes"
          placeholder="Optional description..."
          value={description}
          onChange={(e) => setDescription(e.target.value)}
        />

        <div className="flex items-center justify-end gap-3 pt-2">
          <Button variant="secondary" type="button" onClick={onClose}>Cancel</Button>
          <Button type="submit" isLoading={mutation.isPending}>Log Service</Button>
        </div>
      </form>
    </Modal>
  );
}


// ── Maintenance Types Manager ─────────────────────────────────────────

function MaintenanceTypesManager() {
  const queryClient = useQueryClient();

  const { data: types, isLoading } = useQuery({
    queryKey: ['maintenance-types-all'],
    queryFn: () => listMaintenanceTypes(),
    staleTime: 30_000,
  });

  const [showAdd, setShowAdd] = useState(false);
  const [newName, setNewName] = useState('');
  const [newDesc, setNewDesc] = useState('');
  const [newMiles, setNewMiles] = useState('');
  const [newMonths, setNewMonths] = useState('');
  const [editingId, setEditingId] = useState<number | null>(null);
  const [editName, setEditName] = useState('');
  const [editDesc, setEditDesc] = useState('');
  const [editMiles, setEditMiles] = useState('');
  const [editMonths, setEditMonths] = useState('');
  const [error, setError] = useState('');

  const invalidate = () => queryClient.invalidateQueries({ queryKey: ['maintenance-types'] });

  const createMut = useMutation({
    mutationFn: () =>
      createMaintenanceType({
        name: newName.trim(),
        description: newDesc.trim() || undefined,
        default_interval_miles: newMiles ? Number(newMiles) : undefined,
        default_interval_months: newMonths ? Number(newMonths) : undefined,
      }),
    onSuccess: () => {
      invalidate();
      setShowAdd(false);
      setNewName('');
      setNewDesc('');
      setNewMiles('');
      setNewMonths('');
    },
    onError: (err: any) => setError(err?.message || 'Failed to create'),
  });

  const updateMut = useMutation({
    mutationFn: ({
      id, name, description, default_interval_miles, default_interval_months,
    }: {
      id: number; name: string; description?: string;
      default_interval_miles?: number; default_interval_months?: number;
    }) =>
      updateMaintenanceType(id, { name, description, default_interval_miles, default_interval_months }),
    onSuccess: () => {
      invalidate();
      setEditingId(null);
    },
    onError: (err: any) => setError(err?.message || 'Failed to update'),
  });

  if (isLoading) return <PageSpinner label="Loading maintenance types..." />;

  return (
    <div className="space-y-4">
      <div className="flex items-center justify-between">
        <h3 className="text-sm font-medium text-gray-900 dark:text-gray-100">
          Maintenance Types ({types?.length ?? 0})
        </h3>
        <Button size="sm" icon={<Plus className="h-4 w-4" />} onClick={() => setShowAdd(true)}>
          <span className="hidden sm:inline">Add Type</span>
        </Button>
      </div>

      {error && (
        <div className="p-2 bg-red-50 dark:bg-red-900/20 border border-red-200 dark:border-red-800 rounded-lg text-sm text-red-600 dark:text-red-400">
          {error}
        </div>
      )}

      {/* Add form */}
      {showAdd && (
        <div className="p-3 bg-surface border border-border rounded-lg space-y-3">
          <div className="grid grid-cols-1 sm:grid-cols-2 gap-3">
            <Input
              label="Type Name *"
              placeholder="e.g. Brake Pad Replacement"
              value={newName}
              onChange={(e) => setNewName(e.target.value)}
            />
            <Input
              label="Description"
              placeholder="Optional"
              value={newDesc}
              onChange={(e) => setNewDesc(e.target.value)}
            />
          </div>
          <div className="grid grid-cols-2 gap-3">
            <Input
              label="Default Interval (miles)"
              type="number"
              placeholder="e.g. 5000"
              value={newMiles}
              onChange={(e) => setNewMiles(e.target.value)}
            />
            <Input
              label="Default Interval (months)"
              type="number"
              placeholder="e.g. 6"
              value={newMonths}
              onChange={(e) => setNewMonths(e.target.value)}
            />
          </div>
          <div className="flex items-center gap-2 justify-end">
            <Button variant="secondary" size="sm" onClick={() => setShowAdd(false)}>Cancel</Button>
            <Button
              size="sm"
              onClick={() => { setError(''); createMut.mutate(); }}
              isLoading={createMut.isPending}
              disabled={!newName.trim()}
            >
              Create
            </Button>
          </div>
        </div>
      )}

      {/* Types list */}
      <div className="bg-surface border border-border rounded-xl divide-y divide-border">
        {types?.length === 0 && (
          <p className="text-sm text-gray-400 dark:text-gray-500 text-center py-8">
            No maintenance types defined yet.
          </p>
        )}
        {types?.map((t) => (
          <div key={t.id} className={editingId === t.id ? 'p-3' : 'flex items-center justify-between p-3'}>
            {editingId === t.id ? (
              <div className="space-y-3">
                <div className="grid grid-cols-1 sm:grid-cols-2 gap-3">
                  <Input
                    label="Type Name *"
                    placeholder="e.g. Brake Pad Replacement"
                    value={editName}
                    onChange={(e) => setEditName(e.target.value)}
                    autoFocus
                  />
                  <Input
                    label="Description"
                    placeholder="Optional"
                    value={editDesc}
                    onChange={(e) => setEditDesc(e.target.value)}
                  />
                </div>
                <div className="grid grid-cols-2 gap-3">
                  <Input
                    label="Default Interval (miles)"
                    type="number"
                    placeholder="e.g. 5000"
                    value={editMiles}
                    onChange={(e) => setEditMiles(e.target.value)}
                  />
                  <Input
                    label="Default Interval (months)"
                    type="number"
                    placeholder="e.g. 6"
                    value={editMonths}
                    onChange={(e) => setEditMonths(e.target.value)}
                  />
                </div>
                <div className="flex items-center gap-2 justify-end">
                  <Button variant="secondary" size="sm" onClick={() => setEditingId(null)}>
                    Cancel
                  </Button>
                  <Button
                    size="sm"
                    onClick={() =>
                      updateMut.mutate({
                        id: t.id,
                        name: editName.trim(),
                        description: editDesc.trim() || undefined,
                        default_interval_miles: editMiles ? Number(editMiles) : undefined,
                        default_interval_months: editMonths ? Number(editMonths) : undefined,
                      })
                    }
                    isLoading={updateMut.isPending}
                    disabled={!editName.trim()}
                  >
                    Save
                  </Button>
                </div>
              </div>
            ) : (
              <>
                <div className="min-w-0 flex-1">
                  <div className="flex items-center gap-2">
                    <span className="text-sm font-medium text-gray-900 dark:text-gray-100">
                      {t.name}
                    </span>
                    {!t.is_active && <Badge variant="default">Inactive</Badge>}
                  </div>
                  <div className="flex items-center gap-3 text-xs text-gray-500 dark:text-gray-400 mt-0.5">
                    {t.description && <span>{t.description}</span>}
                    {t.default_interval_miles && (
                      <span>Every {t.default_interval_miles.toLocaleString()} mi</span>
                    )}
                    {t.default_interval_months && <span>Every {t.default_interval_months} mo</span>}
                  </div>
                </div>
                <Button
                  size="sm"
                  variant="ghost"
                  onClick={() => {
                    setEditingId(t.id);
                    setEditName(t.name);
                    setEditDesc(t.description || '');
                    setEditMiles(t.default_interval_miles != null ? String(t.default_interval_miles) : '');
                    setEditMonths(t.default_interval_months != null ? String(t.default_interval_months) : '');
                  }}
                >
                  Edit
                </Button>
              </>
            )}
          </div>
        ))}
      </div>
    </div>
  );
}


// ── Stat Card ─────────────────────────────────────────────────────────

function StatCard({
  label,
  value,
  color,
  icon,
}: {
  label: string;
  value: number;
  color: 'red' | 'amber' | 'green' | 'blue';
  icon: React.ReactNode;
}) {
  const colors = {
    red: 'bg-red-50 dark:bg-red-900/20 text-red-600 dark:text-red-400 border-red-200 dark:border-red-800',
    amber: 'bg-amber-50 dark:bg-amber-900/20 text-amber-600 dark:text-amber-400 border-amber-200 dark:border-amber-800',
    green: 'bg-green-50 dark:bg-green-900/20 text-green-600 dark:text-green-400 border-green-200 dark:border-green-800',
    blue: 'bg-blue-50 dark:bg-blue-900/20 text-blue-600 dark:text-blue-400 border-blue-200 dark:border-blue-800',
  };

  return (
    <div className={`border rounded-xl p-3 ${colors[color]}`}>
      <div className="flex items-center gap-1.5 mb-1">
        {icon}
        <span className="text-xs font-medium">{label}</span>
      </div>
      <p className="text-2xl font-bold">{value}</p>
    </div>
  );
}
