/**
 * EditJobModal — modal dialog for editing an existing job's details.
 *
 * Pre-fills all fields from the current job data. Uses the PUT /api/jobs/:id
 * endpoint via updateJob(). Only sends changed fields (JobUpdate type).
 *
 * Also used from the Office > Manage Jobs page for admin editing.
 */

import { useState, useEffect } from 'react';
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query';
import { Modal } from '../../../components/ui/Modal';
import { Button } from '../../../components/ui/Button';
import { Input } from '../../../components/ui/Input';
import { updateJob, getBillRateTypes } from '../../../api/jobs';
import { getUsers } from '../../../api/auth';
import type { JobResponse, JobUpdate, JobPriority, JobType } from '../../../lib/types';

interface EditJobModalProps {
  isOpen: boolean;
  onClose: () => void;
  job: JobResponse;
  onSaved?: () => void;
}

export function EditJobModal({ isOpen, onClose, job, onSaved }: EditJobModalProps) {
  const queryClient = useQueryClient();

  // Pre-fill form with current job data
  const [form, setForm] = useState<JobUpdate>({
    job_name: job.job_name,
    customer_name: job.customer_name,
    address_line1: job.address_line1 ?? '',
    address_line2: job.address_line2 ?? '',
    city: job.city ?? '',
    state: job.state ?? '',
    zip: job.zip ?? '',
    gps_lat: job.gps_lat ?? undefined,
    gps_lng: job.gps_lng ?? undefined,
    priority: job.priority,
    job_type: job.job_type,
    bill_rate_type_id: job.bill_rate_type_id ?? undefined,
    lead_user_id: job.lead_user_id ?? undefined,
    start_date: job.start_date ?? '',
    due_date: job.due_date ?? '',
    notes: job.notes ?? '',
  });
  const [errorMsg, setErrorMsg] = useState('');

  // Fetch users for lead assignment dropdown
  const { data: users } = useQuery({
    queryKey: ['users-list'],
    queryFn: getUsers,
    staleTime: 60_000,
  });

  // Fetch bill rate types for dropdown
  const { data: billRateTypes } = useQuery({
    queryKey: ['bill-rate-types'],
    queryFn: () => getBillRateTypes(),
    staleTime: 60_000,
  });

  // Reset form when job changes (e.g., modal re-opened)
  useEffect(() => {
    setForm({
      job_name: job.job_name,
      customer_name: job.customer_name,
      address_line1: job.address_line1 ?? '',
      address_line2: job.address_line2 ?? '',
      city: job.city ?? '',
      state: job.state ?? '',
      zip: job.zip ?? '',
      gps_lat: job.gps_lat ?? undefined,
      gps_lng: job.gps_lng ?? undefined,
      priority: job.priority,
      job_type: job.job_type,
      bill_rate_type_id: job.bill_rate_type_id ?? undefined,
      lead_user_id: job.lead_user_id ?? undefined,
      start_date: job.start_date ?? '',
      due_date: job.due_date ?? '',
      notes: job.notes ?? '',
    });
    setErrorMsg('');
  }, [job, isOpen]);

  const saveMutation = useMutation({
    mutationFn: (data: JobUpdate) => updateJob(job.id, data),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['job-detail', job.id] });
      queryClient.invalidateQueries({ queryKey: ['jobs-active'] });
      queryClient.invalidateQueries({ queryKey: ['jobs-all'] });
      onSaved?.();
      onClose();
    },
    onError: (err: Error) => setErrorMsg(err.message || 'Failed to save changes'),
  });

  const handleSubmit = (e: React.FormEvent) => {
    e.preventDefault();
    if (!form.job_name?.trim() || !form.customer_name?.trim()) {
      setErrorMsg('Job name and customer are required.');
      return;
    }
    setErrorMsg('');
    saveMutation.mutate(form);
  };

  const update = (field: keyof JobUpdate, value: string | number | undefined) =>
    setForm((prev) => ({ ...prev, [field]: value }));

  return (
    <Modal isOpen={isOpen} onClose={onClose} title={`Edit Job #${job.job_number}`} size="lg">
      {errorMsg && (
        <div className="mb-4 p-3 bg-red-50 dark:bg-red-900/20 border border-red-200 dark:border-red-800 rounded-lg">
          <p className="text-sm text-red-600 dark:text-red-400">{errorMsg}</p>
        </div>
      )}

      <form onSubmit={handleSubmit} className="space-y-4">
        {/* Name + Customer */}
        <div className="grid grid-cols-2 gap-3">
          <Input
            label="Job Name"
            value={form.job_name ?? ''}
            onChange={(e) => update('job_name', e.target.value)}
            required
          />
          <Input
            label="Customer Name"
            value={form.customer_name ?? ''}
            onChange={(e) => update('customer_name', e.target.value)}
            required
          />
        </div>

        {/* Address */}
        <Input
          label="Address Line 1"
          value={form.address_line1 ?? ''}
          onChange={(e) => update('address_line1', e.target.value)}
          placeholder="123 Main St"
        />

        <Input
          label="Address Line 2"
          value={form.address_line2 ?? ''}
          onChange={(e) => update('address_line2', e.target.value)}
          placeholder="Suite, Apt, etc."
        />

        <div className="grid grid-cols-3 gap-3">
          <Input
            label="City"
            value={form.city ?? ''}
            onChange={(e) => update('city', e.target.value)}
          />
          <Input
            label="State"
            value={form.state ?? ''}
            onChange={(e) => update('state', e.target.value)}
          />
          <Input
            label="ZIP"
            value={form.zip ?? ''}
            onChange={(e) => update('zip', e.target.value)}
          />
        </div>

        {/* Type + Priority */}
        <div className="grid grid-cols-2 gap-3">
          <div>
            <label className="block text-sm font-medium text-gray-700 dark:text-gray-300 mb-1">
              Job Type
            </label>
            <select
              value={form.job_type ?? 'service'}
              onChange={(e) => update('job_type', e.target.value)}
              className="w-full rounded-lg border border-border bg-surface px-3 py-2 text-sm"
            >
              <option value="service">Service</option>
              <option value="new_construction">New Construction</option>
              <option value="remodel">Remodel</option>
              <option value="maintenance">Maintenance</option>
              <option value="emergency">Emergency</option>
            </select>
          </div>
          <div>
            <label className="block text-sm font-medium text-gray-700 dark:text-gray-300 mb-1">
              Priority
            </label>
            <select
              value={form.priority ?? 'normal'}
              onChange={(e) => update('priority', e.target.value)}
              className="w-full rounded-lg border border-border bg-surface px-3 py-2 text-sm"
            >
              <option value="low">Low</option>
              <option value="normal">Normal</option>
              <option value="high">High</option>
              <option value="urgent">Urgent</option>
            </select>
          </div>
        </div>

        {/* Lead Technician + Bill Rate Type */}
        <div className="grid grid-cols-2 gap-3">
          <div>
            <label className="block text-sm font-medium text-gray-700 dark:text-gray-300 mb-1">
              Lead Technician
            </label>
            <select
              value={form.lead_user_id ?? ''}
              onChange={(e) => update('lead_user_id', e.target.value ? Number(e.target.value) : undefined)}
              className="w-full rounded-lg border border-border bg-surface px-3 py-2 text-sm"
            >
              <option value="">— Unassigned —</option>
              {users?.map((u) => (
                <option key={u.id} value={u.id}>{u.display_name}</option>
              ))}
            </select>
          </div>
          <div>
            <label className="block text-sm font-medium text-gray-700 dark:text-gray-300 mb-1">
              Bill Rate Type
            </label>
            <select
              value={form.bill_rate_type_id ?? ''}
              onChange={(e) => update('bill_rate_type_id', e.target.value ? Number(e.target.value) : undefined)}
              className="w-full rounded-lg border border-border bg-surface px-3 py-2 text-sm"
            >
              <option value="">— None —</option>
              {billRateTypes?.map((t) => (
                <option key={t.id} value={t.id}>{t.name}</option>
              ))}
            </select>
          </div>
        </div>

        {/* Dates */}
        <div className="grid grid-cols-2 gap-3">
          <Input
            label="Start Date"
            type="date"
            value={form.start_date ?? ''}
            onChange={(e) => update('start_date', e.target.value)}
          />
          <Input
            label="Due Date"
            type="date"
            value={form.due_date ?? ''}
            onChange={(e) => update('due_date', e.target.value)}
          />
        </div>

        {/* Notes */}
        <div>
          <label className="block text-sm font-medium text-gray-700 dark:text-gray-300 mb-1">Notes</label>
          <textarea
            value={form.notes ?? ''}
            onChange={(e) => update('notes', e.target.value)}
            placeholder="Optional notes..."
            rows={3}
            className="w-full rounded-lg border border-border bg-surface px-3 py-2 text-sm resize-none"
          />
        </div>

        {/* Actions */}
        <div className="flex justify-end gap-2 pt-2">
          <Button variant="secondary" onClick={onClose}>Cancel</Button>
          <Button type="submit" isLoading={saveMutation.isPending}>
            Save Changes
          </Button>
        </div>
      </form>
    </Modal>
  );
}
