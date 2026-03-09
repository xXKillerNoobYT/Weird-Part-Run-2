/**
 * SubSchedulePage — subcontractor scheduling for job sites.
 *
 * Job-centric view: select a job → see/add/edit subcontractor visits.
 * Each visit = a GC coming to our job site on a specific date with
 * arrival/departure times, work description, and status.
 */

import { useState } from 'react';
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import {
  HardHat, Plus, Clock, X, Check, AlertTriangle,
  Briefcase,
} from 'lucide-react';
import { PageSpinner } from '../../../components/ui/Spinner';
import { EmptyState } from '../../../components/ui/EmptyState';
import { Badge } from '../../../components/ui/Badge';
import { Button } from '../../../components/ui/Button';
import { Input } from '../../../components/ui/Input';
import { Modal } from '../../../components/ui/Modal';
import { Card } from '../../../components/ui/Card';
import { useAuthStore } from '../../../stores/auth-store';
import { PERMISSIONS } from '../../../lib/constants';
import {
  getJobSubSchedules,
  scheduleSubcontractor,
  updateSubSchedule,
  cancelSubSchedule,
} from '../../../api/scheduling';
import { getActiveJobs } from '../../../api/jobs';
import { searchGCs } from '../../../api/contacts';
import type {
  SubScheduleResponse, SubScheduleUpdate,
  SubScheduleStatus,
} from '../../../lib/types';


// ── Constants ─────────────────────────────────────────────────────

const STATUS_LABELS: Record<SubScheduleStatus, string> = {
  scheduled: 'Scheduled',
  confirmed: 'Confirmed',
  on_site: 'On Site',
  completed: 'Completed',
  cancelled: 'Cancelled',
  no_show: 'No Show',
};

const STATUS_BADGE: Record<SubScheduleStatus, 'success' | 'warning' | 'danger' | 'info' | 'neutral'> = {
  scheduled: 'neutral',
  confirmed: 'info',
  on_site: 'info',
  completed: 'success',
  cancelled: 'danger',
  no_show: 'danger',
};


// ═══════════════════════════════════════════════════════════════════
// MAIN PAGE
// ═══════════════════════════════════════════════════════════════════

