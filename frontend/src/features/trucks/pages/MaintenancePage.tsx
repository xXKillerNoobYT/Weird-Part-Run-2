/**
 * MaintenancePage — truck maintenance scheduling and history.
 *
 * Stub page. Will show upcoming maintenance, service history, and cost tracking.
 */

import { Calendar } from 'lucide-react';
import { EmptyState } from '../../../components/ui/EmptyState';

export function MaintenancePage() {
  return (
    <EmptyState
      icon={<Calendar className="h-12 w-12" />}
      title="Maintenance"
      description="Schedule truck maintenance, track service history, and monitor costs. Coming soon."
    />
  );
}
