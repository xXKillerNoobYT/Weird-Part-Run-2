/**
 * OverviewTab — Job overview with info card, warranty, stats, and suppliers.
 * Extracted from JobDetailPage.
 */

import { Users, Clock, Package, CalendarClock, Shield } from 'lucide-react';
import { Card, CardHeader } from '../../../../components/ui/Card';
import type { JobResponse } from '../../../../lib/types';
import { PreferredSuppliersSection } from '../PreferredSuppliersSection';

export function OverviewTab({ job }: { job: JobResponse }) {
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
                    : '\u2014'}
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
                    : '\u2014'}
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
                    : '\u2014'}
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
                On Call \u2014 Indefinite Standby
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