export function SubSchedulePage() {
  const queryClient = useQueryClient();
  const { hasPermission } = useAuthStore();
  const canDispatch = hasPermission(PERMISSIONS.DISPATCH_EMPLOYEES);

  // ── State ────────────────────────────────────────────────────────
  const [selectedJobId, setSelectedJobId] = useState<number | null>(null);
  const [showCreateModal, setShowCreateModal] = useState(false);
  const [editingEntry, setEditingEntry] = useState<SubScheduleResponse | null>(null);

  // ── Jobs list ────────────────────────────────────────────────────
  const { data: jobs } = useQuery({
    queryKey: ['active-jobs', 'sub-schedule'],
    queryFn: () => getActiveJobs(),
    staleTime: 60_000,
  });

  // ── Sub schedules for selected job ───────────────────────────────
  const { data: schedules, isLoading: schedulesLoading } = useQuery({
    queryKey: ['sub-schedules', selectedJobId],
    queryFn: () => getJobSubSchedules(selectedJobId!),
    enabled: !!selectedJobId,
    staleTime: 30_000,
  });

  // ── Mutations ────────────────────────────────────────────────────
  const cancelMut = useMutation({
    mutationFn: cancelSubSchedule,
    onSuccess: () => queryClient.invalidateQueries({ queryKey: ['sub-schedules', selectedJobId] }),
  });

  const statusMut = useMutation({
    mutationFn: ({ id, updates }: { id: number; updates: SubScheduleUpdate }) =>
      updateSubSchedule(id, updates),
    onSuccess: () => queryClient.invalidateQueries({ queryKey: ['sub-schedules', selectedJobId] }),
  });

  const activeSchedules = (schedules ?? []).filter(s => s.status !== 'cancelled');

  return (
    <div className="space-y-4">
      {/* ── Header ──────────────────────────────────────────────── */}
      <div className="flex items-center justify-between flex-wrap gap-3">
        <div className="flex items-center gap-3">
          <HardHat size={24} className="text-purple-600 dark:text-purple-400" />
          <div>
            <h1 className="text-xl font-bold text-gray-900 dark:text-white">
              Subcontractor Schedule
            </h1>
            <p className="text-sm text-gray-500 dark:text-gray-400">
              Manage GC/sub visits to your job sites
            </p>
          </div>
        </div>

        {selectedJobId && canDispatch && (
          <Button variant="primary" onClick={() => setShowCreateModal(true)}>
            <Plus size={16} />
            <span className="hidden sm:inline ml-1">Schedule Visit</span>
          </Button>
        )}
      </div>

      {/* ── Job selector ────────────────────────────────────────── */}
      <Card className="p-4">
        <label className="block text-sm font-medium text-gray-700 dark:text-gray-300 mb-2">
          Select Job
        </label>
        <select
          value={selectedJobId ?? ''}
          onChange={e => setSelectedJobId(e.target.value ? Number(e.target.value) : null)}
          className="w-full rounded-lg border border-gray-300 dark:border-gray-600 bg-white dark:bg-gray-800 px-3 py-2 text-sm text-gray-900 dark:text-white"
        >
          <option value="">Choose a job...</option>
          {jobs?.map(j => (
            <option key={j.id} value={j.id}>
              {j.job_name} ({j.status})
            </option>
          ))}
        </select>
      </Card>

      {/* ── Schedule list ───────────────────────────────────────── */}
      {!selectedJobId ? (
        <EmptyState
          icon={Briefcase}
          title="Select a job"
          description="Choose a job above to view and manage subcontractor visits."
        />
      ) : schedulesLoading ? (
        <PageSpinner />
      ) : activeSchedules.length === 0 ? (
        <EmptyState
          icon={HardHat}
          title="No scheduled visits"
          description="No subcontractor visits scheduled for this job."
        />
      ) : (
        <div className="space-y-2">
          {activeSchedules
            .sort((a, b) => a.scheduled_date.localeCompare(b.scheduled_date))
            .map(entry => (
              <SubEntryCard
                key={entry.id}
                entry={entry}
                canManage={canDispatch}
                onStatusChange={(status) =>
                  statusMut.mutate({ id: entry.id, updates: { status } })
                }
                onCancel={() => cancelMut.mutate(entry.id)}
                onEdit={() => setEditingEntry(entry)}
              />
            ))}
        </div>
      )}

      {/* ── Create Modal ────────────────────────────────────────── */}
      {showCreateModal && selectedJobId && (
        <CreateSubScheduleModal
          jobId={selectedJobId}
          onClose={() => setShowCreateModal(false)}
          onSuccess={() => {
            setShowCreateModal(false);
            queryClient.invalidateQueries({ queryKey: ['sub-schedules', selectedJobId] });
          }}
        />
      )}

      {/* ── Edit Modal ──────────────────────────────────────────── */}
      {editingEntry && (
        <EditSubScheduleModal
          entry={editingEntry}
          onClose={() => setEditingEntry(null)}
          onSuccess={() => {
            setEditingEntry(null);
            queryClient.invalidateQueries({ queryKey: ['sub-schedules', selectedJobId] });
          }}
        />
      )}
    </div>
  );
}


// ═══════════════════════════════════════════════════════════════════
// SUB ENTRY CARD
// ═══════════════════════════════════════════════════════════════════

