/**
 * RecentActivityFeed — one-line summaries of the latest stock movements.
 *
 * Shows who moved what, when, with a movement-type indicator.
 */

import {
  ArrowRightLeft, PackagePlus, PackageMinus, Undo2, Wrench, AlertTriangle, Clock,
} from 'lucide-react';
import { Card, CardHeader } from '../../../../components/ui/Card';
import { formatDateTime } from '../../../../lib/utils';
import type { ActivitySummary } from '../../../../lib/types';

const typeIcons: Record<string, typeof ArrowRightLeft> = {
  transfer: ArrowRightLeft,
  receive: PackagePlus,
  consume: PackageMinus,
  return: Undo2,
  adjust: Wrench,
  write_off: AlertTriangle,
};

interface RecentActivityFeedProps {
  activity: ActivitySummary[];
}

export function RecentActivityFeed({ activity }: RecentActivityFeedProps) {
  return (
    <Card>
      <CardHeader title="Recent Activity" />
      {activity.length === 0 ? (
        <p className="text-sm text-gray-500 dark:text-gray-400 py-4 text-center">
          No recent activity
        </p>
      ) : (
        <div className="space-y-1 -mx-6 -mb-6">
          {activity.map((item) => {
            const Icon = typeIcons[item.movement_type] ?? ArrowRightLeft;
            return (
              <div
                key={item.id}
                className="flex items-center gap-3 px-6 py-2.5 hover:bg-gray-50 dark:hover:bg-gray-700/50 transition-colors"
              >
                <Icon className="h-4 w-4 text-gray-500 dark:text-gray-400 flex-shrink-0" />
                <span className="text-sm text-gray-700 dark:text-gray-300 flex-1 truncate">
                  {item.summary}
                </span>
                {item.created_at && (
                  <span className="text-xs text-gray-500 dark:text-gray-400 whitespace-nowrap flex items-center gap-1">
                    <Clock className="h-3 w-3" />
                    {formatDateTime(item.created_at)}
                  </span>
                )}
              </div>
            );
          })}
        </div>
      )}
    </Card>
  );
}
