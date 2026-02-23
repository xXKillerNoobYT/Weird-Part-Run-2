/**
 * ActiveJobsPage — list of currently active field jobs.
 *
 * Stub page. Will show jobs in progress with tech assignments and part consumption.
 *
 * ── DEV NOTE: Tools on Job Dashboard ──────────────────────────
 * When viewing an individual job's detail page, the dashboard should
 * include a section showing tools currently checked out to that job.
 * This ties into the Trucks > Tools and Warehouse > Tools system.
 * Tools flow: Warehouse → Truck → Job (and back).
 * ──────────────────────────────────────────────────────────────
 */

import { Briefcase } from 'lucide-react';
import { EmptyState } from '../../../components/ui/EmptyState';

export function ActiveJobsPage() {
  return (
    <EmptyState
      icon={<Briefcase className="h-12 w-12" />}
      title="Active Jobs"
      description="View jobs in progress, tech assignments, real-time part consumption, and tools on-site. Coming soon."
    />
  );
}