function SubEntryCard({
  entry,
  canManage,
  onStatusChange,
  onCancel,
  onEdit,
}: {
  entry: SubScheduleResponse;
  canManage: boolean;
  onStatusChange: (status: SubScheduleStatus) => void;
  onCancel: () => void;
  onEdit: () => void;
}) {
  const dateDisplay = new Date(entry.scheduled_date + 'T00:00').toLocaleDateString('en-US', {
    weekday: 'short', month: 'short', day: 'numeric', year: 'numeric',
  });

  const isPast = new Date(entry.scheduled_date) < new Date(new Date().toDateString());

  return (
    <Card className="p-3">
      <div className="flex items-start justify-between gap-3">
        <div className="min-w-0 flex-1">
          {/* GC name + date */}
          <div className="flex items-center gap-2 flex-wrap">
            <HardHat size={14} className="text-purple-500 dark:text-purple-400 flex-shrink-0" />
            <span className="font-medium text-sm text-gray-900 dark:text-white">
              {entry.gc_name ?? `GC #${entry.gc_id}`}
            </span>
            <span className="text-sm text-gray-500 dark:text-gray-400">
              {dateDisplay}
            </span>
          </div>

          {/* Status badge */}
          <div className="flex items-center gap-2 mt-1">
            <Badge variant={STATUS_BADGE[entry.status]}>
              {STATUS_LABELS[entry.status]}
            </Badge>
            {isPast && entry.status === 'scheduled' && (
              <Badge variant="warning" className="text-[10px]">
                <AlertTriangle size={10} className="mr-0.5" />
                Past due
              </Badge>
            )}
          </div>

          {/* Time range */}
          {(entry.arrival_time || entry.departure_time) && (
            <div className="flex items-center gap-1 text-xs text-gray-500 dark:text-gray-400 mt-1">
              <Clock size={10} />
              {entry.arrival_time ?? '—'} – {entry.departure_time ?? '—'}
            </div>
          )}

          {/* Work description */}
          {entry.work_description && (
            <p className="text-xs text-gray-600 dark:text-gray-400 mt-1">
              {entry.work_description}
            </p>
          )}

          {/* Notes */}
          {entry.notes && (
            <p className="text-[10px] text-gray-400 dark:text-gray-500 mt-1 italic">
              {entry.notes}
            </p>
          )}
        </div>

        {/* Actions */}
        {canManage && entry.status !== 'completed' && entry.status !== 'cancelled' && (
          <div className="flex items-center gap-1 flex-shrink-0">
            {entry.status === 'scheduled' && (
              <Button
                size="sm"
                variant="secondary"
                onClick={() => onStatusChange('confirmed')}
                title="Confirm"
              >
                <Check size={12} />
              </Button>
            )}
            {entry.status === 'confirmed' && (
              <Button
                size="sm"
                variant="secondary"
                onClick={() => onStatusChange('on_site')}
                title="On Site"
              >
                <HardHat size={12} />
              </Button>
            )}
            {entry.status === 'on_site' && (
              <Button
                size="sm"
                variant="success"
                onClick={() => onStatusChange('completed')}
                title="Complete"
              >
                <Check size={12} />
              </Button>
            )}
            <Button
              size="sm"
              variant="secondary"
              onClick={onEdit}
              title="Edit"
            >
              Edit
            </Button>
            <Button
              size="sm"
              variant="danger"
              onClick={onCancel}
              title="Cancel"
            >
              <X size={12} />
            </Button>
          </div>
        )}
      </div>
    </Card>
  );
}


// ═══════════════════════════════════════════════════════════════════
// CREATE SUB SCHEDULE MODAL
// ═══════════════════════════════════════════════════════════════════

