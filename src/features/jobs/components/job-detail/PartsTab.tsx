/**
 * PartsTab — Table of parts consumed on a job.
 * Extracted from JobDetailPage.
 */

import { useQuery } from '@tanstack/react-query';
import { Package } from 'lucide-react';
import { PageSpinner } from '../../../../components/ui/Spinner';
import { EmptyState } from '../../../../components/ui/EmptyState';
import { getJobParts } from '../../../../api/jobs';

export function PartsTab({ jobId }: { jobId: number }) {
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
