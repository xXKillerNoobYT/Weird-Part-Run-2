/**
 * ToolsTab — Read-only view of tools checked out to a job.
 * Extracted from JobDetailPage.
 *
 * Tools are checked out from the truck or warehouse tools pages;
 * this tab is a visibility-only list showing what's currently at the job site.
 */

import { useQuery } from '@tanstack/react-query';
import { Wrench, Shield, Star } from 'lucide-react';
import { PageSpinner } from '../../../../components/ui/Spinner';
import { Badge } from '../../../../components/ui/Badge';
import { EmptyState } from '../../../../components/ui/EmptyState';
import { getToolsAtLocation } from '../../../../api/tools';

export function ToolsTab({ jobId }: { jobId: number }) {
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
                {tool.assigned_to_name && <span>&rarr; {tool.assigned_to_name}</span>}
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
