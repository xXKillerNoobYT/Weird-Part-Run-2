/**
 * AssignDriverModal — assign a driver (employee) to a vehicle.
 *
 * Fetches the user list, lets the manager pick a driver, choose
 * assignment type, enter commute distance, and optionally mark as take-home.
 */

import { useState } from 'react';
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import { Modal } from '../../../components/ui/Modal';
import { Button } from '../../../components/ui/Button';
import { Input } from '../../../components/ui/Input';
import { getUsers } from '../../../api/auth';
import { assignDriver } from '../../../api/vehicles';
import type { VehicleAssignmentCreate, AssignmentType } from '../../../lib/types';

const ASSIGNMENT_TYPES: { label: string; value: AssignmentType }[] = [
  { label: 'Primary', value: 'primary' },
  { label: 'Authorized', value: 'authorized' },
  { label: 'Temporary', value: 'temporary' },
];

interface AssignDriverModalProps {
  isOpen: boolean;
  onClose: () => void;
  vehicleId: number;
  vehicleName: string;
  /** IDs of drivers already assigned (to filter them out). */
  existingDriverIds?: number[];
}

export function AssignDriverModal({
  isOpen,
  onClose,
  vehicleId,
  vehicleName,
  existingDriverIds = [],
}: AssignDriverModalProps) {
  const queryClient = useQueryClient();

  const [selectedUserId, setSelectedUserId] = useState<number | ''>('');
  const [assignmentType, setAssignmentType] = useState<AssignmentType>('primary');
  const [isTakeHome, setIsTakeHome] = useState(false);
  const [homeToShopMiles, setHomeToShopMiles] = useState('');
  const [notes, setNotes] = useState('');
  const [error, setError] = useState('');

  // Fetch users for the picker
  const { data: users } = useQuery({
    queryKey: ['users'],
    queryFn: getUsers,
    staleTime: 60_000,
  });

  // Filter out already-assigned drivers
  const availableUsers = (users ?? []).filter(
    (u) => !existingDriverIds.includes(u.id),
  );

  const mutation = useMutation({
    mutationFn: (data: VehicleAssignmentCreate) => assignDriver(vehicleId, data),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['vehicles'] });
      queryClient.invalidateQueries({ queryKey: ['vehicle', vehicleId] });
      queryClient.invalidateQueries({ queryKey: ['vehicle-assignments', vehicleId] });
      resetForm();
      onClose();
    },
    onError: (err: any) => {
      setError(err?.response?.data?.detail || err?.response?.data?.message || err?.message || 'Failed to assign driver');
    },
  });

  function resetForm() {
    setSelectedUserId('');
    setAssignmentType('primary');
    setIsTakeHome(false);
    setHomeToShopMiles('');
    setNotes('');
    setError('');
  }

  function handleSubmit(e: React.FormEvent) {
    e.preventDefault();
    setError('');

    if (!selectedUserId) {
      setError('Please select a driver');
      return;
    }

    const data: VehicleAssignmentCreate = {
      user_id: selectedUserId as number,
      assignment_type: assignmentType,
      is_take_home: isTakeHome,
      home_to_shop_miles: homeToShopMiles ? parseFloat(homeToShopMiles) : undefined,
      notes: notes.trim() || undefined,
    };

    mutation.mutate(data);
  }

  return (
    <Modal isOpen={isOpen} onClose={onClose} title="Assign Driver" size="md">
      <form onSubmit={handleSubmit} className="space-y-4">
        {error && (
          <div className="p-3 bg-red-50 dark:bg-red-900/20 border border-red-200 dark:border-red-800 rounded-lg text-sm text-red-600 dark:text-red-400">
            {error}
          </div>
        )}

        <p className="text-sm text-gray-500 dark:text-gray-400">
          Assign a driver to <span className="font-medium text-gray-900 dark:text-gray-100">{vehicleName}</span>.
        </p>

        {/* Driver picker */}
        <div className="space-y-1.5">
          <label className="block text-sm font-medium text-gray-700 dark:text-gray-300">
            Driver *
          </label>
          <select
            value={selectedUserId}
            onChange={(e) => setSelectedUserId(e.target.value ? Number(e.target.value) : '')}
            className="block w-full rounded-lg border border-gray-300 dark:border-gray-600 bg-white dark:bg-gray-800 px-3 py-2 text-sm text-gray-900 dark:text-gray-100 focus:outline-none focus:ring-2 focus:ring-primary-300 focus:border-primary-500"
          >
            <option value="">Select an employee...</option>
            {availableUsers.map((u) => (
              <option key={u.id} value={u.id}>
                {u.display_name} {u.hats?.length ? `(${u.hats.join(', ')})` : ''}
              </option>
            ))}
          </select>
          {availableUsers.length === 0 && (
            <p className="text-xs text-gray-400 dark:text-gray-500">
              All employees are already assigned to this vehicle.
            </p>
          )}
        </div>

        {/* Assignment type + take-home */}
        <div className="grid grid-cols-1 sm:grid-cols-2 gap-4">
          <div className="space-y-1.5">
            <label className="block text-sm font-medium text-gray-700 dark:text-gray-300">
              Assignment Type
            </label>
            <select
              value={assignmentType}
              onChange={(e) => setAssignmentType(e.target.value as AssignmentType)}
              className="block w-full rounded-lg border border-gray-300 dark:border-gray-600 bg-white dark:bg-gray-800 px-3 py-2 text-sm text-gray-900 dark:text-gray-100 focus:outline-none focus:ring-2 focus:ring-primary-300 focus:border-primary-500"
            >
              {ASSIGNMENT_TYPES.map((t) => (
                <option key={t.value} value={t.value}>{t.label}</option>
              ))}
            </select>
          </div>

          <div className="flex items-end">
            <label className="flex items-center gap-2 py-2 cursor-pointer">
              <input
                type="checkbox"
                checked={isTakeHome}
                onChange={(e) => setIsTakeHome(e.target.checked)}
                className="rounded border-gray-300 dark:border-gray-600 text-blue-600 focus:ring-blue-500"
              />
              <span className="text-sm text-gray-700 dark:text-gray-300">Take-Home Vehicle</span>
            </label>
          </div>
        </div>

        {/* Commute distance (manual input) */}
        <Input
          label="Home → Shop Distance (mi)"
          type="number"
          placeholder="e.g. 12.5"
          value={homeToShopMiles}
          onChange={(e) => setHomeToShopMiles(e.target.value)}
          hint="One-time entry — used for daily mileage estimation"
        />

        {/* Notes */}
        <Input
          label="Notes"
          placeholder="Optional notes..."
          value={notes}
          onChange={(e) => setNotes(e.target.value)}
        />

        {/* Actions */}
        <div className="flex items-center justify-end gap-3 pt-2">
          <Button variant="secondary" type="button" onClick={onClose}>
            Cancel
          </Button>
          <Button type="submit" isLoading={mutation.isPending}>
            Assign Driver
          </Button>
        </div>
      </form>
    </Modal>
  );
}
