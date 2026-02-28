/**
 * JobDetailPage — full job view with internal sub-tabs.
 *
 * Sub-tabs: Notebook (default), Overview, Labor, Parts, One-Time Qs
 * These are rendered as an internal tab bar WITHIN the page,
 * NOT as sidebar tabs.
 *
 * Notebook is the DEFAULT tab — field workers need quick access to
 * job info, notes, and tasks when arriving on site.
 */

import { useState, useEffect } from 'react';
import { useParams, useLocation, useNavigate } from 'react-router-dom';
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import {
  ArrowLeft, Briefcase, Clock, Package, HelpCircle,
  Navigation, Users, Square, BookOpen,
  Pause, RotateCcw, Shield, CalendarClock,
} from 'lucide-react';
import { PageSpinner } from '../../../components/ui/Spinner';
import { Button } from '../../../components/ui/Button';
import { Badge } from '../../../components/ui/Badge';
import { Card, CardHeader } from '../../../components/ui/Card';
import { EmptyState } from '../../../components/ui/EmptyState';
import { useAuthStore } from '../../../stores/auth-store';
import { useClockStore } from '../../../stores/clock-store';
import { PERMISSIONS } from '../../../lib/constants';
import {
  getJob, getJobLabor, getJobParts,
  getOneTimeQuestions, createOneTimeQuestion, updateJobStatus,
} from '../../../api/jobs';
import { ClockOutFlow } from '../components/ClockOutFlow';
import {
  JOB_STATUS_LABELS,
  ON_CALL_TYPE_LABELS,
  type JobResponse, type LaborEntryResponse, type JobPartResponse,
  type OneTimeQuestionResponse, type JobStatus, type OnCallType,
  type EntryCreate, type SectionCreate, type TaskStatus, type SectionWithEntries,
} from '../../../lib/types';
import {
  getJobNotebook, createEntry, updateEntry, updateTaskStatus,
  updateFieldValue, deleteEntry, createSection,
} from '../../../api/notebooks';
import { SectionPanel } from '../../notebooks/components/SectionPanel';
import { CreateEntryModal } from '../../notebooks/components/CreateEntryModal';
import { AddSectionModal } from '../../notebooks/components/AddSectionModal';

type SubTab = 'notebook' | 'overview' | 'labor' | 'parts' | 'questions';

const TABS: { id: SubTab; label: string; icon: React.ReactNode }[] = [
  { id: 'notebook', label: 'Notebook', icon: <BookOpen className="h-4 w-4" /> },
  { id: 'overview', label: 'Overview', icon: <Briefcase className="h-4 w-4" /> },
  { id: 'labor', label: 'Labor', icon: <Clock className="h-4 w-4" /> },
  { id: 'parts', label: 'Parts', icon: <Package className="h-4 w-4" /> },
  { id: 'questions', label: 'One-Time Qs', icon: <HelpCircle className="h-4 w-4" /> },
];

const STATUS_COLORS: Record<JobStatus, 'success' | 'warning' | 'default' | 'danger'> = {
  pending: 'warning',
  active: 'success',
  on_hold: 'warning',
  completed: 'default',
  cancelled: 'danger',
  continuous_maintenance: 'success',
  on_call: 'success',
};

