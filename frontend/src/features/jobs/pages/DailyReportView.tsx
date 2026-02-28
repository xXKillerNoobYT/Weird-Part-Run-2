/**
 * DailyReportView — Read-only rendered daily report for a specific job + date.
 *
 * This is the "locked notebook page" described in the plan. Reports are
 * auto-generated at midnight and contain:
 * - Worker clock data (in/out times, GPS, hours)
 * - Question responses (global + one-time)
 * - Parts consumed
 * - Cost summary
 *
 * Once generated, reports are immutable — no editing allowed.
 */

import { useParams, useNavigate } from 'react-router-dom';
import { useQuery } from '@tanstack/react-query';
import {
  ArrowLeft, Lock, Clock, Users, MapPin, Package,
  CheckCircle2, XCircle, MessageSquare, Camera,
} from 'lucide-react';
import { PageSpinner } from '../../../components/ui/Spinner';
import { Badge } from '../../../components/ui/Badge';
import { Card, CardHeader } from '../../../components/ui/Card';
import { EmptyState } from '../../../components/ui/EmptyState';
import { getReport } from '../../../api/jobs';
import type { ReportWorker, ReportPartConsumed, ReportStatus } from '../../../lib/types';

const STATUS_LABELS: Record<ReportStatus, { label: string; variant: 'default' | 'success' | 'warning' }> = {
  generated: { label: 'Generated', variant: 'default' },
  reviewed: { label: 'Reviewed', variant: 'success' },
  locked: { label: 'Locked', variant: 'warning' },
};

function formatTime(isoString: string): string {
  try {
    const d = new Date(isoString);
    return d.toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' });
  } catch {
    return isoString;
  }
}

function formatDate(dateStr: string): string {
  try {
    const d = new Date(dateStr + 'T00:00:00');
    return d.toLocaleDateString([], { weekday: 'long', year: 'numeric', month: 'long', day: 'numeric' });
  } catch {
    return dateStr;
  }
}

// ── Worker Section ──────────────────────────────────────────────

function WorkerCard({ worker }: { worker: ReportWorker }) {
  const totalHours = (worker.regular_hours || 0) + (worker.overtime_hours || 0);

  return (
    <div className="border border-border rounded-lg overflow-hidden">
      {/* Worker header */}
      <div className="bg-gray-50 dark:bg-gray-800/50 px-4 py-3 flex items-center justify-between">
        <div>
          <h4 className="text-sm font-semibold text-gray-900 dark:text-gray-100">
            {worker.display_name}
          </h4>
          <div className="flex items-center gap-3 mt-1 text-xs text-gray-500 dark:text-gray-400">
            <span className="flex items-center gap-1">
              <Clock className="h-3 w-3" />
              {formatTime(worker.clock_in)}
              {worker.clock_out ? ` — ${formatTime(worker.clock_out)}` : ' (still in)'}
            </span>
            {worker.drive_time_minutes > 0 && (
              <span>Drive: {worker.drive_time_minutes}min</span>
            )}
          </div>
        </div>
        <div className="text-right">
          <p className="text-sm font-bold text-gray-900 dark:text-gray-100">
            {totalHours.toFixed(1)}h
          </p>
          {worker.overtime_hours > 0 && (
            <p className="text-xs text-orange-500">+{worker.overtime_hours.toFixed(1)}h OT</p>
          )}
        </div>
      </div>

      {/* GPS info */}
      {(worker.clock_in_gps || worker.clock_out_gps) && (
        <div className="px-4 py-2 border-t border-border flex gap-4 text-xs text-gray-500 dark:text-gray-400">
          {worker.clock_in_gps && (
            <span className="flex items-center gap-1">
              <MapPin className="h-3 w-3 text-green-500" />
              In: {worker.clock_in_gps.lat.toFixed(4)}, {worker.clock_in_gps.lng.toFixed(4)}
            </span>
          )}
          {worker.clock_out_gps && (
            <span className="flex items-center gap-1">
              <MapPin className="h-3 w-3 text-red-500" />
              Out: {worker.clock_out_gps.lat.toFixed(4)}, {worker.clock_out_gps.lng.toFixed(4)}
            </span>
          )}
        </div>
      )}

      {/* Question Responses */}
      {worker.responses.length > 0 && (
        <div className="px-4 py-3 border-t border-border">
          <h5 className="text-xs font-medium text-gray-500 dark:text-gray-400 uppercase tracking-wider mb-2">
            Clock-Out Questions
          </h5>
          <div className="space-y-2">
            {worker.responses.map((resp, idx) => (
              <div key={idx} className="flex items-start gap-2">
                <MessageSquare className="h-3.5 w-3.5 text-gray-400 dark:text-gray-500 mt-0.5 shrink-0" />
                <div className="flex-1 min-w-0">
                  <p className="text-xs font-medium text-gray-700 dark:text-gray-300">
                    {resp.question}
                  </p>
                  <div className="mt-0.5">
                    {resp.type === 'yes_no' ? (
                      <span className={`inline-flex items-center gap-1 text-xs font-medium ${
                        resp.answer ? 'text-green-600 dark:text-green-400' : 'text-red-600 dark:text-red-400'
                      }`}>
                        {resp.answer ? <CheckCircle2 className="h-3 w-3" /> : <XCircle className="h-3 w-3" />}
                        {resp.answer ? 'Yes' : 'No'}
                      </span>
                    ) : (
                      <p className="text-xs text-gray-600 dark:text-gray-300">{String(resp.answer)}</p>
                    )}
                  </div>
                  {resp.photo && (
                    <div className="flex items-center gap-1 mt-1 text-xs text-blue-500">
                      <Camera className="h-3 w-3" />
                      Photo attached
                    </div>
                  )}
                </div>
              </div>
            ))}
          </div>
        </div>
      )}

      {/* One-Time Responses */}
      {worker.one_time_responses.length > 0 && (
        <div className="px-4 py-3 border-t border-border">
          <h5 className="text-xs font-medium text-orange-500 dark:text-orange-400 uppercase tracking-wider mb-2">
            One-Time Questions
          </h5>
          <div className="space-y-2">
            {worker.one_time_responses.map((resp, idx) => (
              <div key={idx} className="flex items-start gap-2">
                <MessageSquare className="h-3.5 w-3.5 text-orange-400 dark:text-orange-500 mt-0.5 shrink-0" />
                <div className="flex-1 min-w-0">
                  <p className="text-xs font-medium text-gray-700 dark:text-gray-300">{resp.question}</p>
                  <p className="text-xs text-gray-600 dark:text-gray-300 mt-0.5">{resp.answer}</p>
                  {resp.photo && (
                    <div className="flex items-center gap-1 mt-1 text-xs text-blue-500">
                      <Camera className="h-3 w-3" />
                      Photo attached
                    </div>
                  )}
                </div>
              </div>
            ))}
          </div>
        </div>
      )}
    </div>
  );
}

