/**
 * CreateVehicleModal — form to create a new vehicle.
 *
 * Fields: vehicle_number, vehicle_name, vehicle_type, make, model, year,
 * color, vin, license_plate, current_odometer, owner_user_id (if private).
 *
 * When vehicle_type is "private_vehicle", an Owner dropdown appears
 * (required by the backend).
 */

import { useState } from 'react';
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query';
import { Modal } from '../../../components/ui/Modal';
import { Button } from '../../../components/ui/Button';
import { Input } from '../../../components/ui/Input';
import { createVehicle } from '../../../api/vehicles';
import { getUsers } from '../../../api/auth';
import type { VehicleCreate, VehicleType } from '../../../lib/types';

const VEHICLE_TYPES: { label: string; value: VehicleType }[] = [
  { label: 'Company Truck', value: 'company_truck' },
  { label: 'Company Van', value: 'company_van' },
  { label: 'Company Car', value: 'company_car' },
  { label: 'Private Vehicle', value: 'private_vehicle' },
];

interface CreateVehicleModalProps {
  isOpen: boolean;
  onClose: () => void;
}

export function CreateVehicleModal({ isOpen, onClose }: CreateVehicleModalProps) {
  const queryClient = useQueryClient();

  const [vehicleNumber, setVehicleNumber] = useState('');
  const [vehicleName, setVehicleName] = useState('');
  const [vehicleType, setVehicleType] = useState<VehicleType>('company_truck');
  const [ownerId, setOwnerId] = useState<number | ''>('');
  const [make, setMake] = useState('');
  const [model, setModel] = useState('');
  const [year, setYear] = useState('');
  const [color, setColor] = useState('');
  const [vin, setVin] = useState('');
  const [licensePlate, setLicensePlate] = useState('');
  const [odometer, setOdometer] = useState('');
  const [error, setError] = useState('');

  const isPrivate = vehicleType === 'private_vehicle';

  // Fetch users for the owner dropdown (only when private vehicle selected)
  const { data: users } = useQuery({
    queryKey: ['users'],
    queryFn: getUsers,
    staleTime: 60_000,
    enabled: isOpen && isPrivate,
  });

  const mutation = useMutation({
    mutationFn: (data: VehicleCreate) => createVehicle(data),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['vehicles'] });
      resetForm();
      onClose();
    },
    onError: (err: any) => {
      // FastAPI returns errors in "detail", our ApiResponse uses "message"
      const msg =
        err?.response?.data?.detail ||
        err?.response?.data?.message ||
        err?.message ||
        'Failed to create vehicle';
      setError(typeof msg === 'string' ? msg : JSON.stringify(msg));
    },
  });

  function resetForm() {
    setVehicleNumber('');
    setVehicleName('');
    setVehicleType('company_truck');
    setOwnerId('');
    setMake('');
    setModel('');
    setYear('');
    setColor('');
    setVin('');
    setLicensePlate('');
    setOdometer('');
    setError('');
  }

  function handleSubmit(e: React.FormEvent) {
    e.preventDefault();
    setError('');

    if (!vehicleNumber.trim()) {
      setError('Vehicle number is required');
      return;
    }
    if (isPrivate && !ownerId) {
      setError('Private vehicles require an owner');
      return;
    }

    const data: VehicleCreate = {
      vehicle_number: vehicleNumber.trim(),
      vehicle_name: vehicleName.trim() || undefined,
      vehicle_type: vehicleType,
      make: make.trim() || undefined,
      model: model.trim() || undefined,
      year: year ? parseInt(year) : undefined,
      color: color.trim() || undefined,
      vin: vin.trim() || undefined,
      license_plate: licensePlate.trim() || undefined,
      current_odometer: odometer ? parseInt(odometer) : undefined,
      owner_user_id: isPrivate && ownerId ? (ownerId as number) : undefined,
    };

    mutation.mutate(data);
  }

  return (
    <Modal isOpen={isOpen} onClose={onClose} title="Create Vehicle" size="lg">
      <form onSubmit={handleSubmit} className="space-y-4">
        {error && (
          <div className="p-3 bg-red-50 dark:bg-red-900/20 border border-red-200 dark:border-red-800 rounded-lg text-sm text-red-600 dark:text-red-400">
            {error}
          </div>
        )}

        {/* Row 1: Number + Type */}
        <div className="grid grid-cols-1 sm:grid-cols-2 gap-4">
          <Input
            label="Vehicle Number *"
            placeholder="T-001"
            value={vehicleNumber}
            onChange={(e) => setVehicleNumber(e.target.value)}
          />
          <div className="space-y-1.5">
            <label className="block text-sm font-medium text-gray-700 dark:text-gray-300">
              Vehicle Type
            </label>
            <select
              value={vehicleType}
              onChange={(e) => setVehicleType(e.target.value as VehicleType)}
              className="block w-full rounded-lg border border-gray-300 dark:border-gray-600 bg-white dark:bg-gray-800 px-3 py-2 text-sm text-gray-900 dark:text-gray-100 focus:outline-none focus:ring-2 focus:ring-primary-300 focus:border-primary-500"
            >
              {VEHICLE_TYPES.map((t) => (
                <option key={t.value} value={t.value}>{t.label}</option>
              ))}
            </select>
          </div>
        </div>

        {/* Owner dropdown — only shown for private vehicles */}
        {isPrivate && (
          <div className="space-y-1.5">
            <label className="block text-sm font-medium text-gray-700 dark:text-gray-300">
              Owner *
            </label>
            <select
              value={ownerId}
              onChange={(e) => setOwnerId(e.target.value ? Number(e.target.value) : '')}
              className="block w-full rounded-lg border border-gray-300 dark:border-gray-600 bg-white dark:bg-gray-800 px-3 py-2 text-sm text-gray-900 dark:text-gray-100 focus:outline-none focus:ring-2 focus:ring-primary-300 focus:border-primary-500"
            >
              <option value="">Select owner...</option>
              {users?.map((u) => (
                <option key={u.id} value={u.id}>{u.display_name}</option>
              ))}
            </select>
            <p className="text-xs text-gray-500 dark:text-gray-400">
              The employee who owns this private vehicle
            </p>
          </div>
        )}

        {/* Row 2: Name */}
        <Input
          label="Vehicle Name"
          placeholder="Big Red, Shop Van, etc."
          value={vehicleName}
          onChange={(e) => setVehicleName(e.target.value)}
          hint="Optional friendly name for the vehicle"
        />

        {/* Row 3: Make + Model + Year */}
        <div className="grid grid-cols-1 sm:grid-cols-3 gap-4">
          <Input
            label="Make"
            placeholder="Ford"
            value={make}
            onChange={(e) => setMake(e.target.value)}
          />
          <Input
            label="Model"
            placeholder="F-150"
            value={model}
            onChange={(e) => setModel(e.target.value)}
          />
          <Input
            label="Year"
            type="number"
            placeholder="2024"
            value={year}
            onChange={(e) => setYear(e.target.value)}
          />
        </div>

        {/* Row 4: Color + License + Odometer */}
        <div className="grid grid-cols-1 sm:grid-cols-3 gap-4">
          <Input
            label="Color"
            placeholder="White"
            value={color}
            onChange={(e) => setColor(e.target.value)}
          />
          <Input
            label="License Plate"
            placeholder="ABC-1234"
            value={licensePlate}
            onChange={(e) => setLicensePlate(e.target.value)}
          />
          <Input
            label="Odometer"
            type="number"
            placeholder="45000"
            value={odometer}
            onChange={(e) => setOdometer(e.target.value)}
          />
        </div>

        {/* Row 5: VIN */}
        <Input
          label="VIN"
          placeholder="1FTFW1E57NFA12345"
          value={vin}
          onChange={(e) => setVin(e.target.value)}
        />

        {/* Actions */}
        <div className="flex items-center justify-end gap-3 pt-2">
          <Button variant="secondary" type="button" onClick={onClose}>
            Cancel
          </Button>
          <Button type="submit" isLoading={mutation.isPending}>
            Create Vehicle
          </Button>
        </div>
      </form>
    </Modal>
  );
}
