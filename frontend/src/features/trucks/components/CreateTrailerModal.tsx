/**
 * CreateTrailerModal — form to create a new job trailer.
 *
 * Fields: trailer_code, name, home_warehouse_id, assigned_driver_user_id, notes.
 */

import { useState } from 'react';
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query';
import { Modal } from '../../../components/ui/Modal';
import { Button } from '../../../components/ui/Button';
import { Input } from '../../../components/ui/Input';
import { createTrailer, listWarehouseLocations } from '../../../api/vehicles';
import { getUsers } from '../../../api/auth';
import { toast } from '../../../lib/toast';
import type { JobTrailerCreate } from '../../../lib/types';

interface CreateTrailerModalProps {
  isOpen: boolean;
  onClose: () => void;
}

export function CreateTrailerModal({ isOpen, onClose }: CreateTrailerModalProps) {
  const queryClient = useQueryClient();

  const [trailerCode, setTrailerCode] = useState('');
  const [name, setName] = useState('');
  const [warehouseId, setWarehouseId] = useState<number | ''>('');
  const [driverId, setDriverId] = useState<number | ''>('');
  const [notes, setNotes] = useState('');
  const [error, setError] = useState('');

  const { data: warehouses } = useQuery({
    queryKey: ['warehouse-locations'],
    queryFn: () => listWarehouseLocations(),
    staleTime: 60_000,
    enabled: isOpen,
  });

  const { data: users } = useQuery({
    queryKey: ['users'],
    queryFn: getUsers,
    staleTime: 60_000,
    enabled: isOpen,
  });

  const mutation = useMutation({
    mutationFn: (data: JobTrailerCreate) => createTrailer(data),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['trailers'] });
      toast.success('Trailer created');
      resetForm();
      onClose();
    },
    onError: (err: any) => {
      const msg =
        err?.response?.data?.detail ||
        err?.response?.data?.message ||
        err?.message ||
        'Failed to create trailer';
      setError(typeof msg === 'string' ? msg : JSON.stringify(msg));
      toast.error('Failed to create trailer');
    },
  });

  function resetForm() {
    setTrailerCode('');
    setName('');
    setWarehouseId('');
    setDriverId('');
    setNotes('');
    setError('');
  }

  function handleSubmit(e: React.FormEvent) {
    e.preventDefault();
    setError('');

    if (!trailerCode.trim()) {
      setError('Trailer code is required');
      return;
    }
    if (!name.trim()) {
      setError('Trailer name is required');
      return;
    }

    const payload: JobTrailerCreate = {
      trailer_code: trailerCode.trim(),
      name: name.trim(),
      home_warehouse_id: warehouseId || undefined,
      assigned_driver_user_id: driverId || undefined,
      notes: notes.trim() || undefined,
    };

    mutation.mutate(payload);
  }

  return (
    <Modal
      isOpen={isOpen}
      onClose={() => { resetForm(); onClose(); }}
      title="New Trailer"
    >
      <form onSubmit={handleSubmit} className="space-y-4">
        {error && (
          <div className="p-3 bg-red-50 dark:bg-red-900/30 text-red-600 dark:text-red-400 rounded-lg text-sm">
            {error}
          </div>
        )}

        <Input
          label="Trailer Code"
          placeholder="e.g. TR-001"
          value={trailerCode}
          onChange={(e) => setTrailerCode(e.target.value)}
          required
        />

        <Input
          label="Trailer Name"
          placeholder="e.g. Main Job Trailer"
          value={name}
          onChange={(e) => setName(e.target.value)}
          required
        />

        <div>
          <label className="block text-sm font-medium mb-1">Home Warehouse</label>
          <select
            value={warehouseId}
            onChange={(e) => setWarehouseId(e.target.value ? Number(e.target.value) : '')}
            className="w-full rounded-md border border-border bg-surface px-3 py-2 text-sm"
          >
            <option value="">— None —</option>
            {warehouses?.map((w) => (
              <option key={w.id} value={w.id}>{w.name}</option>
            ))}
          </select>
        </div>

        <div>
          <label className="block text-sm font-medium mb-1">Assigned Driver</label>
          <select
            value={driverId}
            onChange={(e) => setDriverId(e.target.value ? Number(e.target.value) : '')}
            className="w-full rounded-md border border-border bg-surface px-3 py-2 text-sm"
          >
            <option value="">— None —</option>
            {users?.map((u) => (
              <option key={u.id} value={u.id}>{u.display_name || u.username}</option>
            ))}
          </select>
        </div>

        <div>
          <label className="block text-sm font-medium mb-1">Notes</label>
          <textarea
            value={notes}
            onChange={(e) => setNotes(e.target.value)}
            rows={3}
            className="w-full rounded-md border border-border bg-surface px-3 py-2 text-sm"
            placeholder="Optional notes about this trailer..."
          />
        </div>

        <div className="flex justify-end gap-2 pt-2">
          <Button
            variant="secondary"
            type="button"
            onClick={() => { resetForm(); onClose(); }}
          >
            Cancel
          </Button>
          <Button
            type="submit"
            isLoading={mutation.isPending}
          >
            Create Trailer
          </Button>
        </div>
      </form>
    </Modal>
  );
}