export function JobDetailPage() {
  const { id } = useParams<{ id: string }>();
  const jobId = Number(id);
  const navigate = useNavigate();
  const location = useLocation();
  const { isClockedIn, activeEntry, fetchClockState } = useClockStore();

  const [activeTab, setActiveTab] = useState<SubTab>('notebook');
  const [showClockOutFlow, setShowClockOutFlow] = useState(false);
  const queryClient = useQueryClient();

  // Check if we were navigated here with startClockOut intent (from MyClockPage)
  useEffect(() => {
    if ((location.state as { startClockOut?: boolean })?.startClockOut) {
      setShowClockOutFlow(true);
      // Clear the state so refreshing doesn't re-trigger
      window.history.replaceState({}, document.title);
    }
  }, [location.state]);

  const { data: job, isLoading, error } = useQuery({
    queryKey: ['job-detail', jobId],
    queryFn: () => getJob(jobId),
    staleTime: 15_000,
  });

  // Status mutation — must be called before any early returns (Rules of Hooks)
  const statusMutation = useMutation({
    mutationFn: (newStatus: string) => updateJobStatus(jobId, newStatus),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['job-detail', jobId] });
      queryClient.invalidateQueries({ queryKey: ['jobs-active'] });
      queryClient.invalidateQueries({ queryKey: ['jobs-all'] });
    },
  });

  if (isLoading) return <PageSpinner label="Loading job..." />;
  if (error || !job) {
    return (
      <div className="text-center py-16">
        <p className="text-red-500">Job not found or failed to load.</p>
        <Button variant="secondary" className="mt-4" onClick={() => navigate('/jobs/active')}>
          Back to Jobs
        </Button>
      </div>
    );
  }

  const fullAddress = [job.address_line1, job.city, job.state, job.zip].filter(Boolean).join(', ');
  const hasGps = !!(job.gps_lat && job.gps_lng);
  const isOnThisJob = isClockedIn && activeEntry?.job_id === jobId;

  /**
   * Field-worker status actions — only Put On Hold / Resume.
   * Complete, Cancel, Reopen, and Edit are office-only (Manage Jobs page).
   */
  const fieldActions: { label: string; target: JobStatus; icon: React.ReactNode; variant: 'primary' | 'secondary' | 'warning' }[] = (() => {
    if (job.status === 'active' || job.status === 'continuous_maintenance' || job.status === 'on_call') {
      return [{ label: 'Put On Hold', target: 'on_hold' as JobStatus, icon: <Pause className="h-3.5 w-3.5" />, variant: 'warning' as const }];
    }
    if (job.status === 'on_hold') {
      return [{ label: 'Resume', target: 'active' as JobStatus, icon: <RotateCcw className="h-3.5 w-3.5" />, variant: 'primary' as const }];
    }
    return [];
  })();

  return (
    <div className="space-y-4">
      {/* Back button + Header */}
      <div className="flex items-start gap-3">
        <button
          onClick={() => navigate('/jobs/active')}
          className="mt-1 p-1 rounded-md hover:bg-gray-100 dark:hover:bg-gray-800 transition-colors"
        >
          <ArrowLeft className="h-5 w-5 text-gray-500" />
        </button>

        <div className="flex-1 min-w-0">
          <div className="flex items-center gap-2 mb-1">
            <span className="text-xs font-mono text-gray-500 dark:text-gray-400">
              #{job.job_number}
            </span>
            <Badge variant={STATUS_COLORS[job.status]}>
              {job.status === 'on_call' && job.on_call_type
                ? ON_CALL_TYPE_LABELS[job.on_call_type as OnCallType]
                : JOB_STATUS_LABELS[job.status]}
            </Badge>
            <span className="text-xs capitalize text-gray-500 dark:text-gray-400">
              {job.job_type.replace('_', ' ')}
            </span>
          </div>
          <h1 className="text-xl font-bold text-gray-900 dark:text-gray-100 truncate">
            {job.job_name}
          </h1>
          <p className="text-sm text-gray-500 dark:text-gray-400">
            {job.customer_name}
          </p>
        </div>

        {/* Action buttons — Edit is office-only (Manage Jobs page) */}
        <div className="flex items-center gap-2 flex-shrink-0">
          {(hasGps || fullAddress) && (
            <Button
              variant="secondary"
              size="sm"
              icon={<Navigation className="h-4 w-4" />}
              onClick={() => {
                const dest = hasGps
                  ? `${job.gps_lat},${job.gps_lng}`
                  : encodeURIComponent(fullAddress);
                window.open(`https://www.google.com/maps/dir/?api=1&destination=${dest}`, '_blank');
              }}
            >
              Navigate
            </Button>
          )}
        </div>
      </div>

      {/* Field-worker actions: Put On Hold / Resume only */}
      {fieldActions.length > 0 && (
        <div className="flex items-center gap-2 p-2 bg-surface-secondary rounded-lg border border-border">
          <span className="text-xs text-gray-500 dark:text-gray-400 mr-1">Actions:</span>
          {fieldActions.map((action) => (
            <Button
              key={action.target}
              variant={action.variant === 'warning' ? 'secondary' : action.variant}
              size="sm"
              icon={action.icon}
              onClick={() => statusMutation.mutate(action.target)}
              isLoading={statusMutation.isPending}
            >
              {action.label}
            </Button>
          ))}
        </div>
      )}

      {/* Internal tab bar */}
      <div className="flex gap-1 border-b border-border overflow-x-auto">
        {TABS.map((tab) => (
          <button
            key={tab.id}
            onClick={() => setActiveTab(tab.id)}
            className={`flex items-center gap-1.5 px-3 py-2 text-sm font-medium whitespace-nowrap border-b-2 transition-colors ${
              activeTab === tab.id
                ? 'border-blue-500 text-blue-600 dark:text-blue-400'
                : 'border-transparent text-gray-500 dark:text-gray-400 hover:text-gray-700 dark:hover:text-gray-300'
            }`}
          >
            {tab.icon}
            {tab.label}
          </button>
        ))}
      </div>

      {/* Clock Out Flow (overlays the tabs when active) */}
      {showClockOutFlow && isClockedIn && activeEntry ? (
        <ClockOutFlow
          jobId={jobId}
          laborEntryId={activeEntry.id}
          onComplete={() => {
            setShowClockOutFlow(false);
            fetchClockState();
            navigate('/jobs/my-clock');
          }}
          onCancel={() => setShowClockOutFlow(false)}
        />
      ) : (
        <>
          {/* Clock-out banner for workers on this job */}
          {isOnThisJob && (
            <div className="flex items-center gap-3 p-3 bg-green-50 dark:bg-green-900/20 border border-green-200 dark:border-green-800 rounded-lg">
              <Clock className="h-5 w-5 text-green-600 dark:text-green-400" />
              <span className="text-sm text-green-700 dark:text-green-300 flex-1">
                You are currently clocked in to this job
              </span>
              <Button
                variant="danger"
                size="sm"
                icon={<Square className="h-3.5 w-3.5" />}
                onClick={() => setShowClockOutFlow(true)}
              >
                Clock Out
              </Button>
            </div>
          )}

          {/* Tab content */}
          {activeTab === 'notebook' && <NotebookTab jobId={jobId} />}
          {activeTab === 'overview' && <OverviewTab job={job} />}
          {activeTab === 'labor' && <LaborTab jobId={jobId} />}
          {activeTab === 'parts' && <PartsTab jobId={jobId} />}
          {activeTab === 'questions' && <QuestionsTab jobId={jobId} />}
        </>
      )}

    </div>
  );
}


