/**
 * PreBillingPage — review billable items before invoicing.
 *
 * Stub page. Will show unbilled parts, labor, and job costs ready for export.
 */

import { Receipt } from 'lucide-react';
import { EmptyState } from '../../../components/ui/EmptyState';

export function PreBillingPage() {
  return (
    <EmptyState
      icon={<Receipt className="h-12 w-12" />}
      title="Pre-Billing"
      description="Review unbilled parts and labor charges before generating invoices. Coming soon."
    />
  );
}
