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
  Navigation, Users, Square, BookOpen, AlertTriangle,
  Pause, RotateCcw, Shield, CalendarClock, DollarSign,
  TrendingUp, Layers, Wrench, Star, UserPlus, Building2,
  Link2, Unlink, Phone, Mail, X, HardHat, Crown, MessageSquare,
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
  getJobTeam, addJobTeamMember, removeJobTeamMember,
} from '../../../api/jobs';
import { getEmployees } from '../../../api/people';
import { getJobCostRollup, getJobBudgetStatus } from '../../../api/costs';
import { getToolsAtLocation } from '../../../api/tools';
import {
  getJobCustomers, getJobGCs, linkCustomerToJob, unlinkCustomerFromJob,
  linkGCToJob, unlinkGCFromJob, searchCustomers, searchGCs,
} from '../../../api/contacts';
import type {
  CustomerContactRole,
  GCRelationship, CustomerListItem, GCListItem,
  EmployeeListItem,
} from '../../../lib/types';
import { ClockOutFlow } from '../components/ClockOutFlow';
import { PreferredSuppliersSection } from '../components/PreferredSuppliersSection';
import {
  JOB_STATUS_LABELS,
  ON_CALL_TYPE_LABELS,
  type JobResponse, type JobStatus, type OnCallType,
  type EntryCreate, type SectionCreate, type TaskStatus, type SectionWithEntries,
} from '../../../lib/types';
import {
  getJobNotebook, createEntry, updateEntry, updateTaskStatus,
  updateFieldValue, deleteEntry, createSection,
} from '../../../api/notebooks';
import { SectionPanel } from '../../notebooks/components/SectionPanel';
import { CreateEntryModal } from '../../notebooks/components/CreateEntryModal';
import { AddSectionModal } from '../../notebooks/components/AddSectionModal';
import { ChatMessageView } from '../../chat/components/ChatMessageView';
import { getInbox } from '../../../api/chat';

type SubTab = 'notebook' | 'overview' | 'people' | 'labor' | 'parts' | 'tools' | 'chat' | 'questions' | 'costs';

const BASE_TABS: { id: SubTab; label: string; icon: React.ReactNode }[] = [
  { id: 'notebook', label: 'Notebook', icon: <BookOpen className="h-4 w-4" /> },
  { id: 'overview', label: 'Overview', icon: <Briefcase className="h-4 w-4" /> },
  { id: 'people', label: 'People', icon: <Users className="h-4 w-4" /> },
  { id: 'labor', label: 'Labor', icon: <Clock className="h-4 w-4" /> },
  { id: 'parts', label: 'Parts', icon: <Package className="h-4 w-4" /> },
  { id: 'tools', label: 'Tools', icon: <Wrench className="h-4 w-4" /> },
  { id: 'chat', label: 'Chat', icon: <MessageSquare className="h-4 w-4" /> },
  { id: 'questions', label: 'One-Time Qs', icon: <HelpCircle className="h-4 w-4" /> },
];

