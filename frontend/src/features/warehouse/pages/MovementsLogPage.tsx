/**
 * MovementsLogPage — log of all inventory movements.
 *
 * Stub page. Will show a filterable timeline of part transfers, pulls, and restocks.
 */

import { ArrowRightLeft } from 'lucide-react';
import { EmptyState } from '../../../components/ui/EmptyState';

export function MovementsLogPage() {
  return (
    <EmptyState
      icon={<ArrowRightLeft className="h-12 w-12" />}
      title="Movements Log"
      description="Filterable timeline of all inventory transfers, pulls, and restocks. Coming soon."
    />
  );
}
