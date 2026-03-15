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
  Pause, RotateCcw, DollarSign,
  Wrench, MessageSquare,
} from 'lucide-react';
import { PageSpinner } from '../../../components/ui/Spinner';
import { Button } from '../../../components/ui/Button';
import { Badge } from '../../../components/ui/Badge';
import { useAuthStore } from '../../../stores/auth-store';
import { useClockStore } from '../../../stores/clock-store';
import { PERMISSIONS } from '../../../lib/constants';
import { getJob, updateJobStatus } from '../../../api/jobs';
import {
  JOB_STATUS_LABELS,
  ON_CALL_TYPE_LABELS,
  type JobStatus, type OnCallType,
} from '../../../lib/types';
import { ClockOutFlow } from '../components/ClockOutFlow';
import { NotebookTab } from '../components/job-detail/NotebookTab';
import { OverviewTab } from '../components/job-detail/OverviewTab';
import { PeopleTab } from '../components/job-detail/PeopleTab';
import { LaborTab } from '../components/job-detail/LaborTab';
import { PartsTab } from '../components/job-detail/PartsTab';
import { ToolsTab } from '../components/job-detail/ToolsTab';
import { ChatTab } from '../components/job-detail/ChatTab';
import { QuestionsTab } from '../components/job-detail/QuestionsTab';
import { CostsTab } from '../components/job-detail/CostsTab';

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
    enabled: !isNaN(jobId),
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
