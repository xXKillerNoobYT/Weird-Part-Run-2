/**
 * IncomingOrdersPage — orders in transit or ready for receiving.
 *
 * Stub page. Will handle receiving workflows with barcode scanning support.
 */

import { PackageOpen } from 'lucide-react';
import { EmptyState } from '../../../components/ui/EmptyState';

export function IncomingOrdersPage() {
  return (
    <EmptyState
      icon={<PackageOpen className="h-12 w-12" />}
      title="Incoming Orders"
      description="Receive incoming shipments, verify contents, and route parts to bins. Coming soon."
    />
  );
}
