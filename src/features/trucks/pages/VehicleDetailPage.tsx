/**
 * VehicleDetailPage — full vehicle detail with internal sub-tabs.
 *
 * Sub-tabs: Overview (default), Assignments, Inventory, Deliveries, Maintenance, Mileage.
 * Accessible via /trucks/:id. Follows the JobDetailPage tabbed-detail pattern.
 */

import { useState } from 'react';
import { useParams, useNavigate } from 'react-router-dom';
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import {
  ArrowLeft,
  Truck,
  Car,
  Users,
  Package,
  Wrench,
  Gauge,
  ChevronDown,
  ChevronUp,
  Edit3,
  Save,
  X,
  Plus,
  Trash2,
  Home,
  AlertTriangle,
  DollarSign,
  MapPin,
  Search,
  CheckCircle,
  RotateCcw,
  Camera,
  ImageOff,
} from 'lucide-react';
import { PageSpinner } from '../../../components/ui/Spinner';
import { EmptyState } from '../../../components/ui/EmptyState';
import { Button } from '../../../components/ui/Button';
import { Input } from '../../../components/ui/Input';
import { Badge } from '../../../components/ui/Badge';
import { Card } from '../../../components/ui/Card';
import { PartIdentity } from '../../../components/ui/PartIdentity';
import { useAuthStore } from '../../../stores/auth-store';
import { PERMISSIONS } from '../../../lib/constants';
import {
  getVehicle,
  updateVehicle,
  listAssignments,
  unassignDriver,
  getVehicleInventory,
  listDeliveries,
  markDelivered,
  returnDelivery,
  getMaintenanceSchedule,
  getServiceHistory,
  logService,
  getMaintenanceCosts,
  getMileageLogs,
  listMaintenanceTypes,
  uploadVehiclePhoto,
  removeVehiclePhoto,
} from '../../../api/vehicles';
import { VehicleStatusBadge, VehicleTypeBadge, STATUS_LABELS, TYPE_LABELS } from '../components/VehicleStatusBadge';
import { AssignDriverModal } from '../components/AssignDriverModal';
import type {
  Vehicle,
  VehicleUpdate,
  VehicleType,
  VehicleStatus,
  VehicleAssignment,
  VehicleDeliveryItem,
  DeliveryStatus,
  MaintenanceSchedule,
  MaintenanceRecord,
  MaintenanceRecordCreate,
  MileageLog,
} from '../../../lib/types';


// ── Sub-tab Definitions ──────────────────────────────────────────

type SubTab = 'overview' | 'assignments' | 'inventory' | 'deliveries' | 'maintenance' | 'mileage';

const TABS: { id: SubTab; label: string; mobileLabel: string; icon: React.ReactNode }[] = [
  { id: 'overview', label: 'Overview', mobileLabel: 'Info', icon: <Truck className="h-4 w-4" /> },
  { id: 'assignments', label: 'Assignments', mobileLabel: 'Drivers', icon: <Users className="h-4 w-4" /> },
  { id: 'inventory', label: 'Inventory', mobileLabel: 'Parts', icon: <Package className="h-4 w-4" /> },
  { id: 'deliveries', label: 'Deliveries', mobileLabel: 'Deliver', icon: <MapPin className="h-4 w-4" /> },
  { id: 'maintenance', label: 'Maintenance', mobileLabel: 'Maint.', icon: <Wrench className="h-4 w-4" /> },
  { id: 'mileage', label: 'Mileage', mobileLabel: 'Miles', icon: <Gauge className="h-4 w-4" /> },
];

const STATUS_OPTIONS: { label: string; value: VehicleStatus }[] = [
  { label: 'Active', value: 'active' },
  { label: 'Inactive', value: 'inactive' },
  { label: 'In Maintenance', value: 'maintenance' },
  { label: 'Retired', value: 'retired' },
];

