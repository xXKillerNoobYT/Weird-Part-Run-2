/**
 * PendingTasksList — staged items, active audits, and spot-check requests.
 *
 * Each task shows a severity-colored indicator and contextual detail.
 */

import {
  Package, ClipboardCheck, AlertTriangle, Search,
} from 'lucide-react';
import { Badge } from '../../../../components/ui/Badge';
import { Card, CardHeader } from '../../../../components/ui/Card';
import type { PendingTask } from '../../../../lib/types';

const taskIcons: Record<string, typeof Package> = {
  staged: Package,
  audit: ClipboardCheck,
  spot_check: Search,
  low_stock: AlertTriangle,
};

const severityVariant: Record<string, 'default' | 'warning' | 'danger' | 'primary'> = {
  info: 'default',
  warning: 'warning',
  error: 'danger',
  critical: 'danger',
};

interface PendingTasksListProps {
  tasks: PendingTask[];
}

export function PendingTasksList({ tasks }: PendingTasksListProps) {
  return (
    <Card>
      <CardHeader
        title="Pending Tasks"
        action={
          tasks.length > 0 ? (
            <Badge variant="warning">{tasks.length}</Badge>
          ) : null
        }
      />
      {tasks.length === 0 ? (
        <p className="text-sm text-gray-500 dark:text-gray-400 py-4 text-center">
          All clear — no pending tasks
        </p>
      ) : (
        <div className="space-y-2">
          {tasks.map((task, i) => {
            const Icon = taskIcons[task.task_type] ?? AlertTriangle;
            const variant = severityVariant[task.severity] ?? 'default';
            return (
              <div
                key={`${task.task_type}-${i}`}
                className="flex items-start gap-3 p-3 rounded-lg bg-gray-50 dark:bg-gray-900/50 border border-gray-100 dark:border-gray-700/50"
              >
                <Icon className="h-4 w-4 text-gray-500 dark:text-gray-400 mt-0.5 flex-shrink-0" />
                <div className="min-w-0 flex-1">
                  <div className="flex items-center gap-2">
                    <span className="text-sm font-medium text-gray-900 dark:text-gray-100 truncate">
                      {task.title}
                    </span>
                    <Badge variant={variant} className="text-[10px] flex-shrink-0">
                      {task.severity}
                    </Badge>
                  </div>
                  {task.subtitle && (
                    <p className="text-xs text-gray-500 dark:text-gray-400 mt-0.5 truncate">
                      {task.subtitle}
                    </p>
                  )}
                </div>
              </div>
            );
          })}
        </div>
      )}
    </Card>
  );
}
