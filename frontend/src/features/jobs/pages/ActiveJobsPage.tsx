/**
 * ActiveJobsPage — list of active field jobs with filters and search.
 *
 * Shows job cards with address, status, navigate button, and active worker count.
 * Supports filtering by status, job type, priority, and search.
 */

import { useState, useEffect, useCallback } from 'react';
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import { Plus, Search, Filter, Briefcase, X } from 'lucide-react';
import { useNavigate } from 'react-router-dom';
import { PageSpinner } from '../../../components/ui/Spinner';
import { EmptyState } from '../../../components/ui/EmptyState';
import { Button } from '../../../components/ui/Button';
import { Input } from '../../../components/ui/Input';
import { Modal } from '../../../components/ui/Modal';
import { useAuthStore } from '../../../stores/auth-store';
import { PERMISSIONS } from '../../../lib/constants';
import { getActiveJobs, createJob } from '../../../api/jobs';
import { JobCard } from '../components/JobCard';
import type { JobCreate, JobStatus, JobPriority, JobType } from '../../../lib/types';

const STATUS_OPTIONS: { label: string; value: JobStatus | 'all' }[] = [
  { label: 'All', value: 'all' },
  { label: 'Active', value: 'active' },
  { label: 'On Hold', value: 'on_hold' },
  { label: 'Completed', value: 'completed' },
  { label: 'Cancelled', value: 'cancelled' },
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

export function ActiveJobsPage() {
  const navigate = useNavigate();
  const queryClient = useQueryClient();
  const { hasPermission } = useAuthStore();
  const canManage = hasPermission(PERMISSIONS.MANAGE_JOBS);

  // Filters
  const [search, setSearch] = useState('');
  const [debouncedSearch, setDebouncedSearch] = useState('');
  const [statusFilter, setStatusFilter] = useState<string>('all');
  const [typeFilter, setTypeFilter] = useState<string>('all');
  const [priorityFilter, setPriorityFilter] = useState<string>('all');
  const [showFilters, setShowFilters] = useState(false);

  // Create modal
  const [showCreate, setShowCreate] = useState(false);

  // Debounce search
  useEffect(() => {
    const timer = setTimeout(() => setDebouncedSearch(search), 300);
    return () => clearTimeout(timer);
  }, [search]);

  const { data: jobs, isLoading, error } = useQuery({
    queryKey: ['jobs-active', debouncedSearch, statusFilter, typeFilter, priorityFilter],
    queryFn: () => getActiveJobs({
      search: debouncedSearch || undefined,
      status: statusFilter === 'all' ? undefined : statusFilter,
      job_type: typeFilter === 'all' ? undefined : typeFilter,
      priority: priorityFilter === 'all' ? undefined : priorityFilter,
    }),
    staleTime: 15_000,
  });

  const hasActiveFilters = statusFilter !== 'all' || typeFilter !== 'all' || priorityFilter !== 'all';

  const clearFilters = useCallback(() => {
    setStatusFilter('all');
    setTypeFilter('all');
    setPriorityFilter('all');
  }, []);

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
      {/* Header with search and actions */}
      <div className="flex items-center gap-3">
        <div className="flex-1">
          <Input
            placeholder="Search jobs..."
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

        <Button
          variant={hasActiveFilters ? 'primary' : 'secondary'}
          size="sm"
          icon={<Filter className="h-4 w-4" />}
          onClick={() => setShowFilters(!showFilters)}
        >
          Filter
        </Button>

        {canManage && (
          <Button
            size="sm"
            icon={<Plus className="h-4 w-4" />}
            onClick={() => setShowCreate(true)}
          >
            New Job
          </Button>
        )}
      </div>

      {/* Filter chips */}
      {showFilters && (
        <div className="flex flex-wrap gap-2 p-3 bg-surface-secondary rounded-lg border border-border">
          <div className="flex items-center gap-2">
            <span className="text-xs font-medium text-gray-500 dark:text-gray-400">Status:</span>
            <div className="flex gap-1">
              {STATUS_OPTIONS.map((opt) => (
                <button
                  key={opt.value}
                  onClick={() => setStatusFilter(opt.value)}
                  className={`px-2 py-0.5 text-xs rounded-full transition-colors ${
                    statusFilter === opt.value
                      ? 'bg-blue-100 dark:bg-blue-900/40 text-blue-700 dark:text-blue-300'
                      : 'bg-gray-100 dark:bg-gray-800 text-gray-600 dark:text-gray-400 hover:bg-gray-200 dark:hover:bg-gray-700'
                  }`}
                >
                  {opt.label}
                </button>
              ))}
            </div>
          </div>

          <div className="flex items-center gap-2">
            <span className="text-xs font-medium text-gray-500 dark:text-gray-400">Type:</span>
            <select
              value={typeFilter}
              onChange={(e) => setTypeFilter(e.target.value)}
              className="text-xs rounded-md border border-border bg-surface px-2 py-1"
            >
              {TYPE_OPTIONS.map((opt) => (
                <option key={opt.value} value={opt.value}>{opt.label}</option>
              ))}
            </select>
          </div>

          <div className="flex items-center gap-2">
            <span className="text-xs font-medium text-gray-500 dark:text-gray-400">Priority:</span>
            <select
              value={priorityFilter}
              onChange={(e) => setPriorityFilter(e.target.value)}
              className="text-xs rounded-md border border-border bg-surface px-2 py-1"
            >
              {PRIORITY_OPTIONS.map((opt) => (
                <option key={opt.value} value={opt.value}>{opt.label}</option>
              ))}
            </select>
          </div>

          {hasActiveFilters && (
            <button
              onClick={clearFilters}
              className="text-xs text-blue-500 hover:text-blue-700 dark:hover:text-blue-300"
            >
              Clear filters
            </button>
          )}
        </div>
      )}

      {/* Job grid */}
      {!jobs || jobs.length === 0 ? (
        <EmptyState
          icon={<Briefcase className="h-12 w-12" />}
          title={debouncedSearch || hasActiveFilters ? 'No jobs match filters' : 'No Active Jobs'}
          description={
            debouncedSearch || hasActiveFilters
              ? 'Try adjusting your search or filters.'
              : 'Create your first job to get started tracking field work.'
          }
          action={
            canManage && !debouncedSearch && !hasActiveFilters ? (
              <Button icon={<Plus className="h-4 w-4" />} onClick={() => setShowCreate(true)}>
                Create Job
              </Button>
            ) : undefined
          }
        />
      ) : (
        <div className="grid grid-cols-1 md:grid-cols-2 xl:grid-cols-3 gap-3">
          {jobs.map((job) => (
            <JobCard key={job.id} job={job} />
          ))}
        </div>
      )}

      {/* Create Job Modal */}
      {showCreate && (
        <CreateJobModal
          isOpen={showCreate}
          onClose={() => setShowCreate(false)}
          onCreated={(jobId) => {
            setShowCreate(false);
            queryClient.invalidateQueries({ queryKey: ['jobs-active'] });
            navigate(`/jobs/${jobId}`);
          }}
        />
      )}
    </div>
  );
}


// ── Create Job Modal (inline for now) ────────────────────────────

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

        <div className="grid grid-cols-2 gap-3">
          <div>
            <label className="block text-sm font-medium text-gray-700 dark:text-gray-300 mb-1">
              Job Type
            </label>
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
            <label className="block text-sm font-medium text-gray-700 dark:text-gray-300 mb-1">
              Priority
            </label>
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
          <Button type="submit" isLoading={createMutation.isPending}>
            Create Job
          </Button>
        </div>
      </form>
    </Modal>
  );
}