const TYPE_OPTIONS: { label: string; value: VehicleType }[] = [
  { label: 'Company Truck', value: 'company_truck' },
  { label: 'Company Van', value: 'company_van' },
  { label: 'Company Car', value: 'company_car' },
  { label: 'Private Vehicle', value: 'private_vehicle' },
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


// ── Helper ──────────────────────────────────────────────────────

function VehicleIcon({ type, className }: { type: VehicleType; className?: string }) {
  switch (type) {
    case 'company_van':
    case 'company_truck':
      return <Truck className={className} />;
    default:
      return <Car className={className} />;
  }
}

function InfoRow({ label, value, mono }: { label: string; value: string | null | undefined; mono?: boolean }) {
  if (!value) return null;
  return (
    <div className="flex justify-between text-sm py-1">
      <span className="text-gray-500 dark:text-gray-400">{label}</span>
      <span className={`text-gray-900 dark:text-gray-100 font-medium ${mono ? 'font-mono text-xs' : ''}`}>
        {value}
      </span>
    </div>
  );
}


// ══════════════════════════════════════════════════════════════════
// VEHICLE PHOTO CARD
// ══════════════════════════════════════════════════════════════════

function VehiclePhotoCard({
  vehicleId,
  photoPath,
  canManage,
}: {
  vehicleId: number;
  photoPath: string | null;
  canManage: boolean;
}) {
  const queryClient = useQueryClient();

  const uploadMut = useMutation({
    mutationFn: (file: File) => uploadVehiclePhoto(vehicleId, file),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['vehicle', vehicleId] });
      queryClient.invalidateQueries({ queryKey: ['vehicles'] });
    },
  });

  const removeMut = useMutation({
    mutationFn: () => removeVehiclePhoto(vehicleId),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['vehicle', vehicleId] });
      queryClient.invalidateQueries({ queryKey: ['vehicles'] });
    },
  });

  const handleFileSelect = (e: React.ChangeEvent<HTMLInputElement>) => {
    const file = e.target.files?.[0];
    if (file) uploadMut.mutate(file);
    e.target.value = '';
  };

  return (
    <Card noPadding className="lg:col-span-2">
      <div className="p-4">
        <div className="flex items-center justify-between mb-3">
          <h3 className="text-sm font-semibold text-gray-900 dark:text-gray-100">Vehicle Photo</h3>
          {canManage && (
            <div className="flex items-center gap-2">
              <label className="cursor-pointer">
                <input
                  type="file"
                  accept="image/*"
                  onChange={handleFileSelect}
                  className="hidden"
                />
                <span className="inline-flex items-center gap-1.5 px-3 py-1.5 text-xs font-medium text-blue-500 hover:text-blue-600 hover:bg-blue-50 dark:hover:bg-blue-900/20 rounded-lg transition-colors cursor-pointer">
                  <Camera className="h-3.5 w-3.5" />
                  {photoPath ? 'Change' : 'Upload'}
                </span>
              </label>
              {photoPath && (
                <button
                  onClick={() => {
                    if (window.confirm('Remove vehicle photo?')) removeMut.mutate();
                  }}
                  disabled={removeMut.isPending}
                  className="p-1.5 rounded text-gray-400 hover:text-red-500 hover:bg-red-50 dark:hover:bg-red-900/20 transition-colors"
                  title="Remove photo"
                >
                  <Trash2 className="h-3.5 w-3.5" />
                </button>
              )}
            </div>
          )}
        </div>

        {uploadMut.isPending && (
          <div className="flex items-center gap-2 mb-3 p-2 bg-blue-50 dark:bg-blue-900/20 rounded-lg">
            <div className="h-4 w-4 animate-spin rounded-full border-2 border-blue-500 border-t-transparent" />
            <span className="text-xs text-blue-600 dark:text-blue-400">Uploading photo...</span>
          </div>
        )}

        {photoPath ? (
          <div className="relative rounded-lg overflow-hidden bg-gray-100 dark:bg-gray-800 max-h-64">
            <img
              src={`/api${photoPath}`}
              alt="Vehicle"
              className="w-full h-full object-contain max-h-64"
            />
          </div>
        ) : (
          <div className="flex flex-col items-center justify-center py-8 text-gray-400 dark:text-gray-500">
            <ImageOff className="h-10 w-10 mb-2" />
            <p className="text-sm">No photo uploaded</p>
          </div>
        )}
      </div>
    </Card>
  );
}


// ══════════════════════════════════════════════════════════════════
// OVERVIEW TAB
// ══════════════════════════════════════════════════════════════════

