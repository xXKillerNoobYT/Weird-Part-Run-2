/**
 * ToolsPage — track tools assigned to trucks and technicians.
 *
 * Stub page. Will manage tool inventory, calibration schedules, and check-out history.
 *
 * ── DEV NOTE: Tools Visibility Across Modules ─────────────────
 * Tools are primarily managed through this Trucks > Tools tab,
 * BUT they need to be visible from multiple locations:
 *
 *  1. Trucks > Tools (THIS PAGE)
 *     - Tools assigned to each truck / technician
 *     - Check-out / check-in flow
 *     - Calibration schedules per tool
 *
 *  2. Warehouse Dashboard
 *     - Tools currently at the warehouse (not on a truck or job)
 *     - Tool registration (adding new tools to the system)
 *     - Global view: which trucks/jobs have which tools
 *
 *  3. Jobs Dashboard (per-job detail)
 *     - Tools checked out to that specific job
 *     - Should appear on the job detail page when viewing a job
 *
 * The underlying data model should support tools being at:
 *   warehouse, truck, or job (similar to the stock location_type pattern).
 * ──────────────────────────────────────────────────────────────
 */

import { Wrench } from 'lucide-react';
import { EmptyState } from '../../../components/ui/EmptyState';

export function ToolsPage() {
  return (
    <EmptyState
      icon={<Wrench className="h-12 w-12" />}
      title="Tools"
      description="Track tool assignments, calibration dates, and check-out history. Tools are also visible on the Warehouse Dashboard and per-job views. Coming soon."
    />
  );
}
