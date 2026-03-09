/**
 * DispatchTemplatesPage — manage recurring dispatch templates.
 *
 * Templates define a crew (set of employees), a job, and which days of the week
 * they work. Users can "apply" a template to a date range to bulk-generate
 * dispatch records.
 */

import { useState } from 'react';
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import {
  Repeat, Plus, Play, Trash2, Edit2, Users, Briefcase,
} from 'lucide-react';
import { PageSpinner } from '../../../components/ui/Spinner';
import { EmptyState } from '../../../components/ui/EmptyState';
import { Badge } from '../../../components/ui/Badge';
import { Button } from '../../../components/ui/Button';
import { Input } from '../../../components/ui/Input';
import { Modal } from '../../../components/ui/Modal';
import { Card } from '../../../components/ui/Card';
import { toast } from '../../../lib/toast';
import { useAuthStore } from '../../../stores/auth-store';
import { PERMISSIONS } from '../../../lib/constants';
import {
  listDispatchTemplates,
  createDispatchTemplate,
  updateDispatchTemplate,
  deleteDispatchTemplate,
  applyDispatchTemplate,
} from '../../../api/scheduling';
import { getActiveJobs } from '../../../api/jobs';
import { getEmployees } from '../../../api/people';
import type {
  DispatchTemplateResponse, DispatchTemplateCreate,
  DispatchTemplateMember,
} from '../../../lib/types';


const DAY_LABELS = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];

function daysToBitmask(selectedDays: boolean[]): number {
  return selectedDays.reduce((acc, on, i) => acc | (on ? 1 << i : 0), 0);
}