// ── Parts Table ─────────────────────────────────────────────────

function PartsTable({ parts }: { parts: ReportPartConsumed[] }) {
  if (parts.length === 0) return null;

  const totalCost = parts.reduce((sum, p) => sum + p.total, 0);

  return (
    <Card>
      <CardHeader title="Parts Consumed" subtitle={`${parts.length} items — $${totalCost.toFixed(2)} total`} />
      <div className="overflow-x-auto">
        <table className="w-full text-xs">
          <thead>
            <tr className="border-b border-border">
              <th className="text-left px-4 py-2 text-gray-500 dark:text-gray-400 font-medium">Part</th>
              <th className="text-right px-4 py-2 text-gray-500 dark:text-gray-400 font-medium">Qty</th>
              <th className="text-right px-4 py-2 text-gray-500 dark:text-gray-400 font-medium">Unit Cost</th>
              <th className="text-right px-4 py-2 text-gray-500 dark:text-gray-400 font-medium">Total</th>
            </tr>
          </thead>
          <tbody>
            {parts.map((part, idx) => (
              <tr key={idx} className="border-b border-border last:border-0">
                <td className="px-4 py-2 text-gray-900 dark:text-gray-100">
                  <div>{part.part_name}</div>
                  {part.part_code && (
                    <span className="text-gray-400 dark:text-gray-500 font-mono">{part.part_code}</span>
                  )}
                </td>
                <td className="text-right px-4 py-2 text-gray-700 dark:text-gray-300">{part.qty}</td>
                <td className="text-right px-4 py-2 text-gray-700 dark:text-gray-300">${part.unit_cost.toFixed(2)}</td>
                <td className="text-right px-4 py-2 font-medium text-gray-900 dark:text-gray-100">${part.total.toFixed(2)}</td>
              </tr>
            ))}
          </tbody>
          <tfoot>
            <tr className="bg-gray-50 dark:bg-gray-800/50">
              <td colSpan={3} className="px-4 py-2 text-right font-medium text-gray-700 dark:text-gray-300">
                Total Parts Cost
              </td>
              <td className="px-4 py-2 text-right font-bold text-gray-900 dark:text-gray-100">
                ${totalCost.toFixed(2)}
              </td>
            </tr>
          </tfoot>
        </table>
      </div>
    </Card>
  );
}