// ── Notebook Tab (Default) ─────────────────────────────────────────

function NotebookTab({ jobId }: { jobId: number }) {
  const queryClient = useQueryClient();

  const [showCreateEntry, setShowCreateEntry] = useState<{
    sectionId: number;
    type: 'note' | 'task';
  } | null>(null);
  const [showAddSection, setShowAddSection] = useState(false);
  const [savingFieldId, setSavingFieldId] = useState<number | null>(null);

  const { data, isLoading, error } = useQuery({
    queryKey: ['job-notebook', jobId],
    queryFn: () => getJobNotebook(jobId),
    staleTime: 15_000,
  });

  const invalidate = () => queryClient.invalidateQueries({ queryKey: ['job-notebook', jobId] });

  const createEntryMut = useMutation({
    mutationFn: ({ sectionId, entry }: { sectionId: number; entry: EntryCreate }) =>
      createEntry(sectionId, entry),
    onSuccess: () => { invalidate(); setShowCreateEntry(null); },
  });

  const updateEntryMut = useMutation({
    mutationFn: ({ entryId, title, content }: { entryId: number; title: string; content: string }) =>
      updateEntry(entryId, { title, content }),
    onSuccess: invalidate,
  });

  const deleteEntryMut = useMutation({
    mutationFn: (entryId: number) => deleteEntry(entryId),
    onSuccess: invalidate,
  });

  const taskStatusMut = useMutation({
    mutationFn: ({ entryId, status, partsNote }: { entryId: number; status: TaskStatus; partsNote?: string }) =>
      updateTaskStatus(entryId, { task_status: status, task_parts_note: partsNote }),
    onSuccess: invalidate,
  });

  const fieldValueMut = useMutation({
    mutationFn: ({ entryId, value }: { entryId: number; value: string }) => {
      setSavingFieldId(entryId);
      return updateFieldValue(entryId, { value });
    },
    onSuccess: () => { invalidate(); setSavingFieldId(null); },
    onError: () => setSavingFieldId(null),
  });

  const addSectionMut = useMutation({
    mutationFn: ({ notebookId, section }: { notebookId: number; section: SectionCreate }) =>
      createSection(notebookId, section),
    onSuccess: () => { invalidate(); setShowAddSection(false); },
  });

  if (isLoading) return <PageSpinner label="Loading notebook..." />;
  if (error || !data) {
    return (
      <EmptyState
        icon={<BookOpen className="h-12 w-12" />}
        title="Notebook Unavailable"
        description="Could not load the notebook for this job."
      />
    );
  }

  const { notebook, sections } = data;

  return (
    <div className="space-y-3">
      {/* Section panels */}
      {sections.map((section: SectionWithEntries) => (
        <SectionPanel
          key={section.id}
          section={section}
          onFieldSave={(id, val) => fieldValueMut.mutate({ entryId: id, value: val })}
          onEntryUpdate={(id, title, content) => updateEntryMut.mutate({ entryId: id, title, content })}
          onEntryDelete={(id) => {
            if (window.confirm('Delete this entry?')) deleteEntryMut.mutate(id);
          }}
          onTaskStatusChange={(id, status, partsNote) =>
            taskStatusMut.mutate({ entryId: id, status, partsNote })
          }
          onAddEntry={(sectionId, type) => setShowCreateEntry({ sectionId, type })}
          savingFieldId={savingFieldId}
        />
      ))}

      {/* Add section button */}
      <button
        onClick={() => setShowAddSection(true)}
        className="flex items-center gap-1.5 px-3 py-2 text-xs font-medium text-gray-500 hover:text-blue-500 border border-dashed border-border hover:border-blue-300 rounded-lg transition-colors w-full justify-center"
      >
        <BookOpen className="h-4 w-4" />
        Add Section
      </button>

      {/* Modals */}
      {showCreateEntry && (
        <CreateEntryModal
          defaultType={showCreateEntry.type}
          sectionId={showCreateEntry.sectionId}
          onSubmit={(sectionId, entry) => createEntryMut.mutate({ sectionId, entry })}
          onClose={() => setShowCreateEntry(null)}
          loading={createEntryMut.isPending}
        />
      )}

      {showAddSection && (
        <AddSectionModal
          notebookId={notebook.id}
          onSubmit={(nid, section) => addSectionMut.mutate({ notebookId: nid, section })}
          onClose={() => setShowAddSection(false)}
          loading={addSectionMut.isPending}
        />
      )}
    </div>
  );
}


