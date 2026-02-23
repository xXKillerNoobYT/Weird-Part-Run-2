/**
 * ExportsPage — generate and download report exports.
 *
 * Stub page. Will support CSV, PDF, and Excel exports of various report types.
 */

import { Download } from 'lucide-react';
import { EmptyState } from '../../../components/ui/EmptyState';

export function ExportsPage() {
  return (
    <EmptyState
      icon={<Download className="h-12 w-12" />}
      title="Exports"
      description="Generate and download reports in CSV, PDF, or Excel format. Coming soon."
    />
  );
}
