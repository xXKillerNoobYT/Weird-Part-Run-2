/**
 * DailyDispatchPage — daily workforce dispatch assignment board.
 *
 * Left panel: available employees (not yet dispatched + no time off).
 * Right panel: today's dispatches grouped by job, with status badges.
 * Click-to-assign: select employee → select job → dispatch with conflict warnings.
 * Mobile: stacked layout (dispatches first, then available pool).
 */

import { useState, useMemo } from 'react';
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import {
  Users, Briefcase, Plus, AlertTriangle, ChevronLeft, ChevronRight,
  Clock, UserCheck, MapPin, Check, XCircle,
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
  getDailyDispatch,
  dispatchEmployee,
  cancelDispatch,
  updateDispatchStatus,
  checkDispatchConflicts,
} from '../../../api/scheduling';
import { getActiveJobs } from '../../../api/jobs';
import type {
  DispatchResponse, ScheduleConflict,
  DispatchRoleOnJob, DispatchStatus,
} from '../../../lib/types';


// ── Helpers ───────────────────────────────────────────────────────

function isoDate(d: Date): string {
  return d.toISOString().slice(0, 10);
}

function addDays(d: Date, n: number): Date {
  const dt = new Date(d);
  dt.setDate(dt.getDate() + n);
  return dt;
}

const ROLE_LABELS: Record<DispatchRoleOnJob, string> = {
  lead: 'Lead', worker: 'Worker', apprentice: 'Apprentice', helper: 'Helper', supervisor: 'Supervisor',
};

const ROLE_COLORS: Record<DispatchRoleOnJob, string> = {
  lead: 'bg-indigo-100 text-indigo-700 dark:bg-indigo-900/30 dark:text-indigo-300',
  worker: 'bg-gray-100 text-gray-700 dark:bg-gray-700 dark:text-gray-300',
  apprentice: 'bg-green-100 text-green-700 dark:bg-green-900/30 dark:text-green-300',
  helper: 'bg-cyan-100 text-cyan-700 dark:bg-cyan-900/30 dark:text-cyan-300',
  supervisor: 'bg-amber-100 text-amber-700 dark:bg-amber-900/30 dark:text-amber-300',
};

const STATUS_BADGE: Record<DispatchStatus, 'success' | 'warning' | 'danger' | 'info' | 'neutral'> = {
  scheduled: 'neutral',
  confirmed: 'info',
  on_site: 'info',
  completed: 'success',
  no_show: 'danger',
  cancelled: 'danger',
};



// ═══════════════════════════════════════════════════════════════════
// MAIN PAGE
// ═══════════════════════════════════════════════════════════════════