function OverviewTab({ vehicle }: { vehicle: Vehicle }) {
  const { hasPermission } = useAuthStore();
  const canManage = hasPermission(PERMISSIONS.MANAGE_FLEET);
  const queryClient = useQueryClient();

  const [editing, setEditing] = useState(false);
  const [form, setForm] = useState<VehicleUpdate>({});

  const mutation = useMutation({
    mutationFn: (update: VehicleUpdate) => updateVehicle(vehicle.id, update),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['vehicle', vehicle.id] });
      queryClient.invalidateQueries({ queryKey: ['vehicles'] });
      setEditing(false);
    },
  });

  function startEdit() {
    setForm({
      vehicle_name: vehicle.vehicle_name || '',
      vehicle_type: vehicle.vehicle_type,
      status: vehicle.status,
      make: vehicle.make || '',
      model: vehicle.model || '',
      year: vehicle.year ?? undefined,
      color: vehicle.color || '',
      vin: vehicle.vin || '',
      license_plate: vehicle.license_plate || '',
      current_odometer: vehicle.current_odometer,
      insurance_policy: vehicle.insurance_policy || '',
      insurance_expiry: vehicle.insurance_expiry || '',
      registration_expiry: vehicle.registration_expiry || '',
      notes: vehicle.notes || '',
    });
    setEditing(true);
  }

  function handleSave() {
    mutation.mutate(form);
  }

  return (
    <div className="grid grid-cols-1 lg:grid-cols-2 gap-4">
      {/* Vehicle Details Card */}
      <Card noPadding className="lg:col-span-2">
        <div className="p-4">
          <div className="flex items-center justify-between mb-3">
            <h3 className="text-sm font-semibold text-gray-900 dark:text-gray-100">Vehicle Details</h3>
            {canManage && !editing && (
              <Button size="sm" variant="secondary" icon={<Edit3 className="h-3.5 w-3.5" />} onClick={startEdit}>
                Edit
              </Button>
            )}
            {editing && (
              <div className="flex items-center gap-2">
                <Button size="sm" variant="secondary" icon={<X className="h-3.5 w-3.5" />} onClick={() => setEditing(false)}>
                  Cancel
                </Button>
                <Button size="sm" icon={<Save className="h-3.5 w-3.5" />} isLoading={mutation.isPending} onClick={handleSave}>
                  Save
                </Button>
              </div>
            )}
          </div>

          {mutation.isError && (
            <div className="mb-3 p-2 bg-red-50 dark:bg-red-900/20 border border-red-200 dark:border-red-800 rounded text-sm text-red-600 dark:text-red-400">
              Failed to update vehicle. Please try again.
            </div>
          )}

          {editing ? (
            <EditForm form={form} setForm={setForm} />
          ) : (
            <div className="grid grid-cols-1 sm:grid-cols-2 gap-x-8">
              <div className="space-y-0.5">
                <InfoRow label="Vehicle Name" value={vehicle.vehicle_name} />
                <InfoRow label="Type" value={TYPE_LABELS[vehicle.vehicle_type]} />
                <InfoRow label="Status" value={STATUS_LABELS[vehicle.status]} />
                <InfoRow label="Make" value={vehicle.make} />
                <InfoRow label="Model" value={vehicle.model} />
                <InfoRow label="Year" value={vehicle.year?.toString()} />
                <InfoRow label="Color" value={vehicle.color} />
              </div>
              <div className="space-y-0.5">
                <InfoRow label="VIN" value={vehicle.vin} mono />
                <InfoRow label="License Plate" value={vehicle.license_plate} mono />
                <InfoRow label="Odometer" value={vehicle.current_odometer > 0 ? `${vehicle.current_odometer.toLocaleString()} mi` : null} />
                <InfoRow label="Insurance Policy" value={vehicle.insurance_policy} />
                <InfoRow label="Insurance Expiry" value={vehicle.insurance_expiry} />
                <InfoRow label="Registration Expiry" value={vehicle.registration_expiry} />
                {vehicle.owner_name && <InfoRow label="Owner" value={vehicle.owner_name} />}
              </div>
            </div>
          )}

          {vehicle.notes && !editing && (
            <div className="mt-3 pt-3 border-t border-border">
              <p className="text-xs text-gray-500 dark:text-gray-400 mb-1">Notes</p>
              <p className="text-sm text-gray-700 dark:text-gray-300 whitespace-pre-wrap">{vehicle.notes}</p>
            </div>
          )}
        </div>
      </Card>

      {/* Vehicle Photo */}
      <VehiclePhotoCard vehicleId={vehicle.id} photoPath={vehicle.photo_path} canManage={canManage} />

      {/* Quick Summary Cards */}
      <Card noPadding>
        <div className="p-4">
          <h3 className="text-sm font-semibold text-gray-900 dark:text-gray-100 mb-3">Fleet Info</h3>
          <div className="space-y-0.5">
            <InfoRow label="Primary Driver" value={vehicle.primary_driver_name ?? 'Unassigned'} />
            <InfoRow label="Total Assignments" value={String(vehicle.assignment_count)} />
            <InfoRow label="Next Maintenance" value={vehicle.next_maintenance_type ?? 'None scheduled'} />
            <InfoRow label="Next Due" value={vehicle.next_maintenance_due} />
          </div>
        </div>
      </Card>

      <Card noPadding>
        <div className="p-4">
          <h3 className="text-sm font-semibold text-gray-900 dark:text-gray-100 mb-3">Dates & Registration</h3>
          <div className="space-y-0.5">
            <InfoRow label="Created" value={vehicle.created_at ? new Date(vehicle.created_at + 'Z').toLocaleDateString() : null} />
            <InfoRow label="Last Updated" value={vehicle.updated_at ? new Date(vehicle.updated_at + 'Z').toLocaleDateString() : null} />
            <InfoRow label="Insurance Expiry" value={vehicle.insurance_expiry} />
            <InfoRow label="Registration Expiry" value={vehicle.registration_expiry} />
          </div>
        </div>
      </Card>
    </div>
  );
}

