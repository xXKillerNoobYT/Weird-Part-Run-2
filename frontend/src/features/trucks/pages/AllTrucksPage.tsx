/**
 * AllTrucksPage — fleet-wide truck inventory overview.
 *
 * Stub page. Will display all trucks with stock levels and assignment status.
 */

import { Truck } from 'lucide-react';
import { EmptyState } from '../../../components/ui/EmptyState';

export function AllTrucksPage() {
  return (
    <EmptyState
      icon={<Truck className="h-12 w-12" />}
      title="All Trucks"
      description="Fleet overview showing every truck's inventory levels and tech assignments. Coming soon."
    />
  );
}