// ── Overview Tab ──────────────────────────────────────────────────

function OverviewTab({ job }: { job: JobResponse }) {
  const fullAddress = [job.address_line1, job.address_line2, job.city, job.state, job.zip]
    .filter(Boolean)
    .join(', ');

  return (
    <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
      {/* Info Card */}
      <Card>
        <CardHeader title="Job Information" />
        <div className="px-4 pb-4 space-y-3">
          <InfoRow label="Customer" value={job.customer_name} />
          <InfoRow label="Type" value={job.job_type.replace('_', ' ')} />
          <InfoRow label="Priority" value={job.priority} />
          {job.bill_rate_type_name && <InfoRow label="Bill Rate Type" value={job.bill_rate_type_name} />}
          {fullAddress && <InfoRow label="Address" value={fullAddress} />}
          {job.lead_user_name && <InfoRow label="Lead" value={job.lead_user_name} />}
          {job.start_date && <InfoRow label="Start Date" value={job.start_date} />}
          {job.due_date && <InfoRow label="Due Date" value={job.due_date} />}
          {job.created_at && (
            <InfoRow
              label="Date Added"
              value={new Date(job.created_at + 'Z').toLocaleDateString('en-US', { month: 'short', day: 'numeric', year: 'numeric' })}
            />
          )}
          {job.notes && <InfoRow label="Notes" value={job.notes} />}
        </div>
      </Card>

      {/* Warranty Info Card — only when sub-type is warranty */}
      {job.status === 'on_call' && job.on_call_type === 'warranty' && (
        <Card className="md:col-span-2">
          <CardHeader
            title="Warranty Coverage"
            icon={<Shield className="h-5 w-5 text-sky-500" />}
          />
          <div className="px-4 pb-4">
            <div className="grid grid-cols-3 gap-4">
              {/* Start Date */}
              <div className="text-center p-3 bg-surface-secondary rounded-lg">
                <div className="flex justify-center mb-1 text-gray-400">
                  <CalendarClock className="h-4 w-4" />
                </div>
                <p className="text-sm font-medium text-gray-900 dark:text-gray-100">
                  {job.warranty_start_date
                    ? new Date(job.warranty_start_date + 'T00:00:00').toLocaleDateString('en-US', { month: 'short', day: 'numeric', year: 'numeric' })
                    : '—'}
                </p>
                <p className="text-xs text-gray-500 dark:text-gray-400">Start Date</p>
              </div>

              {/* End Date */}
              <div className="text-center p-3 bg-surface-secondary rounded-lg">
                <div className="flex justify-center mb-1 text-gray-400">
                  <CalendarClock className="h-4 w-4" />
                </div>
                <p className="text-sm font-medium text-gray-900 dark:text-gray-100">
                  {job.warranty_end_date
                    ? new Date(job.warranty_end_date + 'T00:00:00').toLocaleDateString('en-US', { month: 'short', day: 'numeric', year: 'numeric' })
                    : '—'}
                </p>
                <p className="text-xs text-gray-500 dark:text-gray-400">End Date</p>
              </div>

              {/* Days Remaining — color-coded */}
              <div className={`text-center p-3 rounded-lg ${
                job.warranty_days_remaining == null
                  ? 'bg-surface-secondary'
                  : job.warranty_days_remaining <= 0
                    ? 'bg-red-50 dark:bg-red-900/20 border border-red-200 dark:border-red-800'
                    : job.warranty_days_remaining <= 30
                      ? 'bg-amber-50 dark:bg-amber-900/20 border border-amber-200 dark:border-amber-800'
                      : 'bg-green-50 dark:bg-green-900/20 border border-green-200 dark:border-green-800'
              }`}>
                <div className={`flex justify-center mb-1 ${
                  job.warranty_days_remaining == null
                    ? 'text-gray-400'
                    : job.warranty_days_remaining <= 0
                      ? 'text-red-500'
                      : job.warranty_days_remaining <= 30
                        ? 'text-amber-500'
                        : 'text-green-500'
                }`}>
                  <Shield className="h-4 w-4" />
                </div>
                <p className={`text-lg font-bold ${
                  job.warranty_days_remaining == null
                    ? 'text-gray-900 dark:text-gray-100'
                    : job.warranty_days_remaining <= 0
                      ? 'text-red-600 dark:text-red-400'
                      : job.warranty_days_remaining <= 30
                        ? 'text-amber-600 dark:text-amber-400'
                        : 'text-green-600 dark:text-green-400'
                }`}>
                  {job.warranty_days_remaining != null
                    ? (job.warranty_days_remaining <= 0 ? 'Expired' : `${job.warranty_days_remaining}d`)
                    : '—'}
                </p>
                <p className="text-xs text-gray-500 dark:text-gray-400">
                  {job.warranty_days_remaining != null && job.warranty_days_remaining <= 0
                    ? 'Warranty Expired'
                    : 'Days Remaining'}
                </p>
              </div>
            </div>
          </div>
        </Card>
      )}

      {/* On Call Info — simple indicator when sub-type is on_call */}
      {job.status === 'on_call' && job.on_call_type === 'on_call' && (
        <Card className="md:col-span-2">
          <div className="px-4 py-3 flex items-center gap-3">
            <Shield className="h-5 w-5 text-sky-500" />
            <div>
              <p className="text-sm font-medium text-gray-900 dark:text-gray-100">
                On Call — Indefinite Standby
              </p>
              <p className="text-xs text-gray-500 dark:text-gray-400">
                This job has no expiration date. Coverage remains active until status is changed.
              </p>
            </div>
          </div>
        </Card>
      )}

      {/* Stats Card */}
      <Card>
        <CardHeader title="Summary" />
        <div className="px-4 pb-4 space-y-3">
          <div className="grid grid-cols-3 gap-3">
            <StatBox label="Workers" value={String(job.active_workers ?? 0)} icon={<Users className="h-4 w-4" />} />
            <StatBox label="Labor Hours" value={(job.total_labor_hours ?? 0).toFixed(1)} icon={<Clock className="h-4 w-4" />} />
            <StatBox
              label="Parts Cost"
              value={`$${(job.total_parts_cost ?? 0).toFixed(0)}`}
              icon={<Package className="h-4 w-4" />}
            />
          </div>
        </div>
      </Card>
    </div>
  );
}