export function DispatchTemplatesPage() {
  const queryClient = useQueryClient();
  const { hasPermission } = useAuthStore();
  const canManage = hasPermission(PERMISSIONS.DISPATCH_EMPLOYEES);

  // ── Data queries ──────────────────────────────────────────────
  const { data: templates, isLoading } = useQuery({
    queryKey: ['dispatch-templates'],
    queryFn: () => listDispatchTemplates(),
    staleTime: 30_000,
  });

  const { data: jobsData } = useQuery({
    queryKey: ['active-jobs'],
    queryFn: () => getActiveJobs(),
    staleTime: 60_000,
  });
  const jobs = jobsData ?? [];

  const { data: employeesData } = useQuery({
    queryKey: ['employees', 'template-config'],
    queryFn: () => getEmployees({ is_active: true, page: 1, page_size: 200 }),
    staleTime: 60_000,
  });
  const employees = employeesData?.items ?? [];

  // ── Create/edit modal state ───────────────────────────────────
  const [showModal, setShowModal] = useState(false);
  const [editingId, setEditingId] = useState<number | null>(null);
  const [formName, setFormName] = useState('');
  const [formJobId, setFormJobId] = useState<number>(0);
  const [formShiftStart, setFormShiftStart] = useState('07:00');
  const [formShiftEnd, setFormShiftEnd] = useState('15:30');
  const [formLunchStart, setFormLunchStart] = useState('');
  const [formLunchEnd, setFormLunchEnd] = useState('');
  const [formDays, setFormDays] = useState<boolean[]>([false, true, true, true, true, true, false]);
  const [formMembers, setFormMembers] = useState<DispatchTemplateMember[]>([]);
  const [formNotes, setFormNotes] = useState('');

  // ── Apply modal state ─────────────────────────────────────────
  const [applyTemplateId, setApplyTemplateId] = useState<number | null>(null);
  const [applyDateFrom, setApplyDateFrom] = useState('');
  const [applyDateTo, setApplyDateTo] = useState('');
  const [applySkipConflicts, setApplySkipConflicts] = useState(true);

  // ── Mutations ─────────────────────────────────────────────────
  const createMut = useMutation({
    mutationFn: (data: DispatchTemplateCreate) => createDispatchTemplate(data),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['dispatch-templates'] });
      setShowModal(false);
      toast.success('Template created');
    },
    onError: () => toast.error('Failed to create template'),
  });

  const updateMut = useMutation({
    mutationFn: ({ id, data }: { id: number; data: DispatchTemplateCreate }) =>
      updateDispatchTemplate(id, data),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['dispatch-templates'] });
      setShowModal(false);
      toast.success('Template updated');
    },
    onError: () => toast.error('Failed to update template'),
  });

  const deleteMut = useMutation({
    mutationFn: deleteDispatchTemplate,
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['dispatch-templates'] });
      toast.success('Template deleted');
    },
    onError: () => toast.error('Failed to delete template'),
  });

  const applyMut = useMutation({
    mutationFn: () =>
      applyDispatchTemplate(applyTemplateId!, {
        date_from: applyDateFrom,
        date_to: applyDateTo,
        skip_conflicts: applySkipConflicts,
      }),
    onSuccess: (result) => {
      setApplyTemplateId(null);
      toast.success(`${result.created} dispatches created, ${result.skipped} skipped`);
    },
    onError: () => toast.error('Failed to apply template'),
  });

  // ── Handlers ──────────────────────────────────────────────────
  function openCreate() {
    setEditingId(null);
    setFormName('');
    setFormJobId(jobs[0]?.id ?? 0);
    setFormShiftStart('07:00');
    setFormShiftEnd('15:30');
    setFormLunchStart('');
    setFormLunchEnd('');
    setFormDays([false, true, true, true, true, true, false]);
    setFormMembers([]);
    setFormNotes('');
    setShowModal(true);
  }

  function openEdit(t: DispatchTemplateResponse) {
    setEditingId(t.id);
    setFormName(t.name);
    setFormJobId(t.job_id);
    setFormShiftStart(t.shift_start ?? '07:00');
    setFormShiftEnd(t.shift_end ?? '15:30');
    setFormLunchStart(t.lunch_start ?? '');
    setFormLunchEnd(t.lunch_end ?? '');
    setFormDays(DAY_LABELS.map((_, i) => Boolean(t.days_of_week & (1 << i))));
    setFormMembers(t.members.map(m => ({ user_id: m.user_id, role_on_job: m.role_on_job })));
    setFormNotes(t.notes ?? '');
    setShowModal(true);
  }

  function handleSave() {
    const payload: DispatchTemplateCreate = {
      name: formName,
      job_id: formJobId,
      shift_start: formShiftStart || undefined,
      shift_end: formShiftEnd || undefined,
      lunch_start: formLunchStart || undefined,
      lunch_end: formLunchEnd || undefined,
      days_of_week: daysToBitmask(formDays),
      members: formMembers,
      notes: formNotes || undefined,
    };
    if (editingId) {
      updateMut.mutate({ id: editingId, data: payload });
    } else {
      createMut.mutate(payload);
    }
  }

  function toggleMember(userId: number) {
    setFormMembers(prev => {
      const existing = prev.find(m => m.user_id === userId);
      if (existing) return prev.filter(m => m.user_id !== userId);
      return [...prev, { user_id: userId, role_on_job: 'worker' }];
    });
  }

  function openApply(templateId: number) {
    setApplyTemplateId(templateId);
    // Default to next Monday → Friday
    const now = new Date();
    const day = now.getDay();
    const daysUntilMon = day === 0 ? 1 : 8 - day;
    const mon = new Date(now);
    mon.setDate(now.getDate() + daysUntilMon);
    const fri = new Date(mon);
    fri.setDate(mon.getDate() + 4);
    setApplyDateFrom(mon.toISOString().slice(0, 10));
    setApplyDateTo(fri.toISOString().slice(0, 10));
    setApplySkipConflicts(true);
  }

  // ── Render ────────────────────────────────────────────────────
  if (isLoading) return <PageSpinner />;

  return (
    <div className="space-y-4">
      {/* Header */}
      <div className="flex items-center justify-between flex-wrap gap-3">
        <div className="flex items-center gap-3">
          <Repeat size={24} className="text-gray-600 dark:text-gray-400" />
          <div>
            <h1 className="text-xl font-bold text-gray-900 dark:text-white">
              Dispatch Templates
            </h1>
            <p className="text-sm text-gray-500 dark:text-gray-400">
              Reusable crew assignments — apply to any date range
            </p>
          </div>
        </div>
        {canManage && (
          <Button size="sm" onClick={openCreate}>
            <Plus size={14} />
            <span className="hidden sm:inline ml-1">New Template</span>
          </Button>
        )}
      </div>

      {/* Template list */}
      {!templates || templates.length === 0 ? (
        <EmptyState
          icon={<Repeat className="h-12 w-12" />}
          title="No templates yet"
          description="Create a dispatch template to save a recurring crew assignment."
        />
      ) : (
        <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4">
          {templates.map(t => (
            <Card key={t.id} className="p-4">
              <div className="flex items-start justify-between mb-2">
                <h3 className="font-semibold text-gray-900 dark:text-white truncate">
                  {t.name}
                </h3>
                <div className="flex items-center gap-1 flex-shrink-0">
                  {canManage && (
                    <>
                      <button
                        onClick={() => openApply(t.id)}
                        className="p-1 text-green-600 hover:text-green-700"
                        title="Apply template"
                      >
                        <Play size={14} />
                      </button>
                      <button
                        onClick={() => openEdit(t)}
                        className="p-1 text-gray-400 hover:text-gray-600"
                        title="Edit"
                      >
                        <Edit2 size={14} />
                      </button>
                      <button
                        onClick={() => {
                          if (confirm(`Delete "${t.name}"?`)) deleteMut.mutate(t.id);
                        }}
                        className="p-1 text-gray-400 hover:text-red-500"
                        title="Delete"
                      >
                        <Trash2 size={14} />
                      </button>
                    </>
                  )}
                </div>
              </div>

              {/* Job */}
              <div className="flex items-center gap-1.5 text-sm text-gray-600 dark:text-gray-400 mb-2">
                <Briefcase size={12} />
                <span className="truncate">{t.job_name ?? `Job #${t.job_id}`}</span>
              </div>

              {/* Days */}
              <div className="flex gap-1 mb-2">
                {DAY_LABELS.map((d, i) => (
                  <span
                    key={d}
                    className={`text-[10px] px-1.5 py-0.5 rounded font-medium
                      ${t.days_of_week & (1 << i)
                        ? 'bg-blue-100 text-blue-700 dark:bg-blue-900/30 dark:text-blue-300'
                        : 'bg-gray-100 text-gray-400 dark:bg-gray-800 dark:text-gray-600'
                      }`}
                  >
                    {d}
                  </span>
                ))}
              </div>

              {/* Shift + Lunch */}
              {t.shift_start && (
                <div className="text-xs text-gray-500 dark:text-gray-400 mb-2">
                  {t.shift_start} – {t.shift_end}
                  {(t.lunch_start || t.lunch_end) && (
                    <span className="ml-2 text-gray-400 dark:text-gray-500">
                      (lunch {t.lunch_start ?? '—'}–{t.lunch_end ?? '—'})
                    </span>
                  )}
                </div>
              )}

              {/* Members */}
              <div className="flex items-center gap-1.5 text-sm text-gray-600 dark:text-gray-400">
                <Users size={12} />
                <span>
                  {t.members.length} member{t.members.length !== 1 ? 's' : ''}
                </span>
              </div>
              {t.members.length > 0 && (
                <div className="mt-1 flex flex-wrap gap-1">
                  {t.members.map(m => (
                    <Badge key={m.user_id} variant="neutral" className="text-[10px]">
                      {m.user_name ?? `#${m.user_id}`}
                    </Badge>
                  ))}
                </div>
              )}

              {t.notes && (
                <p className="text-xs text-gray-400 dark:text-gray-500 mt-2 line-clamp-2">
                  {t.notes}
                </p>
              )}
            </Card>
          ))}
        </div>
      )}

      {/* ── Create/Edit Modal ──────────────────────────────────── */}
      <Modal
        isOpen={showModal}
        onClose={() => setShowModal(false)}
        title={editingId ? 'Edit Template' : 'New Dispatch Template'}
      >
        <div className="space-y-4">
          <Input
            label="Template Name"
            value={formName}
            onChange={e => setFormName(e.target.value)}
            placeholder="e.g., Main Crew @ Downtown Project"
          />

          <div>
            <label className="block text-sm font-medium text-gray-700 dark:text-gray-300 mb-1">
              Job
            </label>
            <select
              className="w-full text-sm border border-gray-300 dark:border-gray-600 rounded-lg
                         bg-white dark:bg-gray-800 text-gray-700 dark:text-gray-300 px-3 py-2"
              value={formJobId}
              onChange={e => setFormJobId(Number(e.target.value))}
            >
              <option value={0}>Select a job...</option>
              {jobs.map(j => (
                <option key={j.id} value={j.id}>{j.job_name}</option>
              ))}
            </select>
          </div>

          <div className="grid grid-cols-2 gap-3">
            <Input
              label="Shift Start"
              type="time"
              value={formShiftStart}
              onChange={e => setFormShiftStart(e.target.value)}
            />
            <Input
              label="Shift End"
              type="time"
              value={formShiftEnd}
              onChange={e => setFormShiftEnd(e.target.value)}
            />
          </div>

          <div className="grid grid-cols-2 gap-3">
            <Input
              label="Lunch Start"
              type="time"
              value={formLunchStart}
              onChange={e => setFormLunchStart(e.target.value)}
              placeholder="12:00"
            />
            <Input
              label="Lunch End"
              type="time"
              value={formLunchEnd}
              onChange={e => setFormLunchEnd(e.target.value)}
              placeholder="12:30"
            />
          </div>

          {/* Day toggles */}
          <div>
            <label className="block text-sm font-medium text-gray-700 dark:text-gray-300 mb-1">
              Days of Week
            </label>
            <div className="flex gap-1">
              {DAY_LABELS.map((d, i) => (
                <button
                  key={d}
                  onClick={() => setFormDays(prev => prev.map((v, j) => j === i ? !v : v))}
                  className={`flex-1 py-2 text-xs font-medium rounded-lg transition-colors
                    ${formDays[i]
                      ? 'bg-blue-600 text-white'
                      : 'bg-gray-100 text-gray-500 dark:bg-gray-800 dark:text-gray-400'
                    }`}
                >
                  {d}
                </button>
              ))}
            </div>
          </div>

          {/* Member selection */}
          <div>
            <label className="block text-sm font-medium text-gray-700 dark:text-gray-300 mb-1">
              Crew Members
            </label>
            <div className="max-h-40 overflow-y-auto space-y-1 border border-gray-200 dark:border-gray-700 rounded-lg p-2">
              {employees.map(emp => (
                <label key={emp.id} className="flex items-center gap-2 text-sm cursor-pointer py-1 px-1 hover:bg-gray-50 dark:hover:bg-gray-800 rounded">
                  <input
                    type="checkbox"
                    checked={formMembers.some(m => m.user_id === emp.id)}
                    onChange={() => toggleMember(emp.id)}
                    className="rounded"
                  />
                  <span className="text-gray-700 dark:text-gray-300">{emp.display_name}</span>
                </label>
              ))}
            </div>
          </div>

          <Input
            label="Notes"
            value={formNotes}
            onChange={e => setFormNotes(e.target.value)}
            placeholder="Optional notes..."
          />

          <div className="flex justify-end gap-2 pt-2">
            <Button variant="secondary" onClick={() => setShowModal(false)}>
              Cancel
            </Button>
            <Button
              onClick={handleSave}
              disabled={!formName || !formJobId || createMut.isPending || updateMut.isPending}
            >
              {editingId ? 'Update' : 'Create'}
            </Button>
          </div>
        </div>
      </Modal>

      {/* ── Apply Modal ────────────────────────────────────────── */}
      <Modal
        isOpen={applyTemplateId !== null}
        onClose={() => setApplyTemplateId(null)}
        title="Apply Template"
      >
        <div className="space-y-4">
          <p className="text-sm text-gray-600 dark:text-gray-400">
            Generate dispatch records for each template day in the selected range.
          </p>

          <div className="grid grid-cols-2 gap-3">
            <Input
              label="From"
              type="date"
              value={applyDateFrom}
              onChange={e => setApplyDateFrom(e.target.value)}
            />
            <Input
              label="To"
              type="date"
              value={applyDateTo}
              onChange={e => setApplyDateTo(e.target.value)}
            />
          </div>

          <label className="flex items-center gap-2 text-sm">
            <input
              type="checkbox"
              checked={applySkipConflicts}
              onChange={e => setApplySkipConflicts(e.target.checked)}
              className="rounded"
            />
            <span className="text-gray-700 dark:text-gray-300">
              Skip days with conflicts
            </span>
          </label>

          <div className="flex justify-end gap-2 pt-2">
            <Button variant="secondary" onClick={() => setApplyTemplateId(null)}>
              Cancel
            </Button>
            <Button
              onClick={() => applyMut.mutate()}
              disabled={!applyDateFrom || !applyDateTo || applyMut.isPending}
            >
              {applyMut.isPending ? 'Generating...' : 'Generate Dispatches'}
            </Button>
          </div>
        </div>
      </Modal>
    </div>
  );
}
