/**
 * AuditPage — inventory audit and cycle count management.
 *
 * Stub page. Will support barcode-driven cycle counts and discrepancy resolution.
 */

import { ClipboardCheck } from 'lucide-react';
import { EmptyState } from '../../../components/ui/EmptyState';

export function AuditPage() {
  return (
    <EmptyState
      icon={<ClipboardCheck className="h-12 w-12" />}
      title="Audit"
      description="Run cycle counts, reconcile discrepancies, and track audit history. Coming soon."
    />
  );
}
