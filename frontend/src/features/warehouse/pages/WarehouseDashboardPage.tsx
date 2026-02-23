/**
 * WarehouseDashboardPage — warehouse overview and status at a glance.
 *
 * Stub page. Will show bin utilization, pending pulls, and recent movements.
 *
 * ── DEV NOTE: Tools at Warehouse ──────────────────────────────
 * The Warehouse Dashboard should include a "Tools" section/panel that:
 *  1. Shows all tools currently stored at the warehouse
 *  2. Provides the ability to add NEW tools to the system (tool registration)
 *  3. Shows a summary of where all company tools currently are
 *     (which trucks have which tools, which jobs, which are at warehouse)
 *  4. Acts as the "master tools registry" — the primary place to manage
 *     the full tool inventory across the entire company
 *
 * The Trucks > Tools tab manages tools assigned per-truck.
 * The Jobs dashboard should show tools checked out to that job.
 * But the Warehouse Dashboard is the global view / tool admin center.
 * ──────────────────────────────────────────────────────────────
 */

import { Warehouse } from 'lucide-react';
import { EmptyState } from '../../../components/ui/EmptyState';

export function WarehouseDashboardPage() {
  return (
    <EmptyState
      icon={<Warehouse className="h-12 w-12" />}
      title="Warehouse Dashboard"
      description="Overview of bin utilization, pending pulls, warehouse activity, and company-wide tool registry. Coming soon."
    />
  );
}
