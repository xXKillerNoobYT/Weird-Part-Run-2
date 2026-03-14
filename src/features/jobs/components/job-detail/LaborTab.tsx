/**
 * LaborTab — List of labor entries for a job.
 * Extracted from JobDetailPage.
 */

import { useQuery } from '@tanstack/react-query';
import { Clock } from 'lucide-react';
import { PageSpinner } from '../../../../components/ui/Spinner';
import { Badge } from '../../../../components/ui/Badge';
import { EmptyState } from '../../../../components/ui/EmptyState';
import { getJobLabor } from '../../../../api/jobs';

export function LaborTab({ jobId }: { jobId: number }) {
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