export function DailyDispatchPage() {
  const queryClient = useQueryClient();
  const { hasPermission } = useAuthStore();
  const canDispatch = hasPermission(PERMISSIONS.DISPATCH_EMPLOYEES);

  // ── State ────────────────────────────────────────────────────────
  const [selectedDate, setSelectedDate] = useState(() => new Date());
  const [showDispatchModal, setShowDispatchModal] = useState(false);
  const [selectedEmployee, setSelectedEmployee] = useState<{ id: number; display_name: string } | null>(null);

  const dateStr = isoDate(selectedDate);

  // ── Data ─────────────────────────────────────────────────────────
  const { data: daily, isLoading } = useQuery({
    queryKey: ['daily-dispatch', dateStr],
    queryFn: () => getDailyDispatch(dateStr),
    staleTime: 15_000,
  });

  // Group dispatches by job
  const dispatchesByJob = useMemo(() => {
    if (!daily?.dispatches) return new Map<number, DispatchResponse[]>();
    const map = new Map<number, DispatchResponse[]>();
    for (const d of daily.dispatches) {
      if (d.status === 'cancelled') continue; // hide cancelled from main view
      const existing = map.get(d.job_id) ?? [];
      existing.push(d);
      map.set(d.job_id, existing);
    }
    return map;
  }, [daily]);

  const activeDispatches = daily?.dispatches.filter(d => d.status !== 'cancelled') ?? [];
  const availableEmployees = daily?.available_employees ?? [];

  // ── Mutations ────────────────────────────────────────────────────
  const cancelMut = useMutation({
    mutationFn: cancelDispatch,
    onSuccess: () => queryClient.invalidateQueries({ queryKey: ['daily-dispatch', dateStr] }),
  });

  const statusMut = useMutation({
    mutationFn: ({ id, status }: { id: number; status: string }) => updateDispatchStatus(id, status),
    onSuccess: () => queryClient.invalidateQueries({ queryKey: ['daily-dispatch', dateStr] }),
  });

  // ── Nav ──────────────────────────────────────────────────────────
  function prevDay() { setSelectedDate(addDays(selectedDate, -1)); }
  function nextDay() { setSelectedDate(addDays(selectedDate, 1)); }
  function goToday() { setSelectedDate(new Date()); }

  function openDispatch(emp: { id: number; display_name: string }) {
    setSelectedEmployee(emp);
    setShowDispatchModal(true);
  }

  if (isLoading) return <PageSpinner />;

  return (
    <div className="space-y-4">
      {/* ── Header ──────────────────────────────────────────────── */}
      <div className="flex items-center justify-between flex-wrap gap-3">
        <div>
          <h1 className="text-xl font-bold text-gray-900 dark:text-white">
            Daily Dispatch
          </h1>
          <p className="text-sm text-gray-500 dark:text-gray-400">
            {selectedDate.toLocaleDateString('en-US', { weekday: 'long', month: 'long', day: 'numeric', year: 'numeric' })}
            &nbsp;&middot; {activeDispatches.length} dispatched, {availableEmployees.length} available
          </p>
        </div>

        <div className="flex items-center gap-2">
          <Button size="sm" variant="secondary" onClick={prevDay}>
            <ChevronLeft size={16} />
          </Button>
          <Button size="sm" variant="secondary" onClick={goToday}>
            Today
          </Button>
          <Button size="sm" variant="secondary" onClick={nextDay}>
            <ChevronRight size={16} />
          </Button>
        </div>
      </div>

      {/* ── Two-panel layout ────────────────────────────────────── */}
      <div className="grid grid-cols-1 lg:grid-cols-3 gap-4">

        {/* ─── Available Employees ─────────────────────────────── */}
        <Card className="lg:col-span-1 p-4">
          <div className="flex items-center gap-2 mb-3">
            <Users size={16} className="text-green-600 dark:text-green-400" />
            <h2 className="font-semibold text-gray-900 dark:text-white text-sm">
              Available ({availableEmployees.length})
            </h2>
          </div>

          {availableEmployees.length === 0 ? (
            <EmptyState
              icon={UserCheck}
              title="All assigned"
              description="Every employee is dispatched or off today."
            />
          ) : (
            <div className="space-y-1.5 max-h-[500px] overflow-y-auto">
              {availableEmployees.map(emp => (
                <div
                  key={emp.id}
                  className="flex items-center justify-between p-2 rounded-lg bg-gray-50 dark:bg-gray-800 hover:bg-gray-100 dark:hover:bg-gray-750 transition-colors"
                >
                  <div className="min-w-0">
                    <div className="text-sm font-medium text-gray-900 dark:text-white truncate">
                      {emp.display_name}
                    </div>
                    {emp.hats.length > 0 && (
                      <div className="flex flex-wrap gap-1 mt-0.5">
                        {emp.hats.slice(0, 3).map(h => (
                          <Badge key={h} variant="neutral" className="text-[10px]">{h}</Badge>
                        ))}
                      </div>
                    )}
                  </div>

                  {canDispatch && (
                    <Button
                      size="sm"
                      variant="primary"
                      onClick={() => openDispatch(emp)}
                      className="flex-shrink-0 ml-2"
                    >
                      <Plus size={14} />
                      <span className="hidden sm:inline ml-1">Assign</span>
                    </Button>
                  )}
                </div>
              ))}
            </div>
          )}
        </Card>

        {/* ─── Dispatches by Job ───────────────────────────────── */}
        <Card className="lg:col-span-2 p-4">
          <div className="flex items-center gap-2 mb-3">
            <Briefcase size={16} className="text-blue-600 dark:text-blue-400" />
            <h2 className="font-semibold text-gray-900 dark:text-white text-sm">
              Dispatches ({activeDispatches.length})
            </h2>
          </div>

          {dispatchesByJob.size === 0 ? (
            <EmptyState
              icon={MapPin}
              title="No dispatches"
              description="No employees dispatched for this date yet."
            />
          ) : (
            <div className="space-y-4 max-h-[500px] overflow-y-auto">
              {Array.from(dispatchesByJob.entries()).map(([jobId, dispatches]) => (
                <div key={jobId} className="border border-gray-200 dark:border-gray-700 rounded-lg p-3">
                  {/* Job header */}
                  <div className="flex items-center gap-2 mb-2">
                    <Briefcase size={14} className="text-gray-400 dark:text-gray-500" />
                    <span className="font-medium text-sm text-gray-900 dark:text-white">
                      {dispatches[0]?.job_name ?? `Job #${jobId}`}
                    </span>
                    <Badge variant="info" className="text-[10px]">
                      {dispatches.length} worker{dispatches.length !== 1 ? 's' : ''}
                    </Badge>
                  </div>

                  {/* Employee rows */}
                  <div className="space-y-1.5">
                    {dispatches.map(d => (
                      <div
                        key={d.id}
                        className="flex items-center justify-between p-2 rounded bg-gray-50 dark:bg-gray-800"
                      >
                        <div className="min-w-0 flex-1">
                          <div className="flex items-center gap-2">
                            <span className="text-sm font-medium text-gray-900 dark:text-white truncate">
                              {d.user_name ?? `User #${d.user_id}`}
                            </span>
                            <span className={`inline-flex items-center px-1.5 py-0.5 rounded text-[10px] font-medium ${ROLE_COLORS[d.role_on_job] ?? ''}`}>
                              {ROLE_LABELS[d.role_on_job] ?? d.role_on_job}
                            </span>
                            <Badge variant={STATUS_BADGE[d.status]} className="text-[10px]">
                              {d.status.replace(/_/g, ' ')}
                            </Badge>
                          </div>
                          {(d.shift_start || d.shift_end) && (
                            <div className="flex items-center gap-1 text-xs text-gray-500 dark:text-gray-400 mt-0.5">
                              <Clock size={10} />
                              {d.shift_start ?? '—'} – {d.shift_end ?? '—'}
                              {(d.lunch_start || d.lunch_end) && (
                                <span className="ml-1 text-gray-400 dark:text-gray-500">
                                  (lunch {d.lunch_start ?? '—'}–{d.lunch_end ?? '—'})
                                </span>
                              )}
                            </div>
                          )}
                        </div>

                        {canDispatch && d.status !== 'completed' && d.status !== 'cancelled' && (
                          <div className="flex items-center gap-1 ml-2 flex-shrink-0">
                            {/* Quick status updates */}
                            {d.status === 'scheduled' && (
                              <Button
                                size="sm"
                                variant="secondary"
                                onClick={() => statusMut.mutate({ id: d.id, status: 'confirmed' })}
                                title="Confirm"
                              >
                                <Check size={12} />
                              </Button>
                            )}
                            {d.status === 'confirmed' && (
                              <Button
                                size="sm"
                                variant="secondary"
                                onClick={() => statusMut.mutate({ id: d.id, status: 'on_site' })}
                                title="On Site"
                              >
                                <MapPin size={12} />
                              </Button>
                            )}
                            {d.status === 'on_site' && (
                              <Button
                                size="sm"
                                variant="success"
                                onClick={() => statusMut.mutate({ id: d.id, status: 'completed' })}
                                title="Complete"
                              >
                                <Check size={12} />
                              </Button>
                            )}
                            <Button
                              size="sm"
                              variant="danger"
                              onClick={() => cancelMut.mutate(d.id)}
                              title="Cancel dispatch"
                            >
                              <XCircle size={12} />
                            </Button>
                          </div>
                        )}
                      </div>
                    ))}
                  </div>
                </div>
              ))}
            </div>
          )}
        </Card>
      </div>

      {/* ── Dispatch Modal ──────────────────────────────────────── */}
      {showDispatchModal && selectedEmployee && (
        <DispatchModal
          employee={selectedEmployee}
          date={dateStr}
          onClose={() => { setShowDispatchModal(false); setSelectedEmployee(null); }}
          onSuccess={() => {
            setShowDispatchModal(false);
            setSelectedEmployee(null);
            queryClient.invalidateQueries({ queryKey: ['daily-dispatch', dateStr] });
          }}
        />
      )}
    </div>
  );
}