/** Inline edit form for the Overview tab. */
function EditForm({
  form,
  setForm,
}: {
  form: VehicleUpdate;
  setForm: React.Dispatch<React.SetStateAction<VehicleUpdate>>;
}) {
  const set = (field: keyof VehicleUpdate, value: string | number | undefined) =>
    setForm((prev) => ({ ...prev, [field]: value }));

  return (
    <div className="space-y-3">
      <div className="grid grid-cols-1 sm:grid-cols-2 gap-3">
        <Input label="Vehicle Name" value={form.vehicle_name ?? ''} onChange={(e) => set('vehicle_name', e.target.value)} />
        <div className="space-y-1.5">
          <label className="block text-sm font-medium text-gray-700 dark:text-gray-300">Status</label>
          <select
            value={form.status ?? 'active'}
            onChange={(e) => set('status', e.target.value)}
            className="block w-full rounded-lg border border-gray-300 dark:border-gray-600 bg-white dark:bg-gray-800 px-3 py-2 text-sm"
          >
            {STATUS_OPTIONS.map((o) => (
              <option key={o.value} value={o.value}>{o.label}</option>
            ))}
          </select>
        </div>
      </div>
      <div className="grid grid-cols-1 sm:grid-cols-2 gap-3">
        <div className="space-y-1.5">
          <label className="block text-sm font-medium text-gray-700 dark:text-gray-300">Type</label>
          <select
            value={form.vehicle_type ?? 'company_truck'}
            onChange={(e) => set('vehicle_type', e.target.value)}
            className="block w-full rounded-lg border border-gray-300 dark:border-gray-600 bg-white dark:bg-gray-800 px-3 py-2 text-sm"
          >
            {TYPE_OPTIONS.map((o) => (
              <option key={o.value} value={o.value}>{o.label}</option>
            ))}
          </select>
        </div>
        <Input label="Color" value={form.color ?? ''} onChange={(e) => set('color', e.target.value)} />
      </div>
      <div className="grid grid-cols-1 sm:grid-cols-3 gap-3">
        <Input label="Make" value={form.make ?? ''} onChange={(e) => set('make', e.target.value)} />
        <Input label="Model" value={form.model ?? ''} onChange={(e) => set('model', e.target.value)} />
        <Input label="Year" type="number" value={form.year?.toString() ?? ''} onChange={(e) => set('year', e.target.value ? parseInt(e.target.value) : undefined)} />
      </div>
      <div className="grid grid-cols-1 sm:grid-cols-3 gap-3">
        <Input label="VIN" value={form.vin ?? ''} onChange={(e) => set('vin', e.target.value)} />
        <Input label="License Plate" value={form.license_plate ?? ''} onChange={(e) => set('license_plate', e.target.value)} />
        <Input label="Odometer" type="number" value={form.current_odometer?.toString() ?? ''} onChange={(e) => set('current_odometer', e.target.value ? parseInt(e.target.value) : undefined)} />
      </div>
      <div className="grid grid-cols-1 sm:grid-cols-3 gap-3">
        <Input label="Insurance Policy" value={form.insurance_policy ?? ''} onChange={(e) => set('insurance_policy', e.target.value)} />
        <Input label="Insurance Expiry" type="date" value={form.insurance_expiry ?? ''} onChange={(e) => set('insurance_expiry', e.target.value)} />
        <Input label="Registration Expiry" type="date" value={form.registration_expiry ?? ''} onChange={(e) => set('registration_expiry', e.target.value)} />
      </div>
      <div>
        <label className="block text-sm font-medium text-gray-700 dark:text-gray-300 mb-1">Notes</label>
        <textarea
          value={form.notes ?? ''}
          onChange={(e) => set('notes', e.target.value)}
          rows={3}
          className="w-full rounded-lg border border-gray-300 dark:border-gray-600 bg-white dark:bg-gray-800 px-3 py-2 text-sm resize-none"
        />
      </div>
    </div>
  );
}


// ══════════════════════════════════════════════════════════════════
// ASSIGNMENTS TAB
// ══════════════════════════════════════════════════════════════════

function AssignmentsTab({ vehicleId, vehicleName }: { vehicleId: number; vehicleName: string }) {
  const { hasPermission } = useAuthStore();
  const canManage = hasPermission(PERMISSIONS.MANAGE_FLEET);
  const queryClient = useQueryClient();

  const [showAssign, setShowAssign] = useState(false);

  const { data: assignments, isLoading } = useQuery({
    queryKey: ['vehicle-assignments', vehicleId],
    queryFn: () => listAssignments(vehicleId),
    staleTime: 15_000,
  });

  const unassignMut = useMutation({
    mutationFn: (userId: number) => unassignDriver(vehicleId, userId),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['vehicle-assignments', vehicleId] });
      queryClient.invalidateQueries({ queryKey: ['vehicle', vehicleId] });
      queryClient.invalidateQueries({ queryKey: ['vehicles'] });
    },
  });

  if (isLoading) return <PageSpinner label="Loading assignments..." />;

  const existingDriverIds = (assignments ?? []).map((a) => a.user_id);

  return (
    <div className="space-y-3">
      {canManage && (
        <div className="flex justify-end">
          <Button size="sm" icon={<Plus className="h-4 w-4" />} onClick={() => setShowAssign(true)}>
            <span className="hidden sm:inline">Assign Driver</span>
          </Button>
        </div>
      )}

      {!assignments || assignments.length === 0 ? (
        <EmptyState
          icon={<Users className="h-12 w-12" />}
          title="No Drivers Assigned"
          description="Assign drivers to this vehicle to track who drives it."
          action={
            canManage ? (
              <Button icon={<Plus className="h-4 w-4" />} onClick={() => setShowAssign(true)}>
                Assign Driver
              </Button>
            ) : undefined
          }
        />
      ) : (
        <div className="space-y-2">
          {assignments.map((a) => (
            <AssignmentRow
              key={a.id}
              assignment={a}
              canManage={canManage}
              onUnassign={() => {
                if (window.confirm(`Remove ${a.user_name} from this vehicle?`)) {
                  unassignMut.mutate(a.user_id);
                }
              }}
            />
          ))}
        </div>
      )}

      <AssignDriverModal
        isOpen={showAssign}
        onClose={() => setShowAssign(false)}
        vehicleId={vehicleId}
        vehicleName={vehicleName}
        existingDriverIds={existingDriverIds}
      />
    </div>
  );
}

