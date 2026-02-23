/**
 * DraftOrdersPage — purchase orders in draft status.
 *
 * Stub page. Will show POs being assembled before submission to suppliers.
 */

import { FileEdit } from 'lucide-react';
import { EmptyState } from '../../../components/ui/EmptyState';

export function DraftOrdersPage() {
  return (
    <EmptyState
      icon={<FileEdit className="h-12 w-12" />}
      title="Draft POs"
      description="Assemble and review purchase orders before submitting to suppliers. Coming soon."
    />
  );
}
