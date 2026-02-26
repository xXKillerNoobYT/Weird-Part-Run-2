/**
 * ToolsPage — stub for Phase 6 tool tracking and registration.
 *
 * Will include:
 * - Tool registry (add/edit/remove tools)
 * - Tool location tracking (warehouse, trucks, jobs)
 * - Tool checkout/return flow
 * - Tool maintenance schedules
 */

import { Wrench } from 'lucide-react';
import { EmptyState } from '../../../components/ui/EmptyState';

export function WarehouseToolsPage() {
  return (
    <EmptyState
      icon={<Wrench className="h-12 w-12" />}
      title="Tools Registry"
      description="Tool tracking, registration, and location management. Coming in a future update."
    />
  );
}