function InfoRow({ label, value }: { label: string; value: string }) {
  return (
    <div className="flex justify-between text-sm">
      <span className="text-gray-500 dark:text-gray-400">{label}</span>
      <span className="text-gray-900 dark:text-gray-100 font-medium capitalize">{value}</span>
    </div>
  );
}

function StatBox({ label, value, icon }: { label: string; value: string; icon: React.ReactNode }) {
  return (
    <div className="text-center p-3 bg-surface-secondary rounded-lg">
      <div className="flex justify-center mb-1 text-gray-400">{icon}</div>
      <p className="text-lg font-bold text-gray-900 dark:text-gray-100">{value}</p>
      <p className="text-xs text-gray-500 dark:text-gray-400">{label}</p>
    </div>
  );
}


// ── Labor Tab ─────────────────────────────────────────────────────

function LaborTab({ jobId }: { jobId: number }) {
  const { data: entries, isLoading } = useQuery({
    queryKey: ['job-labor', jobId],
    queryFn: () => getJobLabor(jobId),
    staleTime: 15_000,
  });

  if (isLoading) return <PageSpinner label="Loading labor entries..." />;
  if (!entries || entries.length === 0) {
    return <EmptyState icon={<Clock className="h-12 w-12" />} title="No Labor Entries" description="No one has clocked in to this job yet." />;
  }

  return (
    <div className="space-y-2">
      {entries.map((entry) => (
        <div key={entry.id} className="flex items-center gap-3 p-3 bg-surface border border-border rounded-lg">
          <div className="flex-1 min-w-0">
            <p className="text-sm font-medium text-gray-900 dark:text-gray-100">
              {entry.user_name}
            </p>
            <p className="text-xs text-gray-500 dark:text-gray-400">
              {new Date(entry.clock_in).toLocaleDateString()} — {new Date(entry.clock_in).toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' })}
              {entry.clock_out && ` to ${new Date(entry.clock_out).toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' })}`}
            </p>
          </div>
          <div className="text-right">
            {entry.regular_hours != null && (
              <p className="text-sm font-medium text-gray-900 dark:text-gray-100">
                {((entry.regular_hours ?? 0) + (entry.overtime_hours ?? 0)).toFixed(1)}h
              </p>
            )}
            {(entry.overtime_hours ?? 0) > 0 && (
              <p className="text-xs text-orange-500">+{entry.overtime_hours?.toFixed(1)}h OT</p>
            )}
            <Badge variant={entry.status === 'clocked_in' ? 'success' : 'default'}>
              {entry.status.replace('_', ' ')}
            </Badge>
          </div>
        </div>
      ))}
    </div>
  );
}


// ── Parts Tab ─────────────────────────────────────────────────────

function PartsTab({ jobId }: { jobId: number }) {
  const { data: parts, isLoading } = useQuery({
    queryKey: ['job-parts', jobId],
    queryFn: () => getJobParts(jobId),
    staleTime: 15_000,
  });

  if (isLoading) return <PageSpinner label="Loading parts..." />;
  if (!parts || parts.length === 0) {
    return <EmptyState icon={<Package className="h-12 w-12" />} title="No Parts Consumed" description="No parts have been recorded for this job yet." />;
  }

  return (
    <div className="overflow-x-auto">
      <table className="w-full text-sm">
        <thead>
          <tr className="border-b border-border text-left text-xs text-gray-500 dark:text-gray-400">
            <th className="pb-2 font-medium">Part</th>
            <th className="pb-2 font-medium text-right">Qty</th>
            <th className="pb-2 font-medium text-right">Unit Cost</th>
            <th className="pb-2 font-medium text-right">Total</th>
            <th className="pb-2 font-medium">By</th>
          </tr>
        </thead>
        <tbody className="divide-y divide-border">
          {parts.map((p) => (
            <tr key={p.id}>
              <td className="py-2">
                <span className="text-gray-900 dark:text-gray-100">{p.part_name}</span>
                {p.part_code && (
                  <span className="ml-1 text-xs text-gray-400">({p.part_code})</span>
                )}
              </td>
              <td className="py-2 text-right">{p.qty_consumed}</td>
              <td className="py-2 text-right">${(p.unit_cost_at_consume ?? 0).toFixed(2)}</td>
              <td className="py-2 text-right font-medium">
                ${((p.qty_consumed ?? 0) * (p.unit_cost_at_consume ?? 0)).toFixed(2)}
              </td>
              <td className="py-2 text-gray-500 dark:text-gray-400">{p.consumed_by_name}</td>
            </tr>
          ))}
        </tbody>
      </table>
    </div>
  );
}


// ── Questions Tab ─────────────────────────────────────────────────

function QuestionsTab({ jobId }: { jobId: number }) {
  const { hasPermission } = useAuthStore();
  const canManage = hasPermission(PERMISSIONS.MANAGE_JOBS);
  const queryClient = useQueryClient();

  const { data: questions, isLoading } = useQuery({
    queryKey: ['job-one-time-questions', jobId],
    queryFn: () => getOneTimeQuestions(jobId),
    staleTime: 15_000,
  });

  const [showCreate, setShowCreate] = useState(false);
  const [newQuestion, setNewQuestion] = useState('');

  const createMutation = useMutation({
    mutationFn: () => createOneTimeQuestion(jobId, { question_text: newQuestion }),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['job-one-time-questions', jobId] });
      setNewQuestion('');
      setShowCreate(false);
    },
  });

  if (isLoading) return <PageSpinner label="Loading questions..." />;

  return (
    <div className="space-y-3">
      {canManage && (
        <div className="flex justify-end">
          <Button
            size="sm"
            icon={<HelpCircle className="h-4 w-4" />}
            onClick={() => setShowCreate(!showCreate)}
          >
            Ask Question
          </Button>
        </div>
      )}

      {showCreate && (
        <div className="p-3 bg-surface-secondary rounded-lg border border-border space-y-2">
          <textarea
            value={newQuestion}
            onChange={(e) => setNewQuestion(e.target.value)}
            placeholder="Type your one-time question for this job..."
            className="w-full rounded-lg border border-border bg-surface px-3 py-2 text-sm min-h-[80px] resize-none"
          />
          <div className="flex justify-end gap-2">
            <Button variant="secondary" size="sm" onClick={() => setShowCreate(false)}>Cancel</Button>
            <Button
              size="sm"
              isLoading={createMutation.isPending}
              onClick={() => newQuestion.trim() && createMutation.mutate()}
            >
              Send
            </Button>
          </div>
        </div>
      )}

      {!questions || questions.length === 0 ? (
        <EmptyState
          icon={<HelpCircle className="h-12 w-12" />}
          title="No One-Time Questions"
          description="One-time questions appear here when the boss asks specific questions about this job."
        />
      ) : (
        questions.map((q) => (
          <div key={q.id} className="p-3 bg-surface border border-border rounded-lg">
            <div className="flex items-start justify-between gap-2">
              <div>
                <p className="text-sm text-gray-900 dark:text-gray-100">{q.question_text}</p>
                <p className="text-xs text-gray-500 dark:text-gray-400 mt-1">
                  Asked by {q.created_by_name}
                  {q.target_user_name ? ` to ${q.target_user_name}` : ' (everyone)'}
                </p>
              </div>
              <Badge variant={q.status === 'answered' ? 'success' : q.status === 'pending' ? 'warning' : 'default'}>
                {q.status}
              </Badge>
            </div>
            {q.answer_text && (
              <div className="mt-2 p-2 bg-green-50 dark:bg-green-900/20 rounded text-sm text-green-700 dark:text-green-300">
                <strong>Answer:</strong> {q.answer_text}
              </div>
            )}
          </div>
        ))
      )}
    </div>
  );
}
