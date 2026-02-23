/**
 * LaborOverviewPage — labor cost and productivity analytics.
 *
 * Stub page. Will show labor cost breakdown, tech utilization, and productivity metrics.
 */

import { BarChart3 } from 'lucide-react';
import { EmptyState } from '../../../components/ui/EmptyState';

export function LaborOverviewPage() {
  return (
    <EmptyState
      icon={<BarChart3 className="h-12 w-12" />}
      title="Labor Overview"
      description="Analyze labor costs, technician utilization, and productivity trends. Coming soon."
    />
  );
}