function CreateSubScheduleModal({
  jobId,
  onClose,
  onSuccess,
}: {
  jobId: number;
  onClose: () => void;
  onSuccess: () => void;
}) {
  const [gcId, setGcId] = useState<number | null>(null);
  const [gcSearch, setGcSearch] = useState('');
  const [scheduledDate, setScheduledDate] = useState('');
  const [arrivalTime, setArrivalTime] = useState('');
  const [departureTime, setDepartureTime] = useState('');
  const [workDescription, setWorkDescription] = useState('');
  const [notes, setNotes] = useState('');
  const [saving, setSaving] = useState(false);

  // Search for GCs
  const { data: gcResults } = useQuery({
    queryKey: ['gc-search', gcSearch],
    queryFn: () => searchGCs(gcSearch),
    enabled: gcSearch.length >= 2,
    staleTime: 30_000,
  });

  async function handleSubmit(e: React.FormEvent) {
    e.preventDefault();
    if (!gcId || !scheduledDate) return;

    setSaving(true);
    try {
      await scheduleSubcontractor({
        job_id: jobId,
        gc_id: gcId,
        scheduled_date: scheduledDate,
        arrival_time: arrivalTime || undefined,
        departure_time: departureTime || undefined,
        work_description: workDescription || undefined,
        notes: notes || undefined,
      });
      onSuccess();
    } catch (err) {
      console.error('Schedule subcontractor failed:', err);
    } finally {
      setSaving(false);
    }
  }

  return (
    <Modal isOpen onClose={onClose} title="Schedule Subcontractor Visit">
      <form onSubmit={handleSubmit} className="space-y-4">
        {/* GC selector with search */}
        <div>
          <label className="block text-sm font-medium text-gray-700 dark:text-gray-300 mb-1">
            Contractor *
          </label>
          {gcId ? (
            <div className="flex items-center gap-2 p-2 bg-purple-50 dark:bg-purple-900/20 rounded-lg">
              <HardHat size={14} className="text-purple-600 dark:text-purple-400" />
              <span className="text-sm font-medium text-purple-700 dark:text-purple-300 flex-1">
                {gcResults?.find(g => g.id === gcId)?.company_name ?? `GC #${gcId}`}
              </span>
              <button
                type="button"
                onClick={() => { setGcId(null); setGcSearch(''); }}
                className="text-gray-400 hover:text-gray-600"
              >
                <X size={14} />
              </button>
            </div>
          ) : (
            <>
              <Input
                value={gcSearch}
                onChange={e => setGcSearch(e.target.value)}
                placeholder="Search contractors..."
              />
              {gcResults && gcResults.length > 0 && (
                <div className="mt-1 border border-gray-200 dark:border-gray-700 rounded-lg max-h-40 overflow-y-auto">
                  {gcResults.map(gc => (
                    <button
                      key={gc.id}
                      type="button"
                      onClick={() => { setGcId(gc.id); setGcSearch(gc.company_name); }}
                      className="w-full text-left px-3 py-2 text-sm hover:bg-gray-50 dark:hover:bg-gray-800 transition-colors"
                    >
                      <span className="font-medium text-gray-900 dark:text-white">
                        {gc.company_name}
                      </span>
                      {gc.gc_code && (
                        <span className="text-xs text-gray-500 dark:text-gray-400 ml-2">
                          ({gc.gc_code})
                        </span>
                      )}
                    </button>
                  ))}
                </div>
              )}
              {gcSearch.length >= 2 && gcResults?.length === 0 && (
                <p className="text-xs text-gray-400 dark:text-gray-500 mt-1">
                  No contractors found matching "{gcSearch}"
                </p>
              )}
            </>
          )}
        </div>

        {/* Date */}
        <div>
          <label className="block text-sm font-medium text-gray-700 dark:text-gray-300 mb-1">
            Date *
          </label>
          <Input
            type="date"
            value={scheduledDate}
            onChange={e => setScheduledDate(e.target.value)}
            required
          />
        </div>

        {/* Times */}
        <div className="grid grid-cols-2 gap-3">
          <div>
            <label className="block text-sm font-medium text-gray-700 dark:text-gray-300 mb-1">
              Arrival
            </label>
            <Input
              type="time"
              value={arrivalTime}
              onChange={e => setArrivalTime(e.target.value)}
            />
          </div>
          <div>
            <label className="block text-sm font-medium text-gray-700 dark:text-gray-300 mb-1">
              Departure
            </label>
            <Input
              type="time"
              value={departureTime}
              onChange={e => setDepartureTime(e.target.value)}
            />
          </div>
        </div>

        {/* Work description */}
        <div>
          <label className="block text-sm font-medium text-gray-700 dark:text-gray-300 mb-1">
            Work Description
          </label>
          <textarea
            value={workDescription}
            onChange={e => setWorkDescription(e.target.value)}
            rows={2}
            className="w-full rounded-lg border border-gray-300 dark:border-gray-600 bg-white dark:bg-gray-800 px-3 py-2 text-sm text-gray-900 dark:text-white resize-none"
            placeholder="What work will they be doing?"
          />
        </div>

        {/* Notes */}
        <div>
          <label className="block text-sm font-medium text-gray-700 dark:text-gray-300 mb-1">
            Notes
          </label>
          <textarea
            value={notes}
            onChange={e => setNotes(e.target.value)}
            rows={2}
            className="w-full rounded-lg border border-gray-300 dark:border-gray-600 bg-white dark:bg-gray-800 px-3 py-2 text-sm text-gray-900 dark:text-white resize-none"
            placeholder="Any additional notes..."
          />
        </div>

        {/* Actions */}
        <div className="flex justify-end gap-2 pt-2">
          <Button type="button" variant="secondary" onClick={onClose}>
            Cancel
          </Button>
          <Button type="submit" variant="primary" disabled={saving || !gcId || !scheduledDate}>
            {saving ? 'Scheduling...' : 'Schedule Visit'}
          </Button>
        </div>
      </form>
    </Modal>
  );
}