// ═══════════════════════════════════════════════════════════════════
// DISPATCH MODAL — assign employee to job
// ═══════════════════════════════════════════════════════════════════

function DispatchModal({
  employee,
  date,
  onClose,
  onSuccess,
}: {
  employee: { id: number; display_name: string };
  date: string;
  onClose: () => void;
  onSuccess: () => void;
}) {
  const [jobId, setJobId] = useState<number | null>(null);
  const [role, setRole] = useState<DispatchRoleOnJob>('worker');
  const [shiftStart, setShiftStart] = useState('07:00');
  const [shiftEnd, setShiftEnd] = useState('15:30');
  const [lunchStart, setLunchStart] = useState('');
  const [lunchEnd, setLunchEnd] = useState('');
  const [notes, setNotes] = useState('');
  const [conflicts, setConflicts] = useState<ScheduleConflict[]>([]);
  const [saving, setSaving] = useState(false);

  // Load active jobs for the selector
  const { data: jobs } = useQuery({
    queryKey: ['active-jobs'],
    queryFn: () => getActiveJobs(),
    staleTime: 60_000,
  });

  // Check conflicts on mount
  const { data: initialConflicts } = useQuery({
    queryKey: ['dispatch-conflicts', employee.id, date],
    queryFn: () => checkDispatchConflicts(employee.id, date),
    staleTime: 30_000,
  });

  const displayConflicts = conflicts.length > 0 ? conflicts : (initialConflicts ?? []);

  async function handleSubmit(e: React.FormEvent) {
    e.preventDefault();
    if (!jobId) return;

    setSaving(true);
    try {
      const result = await dispatchEmployee({
        job_id: jobId,
        user_id: employee.id,
        dispatch_date: date,
        shift_start: shiftStart || undefined,
        shift_end: shiftEnd || undefined,
        lunch_start: lunchStart || undefined,
        lunch_end: lunchEnd || undefined,
        role_on_job: role,
        notes: notes || undefined,
      });
      if (result.conflicts?.length > 0) {
        setConflicts(result.conflicts);
      }
      onSuccess();
    } catch (err) {
      console.error('Dispatch failed:', err);
    } finally {
      setSaving(false);
    }
  }

  return (
    <Modal isOpen onClose={onClose} title="Dispatch Employee">
      <form onSubmit={handleSubmit} className="space-y-4">
        {/* Employee info */}
        <div className="bg-blue-50 dark:bg-blue-900/20 rounded-lg p-3">
          <div className="text-sm font-medium text-blue-700 dark:text-blue-300">
            {employee.display_name}
          </div>
          <div className="text-xs text-blue-600 dark:text-blue-400">
            Dispatching for {new Date(date + 'T00:00').toLocaleDateString('en-US', {
              weekday: 'long', month: 'long', day: 'numeric',
            })}
          </div>
        </div>

        {/* Today's Assignments — existing dispatches for this employee */}
        {displayConflicts.filter(c => c.conflict_type === 'already_dispatched').length > 0 && (
          <div className="bg-blue-50 dark:bg-blue-900/20 border border-blue-200 dark:border-blue-800 rounded-lg p-3">
            <div className="flex items-center gap-1.5 text-blue-700 dark:text-blue-300 text-sm font-medium mb-1.5">
              <Briefcase size={14} />
              Today's Assignments
            </div>
            {displayConflicts.filter(c => c.conflict_type === 'already_dispatched').map((c, i) => (
              <div key={i} className="flex items-center gap-2 text-xs text-blue-600 dark:text-blue-400 ml-5 mb-1">
                <span className="font-medium">{c.related_job_name ?? 'Unknown job'}</span>
                {c.shift_start && <span className="text-blue-500 dark:text-blue-500">{c.shift_start}–{c.shift_end ?? '?'}</span>}
                {c.role_on_job && (
                  <span className={`inline-flex px-1 py-0.5 rounded text-[10px] font-medium ${ROLE_COLORS[c.role_on_job as DispatchRoleOnJob] ?? 'bg-gray-100 text-gray-600'}`}>
                    {ROLE_LABELS[c.role_on_job as DispatchRoleOnJob] ?? c.role_on_job}
                  </span>
                )}
              </div>
            ))}
          </div>
        )}

        {/* Conflict warnings (non-dispatch: time off, not working day) */}
        {displayConflicts.filter(c => c.conflict_type !== 'already_dispatched').length > 0 && (
          <div className="bg-amber-50 dark:bg-amber-900/20 border border-amber-200 dark:border-amber-800 rounded-lg p-3">
            <div className="flex items-center gap-1.5 text-amber-700 dark:text-amber-300 text-sm font-medium mb-1">
              <AlertTriangle size={14} />
              Scheduling Conflicts
            </div>
            {displayConflicts.filter(c => c.conflict_type !== 'already_dispatched').map((c, i) => (
              <div key={i} className="text-xs text-amber-600 dark:text-amber-400 ml-5">
                &bull; {c.description}
              </div>
            ))}
          </div>
        )}

        {/* Job selector */}
        <div>
          <label className="block text-sm font-medium text-gray-700 dark:text-gray-300 mb-1">
            Job *
          </label>
          <select
            value={jobId ?? ''}
            onChange={e => setJobId(e.target.value ? Number(e.target.value) : null)}
            required
            className="w-full rounded-lg border border-gray-300 dark:border-gray-600 bg-white dark:bg-gray-800 px-3 py-2 text-sm text-gray-900 dark:text-white"
          >
            <option value="">Select a job...</option>
            {jobs?.map(j => (
              <option key={j.id} value={j.id}>
                {j.job_name} ({j.status})
              </option>
            ))}
          </select>
        </div>

        {/* Role */}
        <div>
          <label className="block text-sm font-medium text-gray-700 dark:text-gray-300 mb-1">
            Role on Job
          </label>
          <select
            value={role}
            onChange={e => setRole(e.target.value as DispatchRoleOnJob)}
            className="w-full rounded-lg border border-gray-300 dark:border-gray-600 bg-white dark:bg-gray-800 px-3 py-2 text-sm text-gray-900 dark:text-white"
          >
            {Object.entries(ROLE_LABELS).map(([val, label]) => (
              <option key={val} value={val}>{label}</option>
            ))}
          </select>
        </div>

        {/* Shift times */}
        <div className="grid grid-cols-2 gap-3">
          <div>
            <label className="block text-sm font-medium text-gray-700 dark:text-gray-300 mb-1">
              Start
            </label>
            <Input
              type="time"
              value={shiftStart}
              onChange={e => setShiftStart(e.target.value)}
            />
          </div>
          <div>
            <label className="block text-sm font-medium text-gray-700 dark:text-gray-300 mb-1">
              End
            </label>
            <Input
              type="time"
              value={shiftEnd}
              onChange={e => setShiftEnd(e.target.value)}
            />
          </div>
        </div>

        {/* Lunch break */}
        <div className="grid grid-cols-2 gap-3">
          <div>
            <label className="block text-sm font-medium text-gray-700 dark:text-gray-300 mb-1">
              Lunch Start
            </label>
            <Input
              type="time"
              value={lunchStart}
              onChange={e => setLunchStart(e.target.value)}
              placeholder="12:00"
            />
          </div>
          <div>
            <label className="block text-sm font-medium text-gray-700 dark:text-gray-300 mb-1">
              Lunch End
            </label>
            <Input
              type="time"
              value={lunchEnd}
              onChange={e => setLunchEnd(e.target.value)}
              placeholder="12:30"
            />
          </div>
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
            placeholder="Optional dispatch notes..."
          />
        </div>

        {/* Actions */}
        <div className="flex justify-end gap-2 pt-2">
          <Button type="button" variant="secondary" onClick={onClose}>
            Cancel
          </Button>
          <Button type="submit" variant="primary" disabled={saving || !jobId}>
            {saving ? 'Dispatching...' : 'Dispatch'}
          </Button>
        </div>
      </form>
    </Modal>
  );
}
