/**
 * TimesheetsPage — employee timesheet management.
 *
 * Stub page. Will show time entries, approval workflows, and overtime tracking.
 */

import { Clock } from 'lucide-react';
import { EmptyState } from '../../../components/ui/EmptyState';

export function TimesheetsPage() {
  return (
    <EmptyState
      icon={<Clock className="h-12 w-12" />}
      title="Timesheets"
      description="Track employee hours, manage approvals, and monitor overtime. Coming soon."
    />
  );
}
