/**
 * OverviewTab — vehicle details view/edit + quick summary cards.
 */

import { useState } from 'react';
import { useMutation, useQueryClient } from '@tanstack/react-query';
import { Edit3, Save, X } from 'lucide-react';
import { Button } from '../../../../components/ui/Button';
import { Input } from '../../../../components/ui/Input';
import { Card } from '../../../../components/ui/Card';
import { useAuthStore } from '../../../../stores/auth-store';
import { PERMISSIONS } from '../../../../lib/constants';
import { updateVehicle } from '../../../../api/vehicles';
import { STATUS_LABELS, TYPE_LABELS } from '../VehicleStatusBadge';
import { InfoRow, STATUS_OPTIONS, TYPE_OPTIONS } from './shared';
import { VehiclePhotoCard } from './VehiclePhotoCard';
import type { Vehicle, VehicleUpdate } from '../../../../lib/types';


export function OverviewTab({ vehicle }: { vehicle: Vehicle }) {
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