// ── Main Page ───────────────────────────────────────────────────

export function DailyReportView() {
  const { jobId, date } = useParams<{ jobId: string; date: string }>();
  const navigate = useNavigate();

  const { data: report, isLoading, error } = useQuery({
    queryKey: ['daily-report', jobId, date],
    queryFn: () => getReport(Number(jobId), date!),
    enabled: !!jobId && !!date,
  });

  if (isLoading) return <PageSpinner label="Loading report..." />;

  if (error || !report) {
    return (
      <EmptyState
        icon={<Lock className="h-12 w-12" />}
        title="Report Not Found"
        description="This daily report doesn't exist or hasn't been generated yet."
      />
    );
  }

  const { report_data: data } = report;
  const statusInfo = STATUS_LABELS[report.status] ?? STATUS_LABELS.generated;

  return (
    <div className="max-w-3xl mx-auto space-y-6">
      {/* Back button + Title */}
      <div>
        <button
          onClick={() => navigate('/reports/daily-reports')}
          className="flex items-center gap-1 text-sm text-gray-500 dark:text-gray-400 hover:text-gray-700 dark:hover:text-gray-300 transition-colors mb-3"
        >
          <ArrowLeft className="h-4 w-4" />
          Back to Reports
        </button>

        {/* Report header */}
        <div className="flex items-start justify-between">
          <div>
            <div className="flex items-center gap-2 mb-1">
              <Lock className="h-4 w-4 text-gray-400 dark:text-gray-500" />
              <span className="text-xs font-mono text-gray-500 dark:text-gray-400">
                #{data?.job_number ?? report.job_number}
              </span>
              <Badge variant={statusInfo.variant}>{statusInfo.label}</Badge>
            </div>
            <h1 className="text-xl font-bold text-gray-900 dark:text-gray-100">
              Daily Report — {formatDate(report.report_date)}
            </h1>
            <p className="text-sm text-gray-500 dark:text-gray-400 mt-1">
              {data?.job_name ?? report.job_name}
            </p>
          </div>
        </div>
      </div>

      {/* Summary stats */}
      {data?.summary && (
        <div className="grid grid-cols-3 gap-3">
          <div className="bg-surface border border-border rounded-lg p-4 text-center">
            <Users className="h-5 w-5 text-blue-500 mx-auto mb-1" />
            <p className="text-2xl font-bold text-gray-900 dark:text-gray-100">
              {data.summary.worker_count}
            </p>
            <p className="text-xs text-gray-500 dark:text-gray-400">Workers</p>
          </div>
          <div className="bg-surface border border-border rounded-lg p-4 text-center">
            <Clock className="h-5 w-5 text-green-500 mx-auto mb-1" />
            <p className="text-2xl font-bold text-gray-900 dark:text-gray-100">
              {data.summary.total_labor_hours.toFixed(1)}
            </p>
            <p className="text-xs text-gray-500 dark:text-gray-400">Labor Hours</p>
          </div>
          <div className="bg-surface border border-border rounded-lg p-4 text-center">
            <Package className="h-5 w-5 text-orange-500 mx-auto mb-1" />
            <p className="text-2xl font-bold text-gray-900 dark:text-gray-100">
              ${data.summary.total_parts_cost.toFixed(0)}
            </p>
            <p className="text-xs text-gray-500 dark:text-gray-400">Parts Cost</p>
          </div>
        </div>
      )}

      {/* Workers Section */}
      {data?.workers && data.workers.length > 0 && (
        <div>
          <h2 className="text-sm font-semibold text-gray-900 dark:text-gray-100 mb-3">
            Workers ({data.workers.length})
          </h2>
          <div className="space-y-3">
            {data.workers.map((worker, idx) => (
              <WorkerCard key={idx} worker={worker} />
            ))}
          </div>
        </div>
      )}

      {/* Parts Section */}
      {data?.parts_consumed && <PartsTable parts={data.parts_consumed} />}

      {/* Footer — generation info */}
      <div className="text-center text-xs text-gray-400 dark:text-gray-500 py-4 border-t border-border">
        <Lock className="h-3.5 w-3.5 inline mr-1" />
        Report auto-generated{report.generated_at ? ` on ${new Date(report.generated_at).toLocaleString()}` : ''}
        {' • '}This report is read-only.
      </div>
    </div>
  );
}