function AssignmentRow({
  assignment: a,
  canManage,
  onUnassign,
}: {
  assignment: VehicleAssignment;
  canManage: boolean;
  onUnassign: () => void;
}) {
  const typeColors: Record<string, string> = {
    primary: 'bg-blue-100 dark:bg-blue-900/30 text-blue-700 dark:text-blue-300',
    authorized: 'bg-green-100 dark:bg-green-900/30 text-green-700 dark:text-green-300',
    temporary: 'bg-amber-100 dark:bg-amber-900/30 text-amber-700 dark:text-amber-300',
  };

  return (
    <div className="flex items-center gap-3 p-3 bg-surface border border-border rounded-lg">
      <div className="flex items-center justify-center h-9 w-9 rounded-full bg-gray-100 dark:bg-gray-800 text-gray-500 dark:text-gray-400 shrink-0">
        <Users className="h-4 w-4" />
      </div>
      <div className="flex-1 min-w-0">
        <div className="flex items-center gap-2 flex-wrap">
          <span className="text-sm font-medium text-gray-900 dark:text-gray-100">
            {a.user_name ?? `User #${a.user_id}`}
          </span>
          <span className={`px-2 py-0.5 text-[10px] font-medium rounded-full ${typeColors[a.assignment_type] ?? 'bg-gray-100 dark:bg-gray-800 text-gray-600 dark:text-gray-400'}`}>
            {a.assignment_type}
          </span>
          {a.is_take_home && (
            <span className="flex items-center gap-1 text-[10px] text-blue-500 dark:text-blue-400">
              <Home className="h-3 w-3" /> Take-Home
            </span>
          )}
        </div>
        <div className="flex items-center gap-3 text-xs text-gray-500 dark:text-gray-400 mt-0.5">
          {a.home_to_shop_miles != null && (
            <span>{a.home_to_shop_miles} mi commute</span>
          )}
          {a.start_date && <span>Since {a.start_date}</span>}
          {a.notes && <span className="truncate max-w-[150px]">{a.notes}</span>}
        </div>
      </div>
      {canManage && (
        <button
          onClick={onUnassign}
          className="p-2 text-gray-400 hover:text-red-500 transition-colors shrink-0"
          title="Remove assignment"
        >
          <Trash2 className="h-4 w-4" />
        </button>
      )}
    </div>
  );
}


// ══════════════════════════════════════════════════════════════════
// INVENTORY TAB
// ══════════════════════════════════════════════════════════════════

