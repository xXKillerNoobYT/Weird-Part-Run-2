/**
 * MileagePage — truck mileage tracking and fuel reporting.
 *
 * Stub page. Will display mileage logs, fuel efficiency, and route history.
 */

import { Gauge } from 'lucide-react';
import { EmptyState } from '../../../components/ui/EmptyState';

export function MileagePage() {
  return (
    <EmptyState
      icon={<Gauge className="h-12 w-12" />}
      title="Mileage"
      description="Log mileage, track fuel efficiency, and review route history. Coming soon."
    />
  );
}
