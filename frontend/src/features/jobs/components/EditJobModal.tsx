/**
 * EditJobModal — modal dialog for editing an existing job's details.
 *
 * Pre-fills all fields from the current job data. Uses the PUT /api/jobs/:id
 * endpoint via updateJob(). Only sends changed fields (JobUpdate type).
 *
 * When the status is "on_call", shows a sub-type selector (On Call vs Warranty)
 * with warranty date fields and a recalculate button for the end date.
 *
 * Also used from the Office > Manage Jobs page for admin editing.
 */

import { useState, useEffect, useMemo } from 'react';
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query';
import { RotateCcw } from 'lucide-react';
import { Modal } from '../../../components/ui/Modal';
import { Button } from '../../../components/ui/Button';
import { Input } from '../../../components/ui/Input';
import { updateJob, getBillRateTypes } from '../../../api/jobs';
import { getUsers } from '../../../api/auth';
import { getWarrantyLengthDays } from '../../../api/settings';
import type { JobResponse, JobUpdate, OnCallType } from '../../../lib/types';

interface EditJobModalProps {
  isOpen: boolean;
  onClose: () => void;
  job: JobResponse;
  onSaved?: () => void;
}

/** Calculate end date by adding days to a start date (YYYY-MM-DD). */
function calculateEndDate(startDate: string, days: number): string {
  const d = new Date(startDate + 'T00:00:00');
  d.setDate(d.getDate() + days);
  return d.toISOString().split('T')[0];
}