// ═══════════════════════════════════════════════════════════════════
// EDIT SUB SCHEDULE MODAL
// ═══════════════════════════════════════════════════════════════════

function EditSubScheduleModal({
  entry,
  onClose,
  onSuccess,
}: {
  entry: SubScheduleResponse;
  onClose: () => void;
  onSuccess: () => void;
}) {
  const [scheduledDate, setScheduledDate] = useState(entry.scheduled_date);
  const [arrivalTime, setArrivalTime] = useState(entry.arrival_time ?? '');
  const [departureTime, setDepartureTime] = useState(entry.departure_time ?? '');
  const [workDescription, setWorkDescription] = useState(entry.work_description ?? '');
  const [notes, setNotes] = useState(entry.notes ?? '');
  const [saving, setSaving] = useState(false);

  async function handleSubmit(e: React.FormEvent) {
    e.preventDefault();
    setSaving(true);
    try {
      await updateSubSchedule(entry.id, {
        scheduled_date: scheduledDate,
        arrival_time: arrivalTime || null,
        departure_time: departureTime || null,
        work_description: workDescription || null,
        notes: notes || null,
      });
      onSuccess();
    } catch (err) {
      console.error('Update sub schedule failed:', err);
    } finally {
      setSaving(false);
    }
  }

  return (
    <Modal isOpen onClose={onClose} title="Edit Visit">
      <form onSubmit={handleSubmit} className="space-y-4">
        {/* GC info (read-only) */}
        <div className="bg-purple-50 dark:bg-purple-900/20 rounded-lg p-3">
          <div className="text-sm font-medium text-purple-700 dark:text-purple-300">
            {entry.gc_name ?? `GC #${entry.gc_id}`}
          </div>
        </div>

        {/* Date */}
        <div>
          <label className="block text-sm font-medium text-gray-700 dark:text-gray-300 mb-1">
            Date
          </label>
          <Input
            type="date"
            value={scheduledDate}
            onChange={e => setScheduledDate(e.target.value)}
            required
          />
        </div>

        {/* Times */}
        <div className="grid grid-cols-2 gap-3">
          <div>
            <label className="block text-sm font-medium text-gray-700 dark:text-gray-300 mb-1">
              Arrival
            </label>
            <Input
              type="time"
              value={arrivalTime}
              onChange={e => setArrivalTime(e.target.value)}
            />
          </div>
          <div>
            <label className="block text-sm font-medium text-gray-700 dark:text-gray-300 mb-1">
              Departure
            </label>
            <Input
              type="time"
              value={departureTime}
              onChange={e => setDepartureTime(e.target.value)}
            />
          </div>
        </div>

        {/* Work description */}
        <div>
          <label className="block text-sm font-medium text-gray-700 dark:text-gray-300 mb-1">
            Work Description
          </label>
          <textarea
            value={workDescription}
            onChange={e => setWorkDescription(e.target.value)}
            rows={2}
            className="w-full rounded-lg border border-gray-300 dark:border-gray-600 bg-white dark:bg-gray-800 px-3 py-2 text-sm text-gray-900 dark:text-white resize-none"
          />
        </div>

        {/* Notes */}
        <div>
          <label className="block text-sm font-medium text-gray-700 dark:text-gray-300 mb-1">
            Notes
          </label>
          <textarea
            value={notes}
            onChange={e => setNotes(e.target.value)}
            rows={2}
            className="w-full rounded-lg border border-gray-300 dark:border-gray-600 bg-white dark:bg-gray-800 px-3 py-2 text-sm text-gray-900 dark:text-white resize-none"
          />
        </div>

        {/* Actions */}
        <div className="flex justify-end gap-2 pt-2">
          <Button type="button" variant="secondary" onClick={onClose}>
            Cancel
          </Button>
          <Button type="submit" variant="primary" disabled={saving}>
            {saving ? 'Saving...' : 'Save Changes'}
          </Button>
        </div>
      </form>
    </Modal>
  );
}
