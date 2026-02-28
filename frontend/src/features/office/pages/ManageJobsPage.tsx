/**
 * ManageJobsPage — Office admin page for managing ALL jobs across all statuses.
 *
 * Unlike ActiveJobsPage (which is for field workers to see their current jobs),
 * this is the boss/admin view for managing the full job lifecycle:
 * - See all jobs (active, on hold, completed, cancelled)
 * - Create new jobs
 * - Quick status changes from the list
 * - Edit any job
 * - Filter and sort by any dimension
 *
 * Lives under Office > Manage Jobs tab.
 */

import { useState, useEffect, useCallback } from 'react';
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import {
  Plus, Search, Briefcase, X, ChevronRight, Settings,
  Pause, CheckCircle, XCircle, RotateCcw, Edit2,
  MapPin, Users, Clock,
} from 'lucide-react';
import { useNavigate } from 'react-router-dom';
import { PageSpinner } from '../../../components/ui/Spinner';
import { EmptyState } from '../../../components/ui/EmptyState';
import { Button } from '../../../components/ui/Button';
import { Input } from '../../../components/ui/Input';
import { Badge } from '../../../components/ui/Badge';
import { Modal } from '../../../components/ui/Modal';
import { getActiveJobs, createJob, updateJobStatus } from '../../../api/jobs';
import { EditJobModal } from '../../jobs/components/EditJobModal';
import { ManageBillRateTypesModal } from '../components/ManageBillRateTypesModal';
import { JOB_STATUS_LABELS, ON_CALL_TYPE_LABELS } from '../../../lib/types';
import type { JobCreate, JobListItem, JobResponse, JobStatus, JobPriority, JobType, OnCallType } from '../../../lib/types';

const STATUS_OPTIONS: { label: string; value: JobStatus | 'all' }[] = [
  { label: 'All', value: 'all' },
  { label: 'Pending', value: 'pending' },
  { label: 'Active', value: 'active' },
  { label: 'On Hold', value: 'on_hold' },
  { label: 'Completed', value: 'completed' },
  { label: 'Cancelled', value: 'cancelled' },
  { label: 'Continuous Maint.', value: 'continuous_maintenance' },
  { label: 'On Call / Warranty', value: 'on_call' },
];

const TYPE_OPTIONS: { label: string; value: JobType | 'all' }[] = [
  { label: 'All Types', value: 'all' },
  { label: 'Service', value: 'service' },
  { label: 'New Construction', value: 'new_construction' },
  { label: 'Remodel', value: 'remodel' },
  { label: 'Maintenance', value: 'maintenance' },
  { label: 'Emergency', value: 'emergency' },
];

