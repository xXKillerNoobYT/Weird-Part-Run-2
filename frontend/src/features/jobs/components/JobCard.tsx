/**
 * JobCard — card component for a job in the active jobs list.
 *
 * Shows job number, name, customer, address, status badge, priority indicator,
 * active worker count, and a "Take Me There" navigation button that opens
 * Google Maps directions.
 */

import { MapPin, Navigation, Users, Clock, ChevronRight, ListTodo, CheckCircle2, Package } from 'lucide-react';
import { useNavigate } from 'react-router-dom';
import { Badge } from '../../../components/ui/Badge';
import { JOB_STATUS_LABELS, ON_CALL_TYPE_LABELS } from '../../../lib/types';
import type { JobListItem, JobStatus, JobPriority, OnCallType } from '../../../lib/types';

interface JobCardProps {
  job: JobListItem;
  onClockIn?: (jobId: number) => void;
}

const STATUS_COLORS: Record<JobStatus, 'success' | 'warning' | 'default' | 'danger'> = {
  pending: 'warning',
  active: 'success',
  on_hold: 'warning',
  completed: 'default',
  cancelled: 'danger',
  continuous_maintenance: 'success',
  on_call: 'success',
};

const PRIORITY_COLORS: Record<JobPriority, string> = {
  low: 'text-gray-400 dark:text-gray-500',
  normal: 'text-blue-500 dark:text-blue-400',
  high: 'text-orange-500 dark:text-orange-400',
  urgent: 'text-red-500 dark:text-red-400',
};

function formatAddress(job: JobListItem): string | null {
  const parts = [job.address_line1, job.city, job.state].filter(Boolean);
  return parts.length > 0 ? parts.join(', ') : null;
}

function openGoogleMaps(job: JobListItem) {
  const { gps_lat, gps_lng } = job;
  if (gps_lat && gps_lng) {
    window.open(
      `https://www.google.com/maps/dir/?api=1&destination=${gps_lat},${gps_lng}`,
      '_blank'
    );
  } else {
    // Fallback to address string
    const addr = formatAddress(job);
    if (addr) {
      window.open(
        `https://www.google.com/maps/dir/?api=1&destination=${encodeURIComponent(addr)}`,
        '_blank'
      );
    }
  }
}

export function JobCard({ job, onClockIn }: JobCardProps) {
  const navigate = useNavigate();
  const address = formatAddress(job);
  const hasLocation = !!(job.gps_lat || address);

  return (
    <div
      className="group bg-surface border border-border rounded-xl p-4 hover:border-blue-300 dark:hover:border-blue-600 transition-colors cursor-pointer"
      onClick={() => navigate(`/jobs/${job.id}`)}
    >
      {/* Header row — job number + status + priority */}
      <div className="flex items-start justify-between mb-2">
        <div className="flex-1 min-w-0">
          <div className="flex items-center gap-2 mb-1">
            <span className="text-xs font-mono text-gray-500 dark:text-gray-400">
              #{job.job_number}
            </span>
            <Badge variant={STATUS_COLORS[job.status]}>{JOB_STATUS_LABELS[job.status]}</Badge>
            {job.priority !== 'normal' && (
              <span className={`text-xs font-medium capitalize ${PRIORITY_COLORS[job.priority]}`}>
                {job.priority}
              </span>
            )}
          </div>
          <h3 className="text-sm font-semibold text-gray-900 dark:text-gray-100 truncate">
            {job.job_name}
          </h3>
          <p className="text-xs text-gray-500 dark:text-gray-400 truncate">
            {job.customer_name}
          </p>
        </div>

        <ChevronRight className="h-4 w-4 text-gray-400 dark:text-gray-500 opacity-0 group-hover:opacity-100 transition-opacity mt-1" />
      </div>

      {/* Address + Navigate button */}
      {address && (
        <div className="flex items-center gap-2 mb-3">
          <MapPin className="h-3.5 w-3.5 text-gray-400 dark:text-gray-500 shrink-0" />
          <span className="text-xs text-gray-500 dark:text-gray-400 truncate flex-1">
            {address}
          </span>
          {hasLocation && (
            <button
              onClick={(e) => {
                e.stopPropagation();
                openGoogleMaps(job);
              }}
              className="flex items-center gap-1 px-2 py-1 text-xs font-medium text-blue-600 dark:text-blue-400 bg-blue-50 dark:bg-blue-900/30 rounded-md hover:bg-blue-100 dark:hover:bg-blue-900/50 transition-colors"
              title="Open in Google Maps"
            >
              <Navigation className="h-3 w-3" />
              Navigate
            </button>
          )}
        </div>
      )}

      {/* Stats row */}
      <div className="flex items-center gap-4 text-xs text-gray-500 dark:text-gray-400">
        <div className="flex items-center gap-1">
          <Users className="h-3.5 w-3.5" />
          <span>{job.active_workers} on-site</span>
        </div>
        <div className="flex items-center gap-1">
          <Clock className="h-3.5 w-3.5" />
          <span>{job.total_labor_hours.toFixed(1)}h total</span>
        </div>
        {job.total_parts_cost > 0 && (
          <span className="ml-auto text-green-600 dark:text-green-400">
            ${job.total_parts_cost.toFixed(0)} parts
          </span>
        )}
      </div>

      {/* Task badges — specifically for on_call/warranty jobs dual-listed in Active */}
      {(job.status === 'on_call' || job.status === 'continuous_maintenance') && job.open_task_count > 0 && (
        <div className="mt-2 pt-2 border-t border-border flex items-center gap-2 flex-wrap">
          <span className="inline-flex items-center gap-1 px-2 py-0.5 text-[10px] font-medium bg-blue-50 dark:bg-blue-900/20 text-blue-600 dark:text-blue-400 border border-blue-200 dark:border-blue-800 rounded-full">
            <ListTodo className="h-3 w-3" />
            {job.on_call_type ? ON_CALL_TYPE_LABELS[job.on_call_type as OnCallType] : JOB_STATUS_LABELS[job.status]} · {job.open_task_count} tasks open
          </span>
        </div>
      )}

      {/* Lead user badge */}
      {job.lead_user_name && (
        <div className={`mt-2 pt-2 ${!(job.status === 'on_call' || job.status === 'continuous_maintenance') || job.open_task_count === 0 ? 'border-t border-border' : ''}`}>
          <span className="text-xs text-gray-500 dark:text-gray-400">
            Lead: <span className="font-medium text-gray-700 dark:text-gray-300">{job.lead_user_name}</span>
          </span>
        </div>
      )}
    </div>
  );
}