const COSTS_TAB: { id: SubTab; label: string; icon: React.ReactNode } = {
  id: 'costs', label: 'Costs', icon: <DollarSign className="h-4 w-4" />,
};

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
  const { hasPermission } = useAuthStore();
  const canSeeCosts = hasPermission(PERMISSIONS.SHOW_DOLLAR_VALUES);

  // Conditionally include the Costs tab based on permission
  const TABS = canSeeCosts ? [...BASE_TABS, COSTS_TAB] : BASE_TABS;

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
          className="mt-1 p-2 rounded-md hover:bg-gray-100 dark:hover:bg-gray-800 transition-colors"
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
            className={`flex items-center gap-1.5 px-3 py-2 text-sm font-medium whitespace-nowrap border-b-2 transition-colors ${activeTab === tab.id
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
          {activeTab === 'people' && <PeopleTab jobId={jobId} />}
          {activeTab === 'labor' && <LaborTab jobId={jobId} />}
          {activeTab === 'parts' && <PartsTab jobId={jobId} />}
          {activeTab === 'tools' && <ToolsTab jobId={jobId} />}
          {activeTab === 'chat' && <ChatTab jobId={jobId} jobNumber={job.job_number} />}
          {activeTab === 'questions' && <QuestionsTab jobId={jobId} />}
          {activeTab === 'costs' && canSeeCosts && <CostsTab jobId={jobId} jobName={job.job_name} />}
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

  const { data, isLoading, error, refetch, isFetching } = useQuery({
    queryKey: ['job-notebook', jobId],
    queryFn: () => getJobNotebook(jobId),
    staleTime: 15_000,
    retry: 1, // one automatic retry before showing error
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
      updateTaskStatus(entryId, { status, parts_note: partsNote }),
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

  // ── Error / empty state with actionable recovery ──
  if (error || !data) {
    const errMsg = error instanceof Error ? error.message : '';
    const isNetworkError = errMsg.includes('Network') || errMsg.includes('ECONNREFUSED') || errMsg.includes('fetch');

    return (
      <div className="rounded-lg border border-border bg-surface p-6 text-center space-y-4">
        <div className="flex justify-center">
          <div className="h-12 w-12 rounded-full bg-amber-100 dark:bg-amber-900/30 flex items-center justify-center">
            <AlertTriangle className="h-6 w-6 text-amber-500" />
          </div>
        </div>
        <div>
          <h3 className="text-sm font-semibold text-gray-900 dark:text-gray-100">
            Notebook Unavailable
          </h3>
          <p className="text-xs text-gray-500 dark:text-gray-400 mt-1 max-w-sm mx-auto">
            {isNetworkError
              ? 'Could not reach the server. Check your connection and try again.'
              : 'Could not load or create the notebook for this job. This usually resolves by retrying.'}
          </p>
          {errMsg && !isNetworkError && (
            <p className="text-xs text-red-400 mt-2 font-mono max-w-sm mx-auto truncate">
              {errMsg}
            </p>
          )}
        </div>
        <button
          onClick={() => refetch()}
          disabled={isFetching}
          className="inline-flex items-center gap-2 rounded-lg bg-primary px-4 py-2 text-sm font-medium text-white shadow-sm hover:bg-primary/90 transition-colors disabled:opacity-50"
        >
          <RotateCcw className={`h-4 w-4 ${isFetching ? 'animate-spin' : ''}`} />
          {isFetching ? 'Retrying...' : 'Try Again'}
        </button>
      </div>
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

      {/* Empty notebook state (notebook exists but no sections) */}
      {sections.length === 0 && (
        <EmptyState
          icon={<BookOpen className="h-10 w-10 text-gray-300 dark:text-gray-600" />}
          title="Empty Notebook"
          description="This notebook has no sections yet. Add a section to start organizing your job info, notes, and tasks."
        />
      )}

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
              <div className={`text-center p-3 rounded-lg ${job.warranty_days_remaining == null
                ? 'bg-surface-secondary'
                : job.warranty_days_remaining <= 0
                  ? 'bg-red-50 dark:bg-red-900/20 border border-red-200 dark:border-red-800'
                  : job.warranty_days_remaining <= 30
                    ? 'bg-amber-50 dark:bg-amber-900/20 border border-amber-200 dark:border-amber-800'
                    : 'bg-green-50 dark:bg-green-900/20 border border-green-200 dark:border-green-800'
                }`}>
                <div className={`flex justify-center mb-1 ${job.warranty_days_remaining == null
                  ? 'text-gray-400'
                  : job.warranty_days_remaining <= 0
                    ? 'text-red-500'
                    : job.warranty_days_remaining <= 30
                      ? 'text-amber-500'
                      : 'text-green-500'
                  }`}>
                  <Shield className="h-4 w-4" />
                </div>
                <p className={`text-lg font-bold ${job.warranty_days_remaining == null
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

      {/* Preferred Suppliers */}
      <PreferredSuppliersSection jobId={job.id} className="md:col-span-2" />
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


// ── Costs Tab ──────────────────────────────────────────────────────

/**
 * ChatTab — embedded job chat channel view.
 *
 * Fetches the job's auto-created channel and renders the full message view
 * inline. If no channel exists yet, shows a prompt to start chatting.
 */
function ChatTab({ jobId, jobNumber }: { jobId: number; jobNumber: string }) {
  const { user } = useAuthStore();
  const navigate = useNavigate();

  // Find the job's channel from the inbox
  const { data: inbox, isLoading } = useQuery({
    queryKey: ['chat-inbox'],
    queryFn: () => getInbox(),
  });

  const jobChannel = inbox?.channels?.find(
    (c) => c.channel_type === 'job' && c.job_id === jobId
  );

  if (isLoading) return <PageSpinner label="Loading chat..." />;

  if (!jobChannel) {
    return (
      <div className="text-center py-12 px-4">
        <MessageSquare className="h-8 w-8 text-gray-300 mx-auto mb-2" />
        <p className="text-sm text-gray-500 dark:text-gray-400">No chat channel yet</p>
        <p className="text-xs text-gray-400 mt-1 mb-3">
          Chat channels are automatically created when messages are sent.
        </p>
        <button
          onClick={() => navigate('/chat/inbox')}
          className="text-xs text-primary-600 dark:text-primary-400 hover:underline"
        >
          Go to Chat Inbox
        </button>
      </div>
    );
  }

  return (
    <div className="h-[500px] sm:h-[600px] border border-border rounded-lg overflow-hidden">
      <ChatMessageView
        channelId={jobChannel.id}
        currentUserId={user!.id}
        channelName={`${jobNumber} Chat`}
      />
    </div>
  );
}

/**
 * ToolsTab — read-only view of tools checked out to this job.
 *
 * Tools are checked out from the truck or warehouse tools pages;
 * this tab is a visibility-only list showing what's currently at the job site.
 */
function ToolsTab({ jobId }: { jobId: number }) {
  const { data: tools, isLoading } = useQuery({
    queryKey: ['job-tools', jobId],
    queryFn: () => getToolsAtLocation('job', jobId),
    staleTime: 15_000,
  });

  if (isLoading) return <PageSpinner label="Loading tools..." />;

  if (!tools || tools.length === 0) {
    return (
      <EmptyState
        icon={<Wrench className="h-12 w-12" />}
        title="No Tools at This Job"
        description="Tools are checked out to jobs from the Truck Tools page. When tools are assigned to this job, they'll appear here."
      />
    );
  }

  return (
    <div className="space-y-2">
      <p className="text-sm text-gray-500 dark:text-gray-400 mb-3">
        {tools.length} tool{tools.length !== 1 ? 's' : ''} at this job site
      </p>
      {tools.map((tool) => (
        <div
          key={tool.id}
          className="bg-white dark:bg-gray-800 border border-gray-200 dark:border-gray-700 rounded-lg p-3"
        >
          <div className="flex items-center gap-3">
            <div className="flex-shrink-0 w-8 h-8 rounded-full bg-primary-100 dark:bg-primary-900/30 flex items-center justify-center text-primary-700 dark:text-primary-300">
              <Wrench size={14} />
            </div>
            <div className="flex-1 min-w-0">
              <div className="flex items-center gap-2 flex-wrap">
                <span className="font-medium text-sm text-gray-900 dark:text-gray-100 truncate">
                  {tool.name}
                </span>
                <Badge variant="primary" className="text-xs">
                  {tool.status.replace('_', ' ')}
                </Badge>
                {tool.has_kit && (
                  <span className="inline-flex items-center gap-1 text-xs text-purple-600 dark:text-purple-400">
                    <Shield size={10} /> Kit
                  </span>
                )}
              </div>
              <div className="flex items-center gap-3 mt-0.5 text-xs text-gray-500 dark:text-gray-400">
                <span className="font-mono">{tool.tool_number}</span>
                {tool.brand && <span>{tool.brand}</span>}
                {tool.assigned_to_name && <span>→ {tool.assigned_to_name}</span>}
              </div>
            </div>
            {tool.condition_rating && (
              <span className="flex items-center gap-0.5 flex-shrink-0">
                {[1, 2, 3, 4, 5].map((n) => (
                  <Star
                    key={n}
                    size={10}
                    className={n <= tool.condition_rating! ? 'text-amber-400 fill-amber-400' : 'text-gray-300 dark:text-gray-600'}
                  />
                ))}
              </span>
            )}
          </div>
        </div>
      ))}
    </div>
  );
}


/**
 * CostsTab — Job cost rollup with budget progress bar.
 *
 * Permission: only rendered when canSeeCosts is true (gated at parent level).
 * Shows: parts cost, labor cost, combined total, budget status, and a
 * breakdown of cost sources.
 */
function CostsTab({ jobId, jobName: _jobName }: { jobId: number; jobName: string }) {
  const { data: rollup, isLoading: loadingRollup } = useQuery({
    queryKey: ['job-cost-rollup', jobId],
    queryFn: () => getJobCostRollup(jobId),
    staleTime: 30_000,
  });

  const { data: _budget } = useQuery({
    queryKey: ['job-budget-status', jobId],
    queryFn: () => getJobBudgetStatus(jobId),
    staleTime: 30_000,
  });

  const fmt = (v: number) =>
    `$${v.toLocaleString(undefined, { minimumFractionDigits: 2, maximumFractionDigits: 2 })}`;

  if (loadingRollup) return <PageSpinner label="Loading cost data..." />;
  if (!rollup) {
    return (
      <EmptyState
        icon={<DollarSign className="h-12 w-12" />}
        title="No Cost Data"
        description="Cost information will appear once parts are ordered or labor is recorded for this job."
      />
    );
  }

  const hasBudget = rollup.budget_limit != null && rollup.budget_limit > 0;
  const budgetPct = rollup.budget_pct ?? 0;

  // Color scheme for budget progress
  const budgetColor =
    budgetPct >= 100
      ? 'red'
      : budgetPct >= (rollup.budget_alert_percent ?? 80)
        ? 'amber'
        : 'green';

  const barColorClass = {
    green: 'bg-green-500',
    amber: 'bg-amber-500',
    red: 'bg-red-500',
  }[budgetColor];

  const bgColorClass = {
    green: 'bg-green-50 dark:bg-green-900/20 border-green-200 dark:border-green-800',
    amber: 'bg-amber-50 dark:bg-amber-900/20 border-amber-200 dark:border-amber-800',
    red: 'bg-red-50 dark:bg-red-900/20 border-red-200 dark:border-red-800',
  }[budgetColor];

  const textColorClass = {
    green: 'text-green-700 dark:text-green-300',
    amber: 'text-amber-700 dark:text-amber-300',
    red: 'text-red-700 dark:text-red-300',
  }[budgetColor];

  return (
    <div className="space-y-4">
      {/* Budget Alert Banner — only if budget is set and approaching/over limit */}
      {hasBudget && budgetPct >= (rollup.budget_alert_percent ?? 80) && (
        <div className={`flex items-center gap-3 p-3 rounded-lg border ${bgColorClass}`}>
          <AlertTriangle className={`h-5 w-5 flex-shrink-0 ${budgetColor === 'red' ? 'text-red-500' : 'text-amber-500'
            }`} />
          <div className="flex-1 min-w-0">
            <p className={`text-sm font-medium ${textColorClass}`}>
              {budgetPct >= 100
                ? `Budget exceeded — ${budgetPct.toFixed(0)}% used`
                : `Budget warning — ${budgetPct.toFixed(0)}% used`}
            </p>
            <p className="text-xs text-gray-500 dark:text-gray-400">
              {fmt(rollup.combined_total)} spent of {fmt(rollup.budget_limit!)} budget
            </p>
          </div>
        </div>
      )}

      {/* Cost Summary KPIs */}
      <div className="grid grid-cols-2 sm:grid-cols-4 gap-3">
        <CostKPIBox
          label="Parts Cost"
          value={fmt(rollup.total_parts_cost)}
          icon={<Package className="h-4 w-4" />}
        />
        <CostKPIBox
          label="Labor Cost"
          value={fmt(rollup.total_labor_cost)}
          icon={<Clock className="h-4 w-4" />}
          sub={rollup.total_labor_hours != null ? `${rollup.total_labor_hours.toFixed(1)} hrs` : undefined}
        />
        <CostKPIBox
          label="Combined Total"
          value={fmt(rollup.combined_total)}
          icon={<TrendingUp className="h-4 w-4" />}
          highlight
        />
        <CostKPIBox
          label={hasBudget ? 'Budget Remaining' : 'Budget'}
          value={hasBudget ? fmt(rollup.budget_remaining ?? 0) : 'Not Set'}
          icon={<Layers className="h-4 w-4" />}
          sub={hasBudget ? `of ${fmt(rollup.budget_limit!)}` : undefined}
        />
      </div>

      {/* Budget Progress Bar */}
      {hasBudget && (
        <Card>
          <CardHeader title="Budget Progress" />
          <div className="px-4 pb-4">
            <div className="flex items-center justify-between text-sm mb-2">
              <span className="text-gray-500 dark:text-gray-400">
                {fmt(rollup.combined_total)} spent
              </span>
              <span className={`font-medium ${textColorClass}`}>
                {budgetPct.toFixed(1)}%
              </span>
            </div>
            <div className="h-3 bg-gray-200 dark:bg-gray-700 rounded-full overflow-hidden">
              <div
                className={`h-full rounded-full transition-all duration-500 ${barColorClass}`}
                style={{ width: `${Math.min(budgetPct, 100)}%` }}
              />
            </div>
            {budgetPct > 100 && (
              <div className="flex items-center gap-1.5 mt-2">
                <AlertTriangle className="h-3.5 w-3.5 text-red-500" />
                <span className="text-xs text-red-600 dark:text-red-400 font-medium">
                  Over budget by {fmt(rollup.combined_total - rollup.budget_limit!)}
                </span>
              </div>
            )}
          </div>
        </Card>
      )}

      {/* Cost Breakdown */}
      <Card>
        <CardHeader title="Cost Breakdown" />
        <div className="px-4 pb-4 space-y-3">
          <CostBreakdownRow
            label="Parts / Materials"
            value={fmt(rollup.total_parts_cost)}
            pct={rollup.combined_total > 0
              ? (rollup.total_parts_cost / rollup.combined_total * 100)
              : 0}
            color="bg-blue-500"
          />
          <CostBreakdownRow
            label="Labor"
            value={fmt(rollup.total_labor_cost)}
            pct={rollup.combined_total > 0
              ? (rollup.total_labor_cost / rollup.combined_total * 100)
              : 0}
            color="bg-green-500"
          />
          {rollup.billing_rate != null && rollup.billing_rate > 0 && (
            <div className="pt-2 border-t border-gray-200 dark:border-gray-700 flex justify-between text-sm">
              <span className="text-gray-500 dark:text-gray-400">Billing Rate</span>
              <span className="text-gray-900 dark:text-gray-100 font-medium">
                {fmt(rollup.billing_rate)}/hr
              </span>
            </div>
          )}
        </div>
      </Card>
    </div>
  );
}


/** KPI box for the job costs grid */
function CostKPIBox({
  label, value, icon, sub, highlight,
}: {
  label: string; value: string; icon: React.ReactNode;
  sub?: string; highlight?: boolean;
}) {
  return (
    <div className="bg-white dark:bg-gray-800 rounded-lg p-3 border border-gray-200 dark:border-gray-700">
      <div className="flex items-center gap-1.5 mb-1">
        <span className="text-gray-400 dark:text-gray-500">{icon}</span>
        <span className="text-xs text-gray-500 dark:text-gray-400">{label}</span>
      </div>
      <p className={`text-lg font-bold ${highlight
        ? 'text-primary-600 dark:text-primary-400'
        : 'text-gray-900 dark:text-gray-100'
        }`}>
        {value}
      </p>
      {sub && (
        <p className="text-xs text-gray-400 dark:text-gray-500 mt-0.5">{sub}</p>
      )}
    </div>
  );
}


/** Horizontal breakdown row with proportional bar */
function CostBreakdownRow({
  label, value, pct, color,
}: {
  label: string; value: string; pct: number; color: string;
}) {
  return (
    <div>
      <div className="flex items-center justify-between text-sm mb-1">
        <span className="text-gray-700 dark:text-gray-300">{label}</span>
        <div className="flex items-center gap-2">
          <span className="text-xs text-gray-400">{pct.toFixed(0)}%</span>
          <span className="font-medium text-gray-900 dark:text-gray-100">{value}</span>
        </div>
      </div>
      <div className="h-2 bg-gray-200 dark:bg-gray-700 rounded-full overflow-hidden">
        <div
          className={`h-full rounded-full transition-all ${color}`}
          style={{ width: `${Math.max(pct, 1)}%` }}
        />
      </div>
    </div>
  );
}


// ── People Tab ────────────────────────────────────────────────────

const CONTACT_ROLE_LABELS: Record<CustomerContactRole, string> = {
  owner: 'Owner',
  property_manager: 'Property Manager',
  tenant: 'Tenant',
  site_contact: 'Site Contact',
  billing: 'Billing',
  other: 'Other',
};

const GC_RELATIONSHIP_LABELS: Record<GCRelationship, string> = {
  they_are_gc: 'They hired us',
  we_hired_them: 'We hired them',
};

function PeopleTab({ jobId }: { jobId: number }) {
  const queryClient = useQueryClient();
  const { hasPermission } = useAuthStore();
  const canManage = hasPermission(PERMISSIONS.MANAGE_JOBS);

  // ── Team members ──
  const { data: teamMembers = [] } = useQuery({
    queryKey: ['job-team', jobId],
    queryFn: () => getJobTeam(jobId),
    staleTime: 30_000,
  });

  const [showAddTeam, setShowAddTeam] = useState(false);
  const [teamSearch, setTeamSearch] = useState('');
  const [teamRole, setTeamRole] = useState<'lead' | 'member'>('member');
  const [empResults, setEmpResults] = useState<EmployeeListItem[]>([]);

  const searchEmpMut = useMutation({
    mutationFn: (q: string) => getEmployees({ search: q, page_size: 10 }),
    onSuccess: (data) => setEmpResults(data.items),
  });

  const addTeamMut = useMutation({
    mutationFn: (userId: number) =>
      addJobTeamMember(jobId, { user_id: userId, role: teamRole }),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['job-team', jobId] });
      setShowAddTeam(false);
      setTeamSearch('');
      setEmpResults([]);
    },
  });

  const removeTeamMut = useMutation({
    mutationFn: (memberId: number) => removeJobTeamMember(jobId, memberId),
    onSuccess: () => queryClient.invalidateQueries({ queryKey: ['job-team', jobId] }),
  });

  // ── Linked customers & GCs ──
  const { data: customers = [] } = useQuery({
    queryKey: ['job-customers', jobId],
    queryFn: () => getJobCustomers(jobId),
    staleTime: 30_000,
  });

  const { data: gcs = [] } = useQuery({
    queryKey: ['job-gcs', jobId],
    queryFn: () => getJobGCs(jobId),
    staleTime: 30_000,
  });

  // ── Customer linking ──
  const [custSearch, setCustSearch] = useState('');
  const [custResults, setCustResults] = useState<CustomerListItem[]>([]);
  const [showCustSearch, setShowCustSearch] = useState(false);

  const searchCustMut = useMutation({
    mutationFn: (q: string) => searchCustomers(q),
    onSuccess: (data) => setCustResults(data),
  });

  const linkCustMut = useMutation({
    mutationFn: (custId: number) =>
      linkCustomerToJob(jobId, { customer_id: custId }),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['job-customers', jobId] });
      setShowCustSearch(false);
      setCustSearch('');
      setCustResults([]);
    },
  });

  const unlinkCustMut = useMutation({
    mutationFn: (linkId: number) => unlinkCustomerFromJob(jobId, linkId),
    onSuccess: () =>
      queryClient.invalidateQueries({ queryKey: ['job-customers', jobId] }),
  });

  // ── GC linking ──
  const [gcSearch, setGcSearch] = useState('');
  const [gcResults, setGcResults] = useState<GCListItem[]>([]);
  const [showGcSearch, setShowGcSearch] = useState(false);
  const [gcRelationship, setGcRelationship] = useState<GCRelationship>('they_are_gc');

  const searchGcMut = useMutation({
    mutationFn: (q: string) => searchGCs(q),
    onSuccess: (data) => setGcResults(data),
  });

  const linkGcMut = useMutation({
    mutationFn: (gcId: number) =>
      linkGCToJob(jobId, { gc_id: gcId, relationship: gcRelationship }),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['job-gcs', jobId] });
      setShowGcSearch(false);
      setGcSearch('');
      setGcResults([]);
    },
  });

  const unlinkGcMut = useMutation({
    mutationFn: (linkId: number) => unlinkGCFromJob(jobId, linkId),
    onSuccess: () =>
      queryClient.invalidateQueries({ queryKey: ['job-gcs', jobId] }),
  });

  return (
    <div className="space-y-6">
      {/* ── Team Section ──────────────────────────────────── */}
      <Card className="p-4">
        <div className="flex items-center justify-between mb-3">
          <h3 className="font-semibold text-gray-900 dark:text-white flex items-center gap-2">
            <HardHat size={16} />
            Assigned Team
            <Badge variant="neutral" className="text-xs">{teamMembers.length}</Badge>
          </h3>
          {canManage && (
            <Button
              size="sm"
              variant="secondary"
              onClick={() => setShowAddTeam(!showAddTeam)}
            >
              <UserPlus size={14} />
              <span className="hidden sm:inline ml-1">Add Member</span>
            </Button>
          )}
        </div>

        {/* Add member search panel */}
        {showAddTeam && (
          <div className="mb-3 p-3 bg-surface-secondary rounded-lg border border-border space-y-2">
            {/* Role selector */}
            <div className="flex items-center gap-2">
              <span className="text-xs text-gray-500 dark:text-gray-400">Role:</span>
              <button
                onClick={() => setTeamRole('member')}
                className={`px-2.5 py-1 rounded-md text-xs font-medium transition-colors ${teamRole === 'member'
                  ? 'bg-blue-100 dark:bg-blue-900/40 text-blue-700 dark:text-blue-300'
                  : 'text-gray-500 dark:text-gray-400 hover:bg-surface'
                  }`}
              >
                Member
              </button>
              <button
                onClick={() => setTeamRole('lead')}
                className={`flex items-center gap-1 px-2.5 py-1 rounded-md text-xs font-medium transition-colors ${teamRole === 'lead'
                  ? 'bg-amber-100 dark:bg-amber-900/40 text-amber-700 dark:text-amber-300'
                  : 'text-gray-500 dark:text-gray-400 hover:bg-surface'
                  }`}
              >
                <Crown size={11} />
                Lead
              </button>
            </div>
            {/* Employee search */}
            <div className="flex items-center gap-2">
              <input
                type="text"
                value={teamSearch}
                onChange={e => {
                  setTeamSearch(e.target.value);
                  if (e.target.value.length >= 1) searchEmpMut.mutate(e.target.value);
                  else setEmpResults([]);
                }}
                placeholder="Search employees by name…"
                className="flex-1 text-sm px-3 py-1.5 rounded-md border border-gray-300 dark:border-gray-600 bg-white dark:bg-gray-800 text-gray-900 dark:text-white"
                autoFocus
              />
              <button onClick={() => { setShowAddTeam(false); setTeamSearch(''); setEmpResults([]); }}>
                <X size={16} className="text-gray-400" />
              </button>
            </div>
            {empResults.length > 0 && (
              <div className="space-y-1 max-h-40 overflow-y-auto">
                {empResults
                  .filter(e => !teamMembers.some(m => m.user_id === e.id))
                  .map(emp => (
                    <button
                      key={emp.id}
                      onClick={() => addTeamMut.mutate(emp.id)}
                      disabled={addTeamMut.isPending}
                      className="w-full text-left px-3 py-2 rounded-lg hover:bg-surface text-sm text-gray-900 dark:text-white transition-colors"
                    >
                      <span className="font-medium">{emp.display_name}</span>
                      {emp.email && (
                        <span className="text-gray-500 dark:text-gray-400 ml-2 text-xs">
                          {emp.email}
                        </span>
                      )}
                    </button>
                  ))}
              </div>
            )}
            {teamSearch.length >= 1 && empResults.length === 0 && !searchEmpMut.isPending && (
              <p className="text-xs text-gray-400 dark:text-gray-500 px-1">No matching employees</p>
            )}
          </div>
        )}

        {/* Team member list */}
        {teamMembers.length === 0 ? (
          <p className="text-sm text-gray-400 dark:text-gray-500 py-2">
            No team members assigned yet.
          </p>
        ) : (
          <div className="space-y-2">
            {teamMembers.map(member => (
              <div
                key={member.id}
                className="flex items-center gap-3 p-2.5 rounded-lg bg-surface-secondary border border-border"
              >
                <div className={`flex-shrink-0 w-7 h-7 rounded-full flex items-center justify-center ${member.role === 'lead'
                  ? 'bg-amber-100 dark:bg-amber-900/40'
                  : 'bg-blue-100 dark:bg-blue-900/40'
                  }`}>
                  {member.role === 'lead'
                    ? <Crown size={13} className="text-amber-600 dark:text-amber-400" />
                    : <Users size={13} className="text-blue-600 dark:text-blue-400" />
                  }
                </div>
                <div className="flex-1 min-w-0">
                  <p className="text-sm font-medium text-gray-900 dark:text-gray-100 truncate">
                    {member.display_name}
                  </p>
                  {member.email && (
                    <p className="text-xs text-gray-500 dark:text-gray-400 truncate">
                      {member.email}
                    </p>
                  )}
                </div>
                <Badge variant={member.role === 'lead' ? 'warning' : 'default'}>
                  {member.role === 'lead' ? 'Lead' : 'Member'}
                </Badge>
                {canManage && (
                  <button
                    onClick={() => removeTeamMut.mutate(member.id)}
                    disabled={removeTeamMut.isPending}
                    className="text-gray-300 dark:text-gray-600 hover:text-red-400 dark:hover:text-red-400 transition-colors flex-shrink-0"
                    title="Remove from team"
                  >
                    <X size={15} />
                  </button>
                )}
              </div>
            ))}
          </div>
        )}
      </Card>

      {/* ── Customers Section ─────────────────────────────── */}
      <Card className="p-4">
        <div className="flex items-center justify-between mb-3">
          <h3 className="font-semibold text-gray-900 dark:text-white flex items-center gap-2">
            <UserPlus size={16} />
            Customers
            <Badge variant="neutral" className="text-xs">{customers.length}</Badge>
          </h3>
          {canManage && (
            <Button
              size="sm"
              variant="secondary"
              onClick={() => setShowCustSearch(!showCustSearch)}
            >
              <Link2 size={14} />
              <span className="hidden sm:inline ml-1">Link Customer</span>
            </Button>
          )}
        </div>

        {/* Search to link */}
        {showCustSearch && (
          <div className="mb-3 p-3 bg-surface-secondary rounded-lg border border-border">
            <div className="flex items-center gap-2">
              <input
                type="text"
                value={custSearch}
                onChange={e => {
                  setCustSearch(e.target.value);
                  if (e.target.value.length >= 2) searchCustMut.mutate(e.target.value);
                }}
                placeholder="Search customers..."
                className="flex-1 text-sm px-3 py-1.5 rounded-md border border-gray-300 dark:border-gray-600 bg-white dark:bg-gray-800 text-gray-900 dark:text-white"
                autoFocus
              />
              <button onClick={() => { setShowCustSearch(false); setCustSearch(''); setCustResults([]); }}>
                <X size={16} className="text-gray-400" />
              </button>
            </div>
            {custResults.length > 0 && (
              <div className="mt-2 space-y-1 max-h-40 overflow-y-auto">
                {custResults
                  .filter(c => !customers.some(lc => lc.customer_id === c.id))
                  .map(c => (
                    <button
                      key={c.id}
                      onClick={() => linkCustMut.mutate(c.id)}
                      className="w-full text-left p-2 rounded text-sm hover:bg-gray-100 dark:hover:bg-gray-700 text-gray-700 dark:text-gray-300"
                    >
                      <span className="font-medium">{c.display_name}</span>
                      {c.company_name && (
                        <span className="text-gray-500 dark:text-gray-400 ml-1">({c.company_name})</span>
                      )}
                    </button>
                  ))}
              </div>
            )}
          </div>
        )}

        {/* Linked customers list */}
        {customers.length === 0 ? (
          <p className="text-sm text-gray-400 dark:text-gray-500 text-center py-3">
            No customers linked to this job yet.
          </p>
        ) : (
          <div className="space-y-2">
            {customers.map(c => (
              <div
                key={c.id}
                className="flex items-center justify-between p-3 rounded-lg border border-gray-200 dark:border-gray-700"
              >
                <div className="min-w-0 flex-1">
                  <div className="flex items-center gap-2 flex-wrap">
                    <span className="font-medium text-sm text-gray-900 dark:text-white">
                      {c.customer_name}
                    </span>
                    {c.company_name && (
                      <span className="text-xs text-gray-500 dark:text-gray-400">
                        {c.company_name}
                      </span>
                    )}
                    <Badge variant="neutral" className="text-[10px]">
                      {CONTACT_ROLE_LABELS[c.contact_role]}
                    </Badge>
                    {c.is_primary && <Badge variant="success" className="text-[10px]">Primary</Badge>}
                  </div>
                  <div className="flex items-center gap-3 mt-1 text-xs text-gray-500 dark:text-gray-400">
                    {c.phone && (
                      <span className="flex items-center gap-1">
                        <Phone size={10} /> {c.phone}
                      </span>
                    )}
                    {c.email && (
                      <span className="flex items-center gap-1">
                        <Mail size={10} /> {c.email}
                      </span>
                    )}
                  </div>
                </div>
                {canManage && (
                  <button
                    onClick={() => unlinkCustMut.mutate(c.id)}
                    className="p-1.5 rounded hover:bg-red-50 dark:hover:bg-red-900/20 text-gray-400 hover:text-red-500"
                    title="Unlink customer"
                  >
                    <Unlink size={14} />
                  </button>
                )}
              </div>
            ))}
          </div>
        )}
      </Card>

      {/* ── General Contractors Section ────────────────────── */}
      <Card className="p-4">
        <div className="flex items-center justify-between mb-3">
          <h3 className="font-semibold text-gray-900 dark:text-white flex items-center gap-2">
            <Building2 size={16} />
            General Contractors
            <Badge variant="neutral" className="text-xs">{gcs.length}</Badge>
          </h3>
          {canManage && (
            <Button
              size="sm"
              variant="secondary"
              onClick={() => setShowGcSearch(!showGcSearch)}
            >
              <Link2 size={14} />
              <span className="hidden sm:inline ml-1">Link GC</span>
            </Button>
          )}
        </div>

        {/* Search to link */}
        {showGcSearch && (
          <div className="mb-3 p-3 bg-surface-secondary rounded-lg border border-border">
            <div className="flex items-center gap-2 mb-2">
              <input
                type="text"
                value={gcSearch}
                onChange={e => {
                  setGcSearch(e.target.value);
                  if (e.target.value.length >= 2) searchGcMut.mutate(e.target.value);
                }}
                placeholder="Search general contractors..."
                className="flex-1 text-sm px-3 py-1.5 rounded-md border border-gray-300 dark:border-gray-600 bg-white dark:bg-gray-800 text-gray-900 dark:text-white"
                autoFocus
              />
              <button onClick={() => { setShowGcSearch(false); setGcSearch(''); setGcResults([]); }}>
                <X size={16} className="text-gray-400" />
              </button>
            </div>
            <div className="flex items-center gap-2 mb-2">
              <span className="text-xs text-gray-500 dark:text-gray-400">Relationship:</span>
              <select
                value={gcRelationship}
                onChange={e => setGcRelationship(e.target.value as GCRelationship)}
                className="text-xs px-2 py-1 rounded border border-gray-300 dark:border-gray-600 bg-white dark:bg-gray-800 text-gray-700 dark:text-gray-300"
              >
                <option value="they_are_gc">They hired us</option>
                <option value="we_hired_them">We hired them</option>
              </select>
            </div>
            {gcResults.length > 0 && (
              <div className="space-y-1 max-h-40 overflow-y-auto">
                {gcResults
                  .filter(g => !gcs.some(lg => lg.gc_id === g.id))
                  .map(g => (
                    <button
                      key={g.id}
                      onClick={() => linkGcMut.mutate(g.id)}
                      className="w-full text-left p-2 rounded text-sm hover:bg-gray-100 dark:hover:bg-gray-700 text-gray-700 dark:text-gray-300"
                    >
                      <span className="font-medium">{g.company_name}</span>
                      <Badge variant="neutral" className="text-[10px] ml-2">{g.gc_code}</Badge>
                    </button>
                  ))}
              </div>
            )}
          </div>
        )}

        {/* Linked GCs list */}
        {gcs.length === 0 ? (
          <p className="text-sm text-gray-400 dark:text-gray-500 text-center py-3">
            No general contractors linked to this job yet.
          </p>
        ) : (
          <div className="space-y-2">
            {gcs.map(g => (
              <div
                key={g.id}
                className="flex items-center justify-between p-3 rounded-lg border border-gray-200 dark:border-gray-700"
              >
                <div className="min-w-0 flex-1">
                  <div className="flex items-center gap-2 flex-wrap">
                    <span className="font-medium text-sm text-gray-900 dark:text-white">
                      {g.company_name}
                    </span>
                    <Badge variant="neutral" className="text-[10px] font-mono">
                      {g.gc_code}
                    </Badge>
                    <Badge
                      variant={g.relationship === 'they_are_gc' ? 'success' : 'warning'}
                      className="text-[10px]"
                    >
                      {GC_RELATIONSHIP_LABELS[g.relationship]}
                    </Badge>
                    {g.is_primary && <Badge variant="success" className="text-[10px]">Primary</Badge>}
                  </div>
                  <div className="flex items-center gap-3 mt-1 text-xs text-gray-500 dark:text-gray-400">
                    <span className="capitalize">{g.trade_type.replace('_', ' ')}</span>
                    {g.phone && (
                      <span className="flex items-center gap-1">
                        <Phone size={10} /> {g.phone}
                      </span>
                    )}
                    {g.contract_number && (
                      <span>Contract: {g.contract_number}</span>
                    )}
                  </div>
                </div>
                {canManage && (
                  <button
                    onClick={() => unlinkGcMut.mutate(g.id)}
                    className="p-1.5 rounded hover:bg-red-50 dark:hover:bg-red-900/20 text-gray-400 hover:text-red-500"
                    title="Unlink GC"
                  >
                    <Unlink size={14} />
                  </button>
                )}
              </div>
            ))}
          </div>
        )}
      </Card>
    </div>
  );
}