const PRIORITY_OPTIONS: { label: string; value: JobPriority | 'all' }[] = [
  { label: 'All Priorities', value: 'all' },
  { label: 'Low', value: 'low' },
  { label: 'Normal', value: 'normal' },
  { label: 'High', value: 'high' },
  { label: 'Urgent', value: 'urgent' },
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

/** Color classes for status filter pills — active (selected) and idle (unselected) variants */
const STATUS_PILL_COLORS: Record<string, { active: string; idle: string }> = {
  all:      { active: 'border-blue-300 dark:border-blue-600 bg-blue-50 dark:bg-blue-900/20 text-blue-700 dark:text-blue-300',
              idle:   'border-border bg-surface hover:bg-surface-secondary text-gray-600 dark:text-gray-400' },
  pending:  { active: 'border-amber-300 dark:border-amber-600 bg-amber-50 dark:bg-amber-900/20 text-amber-700 dark:text-amber-300',
              idle:   'border-border bg-surface hover:bg-amber-50 dark:hover:bg-amber-900/10 text-amber-600 dark:text-amber-400' },
  active:   { active: 'border-green-300 dark:border-green-600 bg-green-50 dark:bg-green-900/20 text-green-700 dark:text-green-300',
              idle:   'border-border bg-surface hover:bg-green-50 dark:hover:bg-green-900/10 text-green-600 dark:text-green-400' },
  on_hold:  { active: 'border-amber-300 dark:border-amber-600 bg-amber-50 dark:bg-amber-900/20 text-amber-700 dark:text-amber-300',
              idle:   'border-border bg-surface hover:bg-amber-50 dark:hover:bg-amber-900/10 text-amber-600 dark:text-amber-400' },
  continuous_maintenance:
            { active: 'border-green-300 dark:border-green-600 bg-green-50 dark:bg-green-900/20 text-green-700 dark:text-green-300',
              idle:   'border-border bg-surface hover:bg-green-50 dark:hover:bg-green-900/10 text-green-600 dark:text-green-400' },
  on_call:  { active: 'border-sky-300 dark:border-sky-600 bg-sky-50 dark:bg-sky-900/20 text-sky-700 dark:text-sky-300',
              idle:   'border-border bg-surface hover:bg-sky-50 dark:hover:bg-sky-900/10 text-sky-600 dark:text-sky-400' },
  completed:{ active: 'border-gray-300 dark:border-gray-600 bg-gray-100 dark:bg-gray-800 text-gray-700 dark:text-gray-300',
              idle:   'border-border bg-surface hover:bg-gray-100 dark:hover:bg-gray-800 text-gray-500 dark:text-gray-400' },
  cancelled:{ active: 'border-red-300 dark:border-red-600 bg-red-50 dark:bg-red-900/20 text-red-700 dark:text-red-300',
              idle:   'border-border bg-surface hover:bg-red-50 dark:hover:bg-red-900/10 text-red-600 dark:text-red-400' },
};

const PRIORITY_DOTS: Record<JobPriority, string> = {
  low: 'bg-gray-300 dark:bg-gray-600',
  normal: 'bg-blue-500',
  high: 'bg-orange-500',
  urgent: 'bg-red-500',
};

export function ManageJobsPage() {
  const navigate = useNavigate();
  const queryClient = useQueryClient();

  // Filters
  const [search, setSearch] = useState('');
  const [debouncedSearch, setDebouncedSearch] = useState('');
  const [statusFilter, setStatusFilter] = useState<string>('all');
  const [typeFilter, setTypeFilter] = useState<string>('all');
  const [priorityFilter, setPriorityFilter] = useState<string>('all');

  // Modals
  const [showCreate, setShowCreate] = useState(false);
  const [editingJob, setEditingJob] = useState<JobListItem | null>(null);
  const [showBillRateTypes, setShowBillRateTypes] = useState(false);

  // Debounce search
  useEffect(() => {
    const timer = setTimeout(() => setDebouncedSearch(search), 300);
    return () => clearTimeout(timer);
  }, [search]);

  const { data: jobs, isLoading, error } = useQuery({
    queryKey: ['jobs-all', debouncedSearch, statusFilter, typeFilter, priorityFilter],
    queryFn: () => getActiveJobs({
      search: debouncedSearch || undefined,
      status: statusFilter === 'all' ? undefined : statusFilter,
      job_type: typeFilter === 'all' ? undefined : typeFilter,
      priority: priorityFilter === 'all' ? undefined : priorityFilter,
    }),
    staleTime: 15_000,
  });

  const statusMutation = useMutation({
    mutationFn: ({ jobId, status }: { jobId: number; status: string }) =>
      updateJobStatus(jobId, status),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['jobs-all'] });
      queryClient.invalidateQueries({ queryKey: ['jobs-active'] });
    },
  });

  const hasActiveFilters = statusFilter !== 'all' || typeFilter !== 'all' || priorityFilter !== 'all';

  const clearFilters = useCallback(() => {
    setStatusFilter('all');
    setTypeFilter('all');
    setPriorityFilter('all');
  }, []);

  // Count by status for quick stats
  const counts = {
    total: jobs?.length ?? 0,
    pending: jobs?.filter((j) => j.status === 'pending').length ?? 0,
    active: jobs?.filter((j) => j.status === 'active').length ?? 0,
    on_hold: jobs?.filter((j) => j.status === 'on_hold').length ?? 0,
    completed: jobs?.filter((j) => j.status === 'completed').length ?? 0,
    cancelled: jobs?.filter((j) => j.status === 'cancelled').length ?? 0,
    continuous_maintenance: jobs?.filter((j) => j.status === 'continuous_maintenance').length ?? 0,
    on_call: jobs?.filter((j) => j.status === 'on_call').length ?? 0,
  };

  if (isLoading) return <PageSpinner label="Loading jobs..." />;

  if (error) {
    return (
      <div className="text-center py-16">
        <p className="text-red-500">Failed to load jobs. Please try again.</p>
      </div>
    );
  }

  return (
    <div className="space-y-4">
      {/* Header */}
      <div className="flex items-center justify-between">
        <div>
          <h2 className="text-lg font-semibold text-gray-900 dark:text-gray-100">Manage Jobs</h2>
          <p className="text-sm text-gray-500 dark:text-gray-400">
            Create, edit, and manage all jobs across all statuses.
          </p>
        </div>
        <div className="flex items-center gap-2">
          <Button
            variant="secondary"
            size="sm"
            icon={<Settings className="h-4 w-4" />}
            onClick={() => setShowBillRateTypes(true)}
          >
            Bill Rate Types
          </Button>
          <Button
            size="sm"
            icon={<Plus className="h-4 w-4" />}
            onClick={() => setShowCreate(true)}
          >
            New Job
          </Button>
        </div>
      </div>

      {/* Quick stats */}
      <div className="flex flex-wrap gap-1.5">
        {[
          { label: 'All', count: counts.total, filter: 'all' },
          { label: 'Pending', count: counts.pending, filter: 'pending' },
          { label: 'Active', count: counts.active, filter: 'active' },
          { label: 'On Hold', count: counts.on_hold, filter: 'on_hold' },
          { label: 'Cont. Maint.', count: counts.continuous_maintenance, filter: 'continuous_maintenance' },
          { label: 'On Call / Warr.', count: counts.on_call, filter: 'on_call' },
          { label: 'Completed', count: counts.completed, filter: 'completed' },
          { label: 'Cancelled', count: counts.cancelled, filter: 'cancelled' },
        ].map((stat) => {
          const colors = STATUS_PILL_COLORS[stat.filter] ?? STATUS_PILL_COLORS.all;
          const isSelected = statusFilter === stat.filter;
          return (
            <button
              key={stat.label}
              onClick={() => setStatusFilter(stat.filter)}
              className={`px-2.5 py-1.5 rounded-md border text-xs font-medium transition-colors ${
                isSelected ? colors.active : colors.idle
              }`}
            >
              {stat.label} <span className="font-bold ml-0.5">{stat.count}</span>
            </button>
          );
        })}
      </div>

      {/* Search + Filters */}
      <div className="flex items-center gap-3">
        <div className="flex-1">
          <Input
            placeholder="Search jobs by name, number, or customer..."
            value={search}
            onChange={(e) => setSearch(e.target.value)}
            icon={<Search className="h-4 w-4" />}
            iconRight={
              search ? (
                <button onClick={() => setSearch('')} className="text-gray-400 hover:text-gray-600">
                  <X className="h-4 w-4" />
                </button>
              ) : undefined
            }
          />
        </div>
        <select
          value={typeFilter}
          onChange={(e) => setTypeFilter(e.target.value)}
          className="text-xs rounded-md border border-border bg-surface px-2 py-2"
        >
          {TYPE_OPTIONS.map((opt) => (
            <option key={opt.value} value={opt.value}>{opt.label}</option>
          ))}
        </select>
        <select
          value={priorityFilter}
          onChange={(e) => setPriorityFilter(e.target.value)}
          className="text-xs rounded-md border border-border bg-surface px-2 py-2"
        >
          {PRIORITY_OPTIONS.map((opt) => (
            <option key={opt.value} value={opt.value}>{opt.label}</option>
          ))}
        </select>
        {hasActiveFilters && (
          <button onClick={clearFilters} className="text-xs text-blue-500 hover:text-blue-700">
            Clear
          </button>
        )}
      </div>

      {/* Jobs Table */}
      {!jobs || jobs.length === 0 ? (
        <EmptyState
          icon={<Briefcase className="h-12 w-12" />}
          title={debouncedSearch || hasActiveFilters ? 'No jobs match filters' : 'No Jobs Yet'}
          description="Create your first job to get started."
          action={
            !debouncedSearch && !hasActiveFilters ? (
              <Button icon={<Plus className="h-4 w-4" />} onClick={() => setShowCreate(true)}>
                Create Job
              </Button>
            ) : undefined
          }
        />
      ) : (
        <div className="overflow-x-auto border border-border rounded-lg">
          <table className="w-full text-sm">
            <thead>
              <tr className="bg-surface-secondary border-b border-border text-left text-xs text-gray-500 dark:text-gray-400 uppercase tracking-wider">
                <th className="px-3 py-2 font-medium">Job</th>
                <th className="px-3 py-2 font-medium">Customer</th>
                <th className="px-3 py-2 font-medium">Status</th>
                <th className="px-3 py-2 font-medium text-center">Priority</th>
                <th className="px-3 py-2 font-medium">Type</th>
                <th className="px-3 py-2 font-medium text-center">Tasks</th>
                <th className="px-3 py-2 font-medium text-right">Hours</th>
                <th className="px-3 py-2 font-medium text-right">Parts $</th>
                <th className="px-3 py-2 font-medium text-center">Actions</th>
              </tr>
            </thead>
            <tbody className="divide-y divide-border">
              {jobs.map((job) => (
                <tr
                  key={job.id}
                  className="hover:bg-surface-secondary/50 transition-colors group cursor-pointer"
                  onClick={() => navigate(`/jobs/${job.id}`)}
                >
                  <td className="px-3 py-2.5">
                    <div className="font-medium text-gray-900 dark:text-gray-100">
                      {job.job_name}
                    </div>
                    <div className="text-xs text-gray-500 dark:text-gray-400 font-mono">
                      #{job.job_number}
                    </div>
                  </td>
                  <td className="px-3 py-2.5 text-gray-600 dark:text-gray-300">
                    {job.customer_name}
                  </td>
                  <td className="px-3 py-2.5">
                    <div className="flex flex-col gap-0.5">
                      <Badge variant={STATUS_COLORS[job.status]}>
                        {job.status === 'on_call' && job.on_call_type
                          ? ON_CALL_TYPE_LABELS[job.on_call_type as OnCallType]
                          : JOB_STATUS_LABELS[job.status]}
                      </Badge>
                      {job.status === 'on_call' && job.on_call_type === 'warranty' && job.warranty_end_date && (
                        <span className="text-[10px] text-gray-500 dark:text-gray-400">
                          Exp {new Date(job.warranty_end_date + 'T00:00:00').toLocaleDateString('en-US', { month: 'short', day: 'numeric', year: '2-digit' })}
                        </span>
                      )}
                    </div>
                  </td>
                  <td className="px-3 py-2.5 text-center">
                    <div className="flex items-center justify-center gap-1.5">
                      <div className={`w-2 h-2 rounded-full ${PRIORITY_DOTS[job.priority]}`} />
                      <span className="text-xs capitalize text-gray-500 dark:text-gray-400">
                        {job.priority}
                      </span>
                    </div>
                  </td>
                  <td className="px-3 py-2.5 text-xs capitalize text-gray-500 dark:text-gray-400">
                    {job.job_type.replace('_', ' ')}
                  </td>
                  <td className="px-3 py-2.5 text-center">
                    {job.open_task_count > 0 ? (
                      <span className="inline-flex items-center gap-1 px-1.5 py-0.5 text-[10px] font-medium bg-amber-50 dark:bg-amber-900/20 text-amber-600 dark:text-amber-400 rounded-full">
                        {job.open_task_count}
                      </span>
                    ) : (
                      <span className="text-gray-300 dark:text-gray-600">—</span>
                    )}
                  </td>
                  <td className="px-3 py-2.5 text-right tabular-nums text-gray-700 dark:text-gray-300">
                    {job.total_labor_hours.toFixed(1)}
                  </td>
                  <td className="px-3 py-2.5 text-right tabular-nums text-gray-700 dark:text-gray-300">
                    ${job.total_parts_cost.toFixed(0)}
                  </td>
                  <td className="px-3 py-2.5 text-center" onClick={(e) => e.stopPropagation()}>
                    <div className="flex items-center justify-center gap-1">
                      <button
                        onClick={() => setEditingJob(job)}
                        className="p-1 rounded text-gray-400 hover:text-blue-500 hover:bg-blue-50 dark:hover:bg-blue-900/30 transition-colors"
                        title="Edit job"
                      >
                        <Edit2 className="h-3.5 w-3.5" />
                      </button>
                      {job.status === 'pending' && (
                        <button
                          onClick={() => statusMutation.mutate({ jobId: job.id, status: 'active' })}
                          className="p-1 rounded text-gray-400 hover:text-green-500 hover:bg-green-50 dark:hover:bg-green-900/30 transition-colors"
                          title="Activate"
                        >
                          <CheckCircle className="h-3.5 w-3.5" />
                        </button>
                      )}
                      {(job.status === 'active' || job.status === 'continuous_maintenance' || job.status === 'on_call') && (
                        <>
                          <button
                            onClick={() => statusMutation.mutate({ jobId: job.id, status: 'on_hold' })}
                            className="p-1 rounded text-gray-400 hover:text-yellow-500 hover:bg-yellow-50 dark:hover:bg-yellow-900/30 transition-colors"
                            title="Put on hold"
                          >
                            <Pause className="h-3.5 w-3.5" />
                          </button>
                          <button
                            onClick={() => statusMutation.mutate({ jobId: job.id, status: 'completed' })}
                            className="p-1 rounded text-gray-400 hover:text-green-500 hover:bg-green-50 dark:hover:bg-green-900/30 transition-colors"
                            title="Complete"
                          >
                            <CheckCircle className="h-3.5 w-3.5" />
                          </button>
                        </>
                      )}
                      {job.status === 'on_hold' && (
                        <button
                          onClick={() => statusMutation.mutate({ jobId: job.id, status: 'active' })}
                          className="p-1 rounded text-gray-400 hover:text-green-500 hover:bg-green-50 dark:hover:bg-green-900/30 transition-colors"
                          title="Resume"
                        >
                          <RotateCcw className="h-3.5 w-3.5" />
                        </button>
                      )}
                      {(job.status === 'completed' || job.status === 'cancelled') && (
                        <button
                          onClick={() => statusMutation.mutate({ jobId: job.id, status: 'active' })}
                          className="p-1 rounded text-gray-400 hover:text-blue-500 hover:bg-blue-50 dark:hover:bg-blue-900/30 transition-colors"
                          title="Reopen"
                        >
                          <RotateCcw className="h-3.5 w-3.5" />
                        </button>
                      )}
                    </div>
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      )}

      {/* Create Job Modal */}
      {showCreate && (
        <CreateJobModal
          isOpen={showCreate}
          onClose={() => setShowCreate(false)}
          onCreated={(jobId) => {
            setShowCreate(false);
            queryClient.invalidateQueries({ queryKey: ['jobs-all'] });
            queryClient.invalidateQueries({ queryKey: ['jobs-active'] });
            navigate(`/jobs/${jobId}`);
          }}
        />
      )}

      {/* Edit Job Modal */}
      {editingJob && (
        <EditJobModal
          isOpen={!!editingJob}
          onClose={() => setEditingJob(null)}
          job={editingJob as unknown as import('../../../lib/types').JobResponse}
          onSaved={() => {
            setEditingJob(null);
            queryClient.invalidateQueries({ queryKey: ['jobs-all'] });
          }}
        />
      )}

      {/* Bill Rate Types Modal */}
      <ManageBillRateTypesModal
        isOpen={showBillRateTypes}
        onClose={() => setShowBillRateTypes(false)}
      />
    </div>
  );
}


// ── Create Job Modal (matches the one in ActiveJobsPage) ─────────

interface CreateJobModalProps {
  isOpen: boolean;
  onClose: () => void;
  onCreated: (jobId: number) => void;
}

function CreateJobModal({ isOpen, onClose, onCreated }: CreateJobModalProps) {
  const [form, setForm] = useState<JobCreate>({
    job_number: '',
    job_name: '',
    customer_name: '',
    status: 'active',
    priority: 'normal',
    job_type: 'service',
  });
  const [errorMsg, setErrorMsg] = useState('');

  const createMutation = useMutation({
    mutationFn: (data: JobCreate) => createJob(data),
    onSuccess: (job) => onCreated(job.id),
    onError: (err: Error) => setErrorMsg(err.message || 'Failed to create job'),
  });

  const handleSubmit = (e: React.FormEvent) => {
    e.preventDefault();
    if (!form.job_number.trim() || !form.job_name.trim() || !form.customer_name.trim()) {
      setErrorMsg('Job number, name, and customer are required.');
      return;
    }
    setErrorMsg('');
    createMutation.mutate(form);
  };

  const update = (field: keyof JobCreate, value: string) =>
    setForm((prev) => ({ ...prev, [field]: value }));

  return (
    <Modal isOpen={isOpen} onClose={onClose} title="Create New Job" size="md">
      {errorMsg && (
        <div className="mb-4 p-3 bg-red-50 dark:bg-red-900/20 border border-red-200 dark:border-red-800 rounded-lg">
          <p className="text-sm text-red-600 dark:text-red-400">{errorMsg}</p>
        </div>
      )}

      <form onSubmit={handleSubmit} className="space-y-4">
        <div className="grid grid-cols-2 gap-3">
          <Input
            label="Job Number"
            value={form.job_number}
            onChange={(e) => update('job_number', e.target.value)}
            placeholder="e.g. J-2024-001"
            required
          />
          <Input
            label="Job Name"
            value={form.job_name}
            onChange={(e) => update('job_name', e.target.value)}
            placeholder="Smith Residence Rewire"
            required
          />
        </div>

        <Input
          label="Customer Name"
          value={form.customer_name}
          onChange={(e) => update('customer_name', e.target.value)}
          placeholder="John Smith"
          required
        />

        <Input
          label="Address"
          value={form.address_line1 ?? ''}
          onChange={(e) => update('address_line1', e.target.value)}
          placeholder="123 Main St"
        />

        <div className="grid grid-cols-3 gap-3">
          <Input label="City" value={form.city ?? ''} onChange={(e) => update('city', e.target.value)} />
          <Input label="State" value={form.state ?? ''} onChange={(e) => update('state', e.target.value)} />
          <Input label="ZIP" value={form.zip ?? ''} onChange={(e) => update('zip', e.target.value)} />
        </div>

        <div className="grid grid-cols-2 gap-3">
          <div>
            <label className="block text-sm font-medium text-gray-700 dark:text-gray-300 mb-1">Job Type</label>
            <select
              value={form.job_type}
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
            <label className="block text-sm font-medium text-gray-700 dark:text-gray-300 mb-1">Priority</label>
            <select
              value={form.priority}
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

        <Input
          label="Notes"
          value={form.notes ?? ''}
          onChange={(e) => update('notes', e.target.value)}
          placeholder="Optional notes..."
        />

        <div className="flex justify-end gap-2 pt-2">
          <Button variant="secondary" onClick={onClose}>Cancel</Button>
          <Button type="submit" isLoading={createMutation.isPending}>Create Job</Button>
        </div>
      </form>
    </Modal>
  );
}
