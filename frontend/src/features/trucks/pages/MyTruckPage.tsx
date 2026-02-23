/**
 * MyTruckPage — current user's assigned truck inventory and status.
 *
 * Stub page. Will show the tech's truck stock, recent usage, and restock needs.
 */

import { Truck } from 'lucide-react';
import { EmptyState } from '../../../components/ui/EmptyState';

export function MyTruckPage() {
  return (
    <EmptyState
      icon={<Truck className="h-12 w-12" />}
      title="My Truck"
      description="View your truck's current inventory, recent part usage, and restock requests. Coming soon."
    />
  );
}
