/**
 * ProcurementPage — procurement planning and automated reorder suggestions.
 *
 * Stub page. Will show reorder suggestions based on usage patterns and lead times.
 */

import { Calculator } from 'lucide-react';
import { EmptyState } from '../../../components/ui/EmptyState';

export function ProcurementPage() {
  return (
    <EmptyState
      icon={<Calculator className="h-12 w-12" />}
      title="Procurement Planner"
      description="AI-driven reorder suggestions based on usage patterns, lead times, and stock levels. Coming soon."
    />
  );
}