function InventoryTab({ vehicleId }: { vehicleId: number }) {
  const [search, setSearch] = useState('');

  const { data: inventory, isLoading } = useQuery({
    queryKey: ['vehicle-inventory', vehicleId, search],
    queryFn: () => getVehicleInventory(vehicleId, { search: search || undefined }),
    staleTime: 15_000,
  });

  if (isLoading) return <PageSpinner label="Loading inventory..." />;

  return (
    <div className="space-y-3">
      <div className="flex items-center gap-3 flex-wrap">
        <div className="flex-1 min-w-[200px]">
          <Input
            placeholder="Search parts on vehicle..."
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
      </div>

      {!inventory || inventory.length === 0 ? (
        <EmptyState
          icon={<Package className="h-12 w-12" />}
          title={search ? 'No parts match' : 'No Parts on Vehicle'}
          description={search ? 'Try a different search term.' : 'Add parts to this vehicle from the warehouse.'}
        />
      ) : (
        <>
          <p className="text-xs text-gray-500 dark:text-gray-400">
            {inventory.length} part{inventory.length !== 1 ? 's' : ''} on vehicle
          </p>
          <div className="overflow-x-auto">
            <table className="w-full text-sm">
              <thead>
                <tr className="border-b border-border text-left text-xs text-gray-500 dark:text-gray-400">
                  <th className="pb-2 font-medium">Part</th>
                  <th className="pb-2 font-medium">Category</th>
                  <th className="pb-2 font-medium text-right">Qty</th>
                  <th className="pb-2 font-medium">Supplier</th>
                </tr>
              </thead>
              <tbody className="divide-y divide-border">
                {inventory.map((item) => (
                  <tr key={item.id}>
                    <td className="py-2">
                      <PartIdentity
                        compact
                        partName={item.part_description}
                        partNumber={item.part_number}
                        partId={item.part_id}
                        brandName={item.brand}
                        categoryName={item.category}
                      />
                    </td>
                    <td className="py-2 text-gray-500 dark:text-gray-400">{item.category ?? '—'}</td>
                    <td className="py-2 text-right font-mono">{item.qty}</td>
                    <td className="py-2 text-gray-500 dark:text-gray-400">{item.supplier_name ?? '—'}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        </>
      )}
    </div>
  );
}


// ══════════════════════════════════════════════════════════════════
// DELIVERIES TAB
// ══════════════════════════════════════════════════════════════════

const DELIVERY_VARIANT: Record<DeliveryStatus, 'success' | 'warning' | 'default' | 'danger'> = {
  assigned: 'default',
  loaded: 'default',
  in_transit: 'warning',
  delivered: 'success',
  returned: 'danger',
};

function DeliveriesTab({ vehicleId }: { vehicleId: number }) {
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


// ══════════════════════════════════════════════════════════════════
// MAINTENANCE TAB
// ══════════════════════════════════════════════════════════════════

function MaintenanceTab({ vehicleId }: { vehicleId: number }) {
  const queryClient = useQueryClient();
  const [showSchedule, setShowSchedule] = useState(true);
  const [showHistory, setShowHistory] = useState(true);
  const [showLogService, setShowLogService] = useState(false);

  const { data: schedule, isLoading: loadingSchedule } = useQuery({
    queryKey: ['vehicle-maintenance-schedule', vehicleId],
    queryFn: () => getMaintenanceSchedule(vehicleId),
    staleTime: 30_000,
  });

  const { data: history, isLoading: loadingHistory } = useQuery({
    queryKey: ['vehicle-maintenance-history', vehicleId],
    queryFn: () => getServiceHistory(vehicleId, { limit: 20 }),
    staleTime: 30_000,
  });

  const { data: costs } = useQuery({
    queryKey: ['vehicle-maintenance-costs', vehicleId],
    queryFn: () => getMaintenanceCosts(vehicleId),
    staleTime: 60_000,
  });

  const isLoading = loadingSchedule || loadingHistory;
  if (isLoading) return <PageSpinner label="Loading maintenance..." />;

  // Separate overdue items
  const overdue = (schedule ?? []).filter((s) => s.urgency === 'overdue');

  return (
    <div className="space-y-4">
      {/* Cost summary */}
      {costs && (
        <div className="flex items-center gap-4 text-sm flex-wrap">
          <div className="flex items-center gap-1.5 text-gray-500 dark:text-gray-400">
            <DollarSign className="h-4 w-4 shrink-0" />
            <span>Total: <span className="font-medium text-gray-900 dark:text-gray-100">${costs.total_cost?.toFixed(2) ?? '0.00'}</span></span>
          </div>
          <div className="flex items-center gap-1.5 text-gray-500 dark:text-gray-400">
            <Wrench className="h-4 w-4 shrink-0" />
            <span>{costs.total_records ?? 0} service{(costs.total_records ?? 0) !== 1 ? 's' : ''}</span>
          </div>
        </div>
      )}

      {/* Overdue alerts */}
      {overdue.length > 0 && (
        <div className="p-3 bg-red-50 dark:bg-red-900/20 border border-red-200 dark:border-red-800 rounded-lg">
          <div className="flex items-center gap-2 mb-2">
            <AlertTriangle className="h-4 w-4 text-red-500" />
            <span className="text-sm font-medium text-red-700 dark:text-red-300">
              {overdue.length} Overdue
            </span>
          </div>
          <div className="space-y-1">
            {overdue.map((s) => (
              <p key={s.id} className="text-xs text-red-600 dark:text-red-400">
                {s.maintenance_type_name}
                {s.next_due_miles != null && s.current_odometer != null && ` — ${(s.current_odometer - s.next_due_miles).toLocaleString()} mi overdue`}
              </p>
            ))}
          </div>
        </div>
      )}

      {/* Schedule Section */}
      <CollapsibleSection
        title="Maintenance Schedule"
        count={(schedule ?? []).filter((s) => s.is_enabled).length}
        open={showSchedule}
        onToggle={() => setShowSchedule(!showSchedule)}
      >
        {!schedule || schedule.length === 0 ? (
          <p className="text-sm text-gray-400 dark:text-gray-500 text-center py-4">
            No maintenance schedule configured.
          </p>
        ) : (
          <div className="space-y-1">
            {schedule.filter((s) => s.is_enabled).map((s) => (
              <ScheduleRow key={s.id} schedule={s} />
            ))}
          </div>
        )}
      </CollapsibleSection>

      {/* Log Service */}
      <div className="flex justify-end">
        <Button size="sm" icon={<Plus className="h-4 w-4" />} onClick={() => setShowLogService(!showLogService)}>
          <span className="hidden sm:inline">Log Service</span>
        </Button>
      </div>

      {showLogService && (
        <LogServiceForm
          vehicleId={vehicleId}
          onDone={() => {
            setShowLogService(false);
            queryClient.invalidateQueries({ queryKey: ['vehicle-maintenance-history', vehicleId] });
            queryClient.invalidateQueries({ queryKey: ['vehicle-maintenance-schedule', vehicleId] });
            queryClient.invalidateQueries({ queryKey: ['vehicle-maintenance-costs', vehicleId] });
          }}
        />
      )}

      {/* Service History */}
      <CollapsibleSection
        title="Service History"
        count={(history ?? []).length}
        open={showHistory}
        onToggle={() => setShowHistory(!showHistory)}
      >
        {!history || history.length === 0 ? (
          <p className="text-sm text-gray-400 dark:text-gray-500 text-center py-4">
            No service records yet.
          </p>
        ) : (
          <div className="space-y-2">
            {history.map((r) => (
              <ServiceRecordRow key={r.id} record={r} />
            ))}
          </div>
        )}
      </CollapsibleSection>
    </div>
  );
}

function ScheduleRow({ schedule: s }: { schedule: MaintenanceSchedule }) {
  const urgencyColors = {
    overdue: 'text-red-600 dark:text-red-400',
    soon: 'text-amber-600 dark:text-amber-400',
    normal: 'text-gray-500 dark:text-gray-400',
  };

  return (
    <div className="flex items-center justify-between py-2 px-1">
      <div className="min-w-0">
        <p className="text-sm text-gray-900 dark:text-gray-100">{s.maintenance_type_name}</p>
        <p className="text-xs text-gray-500 dark:text-gray-400">
          Every {s.interval_miles?.toLocaleString() ?? '—'} mi / {s.interval_months ?? '—'} mo
        </p>
      </div>
      <div className="text-right shrink-0 ml-2">
        {s.next_due_date && (
          <p className={`text-xs ${urgencyColors[s.urgency ?? 'normal']}`}>
            Due: {s.next_due_date}
          </p>
        )}
        {s.next_due_miles != null && (
          <p className={`text-xs ${urgencyColors[s.urgency ?? 'normal']}`}>
            {s.next_due_miles.toLocaleString()} mi
          </p>
        )}
        {s.last_performed_at && (
          <p className="text-[10px] text-gray-400 dark:text-gray-500">
            Last: {s.last_performed_at}
          </p>
        )}
      </div>
    </div>
  );
}

function ServiceRecordRow({ record: r }: { record: MaintenanceRecord }) {
  return (
    <div className="flex items-center gap-3 p-2 bg-surface-secondary rounded-lg">
      <div className="flex items-center justify-center h-8 w-8 rounded-full bg-blue-50 dark:bg-blue-900/20 text-blue-500 shrink-0">
        <Wrench className="h-4 w-4" />
      </div>
      <div className="flex-1 min-w-0">
        <p className="text-sm text-gray-900 dark:text-gray-100 truncate">
          {r.maintenance_type_name ?? 'Service'}
        </p>
        <p className="text-xs text-gray-500 dark:text-gray-400">
          {r.service_date}
          {r.vendor && ` · ${r.vendor}`}
          {r.invoice_number && ` · #${r.invoice_number}`}
          {r.odometer_reading && ` · ${r.odometer_reading.toLocaleString()} mi`}
        </p>
      </div>
      {r.cost > 0 && (
        <span className="text-sm font-mono text-gray-900 dark:text-gray-100 shrink-0">
          ${r.cost.toFixed(2)}
        </span>
      )}
    </div>
  );
}

/** Inline form to log a new maintenance service. */
function LogServiceForm({ vehicleId, onDone }: { vehicleId: number; onDone: () => void }) {
  const { data: mtypes } = useQuery({
    queryKey: ['maintenance-types'],
    queryFn: () => listMaintenanceTypes({ active_only: true }),
    staleTime: 120_000,
  });

  const [typeId, setTypeId] = useState<number | ''>('');
  const [serviceDate, setServiceDate] = useState(new Date().toISOString().slice(0, 10));
  const [odometer, setOdometer] = useState('');
  const [cost, setCost] = useState('');
  const [vendor, setVendor] = useState('');
  const [invoiceNumber, setInvoiceNumber] = useState('');
  const [description, setDescription] = useState('');
  const [error, setError] = useState('');

  const mutation = useMutation({
    mutationFn: (data: MaintenanceRecordCreate) => logService(vehicleId, data),
    onSuccess: () => onDone(),
    onError: (err: any) => setError(err?.message || 'Failed to log service'),
  });

  function handleSubmit(e: React.FormEvent) {
    e.preventDefault();
    if (!typeId) { setError('Select a maintenance type'); return; }
    mutation.mutate({
      maintenance_type_id: typeId as number,
      service_date: serviceDate || undefined,
      odometer_reading: odometer ? parseInt(odometer) : undefined,
      cost: cost ? parseFloat(cost) : undefined,
      vendor: vendor.trim() || undefined,
      invoice_number: invoiceNumber.trim() || undefined,
      description: description.trim() || undefined,
    });
  }

  return (
    <form onSubmit={handleSubmit} className="p-4 bg-surface border border-border rounded-xl space-y-3">
      <h4 className="text-sm font-semibold text-gray-900 dark:text-gray-100">Log Service</h4>

      {error && (
        <p className="text-sm text-red-500">{error}</p>
      )}

      <div className="grid grid-cols-1 sm:grid-cols-2 gap-3">
        <div className="space-y-1.5">
          <label className="block text-sm font-medium text-gray-700 dark:text-gray-300">Type *</label>
          <select
            value={typeId}
            onChange={(e) => setTypeId(e.target.value ? Number(e.target.value) : '')}
            className="block w-full rounded-lg border border-gray-300 dark:border-gray-600 bg-white dark:bg-gray-800 px-3 py-2 text-sm"
          >
            <option value="">Select type...</option>
            {(mtypes ?? []).map((t) => (
              <option key={t.id} value={t.id}>{t.name}</option>
            ))}
          </select>
        </div>
        <Input label="Service Date" type="date" value={serviceDate} onChange={(e) => setServiceDate(e.target.value)} />
      </div>
      <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-4 gap-3">
        <Input label="Odometer" type="number" placeholder="45000" value={odometer} onChange={(e) => setOdometer(e.target.value)} />
        <Input label="Cost ($)" type="number" placeholder="0.00" value={cost} onChange={(e) => setCost(e.target.value)} />
        <Input label="Vendor" placeholder="Shop name" value={vendor} onChange={(e) => setVendor(e.target.value)} />
        <Input label="Invoice #" placeholder="INV-12345" value={invoiceNumber} onChange={(e) => setInvoiceNumber(e.target.value)} />
      </div>
      <Input label="Description" placeholder="What was done..." value={description} onChange={(e) => setDescription(e.target.value)} />

      <div className="flex items-center justify-end gap-2 pt-1">
        <Button variant="secondary" size="sm" type="button" onClick={onDone}>Cancel</Button>
        <Button size="sm" type="submit" isLoading={mutation.isPending}>Log Service</Button>
      </div>
    </form>
  );
}


// ══════════════════════════════════════════════════════════════════
// MILEAGE TAB
// ══════════════════════════════════════════════════════════════════

function MileageTab({ vehicleId }: { vehicleId: number }) {
  const { data: logs, isLoading } = useQuery({
    queryKey: ['vehicle-mileage', vehicleId],
    queryFn: () => getMileageLogs(vehicleId, { limit: 30 }),
    staleTime: 15_000,
  });

  if (isLoading) return <PageSpinner label="Loading mileage..." />;

  if (!logs || logs.length === 0) {
    return (
      <EmptyState
        icon={<Gauge className="h-12 w-12" />}
        title="No Mileage Logs"
        description="Daily mileage readings will appear here once logged."
      />
    );
  }

  return (
    <div className="space-y-3">
      <p className="text-xs text-gray-500 dark:text-gray-400">
        Showing last {logs.length} entries
      </p>

      <div className="overflow-x-auto">
        <table className="w-full text-sm">
          <thead>
            <tr className="border-b border-border text-left text-xs text-gray-500 dark:text-gray-400">
              <th className="pb-2 font-medium">Date</th>
              <th className="pb-2 font-medium">Driver</th>
              <th className="pb-2 font-medium text-right">Start</th>
              <th className="pb-2 font-medium text-right">End</th>
              <th className="pb-2 font-medium text-right">Total</th>
              <th className="pb-2 font-medium text-center">Take-Home</th>
            </tr>
          </thead>
          <tbody className="divide-y divide-border">
            {logs.map((log) => (
              <MileageLogRow key={log.id} log={log} />
            ))}
          </tbody>
        </table>
      </div>
    </div>
  );
}

function MileageLogRow({ log }: { log: MileageLog }) {
  const [expanded, setExpanded] = useState(false);

  return (
    <>
      <tr
        className="cursor-pointer hover:bg-gray-50 dark:hover:bg-gray-800/50 transition-colors"
        onClick={() => setExpanded(!expanded)}
      >
        <td className="py-2 text-gray-900 dark:text-gray-100">{log.log_date}</td>
        <td className="py-2 text-gray-500 dark:text-gray-400">{log.driver_name ?? '—'}</td>
        <td className="py-2 text-right font-mono">{log.odometer_start?.toLocaleString() ?? '—'}</td>
        <td className="py-2 text-right font-mono">{log.odometer_end?.toLocaleString() ?? '—'}</td>
        <td className="py-2 text-right font-mono font-medium">
          {log.total_miles?.toLocaleString() ?? '—'} mi
        </td>
        <td className="py-2 text-center">
          {log.is_take_home_day ? (
            <Home className="h-3.5 w-3.5 text-blue-500 inline" />
          ) : (
            <span className="text-gray-300 dark:text-gray-600">—</span>
          )}
        </td>
      </tr>
      {expanded && log.trip_legs && log.trip_legs.length > 0 && (
        <tr>
          <td colSpan={6} className="pb-3 pt-0">
            <div className="ml-4 pl-3 border-l-2 border-blue-200 dark:border-blue-800 space-y-1">
              {log.trip_legs.map((leg, i) => (
                <div key={leg.id ?? i} className="flex items-center gap-3 text-xs text-gray-500 dark:text-gray-400">
                  <span className="capitalize font-medium min-w-[100px]">
                    {leg.leg_type.replace(/_/g, ' ')}
                  </span>
                  <span>{leg.from_label ?? '?'} → {leg.to_label ?? '?'}</span>
                  <span className="font-mono">{leg.actual_miles ?? leg.estimated_miles ?? '—'} mi</span>
                  {leg.is_billable && (
                    <Badge variant="success">billable</Badge>
                  )}
                </div>
              ))}
            </div>
          </td>
        </tr>
      )}
      {expanded && (!log.trip_legs || log.trip_legs.length === 0) && (
        <tr>
          <td colSpan={6} className="pb-2 pt-0">
            <p className="text-xs text-gray-400 dark:text-gray-500 ml-4 italic">
              No trip legs recorded{log.notes ? ` — ${log.notes}` : ''}
            </p>
          </td>
        </tr>
      )}
    </>
  );
}


// ── Shared Collapsible Section ───────────────────────────────────

function CollapsibleSection({
  title,
  count,
  open,
  onToggle,
  children,
}: {
  title: string;
  count?: number;
  open: boolean;
  onToggle: () => void;
  children: React.ReactNode;
}) {
  return (
    <div className="bg-surface border border-border rounded-xl overflow-hidden">
      <button
        onClick={onToggle}
        className="w-full flex items-center justify-between px-4 py-3 hover:bg-gray-50 dark:hover:bg-gray-800/50 transition-colors"
      >
        <div className="flex items-center gap-2">
          <h3 className="text-sm font-medium text-gray-900 dark:text-gray-100">{title}</h3>
          {count != null && count > 0 && <Badge variant="default">{count}</Badge>}
        </div>
        {open ? <ChevronUp className="h-4 w-4 text-gray-400" /> : <ChevronDown className="h-4 w-4 text-gray-400" />}
      </button>
      {open && <div className="px-4 pb-3">{children}</div>}
    </div>
  );
}
