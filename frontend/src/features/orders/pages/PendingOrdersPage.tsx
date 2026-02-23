/**
 * PendingOrdersPage — submitted orders awaiting delivery.
 *
 * Stub page. Will track submitted POs with expected delivery dates and statuses.
 */

import { Clock } from 'lucide-react';
import { EmptyState } from '../../../components/ui/EmptyState';

export function PendingOrdersPage() {
  return (
    <EmptyState
      icon={<Clock className="h-12 w-12" />}
      title="Pending Orders"
      description="Track submitted purchase orders, expected delivery dates, and supplier status. Coming soon."
    />
  );
}