export function EditJobModal({ isOpen, onClose, job, onSaved }: EditJobModalProps) {
  const queryClient = useQueryClient();

  // Pre-fill form with current job data
  const [form, setForm] = useState<JobUpdate>({
    job_name: job.job_name,
    customer_name: job.customer_name,
    status: job.status,
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
    on_call_type: job.on_call_type ?? undefined,
    warranty_start_date: job.warranty_start_date ?? '',
    warranty_end_date: job.warranty_end_date ?? '',
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

  // Fetch global warranty length setting
  const { data: warrantyDays } = useQuery({
    queryKey: ['warranty-length-days'],
    queryFn: getWarrantyLengthDays,
    staleTime: 60_000,
  });

  // Reset form when job changes (e.g., modal re-opened)
  useEffect(() => {
    setForm({
      job_name: job.job_name,
      customer_name: job.customer_name,
      status: job.status,
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
      on_call_type: job.on_call_type ?? undefined,
      warranty_start_date: job.warranty_start_date ?? '',
      warranty_end_date: job.warranty_end_date ?? '',
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

  const update = (field: keyof JobUpdate, value: string | number | undefined | null) =>
    setForm((prev) => ({ ...prev, [field]: value }));

  // ── On Call / Warranty logic ────────────────────────────────────
  const isOnCallStatus = form.status === 'on_call';
  const isWarrantyType = form.on_call_type === 'warranty';
  const defaultDays = warrantyDays ?? 365;

  // Compute what the auto-calculated end date would be
  const autoEndDate = useMemo(() => {
    if (form.warranty_start_date) {
      return calculateEndDate(form.warranty_start_date, defaultDays);
    }
    return '';
  }, [form.warranty_start_date, defaultDays]);

  // Show recalculate button when end date differs from auto-calculated
  const showRecalculate = !!(
    isWarrantyType &&
    form.warranty_start_date &&
    form.warranty_end_date &&
    autoEndDate &&
    form.warranty_end_date !== autoEndDate
  );

  // Handle status change — clear warranty fields when leaving on_call
  const handleStatusChange = (newStatus: string) => {
    update('status', newStatus);
    if (newStatus !== 'on_call') {
      setForm((prev) => ({
        ...prev,
        status: newStatus,
        on_call_type: undefined,
        warranty_start_date: '',
        warranty_end_date: '',
      }));
    }
  };

  // Handle on_call_type change
  const handleOnCallTypeChange = (type: OnCallType) => {
    if (type === 'on_call') {
      // Clear warranty dates when switching to plain on-call
      setForm((prev) => ({
        ...prev,
        on_call_type: 'on_call',
        warranty_start_date: '',
        warranty_end_date: '',
      }));
    } else {
      // Switch to warranty — set start to today if empty
      const today = new Date().toISOString().split('T')[0];
      const startDate = form.warranty_start_date || today;
      const endDate = calculateEndDate(startDate, defaultDays);
      setForm((prev) => ({
        ...prev,
        on_call_type: 'warranty',
        warranty_start_date: startDate,
        warranty_end_date: endDate,
      }));
    }
  };

  // Handle warranty start date change — auto-calculate end date
  const handleWarrantyStartChange = (startDate: string) => {
    const endDate = startDate ? calculateEndDate(startDate, defaultDays) : '';
    setForm((prev) => ({
      ...prev,
      warranty_start_date: startDate,
      warranty_end_date: endDate,
    }));
  };

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

        {/* Status + Type + Priority */}
        <div className="grid grid-cols-3 gap-3">
          <div>
            <label className="block text-sm font-medium text-gray-700 dark:text-gray-300 mb-1">
              Status
            </label>
            <select
              value={form.status ?? 'active'}
              onChange={(e) => handleStatusChange(e.target.value)}
              className="w-full rounded-lg border border-border bg-surface px-3 py-2 text-sm"
            >
              <option value="pending">Pending</option>
              <option value="active">Active</option>
              <option value="on_hold">On Hold</option>
              <option value="continuous_maintenance">Cont. Maintenance</option>
              <option value="on_call">On Call / Warranty</option>
              <option value="completed">Completed</option>
              <option value="cancelled">Cancelled</option>
            </select>
          </div>
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

        {/* On Call / Warranty sub-type selector — only visible when status is on_call */}
        {isOnCallStatus && (
          <div className="p-3 bg-sky-50 dark:bg-sky-900/20 border border-sky-200 dark:border-sky-800 rounded-lg space-y-3">
            <label className="block text-sm font-medium text-sky-800 dark:text-sky-300">
              On Call Sub-type
            </label>
            <div className="flex gap-2">
              <button
                type="button"
                onClick={() => handleOnCallTypeChange('on_call')}
                className={`flex-1 px-3 py-2 rounded-lg text-sm font-medium border transition-colors ${
                  !isWarrantyType
                    ? 'bg-sky-600 text-white border-sky-600'
                    : 'bg-surface border-border text-gray-700 dark:text-gray-300 hover:bg-sky-50 dark:hover:bg-sky-900/10'
                }`}
              >
                On Call
                <span className="block text-xs font-normal mt-0.5 opacity-80">
                  Indefinite standby
                </span>
              </button>
              <button
                type="button"
                onClick={() => handleOnCallTypeChange('warranty')}
                className={`flex-1 px-3 py-2 rounded-lg text-sm font-medium border transition-colors ${
                  isWarrantyType
                    ? 'bg-sky-600 text-white border-sky-600'
                    : 'bg-surface border-border text-gray-700 dark:text-gray-300 hover:bg-sky-50 dark:hover:bg-sky-900/10'
                }`}
              >
                Warranty
                <span className="block text-xs font-normal mt-0.5 opacity-80">
                  Time-bounded coverage
                </span>
              </button>
            </div>

            {/* Warranty date fields */}
            {isWarrantyType && (
              <div className="space-y-3 pt-1">
                <div className="grid grid-cols-2 gap-3">
                  <Input
                    label="Warranty Start"
                    type="date"
                    value={form.warranty_start_date ?? ''}
                    onChange={(e) => handleWarrantyStartChange(e.target.value)}
                  />
                  <div>
                    <Input
                      label="Warranty End"
                      type="date"
                      value={form.warranty_end_date ?? ''}
                      onChange={(e) => update('warranty_end_date', e.target.value)}
                    />
                  </div>
                </div>

                {/* Recalculate button — bright & prominent when end date was manually changed */}
                {showRecalculate && (
                  <button
                    type="button"
                    onClick={() => update('warranty_end_date', autoEndDate)}
                    className="w-full flex items-center justify-center gap-2 px-4 py-2.5 rounded-lg text-sm font-semibold bg-amber-500 hover:bg-amber-600 text-white shadow-sm transition-colors"
                  >
                    <RotateCcw className="h-4 w-4" />
                    Recalculate End Date ({defaultDays} days from start)
                  </button>
                )}

                {/* Info about the default warranty length */}
                <p className="text-xs text-sky-600 dark:text-sky-400">
                  Default warranty: {defaultDays} days (change in Settings &gt; App Config)
                </p>
              </div>
            )}
          </div>
        )}

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
